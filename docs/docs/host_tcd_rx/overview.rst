Overview
########

This implementation is intended for boards that use PCIe with DMA for data
transfer between the host and FPGA.

HostTCD RX transfers acquired samples into separate host DMA buffers for up to
four channels. Host software submits parent descriptors with destination
addresses and a byte count per channel. The FPGA schedules smaller DMA
transfers, reads the selected channel banks and formats samples as IQ16 or
packed IQ12.

Samples receive a shared acquisition tick before packing or DMA. When the
parent's final DMA child retires, one completion record reports its destination
addresses, sample counts and timestamp continuity. Software reads and pops
these records to associate captured samples with their acquisition time.

.. figure:: /images/host_tcd_rx/HostTCD_rx.drawio.svg
   :width: 100%
   :alt: Host parent descriptor submission, four-channel acquisition RAM, DMA to host buffers and completion record readout

   Figure 1. HostTCD RX overview. Solid arrows carry samples; dashed arrows carry control
   and metadata. Sample slots are released after all requested channels have
   been read. Completion records are published at final DMA retirement.

.. contents:: On this page
   :local:
   :depth: 2

.. _host-tcd-rx-terminology:

Terminology and abbreviations
=============================

.. list-table:: Table 1. HostTCD RX terminology
   :header-rows: 1
   :widths: 25 75
   :width: 100%
   :class: hosttcd-terminology

   * - Term
     - Meaning
   * - HostTCD
     - Host-submitted parent descriptors executed by the FPGA DMA sequencer.
   * - Parent descriptor
     - One host submission specifying a destination DMA address for each
       selected channel and a common byte count per channel.
   * - DMA child descriptor
     - One smaller native LitePCIe DMA transfer generated from a parent.
       It writes one channel's samples and respects PCIe page boundaries.
   * - Completion record
     - One record published after the parent's final DMA child retires.
       It reports destination addresses, sample counts and acquisition
       timestamp continuity across all participating channels.
   * - Complex sample / IQ pair
     - One in-phase (I) component and one quadrature (Q) component for one
       channel. Sample counts and byte counts are per channel unless stated
       otherwise. IQ16 stores 16-bit components; IQ12 packs 12-bit components.
   * - Acquisition tick
     - A sample-frame counter shared by all channels. It advances on every
       valid input frame, including dropped frames, and identifies acquisition
       time rather than host arrival time.

HostTCD descriptor table and descriptor sequencer
=================================================

The HostTCD descriptor table queues up to 16 parent descriptors. Each parent specifies
one DMA destination per selected channel and a common byte count. The
sequencer divides parents into channel blocks and 4 KiB boundary fragments,
then programs the LitePCIe DMA descriptor table. Ordered commands keep sample
readout aligned with those destinations. Program mode consumes queued parents;
loop mode repeats them.

See :ref:`host-tcd-rx-descriptor-table` for host submission and configuration.

.. _host-tcd-rx-parent-fields:

Parent descriptor structure
---------------------------

A parent identifies separate host destination buffers for the selected channels,
with a common byte count per channel. The channel map selects which physical
channel supplies each logical destination. Each channel buffer is divided into
1024-sample blocks; shared ``split_size`` is 4096 bytes for IQ16 or 3072 bytes
for IQ12. The sequencer splits these blocks further at PCIe page boundaries.

.. figure:: /images/host_tcd_rx/HostTCD_RX_descriptors.drawio.svg
   :width: 100%
   :alt: Queued RX parents, expanded descriptor fields and address arrows to separate channel destination buffers

   Figure 2. Queued parents, expanded fields of the selected parent and separate
   channel destination buffers, following the TX descriptor diagram layout.
   The example uses the default channel map and four participating channels.
   This is a logical structure, not a packed CSR layout; acquisition timestamps
   are returned in completion records rather than supplied by the parent.

   Editable source: :download:`draw.io diagram </images/host_tcd_rx/HostTCD_RX_descriptors.drawio>`.

See :ref:`host-tcd-rx-descriptor-table` for submission and
:ref:`host-tcd-rx-dma-buffer-layout` for payload layout and length requirements.

Acquisition RAM
===============

The acquisition path stores simultaneous samples from channels A--D in shared
slots across four RAM banks. Each completed slot carries its first acquisition
tick and gap status. A slot remains owned by the reader until all requested
channels have been read. If no slot is free, incoming frames are dropped while
the acquisition counter continues.

See :ref:`host-tcd-rx-memory-layout` for the RAM organization and
:ref:`host-tcd-rx-write-path` for write admission, addressing and slot filling.

Read and format
===============

The read path follows the sequencer's commands to select a completed slot and
channel. It reads eight IQ16 samples in parallel and emits a 256-bit stream,
either preserving IQ16 or packing the upper 12 bits of I and Q as IQ12.
Backpressure pauses readout, and the slot is released after every requested
channel has entered the output FIFO.

See :ref:`Reading Samples <host-tcd-rx-read-path>` for channel selection, address
calculation, IQ packing and slot release.

Completion record FIFO
======================

One record is published when a parent's final DMA child retires. It contains
the destination addresses, acquisition ticks, sample counts and gap flags for
all participating channels. The default FIFO holds 256 records; software reads
each through a snapshot and pops it to release capacity. A full reservation
pool stalls new parents rather than discarding completion records.

See :ref:`host-tcd-rx-timestamp-record-fifo` for record fields and the
snapshot/read/pop procedure.
