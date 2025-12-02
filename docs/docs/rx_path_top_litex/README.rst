rx_path_top (LiteX)
===================

Description
-----------
Top module for packaging IQ samples received from the RF transceiver into stream packets.

**Functionality:**
   - Pack IQ samples from the stream sink into packets and write them into a FIFO buffer.
   - Pack 12-bit IQ samples into 128-bit words to efficiently use data-transfer bandwidth.
   - Store stream packets in an AXI-Stream (AXIS) buffer.


Main block diagram
------------------


The top-level file integrates the following main blocks:


- :ref:`Channel combiner (chnl_combiner) <chnl_combiner>` – Selects the channels for data collection and combines them into 128-bit words.
- :ref:`Bit Width Selector (BitWidthSelector) <bit_width_selector>` – Selects bit width for IQ samples
- :ref:`Packet forming state machine (Data2packetsFSM) <data_to_packets_fsm>` – Packet formation logic
- :ref:`Sample Synchronization Counter (smpl_cnt0) <sample_counter>` – Sample synchronization counter for TX path
- :ref:`Source Endpoint Conversion (ep_conv) <source_conversion>` – Converts source endpoint from internal 128-bit width to the desired source width
- :ref:`Source Endpoint CDC (source_ep_cdc) <source_cdc>` – Source Endpoint clock domain crossing 


This diagram represents the top-level Receive (RX) path. Its primary function is to ingest streaming data (IQ samples), adjust its bit-width, format it into packets, and transfer it safely from the input clock domain to the system's main clock domain.

.. image:: block_diagram.drawio.svg
   :align: center
   :alt: rx_path_top block diagram


Clock domains
^^^^^^^^^^^^^

This module operates in two clock domains:
   - **Sink clock domain** — The left side of the diagram operates in the sink clock domain.
   - **Source clock domain** — The far-right output operates on a different clock (source clock).


.. _chnl_combiner:


Channel Combiner
^^^^^^^^^^^^^^^^


This block interfaces with the sink bus where multiple IQ channels are interleaved. It filters for a specific, user-configured channel and consolidates those samples into 128-bit-wide words.

**Example Scenario:**
If the RX path receives four channels spaced across the 128-bit input bus, but the module is configured to capture only Channel A:

   1. The block isolates samples belonging to Channel A.
   2. It discards data from the other three channels.
   3. It accumulates the Channel A samples until they fill a 128-bit word.
   4. The output is a 128-bit stream containing only interleaved Channel A data.


.. _bit_width_selector:

Bit Width Selector
^^^^^^^^^^^^^^^^^^

This module packs 12-bit samples into 128-bit words, or—if samples are 16-bit—passes them through to 128-bit words. This block has two data paths, which are selected with a multiplexer and demultiplexer:

   1.  **Gearbox Path:** Used when IQ samples are 12-bit wide. The ``ep_gearbox`` module takes 96 bits from the sink bus and packs them into a 128-bit bus.
   2.  **Bypass Path:** Used when IQ samples are 16-bit wide. The sink bus is directly connected to the source.

A First-In-First-Out buffer, ``source_fifo``, located at the output of this block is used to handle back-pressure. 


.. _data_to_packets_fsm:

Packet forming state machine
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

This block transforms a continuous stream of IQ data into packets. Packets consist of a 64-bit header, a 64-bit sample counter, and a payload of configurable size. It uses the following internal modules:
   
   * ``data2packets_fsm``: A finite state machine that controls the packet generation flow. It manages packet-forming logic and controls the writing of data into the FIFO.
   * ``smpl_cnt1``: The sample counter tracks the number of IQ samples processed. It is used to generate sequence numbers/timestamps for packet headers.
   * ``source_fifo``: A secondary buffering stage that stores the organized packet data and handles back-pressure.


+----------------+---------------+------------+----------------------------------------------------------------------------------------+
| Field          | Byte Offset   | Size       | Description                                                                            |
+================+===============+============+========================================================================================+
| **Header**     | 0 - 7         | 8 Bytes    | General packet header.                                                                 |
+----------------+---------------+------------+----------------------------------------------------------------------------------------+
| **Counter**    | 8 - 15        | 8 Bytes    | Sample counter (increased for each IQ sample frame).                                   |
+----------------+---------------+------------+----------------------------------------------------------------------------------------+
| **Payload**    | 16 - 4095     | 4080 Bytes | Payload structure depends on the channels enabled:                                     |
|                |               |            |                                                                                        |
|                |               |            | **Channel A enabled:**                                                                 |
|                |               |            |                                                                                        |
|                |               |            | [AI0, AQ0, AI1, AQ1, ... , AIn, AQn]                                                   |
|                |               |            |                                                                                        |
|                |               |            | **Channels A and B enabled:**                                                          |
|                |               |            |                                                                                        |
|                |               |            | [AI0, AQ0, BI0, BQ0, ... , AIn, AQn, BIn, BQn]                                         |
|                |               |            |                                                                                        |
|                |               |            | **Channels A, B, C, and D enabled:**                                                   |
|                |               |            |                                                                                        |
|                |               |            | [AI0, AQ0, BI0, BQ0, CI0, CQ0, DI0, DQ0, ... , AIn, AQn, BIn, BQn, CIn, CQn, DIn, DQn] |
|                |               |            |                                                                                        |
+----------------+---------------+------------+----------------------------------------------------------------------------------------+

.. _sample_counter:

Sample Synchronization Counter
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

This 64-bit counter is used for TX sample synchronization. It counts incoming samples, incrementing on a valid/ready handshake on the sink stream bus.


.. _source_conversion:

Source Endpoint Conversion
^^^^^^^^^^^^^^^^^^^^^^^^^^

In cases where downstream modules expect a wider/narrower bus width, the ``ep_conv`` module converts the source endpoint from an internal 128-bit width to the desired source width. It is up to the user to calculate the proper bus width and use a fast-enough clock source to handle the desired bandwidth.


.. _source_cdc:

Source Endpoint CDC
^^^^^^^^^^^^^^^^^^^^^^^^^^

In cases where downstream modules expect a different clock domain, the asynchronous FIFO ``source_ep_cdc`` module is used to ensure proper clock-domain crossing.

Timing diagram
------------------

This timing diagram can be used as a reference to get familiar with module behavior.

.. wavedrom::

   { signal: [
   { name: "CLK",  wave: "P........" , period: 2},
   { name: "RESET_N", wave: "0.1......|...|...." },
   { name: "CFG_CH_EN[1:0]",  wave: "x.=......|=.=|....", data: ["0x3", "0x3", ""] },
   { name: "CFG_SMPL_WIDTH[1:0]",  wave: "x.=......|=.=|....", data: ["0x2", "0x2", ""] },
   { name: "CFG_PKT_SIZE[15:0]",  wave: "x.=......|=.=|....", data: ["0x100", "0x100", ""] },
   ['S_AXIS_IQSMPLS',
    { name: "SINK_ACLK",  wave: "P........" , period: 2},
    { name: "SINK_ARESETN", wave: "0.1......|...|...." },
    { name: "SINK_TVALID", wave: "0...1....|...|...." },
    { name: "SINK_TDATA[63:48]",  wave: "x...=.=.=|=.=|....", data: ["BQ(0)", "BQ(n+5)", "", "BQ(679)", "", "BQ(5)"] },
    { name: "SINK_TDATA[47:32]",  wave: "x...=.=.=|=.=|....", data: ["BI(0)", "BI(n+5)", "", "BI(679)", "", "BI(5)"] },
    { name: "SINK_TDATA[31:16]",  wave: "x...=.=.=|=.=|....", data: ["AQ(0)", "AQ(n+5)", "", "AQ(679)", "", "AQ(5)"] },
    { name: "SINK_TDATA[15: 0]",  wave: "x...=.=.=|=.=|....", data: ["AI(0)", "AI(n+5)", "", "AI(679)", "", "AI(5)"] },
    { name: "SINK_TKEEP[7: 0]",  wave: "x...=...=|=.=|....", data: ["0xFF", "", "0xFF", ""] },
    { name: "SINK_TREADY", wave: "0...1....|...|...." },
    { name: "SINK_TLAST", wave: "0........|...|...." },
   ],
   { name: "SMPL_NR_OUT[63: 0]",  wave: "x...=.=.=|=.=|....", data: ["0", "n+5", "", "679", ""] },
   ['M_AXIS_IQPACKET',
    { name: "SOURCE_ACLK",  wave: "P........" , period: 2},
    { name: "SOURCE_ARESETN", wave: "0.1..............." },
    { name: "SOURCE_TVALID", wave: "0.......1........." },
    { name: "SOURCE_TDATA[127:0]",  wave: "x.......=.=.=|=.=.", data: ["HDR", "PLD(0)", "", "PLD(254)", "",] },
    { name: "SOURCE_TKEEP[7: 0]",  wave: "x.......=...=|=...", data: ["0xFF", "", "0xFF"] },
    { name: "SOURCE_TREADY", wave: "0...1............." },
    { name: "SOURCE_TLAST", wave: "0............|1.0." },
   ]
   ],
      "config" : { "hscale" : 1 },
    head:{
       text: ['tspan',
             ['tspan', {'font-weight':'bold'}, 'rx_path_top module timing (MIMO DDR mode, A and B channels enabled, 12b samples, 4096B packet size)']],
       tick:0,
       every:2
     }}