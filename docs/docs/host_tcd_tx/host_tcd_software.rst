Host software guide
###################

This guide covers descriptor submission and completion handling for the
streaming timed-TX path. See :doc:`overview` for the hardware overview.

.. contents:: On this page
   :local:
   :depth: 2

Initialization and configuration
================================

Identify the loaded table version, capabilities and buffer capacities before
configuring the stream. See :ref:`host-tcd-tx-descriptor-csrs` for register
semantics. With execution disabled and the sequencer stopped, select program
mode and reset the table if starting a new stream. Configure the preparation
lead time and prepare the source DMA mappings before staging parents.

Queue the initial parents using the procedure below, then enable execution.
Service completion records during operation to release FIFO capacity and
track when source buffers can be reused.

.. _host-tcd-tx-descriptor-table:

Parent descriptor submission
============================

Software fills one parent at a time through the CSR staging window. For each
logical channel, select its index, write the DMA address high and low words,
then strobe ``ADDRESS_WRITE``. After staging all channels and the shared fields,
strobe ``SUBMIT``. The FPGA validates and copies the addresses before making
the complete parent visible to the DMA sequencer. Wait for acceptance before
changing staging registers; a successful submission clears the address
initialization mask, so every parent needs its addresses written again.

.. figure:: /images/host_tcd_tx/HostTCD_TX_submission.drawio.svg
   :width: 70%
   :align: center
   :alt: TX descriptor staging, per-channel address loop, submission and acceptance checks, and program-mode execution

   Figure 1. HostTCD TX descriptor submission flow. The initial stop and program-mode
   selection apply when preparing a stopped stream; an initialized running
   stream can submit further parents starting at the staging-availability check.

The following algorithm assumes the streaming timed-TX table (version 3),
program mode (``LOOP_PROG_N = 0``), available table capacity and an initialized
TX playback path. Validate inputs against :ref:`host-tcd-tx-descriptor-csrs`
and use the segment size defined in :ref:`host-tcd-tx-segment-playback`.

Synchronize source buffers for DMA before submission and retain their mappings
until safe parent retirement. Choose a timestamp with sufficient lead time
for fetching and playback.

Use ordered register accesses and the generated CSR addresses for the loaded
bitstream. Serialize the entire staging/submission sequence between producers.
``wait_for_clear()`` polls the specified bits and aborts the operation on timeout.

.. code-block:: c
   :caption: Algorithm: fill and submit one HostTCD TX parent descriptor
   :name: host-tcd-tx-fill-descriptor

   wait_for_clear(CSR_TX_HOST_TCD_SUBMIT_STATUS_ADDR, 1, timeout_ms);
   uint32_t buffer_samples = read32(CSR_TX_HOST_TCD_BUFFER_SAMPLES_ADDR);
   uint32_t bytes_per_sample = iq12 ? 3 : 4;
   /* Validate counts and 32-bit byte-count range before these writes. */
   uint32_t bytes_per_channel = samples_per_channel * bytes_per_sample;

   write32(CSR_TX_HOST_TCD_CHANNEL_COUNT_ADDR, channel_count);
   write32(CSR_TX_HOST_TCD_BYTES_PER_CHANNEL_ADDR, bytes_per_channel);
   write32(CSR_TX_HOST_TCD_SAMPLES_PER_CHANNEL_ADDR, samples_per_channel);
   write32(CSR_TX_HOST_TCD_IQ12_ADDR, iq12 ? 1 : 0);
   write32(CSR_TX_HOST_TCD_SPLIT_SIZE_ADDR, buffer_samples * bytes_per_sample);
   write32(CSR_TX_HOST_TCD_TIMESTAMP_HIGH_ADDR, (uint32_t)(timestamp >> 32));
   write32(CSR_TX_HOST_TCD_TIMESTAMP_LOW_ADDR, (uint32_t)timestamp);
   write32(CSR_TX_HOST_TCD_FLAGS_ADDR, 2); /* Disable early-last termination. */

   for (unsigned i = 0; i < channel_count; ++i) {
       write32(CSR_TX_HOST_TCD_ADDRESS_INDEX_ADDR, i);
       write32(CSR_TX_HOST_TCD_ADDRESS_HIGH_ADDR, (uint32_t)(dma_addr[i] >> 32));
       write32(CSR_TX_HOST_TCD_ADDRESS_LOW_ADDR, (uint32_t)dma_addr[i]);
       write32(CSR_TX_HOST_TCD_ADDRESS_WRITE_ADDR, 1);
   }

   write32(CSR_TX_HOST_TCD_SUBMIT_ADDR, 1);
   wait_for_clear(CSR_TX_HOST_TCD_SUBMIT_STATUS_ADDR, 1, timeout_ms);
   uint32_t status = read32(CSR_TX_HOST_TCD_SUBMIT_STATUS_ADDR);

   if (status & 4) {
       uint32_t errors = read32(CSR_TX_HOST_TCD_ERRORS_ADDR);
       /* Submission rejected: inspect errors, correct and retry. */
   } else if (status & 2) {
       /* Parent queued; fetching and playback retirement are still pending. */
   }

.. _host-tcd-tx-completion-record-fifo:

Completion record FIFO
======================

The streaming timed-TX path publishes one completion record after the final
segment outcome of a parent is collected. The record covers all participating
channels, including segments discarded because they were late and samples
skipped after a playback underrun. It reports playback/discard completion,
not descriptor acceptance or prefetch completion.

Each record contains eight 32-bit words (32 bytes). The result FIFO is configured
with depth 16 and a buffered output stage. The CSRs expose whether a record is
available, rather than a readable entry count. Obtain register addresses from
the loaded bitstream's generated CSR map; these registers belong to
``CSR_TX_TIMED_*``, while descriptor submission uses ``CSR_TX_HOST_TCD_*``.

Completion FIFO CSR reference
-----------------------------

These registers belong to the streaming timed-TX completion FIFO. Register
reads do not advance the FIFO; software controls snapshot and pop explicitly.

.. list-table:: Table 1. Completion record FIFO CSRs
   :header-rows: 1
   :widths: 40 60
   :width: 100%
   :class: hosttcd-terminology hosttcd-csr-table

   * - CSR name
     - Description
   * - ``TX_TIMED_RECORD_AVAILABLE``
     - Read-only availability bit. A value of 1 means the FIFO has a completed
       parent record ready to snapshot; this is not an entry count.
   * - ``TX_TIMED_RECORD_SNAPSHOT``
     - Write 1 to copy the oldest available record into ``RECORD_WORD0``
       through ``RECORD_WORD7`` and set ``SNAPSHOT_VALID``. A request with no
       available record captures nothing. Snapshotting does not remove a record.
   * - ``TX_TIMED_SNAPSHOT_VALID``
     - Read-only bit indicating a valid record snapshot. Wait for 1 before
       reading the words. A successful pop or results reset clears it.
   * - ``TX_TIMED_RECORD_WORD0``
     - Read-only snapshot word: parent execution sequence.
   * - ``TX_TIMED_RECORD_WORD1``
     - Read-only snapshot word: requested complex samples per channel.
   * - ``TX_TIMED_RECORD_WORD2``
     - Read-only snapshot word: transmitted complex samples per channel.
   * - ``TX_TIMED_RECORD_WORD3``
     - Read-only snapshot word: skipped complex samples per channel.
   * - ``TX_TIMED_RECORD_WORD4``
     - Read-only snapshot word: outcome flags. Bit 0 indicates late/skipped
       segments; bit 1 indicates playback underrun.
   * - ``TX_TIMED_RECORD_WORD5``
     - Read-only snapshot word: bits 31:0 of the parent's scheduled timestamp.
   * - ``TX_TIMED_RECORD_WORD6``
     - Read-only snapshot word: bits 63:32 of the parent's scheduled timestamp.
   * - ``TX_TIMED_RECORD_WORD7``
     - Read-only snapshot word: total segments accounted for, including
       skipped segments and a shorter final segment.
   * - ``TX_TIMED_RECORD_POP``
     - Write 1 after copying the snapshot to remove the FIFO head, release its
       capacity and clear ``SNAPSHOT_VALID``. Without a valid snapshot it does
       nothing. Take a new snapshot before popping the next record.
   * - ``TX_TIMED_PROTOCOL_ERROR``
     - Read-only sticky completion-accounting error bit. Popping records does
       not clear it; an accepted table reset clears the results state.
       See :ref:`host-tcd-tx-status-errors` for handling.

Reading entries
---------------

Poll ``RECORD_AVAILABLE``, or check it after a TX parent interrupt. Descriptor
``FLAGS`` bit 0 suppresses that parent's interrupt but does not suppress its
completion record. ``wait_for_set()`` polls the specified bits and aborts the
operation on timeout.

.. code-block:: c
   :caption: Algorithm: read and pop HostTCD TX completion records
   :name: host-tcd-tx-read-completion

   while (read32(CSR_TX_TIMED_RECORD_AVAILABLE_ADDR) & 1) {
       uint32_t words[8];

       write32(CSR_TX_TIMED_RECORD_SNAPSHOT_ADDR, 1);
       wait_for_set(CSR_TX_TIMED_SNAPSHOT_VALID_ADDR, 1, timeout_ms);

       for (unsigned i = 0; i < 8; ++i) {
           words[i] = read32(CSR_TX_TIMED_RECORD_WORD0_ADDR + 4 * i);
       }

       uint32_t protocol_error = read32(CSR_TX_TIMED_PROTOCOL_ERROR_ADDR);
       write32(CSR_TX_TIMED_RECORD_POP_ADDR, 1);
       process_tx_record(words, protocol_error); /* Process the local copy. */
   }

Use ordered device register accesses and one consumer for the entire sequence.
Writing one to ``RECORD_SNAPSHOT`` copies the FIFO head into ``RECORD_WORD0``
through ``RECORD_WORD7`` and sets ``SNAPSHOT_VALID``. A request with no available
record captures nothing. The snapshot stays stable while new completions arrive;
reading a word does not advance the FIFO.

After copying all eight words, write one to ``RECORD_POP`` to remove the head
and clear ``SNAPSHOT_VALID``. Pop without a valid snapshot does nothing. Take
a new snapshot for every entry. A full result FIFO backpressures final parent
outcomes and can eventually stall TX buffer reuse and fetching; drain records
regularly even when parent interrupts are disabled.

Record fields
-------------

Word indices start at zero. Sample counts are complex samples per channel,
not the sum across channels. All participating channels share the same outcome.

.. list-table:: Table 2. TX completion record fields
   :header-rows: 1
   :widths: 12 23 65
   :width: 100%
   :class: hosttcd-terminology hosttcd-record-table

   * - Word(s)
     - Field
     - Description
   * - 0
     - ``sequence``
     - Parent execution sequence modulo 2^32. Starts at zero after a results/table reset and advances once per executed parent, including fully skipped parents.
   * - 1
     - ``requested``
     - Requested complex samples per channel, from the parent's ``samples_per_channel``.
   * - 2
     - ``transmitted``
     - Samples per channel accepted by the playback output across all segments; can include a partial segment before an underrun.
   * - 3
     - ``skipped``
     - Requested samples per channel that were not transmitted. Normally ``transmitted + skipped = requested``.
   * - 4
     - ``flags``
     - Bit 0: at least one late or deliberately skipped segment. Bit 1: playback underrun in at least one segment. Both can be set; other bits are zero.
   * - 5--6
     - ``timestamp``
     - Original first-sample timestamp of the parent, low word first. Reconstruct as ``(uint64_t)words[5] | ((uint64_t)words[6] << 32)``. This is the requested schedule, not an actual transmission or host-arrival timestamp.
   * - 7
     - ``chunks``
     - Total TX segments accounted for, including skipped segments and a shorter final segment. Expected value: ``ceil(requested / BUFFER_SAMPLES)``.

Keep a software queue of accepted parents and match records by execution
sequence. The record does not contain source DMA addresses, channel count,
format or a software epoch. Preserve those values and track reset generations
in the driver. A rejected submission does not produce a completion record.

Validate each record's sequence, counts and flags before releasing source
buffers. See :ref:`host-tcd-tx-status-errors` if ``PROTOCOL_ERROR`` is set.

Completion counts summarize the parent; they do not locate individual gaps.
A descriptor table entry becoming free (``TX_HOST_TCD_LEVEL`` decreasing)
or fetching finishing does not release its source buffers. Use the driver's
DMA ownership rules and validated playback completions when recycling mappings.

.. _host-tcd-tx-status-errors:

Status and error handling
=========================

``SUBMIT_STATUS`` bit 0 means validation/copy busy, bit 1 means the last
submission was accepted and bit 2 means it was rejected. ``ERRORS`` provides
sticky diagnostics, including invalid fields, a full table, missing addresses
or staging writes while busy.

``PROTOCOL_ERROR`` is a separate sticky status bit indicating an
unexpected outcome sequence, a transmitted count larger than its segment, or
an aggregate sample count inconsistent with the parent. It is cleared with
the results state by an accepted table reset; popping a record does not clear
it. If set, treat completion accounting as unreliable and recover the stream
before relying on it for buffer ownership.

.. _host-tcd-tx-descriptor-csrs:

Descriptor table CSR reference
==============================

.. list-table:: Table 3. Parent descriptor table and configuration CSRs
   :header-rows: 1
   :widths: 40 60
   :width: 100%
   :class: hosttcd-terminology hosttcd-csr-table

   * - CSR name
     - Description
   * - ``TX_HOST_TCD_VERSION``
     - Read-only table ABI version; streaming timed TX reports version 3.
   * - ``TX_HOST_TCD_CAPABILITIES``
     - Read-only capabilities: bits 0--7 give the maximum channel count,
       bits 8--23 the parent table depth, bit 24 ordered payload commands,
       bit 28 streaming TX, bit 29 timed TX, bit 30 diagnostic fetch and
       bit 31 execution inhibition for table-only builds.
   * - ``TX_HOST_TCD_CHANNEL_COUNT``
     - Stages parent field ``C``, the number of participating channels.
   * - ``TX_HOST_TCD_BYTES_PER_CHANNEL``
     - Stages parent field ``B``, the source payload length for each channel.
   * - ``TX_HOST_TCD_SAMPLES_PER_CHANNEL``
     - Stages parent field ``N``, the complex sample count for each channel.
   * - ``TX_HOST_TCD_IQ12``
     - Stages parent field ``FMT``: 0 selects IQ16; 1 selects packed IQ12.
   * - ``TX_HOST_TCD_FLAGS``
     - Stages parent field ``F``. Bit 0 disables the parent interrupt;
       bit 1 disables early-last termination and is required when ``C > 1``.
   * - ``TX_HOST_TCD_TIMESTAMP_LOW``
     - Stages bits 31:0 of parent field ``T``, the first-sample timestamp.
   * - ``TX_HOST_TCD_TIMESTAMP_HIGH``
     - Stages bits 63:32 of parent field ``T``.
   * - ``TX_HOST_TCD_ADDRESS_INDEX``
     - Selects which logical channel's source address to stage: 0--3 for A--D.
   * - ``TX_HOST_TCD_ADDRESS_HIGH``
     - Stages bits 63:32 of the selected channel's source DMA address.
   * - ``TX_HOST_TCD_ADDRESS_LOW``
     - Stages bits 31:0 of the selected channel's source DMA address.
   * - ``TX_HOST_TCD_ADDRESS_WRITE``
     - Write 1 to copy the address words into the selected staging entry.
   * - ``TX_HOST_TCD_ADDRESSES_WRITTEN``
     - Read-only mask of initialized staging entries. Successful submission
       clears the mask; restage every participating address for each parent.
   * - ``TX_HOST_TCD_SUBMIT``
     - Write 1 to validate and enqueue the staged parent. Keep staging
       registers unchanged until validation and address copying finish.
   * - ``TX_HOST_TCD_SUBMIT_STATUS``
     - Read-only submission result: bit 0 busy, bit 1 last submission accepted,
       bit 2 last submission rejected.
   * - ``TX_HOST_TCD_LEVEL``
     - Read-only occupied parent entry count, including the active fetch.
       A value of 16 fills the current table. An entry is released after its
       fetch completes; this does not release its host DMA buffers.
   * - ``TX_HOST_TCD_ENABLE``
     - Set to 1 to enable execution. Clearing it drains the active parent
       and pending playback before the sequencer stops; queued parents remain.
   * - ``TX_HOST_TCD_LOOP_PROG_N``
     - Selects program or loop mode while stopped. Streaming timed TX requires
       0 (program mode); replaying timestamped parents in loop mode is unsupported.
   * - ``TX_HOST_TCD_RESET``
     - Write 1 while execution is disabled, the sequencer is stopped and
       submission is idle to clear the table and results state. Active reset
       requests are rejected; fatal sequencer faults require a SoC reset.
   * - ``TX_HOST_TCD_SPLIT_SIZE``
     - Segment bytes per channel. At submission it must equal
       ``BUFFER_SAMPLES * 4`` for IQ16 or ``BUFFER_SAMPLES * 3`` for IQ12.
       Streaming TX derives the queued parent's segment size from its format.
   * - ``TX_HOST_TCD_PREPARATION_TICKS``
     - Live scheduling lead-time budget in RX/TX sample ticks; not stored per
       parent. Before fetching, the sequencer skips segments scheduled before
       ``current_tick + PREPARATION_TICKS``. Budget for DMA, unpacking,
       scheduling and counter-snapshot delay. The default is
       ``BUFFER_SAMPLES / 2`` (2048 ticks here). More lead time does not
       guarantee timely playback; late arrivals are still discarded.
   * - ``TX_HOST_TCD_BUFFER_SAMPLES``
     - Read-only segment capacity in complex samples per channel: 4096 in
       the current HiperSDR configuration.
   * - ``TX_HOST_TCD_BUFFER_SLOTS``
     - Read-only TX buffer count per channel: 3 in the current configuration.
   * - ``TX_HOST_TCD_BUSY``
     - Read-only sequencer activity. Poll for 0 after disabling execution
       before changing mode or requesting a table reset.
   * - ``TX_HOST_TCD_COMPLETED_TOTAL``
     - Read-only count of retired parents, after playback or discard.
   * - ``TX_HOST_TCD_OUTSTANDING``
     - Read-only number of issued DMA child descriptors awaiting retirement.
   * - ``TX_HOST_TCD_CHILD_ISSUED``
     - Read-only cumulative count of issued DMA child descriptors.
   * - ``TX_HOST_TCD_CHILD_COMPLETED``
     - Read-only cumulative count of retired DMA child descriptors.
   * - ``TX_HOST_TCD_REJECTED``
     - Read-only count of rejected submission attempts, including attempts
       made while submission is busy.
   * - ``TX_HOST_TCD_ERRORS``
     - Read-only sticky error bitmap for validation, capacity, staging,
       configuration and sequencer faults.
   * - ``TX_HOST_TCD_CLEAR_ERRORS``
     - Write a mask to clear the corresponding sticky error bits. Clearing
       diagnostics does not recover a fatal sequencer fault.
   * - ``TX_HOST_TCD_LOOP_STATUS``
     - In program mode, reports the completed-parent count. Loop-mode index
       and iteration reporting is unused by streaming timed TX.
   * - ``TX_HOST_TCD_RING_SIZE``
     - Loop-mode ring size; unused by streaming timed TX, which uses program mode.

Source DMA addresses must be 32-byte aligned and cover the full per-channel
payload without wrapping the 64-bit address range. Sample counts must be
positive, and byte counts must fit in 32 bits:
``bytes_per_channel = samples_per_channel * (IQ12 ? 3 : 4)``.
Payloads must contain whole complex samples and complete 32-byte DMA beats:
IQ16 byte counts are multiples of 32; IQ12 byte counts are multiples of 96.
Timestamp arithmetic wraps modulo 2^64; keep schedules less than 2^63 ticks
from the current counter to avoid ambiguous ordering.

The table describes the streaming timed-TX CSR set. The timestamp, format,
buffer-capacity and streaming configuration registers depend on the loaded
build. Generated C address macros use the form ``CSR_TX_HOST_TCD_<NAME>_ADDR``.
See :ref:`host-tcd-tx-descriptor-table` for the submission algorithm.
