# LimeIP_HDL

## Description
This repo is ment to be used as **public** location to share code between Lime Microsystems FPGA design projects. 

## Contributing
If you are new here then before commiting any changes or adding any new modules review:
 [coding_guidelines](https://github.com/myriadrf/LimeIP_HDL/blob/main/doc/coding_guidelines.md)

**All modules should have:**
- Self checking test bench
- Document with description what it does and how to use it

## Available modules
Here you can find summary of available modules and their status. <br>

**Status description:** <br>
- :yellow_circle: dev  - module is still under development <br>
- :green_circle: prod - module is tested and proven to be functional

| Module | Version | Status | Description |
| ---  | --- | --- | --- |
|[axis_fifo](./axis_fifo/)| v0.0 | :yellow_circle: dev | AXI Stream FIFO implementation with dual port RAM
|[m_to_axi_lite](https://github.com/myriadrf/LimeIP_HDL/tree/main/m_to_axi_lite)| v0.0 | :yellow_circle: dev | Converts general data bus with data valid signals to AXI4-Lite master interface |
|[gt_channel](https://github.com/myriadrf/LimeIP_HDL/tree/main/gt_channel)| v0.0 | :yellow_circle: dev | Send/receive data trough transceivers (Aurora 8b10b) |
|[lms7002](https://github.com/myriadrf/LimeIP_HDL/tree/main/lms7002)| v0.0 | :yellow_circle: dev | Top module for LMS7002M IC digital interface |
|[gpio_top](https://github.com/myriadrf/LimeIP_HDL/tree/main/gpio_top)| v0.0 | :yellow_circle: dev | Basic Module for GPIO control
|[rx_path_top](./rx_path_top/)| v0.0 | :yellow_circle: dev | Receive and pack IQ samples into Stream packets
|[tx_path_top](./tx_path_top/)| v0.0 | :yellow_circle: dev | Unpack packets into IQ samples, perform synchronisation

