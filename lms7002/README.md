# lms7002_top

## Description
Top module for LMS7002M IC digital interface.

**Functionality:**
- Transmit IQ samples trough s_axi_tx AXI Stream bus
- Receive IQ samples from m_axi_rx AXI Stream bus

**LimeLight digital modes implemented:**
- TRXIQ PULSE
- MIMO DDR
- SISO DDR
- SISO SDR


Detailed IO port description and waveforms can be found [here](./doc/lms7002_top.md).

## Main block diagram:

![top.svg](doc/top.svg)

