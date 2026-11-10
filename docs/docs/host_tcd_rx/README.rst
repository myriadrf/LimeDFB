HostTCD RX
==========

Four-channel sample storage, channel-selective IQ16/IQ12 formatting and
timestamp completions for HostTCD-driven RX DMA.

Memory Layout
-------------

Samples arrive as frames on the 128-bit ``frame_data`` bus. Each valid frame
contains one simultaneous complex sample from each of the four channels
A, B, C and D. Each channel occupies 32 bits: 16-bit I (in-phase) followed
by 16-bit Q (quadrature), with I in the lower bits. Channel A occupies bits
31:0, B occupies 63:32, C occupies 95:64 and D occupies 127:96.

The sample memory is implemented using FPGA **BRAM** (Block Random Access
Memory), the FPGA's dedicated on-chip RAM resources. The following terms
describe the incoming data and its organization in memory:

* **Frame**: one 128-bit input word containing four simultaneous complex
  samples, one from each channel A, B, C and D. 
* **Bank**: the sample memory for one channel. There are four banks, one each
  for channels A, B, C and D. Every accepted frame writes one complex sample
  into each bank at the same time.
* **Lane**: one independent 32-bit-wide RAM array within a bank. Each bank has
  eight lanes. Consecutive samples are written to lanes 0 through 7 in turn;
  reading all eight lanes at the same row returns eight consecutive samples.
  Each 32-bit sample contains 16-bit I (in-phase) and 16-bit Q (quadrature).
* **Slot**: a reusable address region across all lanes of a bank, holding
  ``SLOT_SAMPLES`` samples per channel. The same slot index is used across all
  four banks, so it identifies the same acquisition interval for every channel.
  With the defaults, each slot occupies 128 rows in each lane and holds 1024
  samples per channel. A slot is an address region, not a separate RAM instance.


With the default settings, each bank contains four slots of 1024 IQ16 samples,
giving 16 KiB per bank and 64 KiB overall. Writes distribute consecutive samples
across eight 32-bit lanes. Reading all eight lanes at the same address returns
eight consecutive samples as a 256-bit word.

.. figure:: images/host_tcd_banks_lanes_slots.drawio.svg
   :width: 100%
   :alt: Four channel banks, eight RAM lanes per channel and four slot address regions

   Four channel banks, eight lanes per bank and four slot address regions.
   The highlighted slot spans the same address region across all banks and
   lanes; it is not a separate RAM instance.

The write path stores each accepted input frame in all four channel banks.
See :doc:`Writing Samples <host_tcd_rx_write>` for write admission, address
calculation, sample ordering and slot-filling diagrams.

The read path retrieves a completed slot from a selected channel and formats
its samples into a 256-bit stream. See :doc:`Reading Samples <host_tcd_rx_read>`
for channel selection, address calculation, IQ packing and slot release.

.. toctree::
   :hidden:

   host_tcd_rx_write
   host_tcd_rx_read


Timestamp table
---------------

RX path publishes one timestamp record when the final native DMA child of
a parent retires, across all requested channels. The default FIFO holds 256
records, each containing 24 32-bit words (96 bytes). Use the loaded bitstream's
generated CSR map for register addresses with the ``CSR_LIMETOP_RXTX_TOP_RX_PATH_``
prefix. Below, ``CSR_..._`` abbreviates this prefix.

Reading entries
~~~~~~~~~~~~~~~

Read the oldest completed parent through the snapshot registers. Poll
``CSR_..._METADATA_LEVEL``, or check it after an RX interrupt.
``CSR_..._METADATA_RESERVED`` includes
unfinished parents as well as unread completions; it is not the readable count.

.. code-block:: text

   while read32(CSR_..._METADATA_LEVEL) != 0:
       write32(CSR_..._SNAPSHOT, 1)
       wait until read32(CSR_..._SNAPSHOT_VALID) == 1, with a timeout
       for i in 0..23:
           words[i] = read32(CSR_..._RECORD_WORD0 + 4*i)
       write32(CSR_..._POP, 1)
       process the local copy of words


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
~~~~~~~~~~~~~

Word indices start at zero. All 64-bit fields store the low word first;
reconstruct them as ``uint64(low) | (uint64(high) << 32)``.

.. list-table:: Timestamp record fields
   :header-rows: 1
   :widths: 12 23 65

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

