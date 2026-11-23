FPGA implementation
###################

The acquisition RAM, write path and read/format path are described below.
See :doc:`overview` for the RX data flow.

.. contents:: On this page
   :local:
   :depth: 2


.. _host-tcd-rx-memory-layout:

Memory layout
=============

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

.. figure:: /images/host_tcd_rx/host_tcd_banks_lanes_slots.drawio.svg
   :width: 100%
   :alt: Four channel banks, eight RAM lanes per channel and four slot address regions

   Figure 1. Four channel banks, eight lanes per bank and four slot address regions.
   The highlighted slot spans the same address region across all banks and
   lanes; it is not a separate RAM instance.

.. _host-tcd-rx-write-path:

Writing Samples
===============

The write path stores each accepted four-channel IQ16 frame in sample RAM on
``wr_clk``. For bank, lane and slot definitions, see
:ref:`Memory layout <host-tcd-rx-memory-layout>`.

Write Admission
---------------

``write_fire`` accepts a frame when capture is enabled, ``frame_valid`` is high
and ``wr_flush`` is low. A new slot must be free, with room to publish its
completion descriptor. Once reserved, the slot receives the same acquisition
interval in all four banks.

Write Address Calculation
-------------------------

``wr_slot`` selects the slot and ``wr_offset`` selects the sample position
within it. All banks use the same lane and address:

.. code-block:: text

   ROWS        = SLOT_SAMPLES / 8
   lane        = wr_offset mod 8
   RAM address = wr_slot * ROWS + wr_offset / 8

Division is integer division. The address selects a 32-bit word within one
lane, not a byte. With ``SLOT_SAMPLES=1024``, each slot occupies 128 rows.

In the diagram below, addresses increase downward. Successive writes move
across lanes 0--7 before advancing to the next row. Each lane therefore receives
one write for every eight accepted frames.

.. figure:: /images/host_tcd_rx/host_tcd_slot_address_direction.drawio.svg
   :width: 100%
   :alt: RAM addresses increase downward while writes move across lanes then down one row

   Figure 2. Orange arrows show sample write order within one channel's slot.

For ``wr_slot=2`` and ``wr_offset=13``, the calculation gives:

.. code-block:: text

   lane        = 13 mod 8 = 5
   RAM address = 2 * 128 + 13 / 8 = 257

The next diagram follows that frame from ``frame_data`` into RAM. Each bank
receives its own 32-bit channel sample at lane 5, address 257. Samples 8--12
already occupy lanes 0--4 at this address; samples 14 and 15 will fill lanes 6
and 7 on subsequent accepted frames.

.. figure:: /images/host_tcd_rx/host_tcd_rx_ram_write.drawio.svg
   :width: 100%
   :alt: Frame 13 writes lane 5 address 257 in all four channel banks

   Figure 3. One frame writes A13, B13, C13 and D13 into their respective banks together.
   Sample numbers are offsets within the slot, not acquisition timestamps.

Write Timing and Slot Advancement
---------------------------------

``ram_write_pipeline_proc`` first captures ``wr_data_r``, ``wr_addr_r`` and
``wr_en_r``. On the next rising edge, ``ram_write_proc`` commits the sample.
Thus, with continuous input, one frame is registered while the previous frame
is written to RAM. Advancing the write position does not change the pending
write's registered address.

Each accepted frame increments ``wr_offset``. After ``SLOT_SAMPLES`` frames,
it returns to zero and ``wr_slot`` advances, wrapping after the final slot.
Invalid or dropped frames do not advance this position. The timeline below
shows the first slot's final sample committing while the next slot's first
sample is registered; all four banks follow the same progression.

.. figure:: /images/host_tcd_rx/host_tcd_rx_fill_cycles.drawio.svg
   :width: 100%
   :alt: Cycle-by-cycle write registration, RAM commits and the transition from slot 0 to slot 1

   Figure 4. Continuous accepted frames, including the one-clock write pipeline and
   the slot 0 to slot 1 transition.

Slot Completion and Overflow
----------------------------

The first stored frame captures the slot's acquisition tick. The final frame
raises ``slot_valid`` with ``slot_index``, ``slot_tick`` and ``slot_gap``;
these remain available until ``slot_ready`` accepts the descriptor. The final
RAM write commits one clock after frame acceptance. The external ownership
FIFO's clock crossing prevents readout from seeing uncommitted data.

The writer can reuse a slot only after readout releases it. The AFE cannot be
paused: if a frame cannot be accepted, all four channel samples are dropped.
The acquisition counter still advances on every valid input frame, so the next
stored slot carries its actual first tick and a gap flag. The wrapper exposes
the dropped-frame count through the ``dropped`` CSR, with synchronization delay.

.. _host-tcd-rx-read-path:

Reading Samples
===============

The read path runs on ``rd_clk`` and retrieves one completed slot from one
selected channel at a time. It packs the samples as IQ16 or IQ12 and emits a
256-bit stream. For bank, lane and slot definitions, see
:ref:`Memory layout <host-tcd-rx-memory-layout>`.

Channel Selection and Read Address
----------------------------------

A command is accepted when ``command_valid`` and ``command_ready`` are both
asserted. ``readout_proc`` latches ``command_slot``, ``command_channel`` and
``command_iq12``, then starts at ``rd_row=0``. All eight lanes of the selected
channel bank use the same RAM address:

.. code-block:: text

   ROWS        = SLOT_SAMPLES / 8
   RAM address = rd_slot * ROWS + rd_row

Each ``read_fire`` retrieves eight consecutive IQ16 samples and advances
``rd_row`` until the final row. For ``rd_slot=2`` and ``rd_row=1`` with the default geometry,
address 257 returns sample positions 8--15 from that slot. Other channel banks
are not read.

.. figure:: /images/host_tcd_rx/host_tcd_rx_ram_read.drawio.svg
   :width: 100%
   :alt: Reading address 257 in all eight lanes of channel C retrieves samples 8 through 15

   Figure 5. Read example after slot completion: ``rd_channel=2``, ``rd_slot=2``,
   ``rd_row=1``. All eight lanes of channel C read address 257 in parallel.

IQ Packing and Output
---------------------

``ram_read_proc`` registers the lane outputs in ``bank_data``. On the next
``rd_clk`` edge, ``packing_proc`` selects the channel and registers its packed
samples. IQ16 preserves all 256 bits; IQ12 keeps bits 15:4 of each I and Q
component, producing 192 useful bits per RAM read. The reservoir combines
successive packed reads into complete 256-bit output words, accepted when
``source_valid`` and ``source_ready`` are both asserted.

Slot Ownership and Backpressure
-------------------------------

The scheduler retains each completed-slot descriptor while reading every
requested channel. It returns the slot through the ``released_slots``
asynchronous FIFO only after all requested channel data has been accepted into
the output FIFO.
RAM is never overwritten while owned by the reader. Stalls propagate from DMA
through the output FIFO, formatter and synchronous-read capacity tracker.
The tracker reserves room for read results already in flight.

Read reservations are registered in 64-bit units, removing the combinational
path from DMA backpressure through capacity arithmetic to the RAM read enable.
The formatter holds four DMA words, allowing one IQ16 output beat per processing
clock once output starts and while the sink remains ready. IQ12 appends packed
data at fixed 64-bit boundaries rather than using a bit-addressed barrel shifter.

RX version 2 aggregates slot metadata into one completion per HostTCD parent
execution, across all requested channels.


Timing and TX synchronization
=============================

The 64-bit acquisition counter advances on every valid input frame, including
frames dropped due to full sample storage. It is supplied directly to the
existing TX sample-number synchronization interface in the acquisition clock
domain. A software buffer flush does not reset this timer; FPGA reset does.
Timestamp tick units are sample frames, not DMA words or bytes.

The read scheduler associates each selected interval with its stored first
tick. A separate ordered association FIFO follows native descriptors until
the LitePCIe table retires them. Completion is published at retirement of
the last fragment of the entire parent, across all channels. This means the DMA writer has
emitted the writes; it is not a PCIe acknowledgement or a replacement for
the driver's DMA mapping, ordering and cache synchronization requirements.

Validation and device limits
============================


The regression suite includes a GHDL testbench for the actual VHDL RAM and
formatter, plus a control integration test using the real LitePCIe DMA writer::

    python -m unittest discover -s tools/tests -v

The VHDL testbench also accepts ``TEST_SLOT_SAMPLES`` and ``STALL_OUTPUT``
generics. Regression runs cover 32-sample and 1024-sample slots with stalls,
plus 1024-sample slots with an always-ready sink and an IQ16 throughput check.

The November 3 full-board timing review found WNS -0.677 ns, TNS -1253.854 ns
and 5407 failing setup endpoints. Detailed queries of the routed checkpoint
identified a -0.649 ns command-FIFO-to-buffer path and a -0.439 ns internal
channel-select-to-reservoir path. The acquisition-side buffer paths met setup
timing with only +0.014 ns margin.

The command FIFO now has a registered output, and command validation runs one
cycle before admission. Its reservation limit still includes every queued
command, including the buffered output slot. The VHDL formatter registers
channel selection and IQ truncation before reservoir insertion. A four-word
reservoir reserves capacity for both RAM and packing stages, preserving one
IQ16 beat per clock after startup. These changes leave the CSR and sample
formats unchanged.

The revised buffer was routed out of context at write/read clocks of
525/300 MHz on ``xcau15p-ffvb676-2-i``: WNS +0.374 ns overall and +0.537 ns
in the processing domain, with no setup/hold failures. It uses 32 RAMB18
primitives, 2579 LUTs and 2694 registers. These isolated results exclude module
I/O paths and do not qualify full-board timing.

Use the repository's LiteX dependency when generating RTL (for example,
``PYTHONPATH=deps/litex``). The configured system interpreter's older LiteX
does not support the VHDL converter arguments already used by this project.
LimeTop with the replacement RX path was elaborated using the repository
dependency, including the existing TX path.

The VHDL core was synthesized out of context with Vivado 2022.2 for Artix-7
``xc7a200tfbg676-2`` and Artix UltraScale+ ``xcau15p-ffvb676-2-i``. Both infer
32 RAMB18 primitives for sample RAM. This checks inference, not timing closure.
Cyclone V synthesis remains unverified: the local Quartus installation lacks
Cyclone V device support. A full board image and routed report are now available,
but the inspected report does not meet timing.

The default direct-write design still requires acquisition BRAM/control to
meet the actual interface clock. This option retains the board's existing
clock generation: ``afe`` is currently 525 MHz and input valid marks sample
frames; 491.52 MSps is the intended sample rate, not a new generated clock.
The processing path must sustain average traffic:
all four channels at 491.52 MSps require 7.86432 GB/s for IQ16 or 5.89824 GB/s
for IQ12, before PCIe overhead. Finite BRAM cannot compensate for insufficient
sustained DMA throughput. Board-level clock constraints, placement/routing
and hardware acquisition tests remain necessary before deployment.
