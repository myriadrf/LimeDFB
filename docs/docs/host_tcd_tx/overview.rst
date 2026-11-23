Overview
########

This implementation is intended for boards that use PCIe with DMA for data
transfer between the host and FPGA.

HostTCD TX transfers samples from separate host DMA buffers for up to four
channels into the FPGA for timestamped playback. Host software submits parent
descriptors with source addresses, a byte count per channel, the sample format
and the timestamp of the first sample. The FPGA schedules smaller DMA reads,
unpacks IQ16 or packed IQ12 payloads and stores the samples in channel RAM.

.. figure:: /images/host_tcd_tx/HostTCD_tx.drawio.svg
   :width: 100%
   :alt: Host parent descriptor submission and source buffers, DMA descriptor sequencing, IQ unpacking, three TX buffers per channel, timed AFE playback and completion record readout

   Figure 1. HostTCD TX overview. Solid arrows carry samples; dashed arrows carry control
   and metadata.

.. contents:: On this page
   :local:
   :depth: 2

.. _host-tcd-tx-terminology:

Terminology and abbreviations
=============================

.. list-table:: Table 1. HostTCD TX terminology
   :header-rows: 1
   :widths: 25 75
   :width: 100%
   :class: hosttcd-terminology

   * - Term
     - Meaning
   * - HostTCD
     - Host-submitted parent descriptors executed by the FPGA DMA sequencer.
   * - Parent descriptor
     - One host submission covering selected channels, their source DMA
       addresses, common payload counts, format and first-sample timestamp.
   * - DMA child descriptor
     - One smaller native LitePCIe DMA transfer generated from a parent
       descriptor. It targets one channel and respects PCIe page boundaries.
   * - TX segment
     - A fixed-size sample interval within a TX parent descriptor. Its payload
       is ``split_size`` bytes per channel and fits one TX buffer per channel.
       A segment can require multiple DMA child descriptors.
   * - TX buffer
     - A reusable FPGA sample-memory region holding one TX segment for one
       channel. The same buffer index is used across participating channels.
       Hardware interfaces may call this region a slot.
   * - Completion record
     - One record per retired parent descriptor. TX records describe transmitted/skipped
       samples and errors.
   * - Complex sample / IQ pair
     - One in-phase (I) component and one quadrature (Q) component for one channel.
       Sample counts and byte counts are per channel unless stated otherwise.
   * - Sample tick
     - One position on the shared RX/TX sample timeline. TX segment timestamps
       advance by samples per segment, not by payload byte count.

HostTCD descriptor table and descriptor sequencer
=================================================

The HostTCD descriptor table queues up to 16 parent descriptors. Each entry
specifies one source DMA address per participating channel, shared byte and
sample counts, the sample format and a first-sample timestamp. Channel buffers
do not need to be adjacent in host memory. Each parent is divided into segments
of up to ``split_size`` bytes per channel, each fitting one TX buffer per
channel. The final segment may be shorter, only its valid samples are played.

The descriptor sequencer visits each segment's participating channels in order
and divides their source ranges into DMA child descriptors at 4 KiB boundaries.
It programs the LitePCIe DMA reader descriptor table and sends matching ordered
commands to the TX payload loader, keeping incoming bytes associated with the
correct channel and segment. Timed parents execute once in program mode;
loop mode is unsupported.

See :ref:`host-tcd-tx-descriptor-table` for host submission and configuration,
and :ref:`host-tcd-tx-completion-record-fifo` for completion readout.

.. _host-tcd-tx-parent-fields:

Parent descriptor structure
---------------------------

A parent identifies separate host sample buffers for the selected channels.
The main fields below describe their addresses, common length and playback
start time. The diagram also shows the shared split-size configuration that
determines how each buffer is divided into segments.

.. figure:: /images/host_tcd_tx/HostTCD_tx_descriptors.drawio.svg
   :width: 100%
   :alt: Queued parent descriptors with compact fields, an expanded view of the selected parent and address arrows to separate segmented host channel buffers

   Figure 2. The example uses four participating channels, with each
   source address pointing to the first payload byte of its channel buffer.
   Queued parents show the main fields this is
   a logical structure rather than a packed CSR layout.

See :ref:`host-tcd-tx-descriptor-csrs` in the host software guide for the
register reference and descriptor validation requirements.

.. _host-tcd-tx-segment-playback:

Segment buffering
=================

The FPGA divides each channel's host buffer into segments of up to
``split_size`` bytes, with the same segment boundaries across all participating
channels. DMA reads fetch each segment's channel payloads, unpack IQ16 or IQ12
samples and fill one TX buffer per channel. The final segment may contain
fewer samples. The default configuration provides three buffers of 4096 complex
samples per channel. During continuous operation, one buffer is being played,
a second is already loaded and ready for playback, and a third is being
prefetched. The buffers rotate through these roles as segments complete.

.. figure:: /images/host_tcd_tx/host_tcd_tx_buffers.drawio.svg
   :width: 100%
   :alt: DMA prefetch and unpacking alongside three per-channel buffers in playback, ready and prefetch roles, followed by timestamp scheduling and TX output

   Figure 3. Prefetch and play through three buffers per channel. Buffer roles rotate
   after release; ``T`` is the parent timestamp and ``K`` is samples per full
   segment.

Timed playback
==============

Each segment carries a scheduled start tick derived from the parent timestamp
and its sample offset. Playback waits until that segment is fully buffered for
every participating channel, then starts all channels together when the shared
RX/TX sample counter reaches the scheduled tick. Only valid samples are played;
buffers are released after playback or discard. A segment that cannot start on
time is skipped, while later segments retain their original timestamps.

.. figure:: /images/host_tcd_tx/host_tcd_tx_recovery.drawio.svg
   :width: 100%
   :alt: Sample timeline showing late segments discarded while later segments retain their timestamps and one aggregate parent completion

   Figure 4. HostTCD TX timestamp recovery. In the example,
   segment 1 is late and segment 2 has insufficient preparation time. Playback
   resumes with segment 3 at its original timestamp, leaving a gap across all
   participating channels. Segment indices and buffer roles are illustrative.

When a segment cannot start on time, the FPGA:

* Discards that segment without shifting subsequent timestamps.
* Selects the earliest remaining segment with enough lead time for DMA,
  unpacking and scheduling.
* Advances the host address and sample offset consistently across all
  participating channels.
* Rechecks readiness at the selected timestamp and skips again if necessary.
* Discards the remaining parent if no usable segment remains.


Completion record FIFO
======================

The completion record FIFO lets software track parent retirement and determine
when host source buffers can be reused. After all segments of a parent have
been played or discarded and its outstanding DMA accesses have drained, the
FPGA publishes one record covering all participating channels. It reports the
parent sequence, requested, transmitted and skipped sample counts, timestamp,
segment count and outcome flags.

Software snapshots the oldest record, reads its fields and pops it to release
FIFO capacity. Records remain queued until popped; a full FIFO backpressures
completion handling and can eventually stall TX fetching. Interrupts can
notify software of new completions, or software can poll for available records.

See :ref:`host-tcd-tx-completion-record-fifo` in the host software guide for
the record layout, snapshot/read/pop algorithm and buffer ownership rules.
