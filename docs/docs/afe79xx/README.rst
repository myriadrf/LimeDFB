afe79xx
=======

Top-level module for the AFE7901 IC digital interface.

Functionality
-------------

**Receive Path (RX):**

- Receives IQ samples from the AFE7901 IC via the JESD core.
- Deinterleaves incoming data to restore sample order.
- Performs channel multiplexing to align AFE channels with system channels.
- Decimates received IQ samples to match system rates.

**Transmit Path (TX):**

- Transmits IQ samples to the AFE7901 IC.
- Interleaves data as required by the JESD protocol.
- Performs channel multiplexing to map system channels to the AFE7901 channels.
- Interpolates data to match the required transmission rate.

Main Block Diagram
------------------

The top-level file integrates the following main blocks:

- :ref:`AFE79xx JESD IP Core <afe79xx_jesd_ip_top_module>` – Digital JESD interface to the AFE79xx.
- :ref:`TX/RX CDC <txrx_cdc_module>` – Clock-domain crossing for TX/RX paths.
- :ref:`TX/RX Converters <txrx_conv_module>` – Bus width converters.
- :ref:`Interleaver/Deinterleaver <interleaver_module>` – Sample interleaving and deinterleaving.
- :ref:`TX/RX Channel Multiplexer <txrx_channel_mux_module>` – Channel reordering and mapping.
- :ref:`Resamplers <resamplers_module>` – Interpolation (TX) and decimation (RX).

.. drawio-image:: afe79xx.drawio
   :align: center
   :format: svg
   :page-index: 0
   :alt: Main block diagram for afe79xx module


.. _afe79xx_jesd_ip_top_module:

AFE79xx JESD IP Core
^^^^^^^^^^^^^^^^^^^^
The Texas Instruments JESD IP core.

.. note::
    This core is external and is not included with the LimeDFB distribution.

.. _txrx_cdc_module:

TX/RX CDC
^^^^^^^^^
Manages Clock Domain Crossing (CDC) between the clock domain used by the JESD core and the main system clock.

.. _txrx_conv_module:

TX/RX Converters
^^^^^^^^^^^^^^^^
Adapts the data bus width, converting between the 128-bit bus used by system modules and the 256-bit bus required by the JESD core.

.. _interleaver_module:

Interleaver/Deinterleaver
^^^^^^^^^^^^^^^^^^^^^^^^^
The JESD core operates on interleaved samples. This module performs the necessary interleaving (TX) and deinterleaving (RX) to ensure correct sample ordering.

.. _txrx_channel_mux_module:

TX/RX Channel Multiplexer
-------------------------
The physical mapping of JESD/AFE channels does not correspond 1:1 with system/board channels. This multiplexer performs the necessary channel reordering to ensure correct signal routing.

.. _resamplers_module:

Resamplers
----------

The Resampler module implements configurable upsampling (TX) and downsampling (RX) via a cascade of 2x filters.

* **Architecture:** Cascade of 2x interpolating (HB1) or decimating (HB2d) filters.
* **Resampling Ratios:** Configurable cascade length. A length of 3 (shown below) enables 1x, 2x, 4x, and 8x rates.
* **Precision:** Filters operate on 18-bit I/Q samples, utilizing padding and truncation stages to interface with the 16-bit bus.

.. note::
   The diagram below simplifies the view by showing a single sample path; however, the hardware processes both I and Q channels in parallel.

.. drawio-image:: resampler.drawio
   :align: center
   :format: svg
   :page-index: 0
   :alt: Resampler details for TX/RX paths