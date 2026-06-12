#!/usr/bin/env python3
from litex.soc.interconnect.stream import Endpoint, BufferizeEndpoints, DIR_SOURCE, DIR_SINK
from types import SimpleNamespace
from migen import *
from litex.soc.interconnect.axi import *
from litex.soc.interconnect.csr import *


from litescope import LiteScopeAnalyzer
from migen.genlib.cdc import MultiReg

from gateware.common import *
from litex.soc.cores.spi import SPIMaster

class TxDsp4Ch(LiteXModule):
    """
    4-channel 128-bit AXI-Stream wrapper.

    Channel packing:
      ch0: sink.data[ 31:  0] = {xq0, xi0}
      ch1: sink.data[ 63: 32] = {xq1, xi1}
      ch2: sink.data[ 95: 64] = {xq2, xi2}
      ch3: sink.data[127: 96] = {xq3, xi3}

    Only channel 0 is processed by TxDsp1Ch.
    Channels 1..3 are passed through unchanged.

    Important:
      tx_dsp has no valid/ready or clock-enable input. This wrapper assumes
      a continuous stream with no meaningful downstream backpressure. If
      source.ready can stall, tx_dsp cannot be cleanly stopped unless the VHDL
      block is modified to add a clock-enable/sample-valid port.
    """
    def __init__(self,
                 platform,
                 sys_clk_freq = 300e6,
                 clk1_domain="sys",
                 clk2_domain="sys2x",
                 txchaincfg_start_addr=0,
                 cfr0cfg_start_addr=64,
                 cfr1cfg_start_addr=128,
                 fir0cfg_start_addr=192,
                 fir1cfg_start_addr=256,
                 instance_name="tx_dsp_4ch_i"):

        self.platform = platform

        self.sink   = AXIStreamInterface(128, clock_domain=clk1_domain)
        self.source = AXIStreamInterface(128, clock_domain=clk1_domain)

        # ---------------------------------------------------------------------
        # External reset/control interface
        # ---------------------------------------------------------------------
        self.reset_n = Signal(reset=1)

        # SPI interface
        self.sdin  = Signal()
        self.sclk  = Signal()
        self.sen   = Signal()
        self.sdout = Signal()

        # BRAM control interface from TxDsp1Ch
        self.mem_web   = Signal()
        self.mem_enb   = Signal()
        self.mem_addrb = Signal(15)
        self.mem_doutb = Signal(128)

        # Monitoring path inputs to TxDsp1Ch
        self.moni = Signal(16)
        self.monq = Signal(16)

        # Board SPI (used in DPD)
        # SPI master used to configure tx_dsp over its internal SPI port.
        self.spimaster_board_spi = spi = SPIMaster(
            pads=None,
            data_width=32,
            sys_clk_freq=sys_clk_freq,
            spi_clk_freq=10e6,
            with_csr=True,
        )

        spi.add_clk_divider()

        # Connect LiteX SPI master to tx_dsp SPI pins.
        self.comb += [
            self.sclk.eq(spi.pads.clk),
            self.sen.eq(spi.pads.cs_n),  # tx_dsp sen is active-low, same polarity as cs_n.
            self.sdin.eq(spi.pads.mosi),
            spi.pads.miso.eq(self.sdout),
        ]

        # ---------------------------------------------------------------------
        # 1-channel TX DSP instance for channel 0
        # ---------------------------------------------------------------------


        self.txdsp1ch = TxDsp1Ch(
            platform,
            clk1_domain=clk1_domain,
            clk2_domain=clk2_domain,
            txchaincfg_start_addr=txchaincfg_start_addr,
            cfr0cfg_start_addr=cfr0cfg_start_addr,
            cfr1cfg_start_addr=cfr1cfg_start_addr,
            fir0cfg_start_addr=fir0cfg_start_addr,
            fir1cfg_start_addr=fir1cfg_start_addr,
            instance_name=instance_name + "_txdsp1ch"
        )

        # ---------------------------------------------------------------------
        # Stream/control wiring
        # ---------------------------------------------------------------------
        self.comb += [
            # AXI-Stream handshake.
            #
            # This is a simple pass-through handshake. It is valid only when
            # the DSP can run continuously and source.ready is normally high.
            self.sink.ready.eq(self.source.ready),
            self.source.valid.eq(self.sink.valid),

            # Reset/control to TxDsp1Ch
            self.txdsp1ch.reset_n.eq(self.reset_n),

            self.txdsp1ch.sdin.eq(self.sdin),
            self.txdsp1ch.sclk.eq(self.sclk),
            self.txdsp1ch.sen.eq(self.sen),
            self.sdout.eq(self.txdsp1ch.sdout),

            self.mem_web.eq(self.txdsp1ch.mem_web),
            self.mem_enb.eq(self.txdsp1ch.mem_enb),
            self.mem_addrb.eq(self.txdsp1ch.mem_addrb),
            self.mem_doutb.eq(self.txdsp1ch.mem_doutb),

            self.txdsp1ch.moni.eq(self.moni),
            self.txdsp1ch.monq.eq(self.monq),

            # -----------------------------------------------------------------
            # Channel 0 into TxDsp1Ch
            # -----------------------------------------------------------------
            self.txdsp1ch.xi.eq(self.sink.data[0:16]),
            self.txdsp1ch.xq.eq(self.sink.data[16:32]),

            # Channel 0 output from TxDsp1Ch
            self.source.data[0:16].eq(self.txdsp1ch.yi),
            self.source.data[16:32].eq(self.txdsp1ch.yq),

            # -----------------------------------------------------------------
            # Channels 1..3 passthrough
            # -----------------------------------------------------------------
            self.source.data[32:128].eq(self.sink.data[32:128]),
        ]

class TxDsp1Ch(LiteXModule):
    """
    LiteX/Migen black-box wrapper for VHDL entity `tx_dsp`.

    VHDL clocks:
      - clk1: 245.76 MHz
      - clk2: 491.52 MHz

    The wrapper exposes raw IQ sample ports, SPI config ports, BRAM control
    outputs, and monitor input ports exactly as in the VHDL entity.
    """
    def __init__(self,
                 platform,
                 clk1_domain="sys",
                 clk2_domain="sys2x",
                 txchaincfg_start_addr=0,
                 cfr0cfg_start_addr=64,
                 cfr1cfg_start_addr=128,
                 fir0cfg_start_addr=192,
                 fir1cfg_start_addr=256,
                 instance_name="tx_dsp_1ch_i"):

        self.platform = platform
        # ---------------------------------------------------------------------
        # Reset
        # ---------------------------------------------------------------------
        self.reset_n = Signal(reset=1)  # active-low reset

        # ---------------------------------------------------------------------
        # Block sample inputs/outputs
        # ---------------------------------------------------------------------
        self.xi = Signal(16)
        self.xq = Signal(16)

        self.yi = Signal(16)
        self.yq = Signal(16)

        # ---------------------------------------------------------------------
        # SPI interface
        # ---------------------------------------------------------------------
        self.sdin  = Signal()
        self.sclk  = Signal()
        self.sen   = Signal()  # active-low enable
        self.sdout = Signal()

        # ---------------------------------------------------------------------
        # Control interface to BRAM
        # ---------------------------------------------------------------------
        self.mem_web   = Signal()
        self.mem_enb   = Signal()
        self.mem_addrb = Signal(15)
        self.mem_doutb = Signal(128)

        # ---------------------------------------------------------------------
        # Monitoring path capture inputs
        # ---------------------------------------------------------------------
        self.moni = Signal(16)
        self.monq = Signal(16)

        # ---------------------------------------------------------------------
        # DPD control signals
        # ---------------------------------------------------------------------
        self.adpd_ctrl_reg = Signal(16)
        self.adpd_data_reg = Signal(16)

        # ---------------------------------------------------------------------
        # VHDL instance
        # ---------------------------------------------------------------------
        self.tx_dsp = Instance("tx_dsp",
            # Generics
            p_TXCHAINCFG_START_ADDR = txchaincfg_start_addr,
            p_CFR0CFG_START_ADDR    = cfr0cfg_start_addr,
            p_CFR1CFG_START_ADDR    = cfr1cfg_start_addr,
            p_FIR0CFG_START_ADDR    = fir0cfg_start_addr,
            p_FIR1CFG_START_ADDR    = fir1cfg_start_addr,

            # Clocks
            i_clk1    = ClockSignal(clk1_domain),
            i_clk2    = ClockSignal(clk2_domain),

            # Reset
            i_reset_n = self.reset_n,

            # Block inputs/outputs
            i_xi      = self.xi,
            i_xq      = self.xq,
            o_yi      = self.yi,
            o_yq      = self.yq,

            # SPI interface
            i_sdin    = self.sdin,
            i_sclk    = self.sclk,
            i_sen     = self.sen,
            o_sdout   = self.sdout,

            # Control interface to BRAM
            o_mem_web   = self.mem_web,
            o_mem_enb   = self.mem_enb,
            o_mem_addrb = self.mem_addrb,
            o_mem_doutb = self.mem_doutb,

            # Monitoring path capture
            i_moni    = self.moni,
            i_monq    = self.monq,

            # DPD control signals
            o_adpd_ctrl_reg = self.adpd_ctrl_reg,
            o_adpd_data_reg = self.adpd_data_reg
        )

        self.tx_dsp_conv = add_vhd2v_converter(self.platform,
            instance = self.tx_dsp,
            files    = [
                "gateware/LimeDFB/dsp/DPD/src/txchain/tx_dsp.vhd",
                "gateware/LimeDFB/dsp/DPD/src/txchain/bram_write.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_cfr.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_division.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_fehf.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_fircms.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_gfirhf.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_hb1e.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_hb1o.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_hb1.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_mem_package.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_sqroot.vhd",
                "gateware/LimeDFB/dsp/DPD/src/adpd/iqim_gain_corr.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/mcfg32wm_fsm.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/mcfg64wm_fsm.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/mcfg_components.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/txchaincfg.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/add26.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/bcla2.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/bcla8.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/clkdiv.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/csdm26x4.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/csec.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb1d.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb1e.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb1o.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb1.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb2e.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb2o.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/hb2.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/ta26.vhd",
                "gateware/LimeDFB/dsp/DPD/src/hb/tt.vhd",
            ],
        )

        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.tx_dsp)
