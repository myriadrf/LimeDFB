
# Entity: RX_PATH_TOP 
- **File**: rx_path_top.vhd

## Diagram
![Diagram](RX_PATH_TOP.svg "Diagram")
## Description

Top module for packaging IQ samples received from lms7002 module into stream packets.

Functionality: - Pack IQ samples from s_axis_iqsmpls stream int Stream packets - Store Stream packets into AXIS buffer.





![alt text](wavedrom_VZPF0.svg "title")

 


## Generics

| Generic name                   | Type    | Value | Description |
| ------------------------------ | ------- | ----- | ----------- |
| G_S_AXIS_IQSMPLS_BUFFER_WORDS  | integer | 16    |             |
| G_M_AXIS_IQPACKET_BUFFER_WORDS | integer | 512   |             |

## Ports

| Port name       | Direction | Type                          | Description                                           |
| --------------- | --------- | ----------------------------- | ----------------------------------------------------- |
| CLK             | in        | std_logic                     | Sys clock                                             |
| RESET_N         | in        | std_logic                     | Sys active low reset                                  |
| SMPL_NR_OUT     | out       | std_logic_vector(63 downto 0) | Sample Nr. output, synchronous to S_AXIS_IQSMPLS_ACLK |
| S_AXIS_IQSMPLS  | in        | Virtual bus                   | AXI Stream Slave bus for IQ samples                   |
| M_AXIS_IQPACKET | out       | Virtual bus                   | AXI Stream Master bus for Stream packets              |
| CFG             | in        | Virtual bus                   | Configuration signals                                 |
| SMPL_NR_IN      | in        | Virtual bus                   | Sample Nr. input                                      |
| TXFLAGS         | in        | Virtual bus                   | TX Flag capture                                       |

### Virtual Buses

#### S_AXIS_IQSMPLS

| Port name              | Direction | Type                          | Description                                                           |
| ---------------------- | --------- | ----------------------------- | --------------------------------------------------------------------- |
| S_AXIS_IQSMPLS_ACLK    | in        | std_logic                     |                                                                       |
| S_AXIS_IQSMPLS_ARESETN | in        | std_logic                     |                                                                       |
| S_AXIS_IQSMPLS_TVALID  | in        | std_logic                     |                                                                       |
| S_AXIS_IQSMPLS_TREADY  | out       | std_logic                     | Indicates when FIFO comes out of reset. Slave can allways accept data |
| S_AXIS_IQSMPLS_TDATA   | in        | std_logic_vector(63 downto 0) |                                                                       |
| S_AXIS_IQSMPLS_TKEEP   | in        | std_logic_vector(7 downto 0)  |                                                                       |
| S_AXIS_IQSMPLS_TLAST   | in        | std_logic                     |                                                                       |
#### M_AXIS_IQPACKET

| Port name               | Direction | Type                          | Description |
| ----------------------- | --------- | ----------------------------- | ----------- |
| M_AXIS_IQPACKET_ACLK    | in        | std_logic                     |             |
| M_AXIS_IQPACKET_ARESETN | in        | std_logic                     |             |
| M_AXIS_IQPACKET_TVALID  | out       | std_logic                     |             |
| M_AXIS_IQPACKET_TREADY  | in        | std_logic                     |             |
| M_AXIS_IQPACKET_TDATA   | out       | std_logic_vector(63 downto 0) |             |
| M_AXIS_IQPACKET_TKEEP   | out       | std_logic_vector(7 downto 0)  |             |
| M_AXIS_IQPACKET_TLAST   | out       | std_logic                     |             |
#### CFG

| Port name      | Direction | Type                          | Description                                                 |
| -------------- | --------- | ----------------------------- | ----------------------------------------------------------- |
| CFG_CH_EN      | in        | std_logic_vector(1 downto 0)  | Channel enable. 0- Channel Disabled, 1-Channel Enabled      |
| CFG_SMPL_WIDTH | in        | std_logic_vector(1 downto 0)  | Sample width selection. "10"-12bit, "01"-14bit, "00"-16bit; |
| CFG_PKT_SIZE   | in        | std_logic_vector(15 downto 0) | Paket size in 128b words. Min=4, Max=256.                   |
#### SMPL_NR_IN

| Port name   | Direction | Type                          | Description             |
| ----------- | --------- | ----------------------------- | ----------------------- |
| SMPL_NR_EN  | in        | std_logic                     | Enable sample number    |
| SMPL_NR_CLR | in        | std_logic                     | Cleas sample number     |
| SMPL_NR_LD  | in        | std_logic                     | Load sample number      |
| SMPL_NR_IN  | in        | std_logic_vector(63 downto 0) | Sample Nr. when loading |
#### TXFLAGS

| Port name            | Direction | Type      | Description               |
| -------------------- | --------- | --------- | ------------------------- |
| TXFLAGS_PCT_LOSS     | in        | std_logic | TX packet loss flag input |
| TXFLAGS_PCT_LOSS_CLR | in        | std_logic | TX packet loss flag clear |

## Signals

| Name                        | Type                                                                                      | Description |
| --------------------------- | ----------------------------------------------------------------------------------------- | ----------- |
| axis_iqcombined             | t_AXI_STREAM(tdata( 63 downto 0),<br><span style="padding-left:20px"> tkeep( 7 downto 0)) |             |
| axis_iqbitpacked            | t_AXI_STREAM(tdata( 63 downto 0),<br><span style="padding-left:20px"> tkeep( 7 downto 0)) |             |
| axis_iq128                  | t_AXI_STREAM(tdata(127 downto 0),<br><span style="padding-left:20px"> tkeep(15 downto 0)) |             |
| axis_iqsmpls_fifo           | t_AXI_STREAM(tdata(127 downto 0),<br><span style="padding-left:20px"> tkeep(15 downto 0)) |             |
| axis_iqpacket_fifo          | t_AXI_STREAM(tdata(127 downto 0),<br><span style="padding-left:20px"> tkeep(15 downto 0)) |             |
| axis_iqpacket               | t_AXI_STREAM(tdata(127 downto 0),<br><span style="padding-left:20px"> tkeep(15 downto 0)) |             |
| axis_iqpacket_wr_data_count | std_logic_vector(8 downto 0)                                                              |             |
| sample_nr_counter           | unsigned(63 downto 0)                                                                     |             |
| bitpacked_sample_nr_counter | unsigned(63 downto 0)                                                                     |             |
| cfg_pkt_size_mul8           | std_logic_vector(15 downto 0)                                                             |             |
| cfg_pkt_size_div128         | std_logic_vector(15 downto 0)                                                             |             |
| pkt_size                    | std_logic_vector(15 downto 0)                                                             |             |

## Processes
- SAMPLE_CNT_PROC: ( S_AXIS_IQSMPLS_ACLK, S_AXIS_IQSMPLS_ARESETN )
- PACKET_SAMPLE_CNT_PROC: ( CLK, RESET_N )
- unnamed: ( all )

## Instantiations

- inst_iq_stream_combiner: work.iq_stream_combiner
- inst_bit_pack: work.bit_pack
- inst_axis_nto1_converter: work.axis_nto1_converter
- inst_axis_iqsmpls_fifo: work.fifo_axis_wrap
- inst_data2packets_fsm: work.data2packets_fsm
- inst_axis_dwidth_converter_128_to_64: axis_dwidth_converter_128_to_64
