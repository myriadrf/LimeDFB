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


# -----------------------------
# Utility functions
# -----------------------------
def swap_iq(x):
    i1 = x[0:16]
    q1 = x[16:32]
    q1_neg = -q1

    return Cat(i1, q1_neg)


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
        self.phy = AFE79xxPHY(
            platform       = platform,
            pads           = pads,
            afe_sys_cd     = afe_sys_cd,
            reg00          = self.reg00,
            core_ctrl      = self.core_ctrl,
            rx_ctrl        = self.rx_ctrl,
            rx_cfg0        = self.rx_cfg0,
            rx_cfg1        = self.rx_cfg1,
            rx_cfg2        = self.rx_cfg2,
            rx_status0     = self.rx_status0,
            tx_ctrl        = self.tx_ctrl,
            tx_cfg0        = self.tx_cfg0,
            tx_cfg1        = self.tx_cfg1,
            tx_status0     = self.tx_status0,
            core_status0   = self.core_status0,
        )

        # Native AFE streams. RX/TX formatting and DSP stay in this wrapper for
        # now and will be split in a later refactor.
        self.afe_source = afe_source = self.phy.source
        self.afe_sink   = afe_sink   = self.phy.sink
        self.rx_en      = Signal()

        # IQ swap belongs to sample formatting, not to the PHY.
        self.rx_swap_iq = Signal(4)
        self.tx_swap_iq = Signal(4)
        self.specials += MultiReg(self.rx_cfg3.fields.swap_iq, self.rx_swap_iq, afe_sys_cd, 2, 0)
        self.specials += MultiReg(self.tx_cfg3.fields.swap_iq, self.tx_swap_iq, afe_sys_cd, 2, 0)

        # Compatibility aliases for signals that may be referenced by board-level
        # integration/debug code. New code should prefer self.phy.<signal>.
        self.xcvr_rx_clock = self.phy.xcvr_rx_clock
        self.xcvr_tx_clock = self.phy.xcvr_tx_clock
        self.jesd_freerun_clk = self.phy.jesd_freerun_clk
        self.tiafe_jesd_plls_locked = self.phy.tiafe_jesd_plls_locked

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

        # -----------------------------------------
        # RX data path
        self.rx_formatter = AFE79xxRXFormatter(
            afe_sys_cd    = afe_sys_cd,
            afe_sys_2x_cd = afe_sys_2x_cd,
        )

        self.comb += [
            # AFE PHY -> RX formatter
            self.rx_formatter.sink.data.eq(afe_source.data),
            self.rx_formatter.sink.valid.eq(afe_source.valid),

            # Formatter control
            self.rx_formatter.enable.eq(self.rx_en),
            self.rx_formatter.swap_iq.eq(self.rx_swap_iq),
        ]

        self.rx = AFE79xxRX(platform, clk_domain=afe_sys_2x_cd)

        # Preserve decimator CSR names without registering the module twice.
        self.autocsr_exclude = {"rx"}
        object.__setattr__(self, "decimate", self.rx.decimate)

        # rx_formatter -> rx
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

        # rx -> source_cdc
        self.comb += [
            self.source_cdc.sink.valid.eq(self.rx.source.valid),
            self.source_cdc.sink.data.eq(self.rx.source.data),
            self.rx.source.ready.eq(self.source_cdc.sink.ready),
        ]

        # source_cdc -> source
        self.comb += self.source_cdc.source.connect(self.source)


        # -----------------------------------------
        # TX data path
        self.tx_en     = Signal()

        self.sink_cdc = stream.ClockDomainCrossing(
            layout         =[("data", 128)],
            cd_from        =s_clk_domain,
            cd_to          =afe_dsp_cd if with_dpd else afe_sys_2x_cd,
            buffered       =True,
            depth          =32
        )

        # sink -> sink_cdc
        self.comb += [
            self.sink_cdc.sink.data.eq(self.sink.data),
            self.sink_cdc.sink.valid.eq(self.sink.valid),
            self.sink.ready.eq(self.sink_cdc.sink.ready),
        ]

        from gateware.LimeDFB.dsp.interpolate_4ch.interpolate_4ch import Interpolate4ch
        self.interpolate = Interpolate4ch(platform, clk_domain=afe_sys_2x_cd, num_stages=3)

        self.Resampler_max_value = CSRStatus(size=4, description="Maximum divider value for resampling")
        # Temp workaround begin
        #self.comb += self.Resampler_max_value.status.eq(resampling_stages)
        if resampling_stages != 0:
            raise ValueError(
                f"resampling_stages must be 0 for this xilinx int/dec configuration (got {resampling_stages})"
            )
        self.comb += self.Resampler_max_value.status.eq(3)  # Temp workaround end

        interpolate_source = self.sink_cdc.source
        if with_dpd:
            from gateware.LimeDFB.dsp.tx_dsp_4ch.tx_dsp_4ch import TxDsp4Ch
            self.tx_dsp = tx_dsp = TxDsp4Ch(platform, sys_clk_freq=sys_clk_freq, clk_domain=afe_dsp_cd)

            self.comb += [self.tx_dsp.reset_n.eq(~ResetSignal(afe_dsp_cd)),
                          ]

            # sink_cdc -> tx_dsp
            self.comb += [
                self.tx_dsp.sink.data.eq(self.sink_cdc.source.data),
                self.tx_dsp.sink.valid.eq(self.sink_cdc.source.valid),
                self.sink_cdc.source.ready.eq(self.tx_dsp.sink.ready),
            ]

            self.dsp_cdc = stream.ClockDomainCrossing(
                layout         =[("data", 128)],
                cd_from        =afe_dsp_cd,
                cd_to          =afe_sys_2x_cd,
                buffered       =True,
                depth          =32
            )

            # tx_dsp -> dsp_cdc
            self.comb += [
                self.dsp_cdc.sink.data.eq(self.tx_dsp.source.data),
                self.dsp_cdc.sink.valid.eq(self.tx_dsp.source.valid),
                self.tx_dsp.source.ready.eq(self.dsp_cdc.sink.ready),
            ]
            interpolate_source = self.dsp_cdc.source

        self.comb += [
            self.interpolate.aresetn.eq(self.tx_en),
            self.interpolate.sink.data.eq(interpolate_source.data),
            self.interpolate.sink.valid.eq(interpolate_source.valid),
            interpolate_source.ready.eq(self.interpolate.sink.ready),
        ]

        tx_a_data = self.interpolate.source.data[0:32]
        if with_dpd:
            # ------------------------------------------------------------
            # QADPD on TX Channel A only, after interpolate
            # ------------------------------------------------------------
            from gateware.LimeDFB.dsp.DPD.src.adpd.qadpd import QADPD
            self.submodules.qadpd_a = QADPD(
                platform,
                n=4,
                m=2,
                mul_n=18,
                clk_domain=afe_sys_2x_cd,
            )

            # Channel A from interpolate:
            # bits [0:16]  = I
            # bits [16:32] = Q
            #
            # QADPD input is 14-bit, while interpolate output is 16-bit.
            # Use [2:16] to keep the signed MSBs and drop 2 LSBs.
            self.comb += [
                self.qadpd_a.reset_n.eq(self.tx_en),
                self.qadpd_a.reset_mem_n.eq(self.tx_en),

                # If QADPD config SPI is unused for now, tie these off.
                self.qadpd_a.sclk.eq(self.tx_dsp.sclk),
                self.qadpd_a.spi_ctrl.eq(self.tx_dsp.adpd_ctrl_reg),
                self.qadpd_a.spi_data.eq(self.tx_dsp.adpd_data_reg),

                self.qadpd_a.xpi.eq(self.interpolate.source.data[2:16]),
                self.qadpd_a.xpq.eq(self.interpolate.source.data[18:32]),
            ]

            # QADPD output is 18-bit. Convert back to 16-bit for TX stream.
            # Use [2:18] to keep signed MSBs and drop 2 LSBs.
            tx_a_data = Signal(32)
            self.comb += [
                tx_a_data[0:16].eq(self.qadpd_a.ypi[2:18]),
                tx_a_data[16:32].eq(self.qadpd_a.ypq[2:18]),
            ]


            # ------------------------------------------------------------
            # QADPD Capture
            # ------------------------------------------------------------
            from gateware.LimeDFB.dsp.DPD.src.txchain.dpd_capture_buffer import DPDCaptureBuffer
            self.dpd_capture_buffer = DPDCaptureBuffer(platform, 0x20000, "sys", afe_sys_2x_cd, 128, 13)


            # TX Channel A before DPD.
            # interpolate.source.data[0:16]  = A I before DPD
            # interpolate.source.data[16:32] = A Q before DPD
            tx_a_before_dpd = self.interpolate.source.data[0:32]

            # TX Channel A after DPD.
            # tx_a_data[0:16]  = A I after DPD
            # tx_a_data[16:32] = A Q after DPD
            tx_a_after_dpd = tx_a_data

            # Select logical RX channel after AFE remap: 0=A, 1=B, 2=C, 3=D.
            # Set the SPI configuration before starting a capture.
            capture_channel = Signal(2)
            self.specials += MultiReg(
                i=self.tx_dsp.txdsp1ch.sel_moni_source,
                o=capture_channel,
                odomain=afe_sys_2x_cd,
            )
            rx_from_afe = Signal(32)
            self.comb += rx_from_afe.eq(Array([
                self.rx_formatter.source.data[32*ch:32*(ch + 1)] for ch in range(4)
            ])[capture_channel])


            self.comb += [
                self.dpd_capture_buffer.reset_n.eq(~ResetSignal("sys")),
                self.dpd_capture_buffer.start_write.eq(self.tx_dsp.txdsp1ch.mem_start_write),
                self.tx_dsp.txdsp1ch.mem_full.eq(self.dpd_capture_buffer.full),

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

        tx_conv = stream.Converter(nbits_from=128, nbits_to=256)
        tx_conv = ClockDomainsRenamer(afe_sys_2x_cd)(tx_conv)
        self.tx_conv = tx_conv


        # Omit parts of Axi interface we don't use + data, because we handle that seperately
        # AFE bindings do not correspond to ABCD channels, channels need to be muxed to fit
        # IQ mux Logic: Mux(condition, swapped_data, normal_data)
        self.comb += [
            # -----------------------------------------------------------------
            # Channel A -> AFE CH 4 (Bits 96-128) | Controlled by tx_swap_iq[0]
            # -----------------------------------------------------------------
            tx_conv.sink.data[96:128].eq(Mux(self.tx_swap_iq[0],swap_iq(tx_a_data),tx_a_data)),
            # -----------------------------------------------------------------
            # Channel B -> AFE CH 3 (Bits 64-96) | Controlled by tx_swap_iq[1]
            # -----------------------------------------------------------------
            tx_conv.sink.data[64:96].eq(Mux(self.tx_swap_iq[1],swap_iq(self.interpolate.source.data[32:64]),self.interpolate.source.data[32:64])),
            # -----------------------------------------------------------------
            # Channel C -> AFE CH 1 (Bits 0-32) | Controlled by tx_swap_iq[2]
            # -----------------------------------------------------------------
            tx_conv.sink.data[0:32].eq(Mux(self.tx_swap_iq[2],swap_iq(self.interpolate.source.data[64:96]),self.interpolate.source.data[64:96])),
            # -----------------------------------------------------------------
            # Channel D -> AFE CH 2 (Bits 32-64) | Controlled by tx_swap_iq[3]
            # -----------------------------------------------------------------
            tx_conv.sink.data[32:64].eq(Mux(self.tx_swap_iq[3],swap_iq(self.interpolate.source.data[96:128]),self.interpolate.source.data[96:128])),
        ]


        self.comb += [
            self.tx_conv.sink.valid.eq(self.interpolate.source.valid),
            self.interpolate.source.ready.eq(tx_conv.sink.ready),
        ]


        self.tx_interleaved = Endpoint([("data", 256)])
        # self.tx_conv.source.connect(self.tx_interleaved,omit={"data"})
        self.comb += [
            self.tx_interleaved.valid.eq(self.tx_conv.source.valid),
            self.tx_conv.source.ready.eq(self.tx_interleaved.ready),
        ]
        # self.tx_conv.source.data[0:128] holds AI0, AQ0, BI0 ...
        # self.tx_conv.source.data[128:256] holds AI1, AQ1, BI1 ...
        # self.tx_interleaved.data should hold AI0, AI1, AQ0, AQ1, BI0, BI1 ...
        for j in range(4 * 2):
            # lower 16 bits from data_s0
            self.comb += self.tx_interleaved.data[32*j:32*j+16].eq(self.tx_conv.source.data[16*j:16*j+16])
            # upper 16 bits from data_s1
            self.comb += self.tx_interleaved.data[32*j+16:32*j+32].eq(self.tx_conv.source.data[16*j+128:16*j+16+128])

        self.tx_cdc = stream.ClockDomainCrossing(
            layout         =[("data", 256)],
            cd_from        =afe_sys_2x_cd,
            cd_to          =afe_sys_cd,
            buffered       =True,
            depth          =32
        )
        self.comb += [
            self.tx_interleaved.connect(self.tx_cdc.sink),
            self.tx_cdc.source.connect(afe_sink,omit={"ready"}),
            # If in reset, assert ready to 'clear out' everything
            self.tx_cdc.source.ready.eq(afe_sink.ready | ~self.tx_en)
        ]

        # Signal lists for debugging
        self.flow_control_signals = SimpleNamespace()
        self.flow_control_signals.m_clk = [
            afe_source.valid,
            afe_source.ready,
        ]

        self.flow_control_signals.s_clk = [
            afe_sink.ready,
            afe_sink.valid,
        ]

        self.flow_control_signals.m_clk += [

        ]
        self.flow_control_signals.s_clk += [
            self.tx_cdc.source.valid,
            self.flow_control_signals.s_clk[0], # afe_sink.ready
        ]
        self.flow_control_signals.demux_clk = [
            self.source.valid,
            self.source.ready,
            self.sink.valid,
            self.sink.ready,
            self.tx_conv.sink.valid,
            self.tx_conv.sink.ready,
            self.tx_conv.source.valid,
            self.tx_conv.source.ready,
            self.tx_cdc.sink.valid,
            self.tx_cdc.sink.ready,
        ]
        if resampling_stages > 0:
            self.flow_control_signals.demux_clk += [
                self.RX_A_RESAMPLER.sink.valid,
                self.RX_A_RESAMPLER.sink.ready,
                self.RX_A_RESAMPLER.source.valid,
                self.RX_A_RESAMPLER.source.ready,
                self.TX_A_RESAMPLER.sink.valid,
                self.TX_A_RESAMPLER.sink.ready,
                self.TX_A_RESAMPLER.source.valid,
                self.TX_A_RESAMPLER.source.ready,
            ]


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

    def _add_platform_sources(self):
        platform = self.platform

        for source in [
            "./gateware/AFE79xx/afe79xx_jesd_ip_top.v",
            "./gateware/AFE79xx/afe79xx_ti_ip_top.v",
            "./gateware/AFE79xx/afe79xx_xcvr_top.v",
            "./gateware/AFE79xx/afe79xx_xcvr_wrapper.sv",
            "./gateware/AFE79xx/TI_IP_core_66b64/TI_204c_IP_6664.svp",
        ]:
            platform.add_source(source)

        ip_path = os.path.abspath(
            "./gateware/AFE79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/"
            "gth_uscale_64b66b_xcvr_xcau15p.xci"
        )

        platform.toolchain.project_commands += [
            f"import_ip {ip_path}",
            "upgrade_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p]",
            "synth_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p] -force",
            "set hipersdr_44xx_defines {{GT_XCVR_NAME=gth_uscale_64b66b_xcvr_xcau15p}}",
            "set_property verilog_define $hipersdr_44xx_defines [get_filesets sources_1]",
            "get_ips",
        ]

        #platform.add_source("./gateware/AFE79xx/afe79xx_jesd_ip_top.v")
        #platform.add_source("./gateware/AFE79xx/afe79xx_ti_ip_top.v")
        #platform.add_source("./gateware/AFE79xx/afe79xx_xcvr_top.v")
        #platform.add_source("./gateware/AFE79xx/afe79xx_xcvr_wrapper.sv")
        #platform.add_source("./gateware/AFE79xx/TI_IP_core_66b64/TI_204c_IP_6664.svp")
#
        ##platform.add_ip("./gateware/afe79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth_uscale_64b66b_xcvr_xcau15p.xci")
        ##platform.toolchain.project_commands.append("source " + os.path.abspath("./gateware/afe79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth_uscale_64b66b_xcvr_xcau15p.tcl"))
        ##platform.toolchain.project_commands.append("synth_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p] -force")
#
        #platform.toolchain.project_commands.append("import_ip " + os.path.abspath("./gateware/AFE79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth_uscale_64b66b_xcvr_xcau15p.xci"))
        #platform.toolchain.project_commands.append("upgrade_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p]")
        #platform.toolchain.project_commands.append("synth_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p] -force")
        #platform.toolchain.project_commands.append("set hipersdr_44xx_defines {{GT_XCVR_NAME=gth_uscale_64b66b_xcvr_xcau15p}}")
        #platform.toolchain.project_commands.append("set_property verilog_define $hipersdr_44xx_defines [get_filesets sources_1]")
        #platform.toolchain.project_commands.append("get_ips")

    def _add_timing_constraints(self):
        timings_sdc_filename = "afe79xx_timing.xdc"

        with open(timings_sdc_filename, "w") as f:
            f.write("# FPGA_GT_AFEREF 245.76Mhz\n")
            f.write("create_clock -period 4.069 -name fpga_gt_aferef_clk "
                    "[get_ports afe79xx_serdes_x4_fpga_gt_aferef_p]\n\n")

            f.write("# FPGA_SYSREF 3.84Mhz\n")
            f.write("create_clock -period 260.416 -name fpga_sysref_clk "
                    "[get_ports FPGA_SYSREF_p]\n\n")

            f.write("set_clock_groups -name afe_async2 -asynchronous "
                    "-group [get_clocks xcvr_top_inst_n_0]\n\n")

            f.write("set_clock_groups -name afe_async3 -asynchronous "
                    "-group [get_clocks xcvr_top_inst_n_1]\n\n")

        self.platform.add_source(timings_sdc_filename)
