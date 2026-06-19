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
from litex.soc.interconnect.axi.axi_lite import axi_lite_to_simple


class DspMmap128ToAXILite32(LiteXModule):
    """
    128-bit DSP write-side RAM exposed as 32-bit AXI-Lite mmap.

    CPU side:
        AXI-Lite, 32-bit, usually sys clock domain.

    DSP side:
        128-bit write port, usually clk1_domain.

    CPU address layout:

        base + 16*n + 0x0  -> dsp_data[ 31:  0]
        base + 16*n + 0x4  -> dsp_data[ 63: 32]
        base + 16*n + 0x8  -> dsp_data[ 95: 64]
        base + 16*n + 0xc  -> dsp_data[127: 96]

    One DSP row = four CPU-visible 32-bit words.
    """

    def __init__(self,
                 size=0x80000,
                 axi_domain="sys",
                 dsp_domain="sys",
                 dsp_addr_width=15,
                 dsp_addr_shift=0,
                 dsp_we_active_low=False):

        # Each 128-bit DSP row is 16 bytes.
        assert size % 16 == 0

        row_depth = size // 16
        row_bits  = log2_int(row_depth)

        # Make sure selected DSP address slice fits.
        assert dsp_addr_shift + row_bits <= dsp_addr_width

        # ---------------------------------------------------------------------
        # Public interfaces
        # ---------------------------------------------------------------------

        self.bus = AXILiteInterface(
            address_width = 32,
            data_width    = 32,
            clock_domain  = axi_domain,
        )

        self.dsp_en   = Signal()
        self.dsp_we   = Signal()
        self.dsp_addr = Signal(dsp_addr_width)
        self.dsp_data = Signal(128)

        # ---------------------------------------------------------------------
        # Four 32-bit banks make one logical 128-bit row
        # ---------------------------------------------------------------------

        banks = [
            Memory(32, row_depth, name=f"dsp_mmap_bank{i}")
            for i in range(4)
        ]

        cpu_ports = [
            mem.get_port(
                write_capable  = True,
                we_granularity = 8,
                mode           = WRITE_FIRST,
                clock_domain   = axi_domain,
            )
            for mem in banks
        ]

        dsp_ports = [
            mem.get_port(
                write_capable  = True,
                we_granularity = 8,
                mode           = WRITE_FIRST,
                clock_domain   = dsp_domain,
            )
            for mem in banks
        ]

        for mem, cpu_port, dsp_port in zip(banks, cpu_ports, dsp_ports):
            self.specials += mem, cpu_port, dsp_port

        # ---------------------------------------------------------------------
        # AXI-Lite CPU side
        # ---------------------------------------------------------------------
        #
        # axi_lite_to_simple() outputs a 32-bit word address after removing
        # AXI byte offset bits.
        #
        # For size=0x1000:
        #   CPU sees 0x1000 / 4 = 1024 32-bit words.
        #   row_bits = log2(256) = 8.
        #   cpu_word_adr has row_bits + 2 = 10 bits.
        #
        # cpu_word_adr[1:0] selects one 32-bit bank/lane.
        # cpu_word_adr[9:2] selects one 128-bit DSP row.
        # ---------------------------------------------------------------------

        cpu_word_adr = Signal(row_bits + 2)
        cpu_row      = Signal(row_bits)
        cpu_lane     = Signal(2)

        cpu_dat_r = Signal(32)
        cpu_dat_w = Signal(32)
        cpu_we    = Signal(4)
        cpu_re    = Signal()

        # Latched read lane.
        #
        # This is important because synchronous RAM returns data one cycle after
        # the read address phase. Without latching the lane, the read-data mux
        # can select the wrong bank during the AXI-Lite response phase.
        cpu_lane_r = Signal(2)

        self.comb += [
            cpu_lane.eq(cpu_word_adr[0:2]),
            cpu_row.eq(cpu_word_adr[2:]),
        ]

        sync_axi = getattr(self.sync, axi_domain)
        sync_axi += [
            If(cpu_re, cpu_lane_r.eq(cpu_lane))
        ]

        for i in range(4):
            self.comb += [
                cpu_ports[i].adr.eq(cpu_row),
                cpu_ports[i].dat_w.eq(cpu_dat_w),

                # Only selected 32-bit bank receives CPU byte-lane write strobes.
                cpu_ports[i].we.eq(Mux(cpu_lane == i, cpu_we, 0)),
            ]

        self.comb += cpu_dat_r.eq(Array([p.dat_r for p in cpu_ports])[cpu_lane_r])

        fsm, comb = axi_lite_to_simple(
            axi_lite   = self.bus,
            port_adr   = cpu_word_adr,
            port_dat_r = cpu_dat_r,
            port_dat_w = cpu_dat_w,
            port_re    = cpu_re,
            port_we    = cpu_we,
        )

        self.axi_lite_fsm = fsm
        self.comb += comb

        # ---------------------------------------------------------------------
        # DSP write side
        # ---------------------------------------------------------------------
        #
        # dsp_addr_shift selects address unit conversion:
        #
        #   dsp_addr_shift = 0  if dsp_addr addresses 128-bit rows
        #   dsp_addr_shift = 2  if dsp_addr addresses 32-bit words
        #   dsp_addr_shift = 4  if dsp_addr addresses bytes
        #
        # dsp_we_active_low:
        #
        #   False -> write when dsp_en &  dsp_we
        #   True  -> write when dsp_en & ~dsp_we
        # ---------------------------------------------------------------------

        dsp_row = Signal(row_bits)
        dsp_wr  = Signal()

        self.comb += dsp_row.eq(
            self.dsp_addr[dsp_addr_shift:dsp_addr_shift + row_bits]
        )

        if dsp_we_active_low:
            self.comb += dsp_wr.eq(self.dsp_en & ~self.dsp_we)
        else:
            self.comb += dsp_wr.eq(self.dsp_en & self.dsp_we)

        for i in range(4):
            self.comb += [
                dsp_ports[i].adr.eq(dsp_row),
                dsp_ports[i].dat_w.eq(self.dsp_data[32*i:32*(i + 1)]),

                # Full 32-bit write into each bank when DSP write is active.
                dsp_ports[i].we.eq(Replicate(dsp_wr, 4)),
            ]


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
                 ):

        self.platform = platform

        self.sink   = AXIStreamInterface(128, clock_domain=clk1_domain)
        self.source = AXIStreamInterface(128, clock_domain=clk1_domain)

        # ---------------------------------------------------------------------
        # External reset/control interface
        # ---------------------------------------------------------------------
        self.reset_n = Signal(reset=1)

        self.adpd_ctrl_reg = Signal(16)
        self.adpd_data_reg = Signal(16)

        # SPI interface
        self.sdin  = Signal()
        self.sclk  = Signal()
        self.sen   = Signal()
        self.sdout = Signal()


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
            txchaincfg_start_addr=txchaincfg_start_addr,
            cfr0cfg_start_addr=cfr0cfg_start_addr,
            cfr1cfg_start_addr=cfr1cfg_start_addr,
            fir0cfg_start_addr=fir0cfg_start_addr,
            fir1cfg_start_addr=fir1cfg_start_addr,
        )

        # ---------------------------------------------------------------------
        # MMAP RAM exposed to CPU
        # ---------------------------------------------------------------------
        #
        #self.txdsp_mmap = DspMmap128ToAXILite32(
        #    size              = 0x20000,
        #    axi_domain        = "sys",
        #    dsp_domain        = clk2_domain,
        #    dsp_addr_width    = 13,
#
        #    # Use 0 if mem_addrb already addresses 128-bit rows.
        #    # Use 2 if mem_addrb addresses 32-bit words.
        #    # Use 4 if mem_addrb addresses bytes.
        #    dsp_addr_shift    = 0,
#
        #    # Check VHDL polarity.
        #    # If mem_web means "write enable bar", keep True.
        #    # If mem_web is active-high write enable, set False.
        #    dsp_we_active_low = False,
        #)
#
        ## Expose AXI-Lite bus to SoC.
        #self.mmap = self.txdsp_mmap.bus
#
        #self.comb += [
        #    self.txdsp_mmap.dsp_en.eq(self.txdsp1ch.mem_enb),
        #    self.txdsp_mmap.dsp_we.eq(self.txdsp1ch.mem_web),
        #    self.txdsp_mmap.dsp_addr.eq(self.txdsp1ch.mem_addrb),
        #    self.txdsp_mmap.dsp_data.eq(self.txdsp1ch.mem_doutb),
        #]


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

            self.adpd_ctrl_reg.eq(self.txdsp1ch.adpd_ctrl_reg),
            self.adpd_data_reg.eq(self.txdsp1ch.adpd_data_reg),

            self.txdsp1ch.sdin.eq(self.sdin),
            self.txdsp1ch.sclk.eq(self.sclk),
            self.txdsp1ch.sen.eq(self.sen),
            self.sdout.eq(self.txdsp1ch.sdout),

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
                 fir1cfg_start_addr=256):

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
        # DPD control signals
        # ---------------------------------------------------------------------
        self.adpd_ctrl_reg = Signal(16)
        self.adpd_data_reg = Signal(16)

        self.mem_start_write = Signal()
        self.mem_full = Signal()

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

            # DPD control signals
            o_adpd_ctrl_reg = self.adpd_ctrl_reg,
            o_adpd_data_reg = self.adpd_data_reg,
            o_mem_start_write = self.mem_start_write,
            i_mem_full = self.mem_full,
        )

        self.tx_dsp_conv = add_vhd2v_converter(self.platform,
            instance = self.tx_dsp,
            files    = [
                "gateware/LimeDFB/dsp/DPD/src/txchain/tx_dsp.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/txchain/bram_write.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_cfr.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_division.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_fehf.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_fircms.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_gfirhf.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_hb1e.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_hb1o.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_hb1.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_mem_package.vhd",
                "gateware/LimeDFB/dsp/DPD/src/cfr_nr/nr_sqroot.vhd",
                "gateware/LimeDFB/dsp/DPD/src/adpd/iqim_gain_corr.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/mcfg32wm_fsm.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/mcfg64wm_fsm.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/mcfg_components.vhd",
                "gateware/LimeDFB/dsp/DPD/src/spi/txchaincfg.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/add26.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/bcla2.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/bcla8.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/clkdiv.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/csdm26x4.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/csec.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb1d.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb1e.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb1o.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb1.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb2e.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb2o.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/hb2.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/ta26.vhd",
                #"gateware/LimeDFB/dsp/DPD/src/hb/tt.vhd",
            ],
        )

        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.tx_dsp)
