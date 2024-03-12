# gpio_top

## Description
Basic module for controlling various GPIO signals. 
Designed to be connected straight to vendor-specific tri-state IO buffers. 

**Functionality:**
- Provides a method to override regular output value
- Reading IO value always returns actual value of the port, regardless of GPIO direction chosen

Detailed IO port description and waveforms can be found [here](./doc/gpio_top.md).

