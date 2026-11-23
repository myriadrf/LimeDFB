Host software guide
###################

HostTCD receives samples into separate host DMA buffers for channels A--D.
Each parent descriptor specifies the channel count, one DMA address per channel,
and the byte count per channel. One completion record describes the whole parent.


.. contents:: On this page
   :local:
   :depth: 2

Initialization and configuration
================================

Identify the loaded RX and HostTCD versions and use the matching CSR map.
See :ref:`host-tcd-rx-descriptor-csrs` and :ref:`host-tcd-rx-acquisition-csrs`
for register semantics.
With acquisition and descriptor execution disabled and the DMA writer idle,
configure ``iq12``, ``channel_map`` and a new ``epoch`` while flushed. Clear
``flush``, wait for acknowledgement and check status before configuring the
matching ``split_size`` and preparing destination DMA mappings.

Queue the initial parents using the procedure below, enable HostTCD execution,
then start acquisition. Service completion records during operation to release
FIFO capacity and track when destination buffers can be reused.

.. _host-tcd-rx-descriptor-table:

Parent descriptor submission
============================

Software fills one parent at a time through the CSR staging window. For each
logical channel, select its index, write the DMA address high and low words,
then strobe ``ADDRESS_WRITE``. After staging all channels and the common byte
count, strobe ``SUBMIT``. The FPGA validates and copies the addresses before
making the complete parent visible to the DMA sequencer. Wait for acceptance
before changing staging registers; a successful submission clears the address
initialization mask, so every parent needs its addresses written again.

.. figure:: /images/host_tcd_rx/HostTCD_RX_submission.drawio.svg
   :width: 50%
   :align: center
   :alt: HostTCD RX initialization, address staging, submission and execution algorithm

   Figure 1. HostTCD RX parent descriptor submission procedure.

The following algorithm assumes program mode, available table capacity and
matching RX format, channel map and split size. ``dma_addr`` contains
driver-provided DMA addresses, not application pointers. Use ordered register
accesses and the generated CSR addresses for the loaded bitstream.
``wait_for_clear()`` polls the specified bits and aborts the operation on timeout.

.. code-block:: c
   :caption: Algorithm: fill and submit one HostTCD RX parent descriptor
   :name: host-tcd-rx-fill-descriptor

   wait_for_clear(CSR_RX_HOST_TCD_SUBMIT_STATUS_ADDR, 1, timeout_ms);
   write32(CSR_RX_HOST_TCD_CHANNEL_COUNT_ADDR, channel_count);
   write32(CSR_RX_HOST_TCD_BYTES_PER_CHANNEL_ADDR, bytes_per_channel);
   write32(CSR_RX_HOST_TCD_FLAGS_ADDR, 2); /* Disable early-last termination. */

   for (unsigned i = 0; i < channel_count; ++i) {
       write32(CSR_RX_HOST_TCD_ADDRESS_INDEX_ADDR, i);
       write32(CSR_RX_HOST_TCD_ADDRESS_HIGH_ADDR, (uint32_t)(dma_addr[i] >> 32));
       write32(CSR_RX_HOST_TCD_ADDRESS_LOW_ADDR, (uint32_t)dma_addr[i]);
       write32(CSR_RX_HOST_TCD_ADDRESS_WRITE_ADDR, 1);
   }

   write32(CSR_RX_HOST_TCD_SUBMIT_ADDR, 1);
   wait_for_clear(CSR_RX_HOST_TCD_SUBMIT_STATUS_ADDR, 1, timeout_ms);
   uint32_t status = read32(CSR_RX_HOST_TCD_SUBMIT_STATUS_ADDR);

   if (status & 4) {
       /* Submission rejected: inspect errors, correct and retry. */
   } else if (status & 2) {
       /* Parent queued; DMA completion and buffer release are still pending. */
   }

.. _host-tcd-rx-timestamp-record-fifo:

Completion record FIFO
======================

RX path publishes one completion record when the final native DMA child of
a parent retires, across all requested channels. The default FIFO holds 256
records, each containing 24 32-bit words (96 bytes). Use the loaded bitstream's
generated CSR map for register addresses with the ``CSR_LIMETOP_RXTX_TOP_RX_PATH_``
prefix. Below, ``CSR_..._`` abbreviates this prefix.

Reading entries
---------------

Read the oldest completed parent through the snapshot registers. Poll
``CSR_..._METADATA_LEVEL``, or check it after an RX interrupt.
``CSR_..._METADATA_RESERVED`` includes
unfinished parents as well as unread completions; it is not the readable count.
``wait_for_set()`` polls the specified bits and aborts the operation on timeout.

.. code-block:: c

   while (read32(CSR_..._METADATA_LEVEL) != 0) {
       uint32_t words[24];

       write32(CSR_..._SNAPSHOT, 1);
       wait_for_set(CSR_..._SNAPSHOT_VALID, 1, timeout_ms);

       for (unsigned i = 0; i < 24; ++i) {
           words[i] = read32(CSR_..._RECORD_WORD0 + 4 * i);
       }

       write32(CSR_..._POP, 1);
       process_record(words); /* Process the local copy. */
   }


Use ordered device register accesses. Writing one to ``CSR_..._SNAPSHOT`` latches the
FIFO head into ``CSR_..._RECORD_WORD0`` through ``CSR_..._RECORD_WORD23``; a request
with no available head captures nothing. Wait for ``CSR_..._SNAPSHOT_VALID`` before copying all
24 words. The snapshot stays stable while new completions arrive. Reading a
word does not advance the FIFO, and there is no random entry index.

After copying, write one to ``CSR_..._POP`` to remove that entry, clear
``CSR_..._SNAPSHOT_VALID`` and release one reservation. Pop without a valid snapshot does nothing. Take
a new snapshot for each entry and use a single consumer for the entire sequence.
If entries are not popped, reservations reach capacity and stall new parents;
incoming samples can then be dropped when acquisition RAM fills. Do not pop
independently while ``HostTCDStream`` owns the stream.

Record fields
-------------

Word indices start at zero. All 64-bit fields store the low word first;
reconstruct them as ``uint64(low) | (uint64(high) << 32)``.

.. list-table:: Table 1. Completion record fields
   :header-rows: 1
   :widths: 12 23 65
   :width: 100%
   :class: hosttcd-terminology hosttcd-record-table

   * - Word(s)
     - Field
     - Description
   * - 0
     - ``epoch``
     - Software stream generation, configured while flushed; identifies the session, not a time value.
   * - 1
     - ``parent_sequence``
     - Parent execution sequence modulo 2^32; advances for repeated loop executions even when addresses repeat.
   * - 2
     - ``flags``
     - Bit 8: IQ12 format (otherwise IQ16); bit 16: valid record; bit 17: gap before parent; bit 18: internal gap; bit 19: timestamp discontinuity without an acquisition gap flag.
   * - 3
     - ``channel_map``
     - Two bits per logical destination; destination ``i`` uses physical channel ``(words[3] >> (2*i)) & 3``, where 0--3 mean A--D.
   * - 4
     - ``channel_count``
     - Number of logical destinations, from 1 to 4.
   * - 5
     - ``physical_channel_mask``
     - Bits 0--3 identify participating physical channels A--D.
   * - 6--13
     - ``dma_base_addresses``
     - Four 64-bit destination addresses in logical order. Destination ``i`` uses low word ``6 + 2*i`` and high word ``7 + 2*i``; unused addresses are zero. These are DMA addresses, not application virtual addresses or descriptor staging addresses.
   * - 14--15
     - ``first_tick``
     - Acquisition tick of the first sample in the parent.
   * - 16--17
     - ``last_block_tick``
     - Acquisition tick of the first sample in the parent's final block, not its final sample.
   * - 18
     - ``samples_per_channel``
     - Total complex samples in each destination buffer.
   * - 19
     - ``bytes_per_channel``
     - Total payload bytes in each destination buffer.
   * - 20
     - ``block_count``
     - Acquisition blocks per channel; a block normally holds 1024 complex samples.
   * - 21
     - ``contiguous_samples``
     - Length of the initial contiguous sample interval per channel.
   * - 22
     - ``first_gap_offset``
     - Sample index of the first internal discontinuity, or ``0xffffffff`` when absent.
   * - 23
     - ``reserved``
     - Zero.


The acquisition counter advances on every valid input frame, including dropped
frames, and all channels share a frame's tick. It resets on acquisition-domain
reset, not ordinary stop/start or buffer flush. Ticks are sample frames, not UTC
or host arrival times. For ``0 <= k < contiguous_samples``, sample ``k`` in every
destination has timestamp ``(first_tick + k) mod 2^64``. Divide tick differences
by the actual sample rate to obtain seconds.

A gap before the parent does not invalidate its contiguous prefix. An internal
gap limits reconstruction to that prefix; this summary cannot reconstruct all
later timestamps. Reject records with flag bit 19 set. Validate the epoch,
sequence, addresses, counts and flags before delivering samples. Apply the
driver's DMA ordering and cache synchronization before reading sample buffers.
Popping metadata releases table capacity; buffer reuse still requires consumer
release and separate ownership tracking.

Obtain register addresses from the loaded bitstream's generated ``csr.csv``.
For BAR0 byte offsets, subtract the LiteX CSR base ``0xf0000000`` from the
addresses listed there.

.. _host-tcd-rx-dma-buffer-layout:

Host DMA buffer layout
======================

Sample format and channel mapping
---------------------------------

``iq12=0`` preserves I16/Q16, producing 4096 bytes per channel slot.
``iq12=1`` selects bits 15:4 of each component, producing 3072 bytes per
channel slot. I precedes Q, samples are in acquisition order, and the first
sample occupies the least significant bits of the first DMA word. The
formatter has a 256-bit output in either mode.

Set HostTCD ``split_size`` to exactly 4096 or 3072 respectively, and set
``bytes_per_channel`` to a positive multiple of that size. Addresses retain
32-byte alignment. HostTCD rejects partial-slot parent lengths and refuses
to run with an incompatible split size. Native 4 KiB address-boundary
fragments may cut an IQ12 sample; formatter state persists across them.

``channel_map`` has four two-bit entries, logical destination zero in bits
1:0. The default ``0xe4`` maps logical indices 0,1,2,3 to physical channels
0,1,2,3. The map must be a permutation; HostTCD ``channel_count`` selects its
first N entries. For example ``0x72`` maps to 2,0,3,1. Duplicate mappings are
rejected by the acquisition path's status check.

Transfer split size
-------------------

``split_size`` controls how many bytes the FPGA schedules for one channel
before switching to the next. For this RX path it must equal 1024 samples:

* IQ16: ``split_size = 4096`` bytes.
* IQ12: ``split_size = 3072`` bytes.

``bytes_per_channel`` is the total buffer length and must be a multiple of
``split_size``. Splitting affects transfer scheduling; samples remain consecutive
in each buffer. PCIe fragments do not add headers or padding.

Buffer ownership
----------------

Match each Completion record FIFO entry to its buffers using the epoch, parent
sequence and DMA addresses. Synchronize DMA memory before CPU access. Reuse a
buffer only after DMA completion and consumer release; popping a timestamp
record alone does not release it.

Stopping and reconfiguration
============================

Disable HostTCD first and keep acquisition running until the current parent
drains and ``busy`` clears. Then stop acquisition, consume completions and
assert ``flush`` before reconfiguration. A parent cannot drain after its sample
supply stops.

Flush changes require stream-start RX enable, HostTCD busy and native writer
enable to be zero. An unsafe request is ignored and reported in status bit 4;
clear the request before continuing. Fatal sequencer or DMA faults require
SoC reset recovery.


.. _host-tcd-rx-status-errors:

Status and error handling
=========================

``SUBMIT_STATUS`` bit 0 reports validation/copy busy, bit 1 acceptance and bit 2
rejection. ``ERRORS`` is sticky: bit 0 invalid parent, bit 1 full table, bit 2
submission in loop mode, bit 3 invalid split size, bit 4 CSR bus failure, bit 5
unexpected DMA retirement, bit 6 reset while busy, bit 7 mode change while busy,
bit 8 missing address, bit 9 staging or submission while busy and bit 10 invalid
address index. Bus failure and unexpected retirement latch a fatal sequencer
fault; clearing error bits alone does not resume execution.

.. _host-tcd-rx-descriptor-csrs:

Descriptor table CSR reference
==============================

.. list-table:: Table 2. Parent descriptor table and configuration CSRs
   :header-rows: 1
   :widths: 40 60
   :width: 100%
   :class: hosttcd-terminology hosttcd-csr-table

   * - CSR name
     - Description
   * - ``RX_HOST_TCD_VERSION``
     - Read-only descriptor table ABI version: 2.
   * - ``RX_HOST_TCD_CAPABILITIES``
     - Read-only capabilities: bits 0--7 give the maximum channel count, bits
       8--23 the parent table depth and bit 24 ordered payload commands. Bit 31
       inhibits execution for table-only builds. The replacement RX path
       supports four channels and 16 parents.
   * - ``RX_HOST_TCD_CHANNEL_COUNT``
     - Stages the participating logical destination count, from 1 to 4.
   * - ``RX_HOST_TCD_BYTES_PER_CHANNEL``
     - Stages the destination payload length per channel; a positive multiple
       of split size.
   * - ``RX_HOST_TCD_FLAGS``
     - Stages parent flags. Bit 0 disables the parent interrupt; bit 1 disables
       early-last termination and is required for multiple channels. Use 2 for
       fixed-length parents with interrupts.
   * - ``RX_HOST_TCD_ADDRESS_INDEX``
     - Selects the logical destination address to stage, from 0 to 3. Physical
       channel selection comes from the RX channel map.
   * - ``RX_HOST_TCD_ADDRESS_HIGH``
     - Stages bits 63:32 of the selected destination DMA address.
   * - ``RX_HOST_TCD_ADDRESS_LOW``
     - Stages bits 31:0 of the selected destination DMA address.
   * - ``RX_HOST_TCD_ADDRESS_WRITE``
     - Write 1 to copy the staged high and low words into the selected address
       entry.
   * - ``RX_HOST_TCD_ADDRESSES_WRITTEN``
     - Read-only initialized-address mask. Successful submission clears it;
       restage every participating address for each parent.
   * - ``RX_HOST_TCD_SUBMIT``
     - Write 1 to validate and enqueue a parent. Keep staging registers
       unchanged until validation and copying finish.
   * - ``RX_HOST_TCD_SUBMIT_STATUS``
     - Read-only result: bit 0 validation/copy busy, bit 1 last submission
       accepted, bit 2 last submission rejected.
   * - ``RX_HOST_TCD_LEVEL``
     - Read-only occupied parent entry count, including active work. Program
       mode consumes entries; loop mode recycles them. This is not the
       completion record count.
   * - ``RX_HOST_TCD_ENABLE``
     - Set to 1 to execute queued parents. Clear to drain the active parent and
       stop; keep acquisition running until busy clears.
   * - ``RX_HOST_TCD_LOOP_PROG_N``
     - Select while stopped: 0 executes parents once in program mode; 1 repeats
       the queued table in loop mode. Stage parents in program mode before
       selecting loop mode.
   * - ``RX_HOST_TCD_RESET``
     - Write 1 while execution is disabled, submission idle and the sequencer
       stopped to clear the table. Active reset requests are rejected; fatal
       sequencer faults require SoC reset.
   * - ``RX_HOST_TCD_SPLIT_SIZE``
     - Channel-block size in bytes: 4096 for IQ16 or 3072 for IQ12 with 1024
       samples per block. Must match the acquisition format.
   * - ``RX_HOST_TCD_COMPLETED_TOTAL``
     - Read-only cumulative retired-parent count, including repeated loop
       executions.
   * - ``RX_HOST_TCD_LOOP_STATUS``
     - Program mode: completed-parent count. Loop mode: current parent index in
       the low table-index bits, followed by the loop iteration count. Index
       width depends on table depth (4 bits for 16 entries).
   * - ``RX_HOST_TCD_ERRORS``
     - Read-only sticky error bitmap; see status and error handling below.
   * - ``RX_HOST_TCD_CLEAR_ERRORS``
     - Write a mask to clear corresponding sticky error bits. Clearing
       diagnostics does not recover a fatal sequencer fault.
   * - ``RX_HOST_TCD_BUSY``
     - Read-only sequencer activity. Wait for 0 after disabling execution
       before changing mode, resetting or stopping acquisition.
   * - ``RX_HOST_TCD_OUTSTANDING``
     - Read-only issued DMA child descriptors awaiting retirement.
   * - ``RX_HOST_TCD_CHILD_ISSUED``
     - Read-only cumulative issued-child count.
   * - ``RX_HOST_TCD_CHILD_COMPLETED``
     - Read-only cumulative retired-child count.
   * - ``RX_HOST_TCD_REJECTED``
     - Read-only rejected-submission count, including submission attempts while
       busy.
   * - ``RX_HOST_TCD_RING_SIZE``
     - Read-only number of parents captured when loop execution starts.

Destination DMA addresses must be 32-byte aligned and cover the entire payload
without wrapping the 64-bit address range. Use positive per-channel lengths
that are multiples of the configured block size. RX format, channel mapping
and epoch are configured in the acquisition path, rather than staged per parent.

Generated C address macros use ``CSR_RX_HOST_TCD_<NAME>_ADDR``. Resolve addresses
from the loaded bitstream's CSR map; see :ref:`host-tcd-rx-descriptor-table`
for the submission algorithm.

.. _host-tcd-rx-acquisition-csrs:

Acquisition and completion CSR reference
========================================

These registers belong to the replacement RX path. The names below omit the
``LIMETOP_RXTX_TOP_RX_PATH_`` prefix used in the current HiperSDR CSR map.
Generated C address macros add ``CSR_`` and ``_ADDR``. The descriptor table
above uses its separate ``RX_HOST_TCD_`` prefix.

.. list-table:: Table 3. Acquisition and completion CSRs
   :header-rows: 1
   :widths: 40 60
   :width: 100%
   :class: hosttcd-terminology hosttcd-csr-table

   * - CSR name
     - Description
   * - ``VERSION``
     - Read-only acquisition/completion ABI version: 2.
   * - ``FLUSH``
     - Defaults to 1. Hold while stopped to clear queues and apply
       configuration. Clear and wait for status bit 0 to clear before
       acquisition. Never flush active DMA.
   * - ``IQ12``
     - Format configuration while flushed: 0 preserves IQ16; 1 packs the upper
       twelve bits of I and Q.
   * - ``CHANNEL_MAP``
     - Four two-bit logical-to-physical indices; must be a permutation. Default
       0xe4 selects A, B, C, D in order. Frozen during operation.
   * - ``EPOCH``
     - Software stream generation, applied while flushed and copied into
       completions.
   * - ``STATUS``
     - Read-only bitmap: bit 0 flush acknowledged, bit 1 capture active, bit 2
       fatal, bit 3 invalid channel map, bit 4 blocked flush request.
   * - ``DROPPED``
     - Read-only live dropped-frame count with clock-crossing synchronization
       delay.
   * - ``BLOCK_SAMPLES``
     - Read-only samples per channel in one acquisition block; normally 1024.
   * - ``BLOCK_BYTES``
     - Read-only bytes per channel block for the active format: normally 4096
       for IQ16 or 3072 for IQ12.
   * - ``METADATA_CAPACITY``
     - Read-only completion reservation capacity; defaults to 256 records.
   * - ``METADATA_LEVEL``
     - Read-only number of completed records available to snapshot.
   * - ``METADATA_RESERVED``
     - Read-only reservations including unfinished parents and unread records.
       Capacity exhaustion stalls new parents.
   * - ``METADATA_RECORD_WORDS``
     - Read-only record length: 24 words.
   * - ``SNAPSHOT``
     - Write 1 to latch the oldest completed record. An empty FIFO captures
       nothing.
   * - ``SNAPSHOT_VALID``
     - Read-only indication that snapshot words are valid and stable.
   * - ``RECORD_WORD0 through RECORD_WORD23``
     - Read-only snapshot words. Read all 24 before popping; 64-bit fields use
       low word first.
   * - ``POP``
     - Write 1 after copying a valid snapshot to remove the record and release
       its reservation. Does nothing without a valid snapshot.
   * - ``IRQ_ENABLE``
     - Enables the acquisition IRQ while a completion is available or the
       acquisition path is fatal; routed to the existing RX MSI.

See :ref:`host-tcd-rx-timestamp-record-fifo` for record fields and the
snapshot/read/pop procedure.
