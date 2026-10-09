#!/usr/bin/env python3
from litex.soc.interconnect.stream import Endpoint, BufferizeEndpoints, DIR_SOURCE, DIR_SINK
from types import SimpleNamespace
from migen import *
from litex.soc.interconnect.axi import *
from litex.soc.interconnect.csr import *


from litescope import LiteScopeAnalyzer
from migen.genlib.cdc import MultiReg

from gateware.LimeDFB.Resampler.Resampler import Resampler

from gateware.common import *
from gateware.LimeDFB.afe79xx.afe79xx_phy import AFE79xxPHY
from gateware.LimeDFB.afe79xx.afe79xx_rx import AFE79xxRX
from gateware.LimeDFB.afe79xx.afe79xx_rx_formatter import AFE79xxRXFormatter
from gateware.LimeDFB.afe79xx.afe79xx_tx_formatter import AFE79xxTXFormatter
from gateware.LimeDFB.afe79xx.afe79xx_tx import AFE79xxTX


class afe79xx(LiteXModule):
    def __init__(self, soc, platform, pads,
                 s_clk_domain = "sys500",
                 m_clk_domain = "sys500",
                 sys_clk_freq = 300e6,
                 afe_sys_cd = "fpga_1pps",
                 afe_sys_2x_cd = "fpga_1pps_2x",
                 afe_dsp_cd = "fpga_1pps_dsp",
                 with_debug = False,
                 resampling_stages = 2,
                 with_dpd = False):

        self.platform = platform


        # Add CSRs
        self._add_csrs()

        # Sources/Sinks
        self.source = AXIStreamInterface(128, clock_domain=m_clk_domain)
        self.sink   = AXIStreamInterface(128, clock_domain=s_clk_domain)

        # ---------------------------------------------------------------------
        # AFE/JESD PHY
        # ---------------------------------------------------------------------
        self._add_phy(platform,pads,afe_sys_cd)


        # ---------------------------------------------------------------------
        # Control/Misc
        # ---------------------------------------------------------------------
        self.rx_en = Signal()
        self.tx_en     = Signal()

        # IQ swap belongs to sample formatting, not to the PHY.
        self.rx_swap_iq = Signal(4)
        self.tx_swap_iq = Signal(4)
        self.specials += MultiReg(self.rx_cfg3.fields.swap_iq, self.rx_swap_iq, afe_sys_cd,2,0)
        self.specials += MultiReg(self.tx_cfg3.fields.swap_iq,self.tx_swap_iq,afe_sys_cd,2,0)


        # LiteScope example.
        # ------------------
        # Setup LiteScope Analyzer to capture some of the AXI-Lite MMAP signals.
        if with_debug:
            analyzer_signals = [
            ]

            self.analyzer = LiteScopeAnalyzer(analyzer_signals,
                depth        = 512,
                clock_domain = "sys",
                register     = True,
                csr_csv      = "afe79xx_analyzer.csv"
            )

        # ---------------------------------------------------------------------
        # RX data path
        # ---------------------------------------------------------------------
        # AFE79xxPHY(afe_source) -> AFE79xxRXFormatter -> AFE79xxRX -> source_cdc -> source

        # AFE79xxRXFormatter
        self.rx_formatter = AFE79xxRXFormatter(
            afe_sys_cd    = afe_sys_cd,
            afe_sys_2x_cd = afe_sys_2x_cd,
        )

        # Connect AFE79xxPHY(afe_source) -> AFE79xxRXFormatter
        self.comb += [
            # AFE PHY -> RX formatter
            self.rx_formatter.sink.data.eq(self.afe_source.data),
            self.rx_formatter.sink.valid.eq(self.afe_source.valid),

            # Formatter control
            self.rx_formatter.enable.eq(self.rx_en),
            self.rx_formatter.swap_iq.eq(self.rx_swap_iq),
        ]

        # AFE79xxRX
        self.rx = AFE79xxRX(platform, clk_domain=afe_sys_2x_cd)

        # Preserve decimator CSR names without registering the module twice.
        self.autocsr_exclude = {"rx"}
        object.__setattr__(self, "decimate", self.rx.decimate)

        # Connect AFE79xxRXFormatter -> AFE79xxRX
        self.comb += [
            self.rx.enable.eq(self.rx_en),
            self.rx_formatter.source.connect(self.rx.sink),
        ]

        self.source_cdc = stream.ClockDomainCrossing(
            layout         =[("data", 128)],
            cd_from        =afe_sys_2x_cd,
            cd_to          =m_clk_domain,
            buffered       =True,
            depth          =32
        )

        # Connect AFE79xxRX -> source_cdc
        self.comb += [
            self.source_cdc.sink.valid.eq(self.rx.source.valid),
            self.source_cdc.sink.data.eq(self.rx.source.data),
            self.rx.source.ready.eq(self.source_cdc.sink.ready),
        ]

        # Connect source_cdc -> source
        self.comb += self.source_cdc.source.connect(self.source)


        # ---------------------------------------------------------------------
        # TX data path
        # ---------------------------------------------------------------------
        # sink -> sink_cdc -> AFE79xxTX -> AFE79xxTXFormatter -> AFE79xxPHY(afe_sink)

        self.sink_cdc = stream.ClockDomainCrossing(
            layout         =[("data", 128)],
            cd_from        =s_clk_domain,
            cd_to          =afe_dsp_cd if with_dpd else afe_sys_2x_cd,
            buffered       =True,
            depth          =32
        )

        # Connect sink -> sink_cdc
        self.comb += [
            self.sink_cdc.sink.data.eq(self.sink.data),
            self.sink_cdc.sink.valid.eq(self.sink.valid),
            self.sink.ready.eq(self.sink_cdc.sink.ready),
        ]


        # AFE79xxTX
        self.tx = AFE79xxTX(
            platform,
            sys_clk_freq=sys_clk_freq,
            afe_sys_2x_cd=afe_sys_2x_cd,
            afe_dsp_cd=afe_dsp_cd,
            with_dpd=with_dpd,
        )

        # Preserve CSR names without registering the modules twice.
        self.autocsr_exclude.add("tx")
        object.__setattr__(self, "interpolate", self.tx.interpolate)
        object.__setattr__(self, "Resampler_max_value", self.tx.Resampler_max_value)


        if with_dpd:
            object.__setattr__(self, "tx_dsp", self.tx.tx_dsp)
            object.__setattr__(self, "qadpd_a", self.tx.qadpd_a)

        # Connect sink_cdc -> AFE79xxTX
        self.comb += [
            self.tx.tx_en.eq(self.tx_en),
            self.tx.sink.data.eq(self.sink_cdc.source.data),
            self.tx.sink.valid.eq(self.sink_cdc.source.valid),
            self.sink_cdc.source.ready.eq(self.tx.sink.ready),
        ]

        self.tx_formatter = AFE79xxTXFormatter(
            afe_sys_cd=afe_sys_cd,
            afe_sys_2x_cd = afe_sys_2x_cd,
        )

        # Connect AFE79xxTX -> AFE79xxTXFormatter -> AFE79xxPHY(afe_sink)
        self.comb += [
            self.tx_formatter.tx_en.eq(self.tx_en),
            self.tx_formatter.tx_swap_iq.eq(self.tx_swap_iq),

            self.tx.source.connect(self.tx_formatter.sink),

            self.afe_sink.data.eq(self.tx_formatter.source.data),
            self.afe_sink.valid.eq(self.tx_formatter.source.valid),
            self.tx_formatter.source.ready.eq(self.afe_sink.ready),
        ]


        # ------------------------------------------------------------
        # QADPD Capture
        # ------------------------------------------------------------
        if with_dpd:
            self._add_dpd_capture(platform, afe_sys_2x_cd)


    def _add_csrs(self):
        self.reg00 = CSRStorage(fields=[
            CSRField("afe_reset", size=1, offset=0, reset=0),
            CSRField("afe_trst", size=1, offset=1, reset=0),
            CSRField("afe_sleep", size=1, offset=2, reset=0),
        ])

        self.core_ctrl = CSRStorage(fields=[
            CSRField("afe_core_rst_n", size=1, offset=0, reset=0),
            CSRField("afe_init_trigger", size=1, offset=1, reset=0),
        ])

        self.rx_ctrl = CSRStorage(fields=[
            CSRField("tiafe_rx_sync_reset", size=1, offset=0, reset=1),
            CSRField("rx_clr_sysref_realign_count", size=1, offset=1, reset=0),
        ])

        self.rx_cfg0 = CSRStorage(fields=[
            CSRField("tiafe_cfg_rx_lane_enabled", size=4, offset=0, reset=0x0),
            CSRField("tiafe_cfg_rx_lane_polarity", size=4, offset=4, reset=0),
        ])

        self.rx_cfg1 = CSRStorage(fields=[
            CSRField("tiafe_cfg_rx_lane_map", size=16, offset=0, reset=0),
        ])

        self.rx_cfg2 = CSRStorage(fields=[
            CSRField("tiafe_cfg_rx_buffer_release_delay", size=10, offset=0, reset=0),
        ])

        self.rx_cfg3 = CSRStorage(fields=[
            CSRField("swap_iq", size=4, offset=0, reset=0xF),
        ])

        self.rx_status0 = CSRStatus(fields=[
            CSRField("jesd_rx_sysref_realign_count", size=4, offset=0, reset=0),
        ])

        self.tx_ctrl = CSRStorage(fields=[
            CSRField("tiafe_tx_sync_reset", size=1, offset=0, reset=1),
            CSRField("tx_clr_sysref_realign_count", size=1, offset=1, reset=0),

        ])

        self.tx_cfg0 = CSRStorage(fields=[
            CSRField("tiafe_cfg_tx_lane_enabled", size=4, offset=0, reset=0x0),
            CSRField("tiafe_cfg_tx_lane_polarity", size=4, offset=4, reset=0),
        ])

        self.tx_cfg1 = CSRStorage(fields=[
            CSRField("tiafe_cfg_tx_lane_map", size=16, offset=0, reset=0),
        ])

        self.tx_cfg3 = CSRStorage(fields=[
            CSRField("swap_iq", size=4, offset=0, reset=0xF),
        ])

        self.tx_status0 = CSRStatus(fields=[
            CSRField("jesd_tx_sysref_realign_count", size=4, offset=0, reset=0),
        ])

        self.ch_en = CSRStorage(2, reset=3,
                                description="01 - Channel A enabled, 10 - Channel B enabled, 11 - Channels A and B enabled"
                                )
        self.smpl_width = CSRStorage(2, reset=2,
                                     description="10 - 12bit, 01 - Reserved, 00 - 16bit"
                                     )
        self.pkt_size = CSRStorage(16, reset=253,
                                   description="Packet Size in bytes, "
                                   )

        self.core_status0 = CSRStatus(fields=[
            CSRField("xcvr_plls_locked", size=1, offset=0, reset=0),
            CSRField("rx_all_lanes_locked", size=1, offset=1, reset=0),
        ])

    def _add_phy(
            self,
            platform,
            pads,
            afe_sys_cd,
    ):

        self.phy = AFE79xxPHY(
            platform=platform,
            pads=pads,
            afe_sys_cd=afe_sys_cd,
            reg00=self.reg00,
            core_ctrl=self.core_ctrl,
            rx_ctrl=self.rx_ctrl,
            rx_cfg0=self.rx_cfg0,
            rx_cfg1=self.rx_cfg1,
            rx_cfg2=self.rx_cfg2,
            rx_status0=self.rx_status0,
            tx_ctrl=self.tx_ctrl,
            tx_cfg0=self.tx_cfg0,
            tx_cfg1=self.tx_cfg1,
            tx_status0=self.tx_status0,
            core_status0=self.core_status0,
        )

        # Native AFE streams.
        self.afe_source = self.phy.source
        self.afe_sink = self.phy.sink

        # Compatibility aliases for signals that may be referenced by board-level
        # integration/debug code. New code should prefer self.phy.<signal>.
        self.xcvr_rx_clock = self.phy.xcvr_rx_clock
        self.xcvr_tx_clock = self.phy.xcvr_tx_clock
        self.jesd_freerun_clk = self.phy.jesd_freerun_clk
        self.tiafe_jesd_plls_locked = self.phy.tiafe_jesd_plls_locked

    def _add_dpd_capture(
            self,
            platform,
            afe_sys_2x_cd,
    ):

        from gateware.LimeDFB.dsp.DPD.src.txchain.dpd_capture_buffer import DPDCaptureBuffer
        self.dpd_capture_buffer = DPDCaptureBuffer(
            platform,
            0x20000,
            "sys",
            afe_sys_2x_cd,
            128,
            13
        )

        # TX Channel A before DPD.
        tx_a_before_dpd = self.tx.tx_a_before_dpd

        # TX Channel A after DPD.
        tx_a_after_dpd = self.tx.tx_a_after_dpd

        # Select logical RX channel after AFE remap: 0=A, 1=B, 2=C, 3=D.
        # Set the SPI configuration before starting a capture.
        capture_channel = Signal(2)
        self.specials += MultiReg(
            i=self.tx.tx_dsp.txdsp1ch.sel_moni_source,
            o=capture_channel,
            odomain=afe_sys_2x_cd,
        )

        rx_from_afe = Signal(32)
        self.comb += rx_from_afe.eq(Array([
            self.rx_formatter.source.data[32 * ch:32 * (ch + 1)] for ch in range(4)
        ])[capture_channel])

        self.comb += [
            self.dpd_capture_buffer.reset_n.eq(~ResetSignal("sys")),
            self.dpd_capture_buffer.start_write.eq(self.tx.tx_dsp.txdsp1ch.mem_start_write),
            self.tx.tx_dsp.txdsp1ch.mem_full.eq(self.dpd_capture_buffer.full),

            # x = TX Channel A before DPD
            self.dpd_capture_buffer.xpi.eq(tx_a_before_dpd[0:16]),
            self.dpd_capture_buffer.xpq.eq(tx_a_before_dpd[16:32]),

            # y = TX Channel A after DPD
            self.dpd_capture_buffer.ypi.eq(tx_a_after_dpd[0:16]),
            self.dpd_capture_buffer.ypq.eq(tx_a_after_dpd[16:32]),

            # xi/xq = selected RX feedback channel from AFE receive
            self.dpd_capture_buffer.xi.eq(rx_from_afe[0:16]),
            self.dpd_capture_buffer.xq.eq(rx_from_afe[16:32]),
        ]