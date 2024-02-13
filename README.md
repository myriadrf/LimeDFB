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
|[m_to_axi_lite](https://github.com/myriadrf/LimeIP_HDL/tree/main/m_to_axi_lite)| v0.0 | :yellow_circle: dev | Converts general data bus with data valid signals to AXI4-Lite master interface |
|[gt_channel](https://github.com/myriadrf/LimeIP_HDL/tree/main/gt_channel)| v0.0 | :yellow_circle: dev | Send/receive data trough transceivers (Aurora 8b10b) |
|[lms7002](https://github.com/myriadrf/LimeIP_HDL/tree/main/lms7002)| v0.0 | :yellow_circle: dev | Top module for LMS7002M IC digital interface |

