#!/usr/bin/env python3
from litex.soc.interconnect.stream import Endpoint, BufferizeEndpoints, DIR_SOURCE, DIR_SINK
from types import SimpleNamespace
from migen import *
from litex.soc.interconnect.axi import *
from litex.soc.interconnect.csr import *


from litescope import LiteScopeAnalyzer
from migen.genlib.cdc import MultiReg

from gateware.LimeDFB.Resampler.Resampler import Resampler


# -----------------------------
# Utility functions
# -----------------------------
def swap_iq(x):
    i1 = x[0:16]
    q1 = x[16:32]
    q1_neg = -q1

    return Cat(i1, q1_neg)

class afe79xx(LiteXModule):
    def __init__(self, soc, platform, pads, double_clk_domain, s_clk_domain="sys", m_clk_domain="sys", demux_clk_domain="sys500", with_debug=False, demux=True, resampling_stages=2):
        # Add CSRs

        self.reg00  = CSRStorage(fields=[
            CSRField("afe_reset",   size=1, offset=0, reset=0),
            CSRField("afe_trst",    size=1, offset=1, reset=0),
            CSRField("afe_sleep",   size=1, offset=2, reset=0),
        ])

        self.core_ctrl    = CSRStorage(fields=[
            CSRField("afe_core_rst_n",              size=1, offset=0, reset=0),
            CSRField("afe_init_trigger",            size=1, offset=1, reset=0),
        ])

        self.rx_ctrl    = CSRStorage(fields=[
            CSRField("tiafe_rx_sync_reset",         size=1, offset=0, reset=1),
            CSRField("rx_clr_sysref_realign_count", size=1, offset=1, reset=0),
        ])

        self.rx_cfg0    = CSRStorage(fields=[
            CSRField("tiafe_cfg_rx_lane_enabled",   size=4, offset=0, reset=0x0),
            CSRField("tiafe_cfg_rx_lane_polarity",  size=4, offset=4, reset=0),
        ])

        self.rx_cfg1    = CSRStorage(fields=[
            CSRField("tiafe_cfg_rx_lane_map",       size=16, offset=0, reset=0),
        ])

        self.rx_cfg2 = CSRStorage(fields=[
            CSRField("tiafe_cfg_rx_buffer_release_delay",       size=10, offset=0, reset=0),
        ])

        self.rx_cfg3 = CSRStorage(fields=[
            CSRField("swap_iq",       size=4, offset=0, reset=0xF),
        ])

        self.rx_status0 = CSRStatus(fields=[
            CSRField("jesd_rx_sysref_realign_count",       size=4, offset=0, reset=0),
        ])

        self.tx_ctrl    = CSRStorage(fields=[
            CSRField("tiafe_tx_sync_reset",         size=1, offset=0, reset=1),
            CSRField("tx_clr_sysref_realign_count", size=1, offset=1, reset=0),

        ])

        self.tx_cfg0    = CSRStorage(fields=[
            CSRField("tiafe_cfg_tx_lane_enabled",   size=4, offset=0, reset=0x0),
            CSRField("tiafe_cfg_tx_lane_polarity",  size=4, offset=4, reset=0),
        ])

        self.tx_cfg1    = CSRStorage(fields=[
            CSRField("tiafe_cfg_tx_lane_map",       size=16, offset=0, reset=0),
        ])

        self.tx_cfg3 = CSRStorage(fields=[
            CSRField("swap_iq",       size=4, offset=0, reset=0xF),
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

        # Conditional sources/sinks based on demux parameter
        if not demux:
            # Direct sources/sinks (only when demux=False)
            self.source = AXIStreamInterface(256, clock_domain=m_clk_domain)
            self.sink   = AXIStreamInterface(256, clock_domain=s_clk_domain)
        else:
            self.source = AXIStreamInterface(128, clock_domain=demux_clk_domain)
            self.sink   = AXIStreamInterface(128, clock_domain=demux_clk_domain)

        self.afe_source = afe_source = AXIStreamInterface(256, clock_domain=m_clk_domain)
        self.afe_sink   = afe_sink   = AXIStreamInterface(256, clock_domain=s_clk_domain)
        self.rx_en      = Signal()

        # Add sources
        platform.add_source("./gateware/AFE79xx/afe79xx_jesd_ip_top.v")
        platform.add_source("./gateware/AFE79xx/afe79xx_ti_ip_top.v")
        platform.add_source("./gateware/AFE79xx/afe79xx_xcvr_top.v")
        platform.add_source("./gateware/AFE79xx/afe79xx_xcvr_wrapper.sv")
        platform.add_source("./gateware/AFE79xx/TI_IP_core_66b64/TI_204c_IP_6664.svp")

        #platform.add_ip("./gateware/afe79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth_uscale_64b66b_xcvr_xcau15p.xci")
        #platform.toolchain.project_commands.append("source " + os.path.abspath("./gateware/afe79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth_uscale_64b66b_xcvr_xcau15p.tcl"))
        #platform.toolchain.project_commands.append("synth_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p] -force")

        platform.toolchain.project_commands.append("import_ip " + os.path.abspath("./gateware/AFE79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth_uscale_64b66b_xcvr_xcau15p.xci"))
        platform.toolchain.project_commands.append("upgrade_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p]")
        platform.toolchain.project_commands.append("synth_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p] -force")
        platform.toolchain.project_commands.append("set hipersdr_44xx_defines {{GT_XCVR_NAME=gth_uscale_64b66b_xcvr_xcau15p}}")
        platform.toolchain.project_commands.append("set_property verilog_define $hipersdr_44xx_defines [get_filesets sources_1]")
        platform.toolchain.project_commands.append("get_ips")

        # Timing Constraints -----------------------------------------------------------------------
        # FIXME: Improve, minimal for now.
        timings_sdc_filename = "afe79xx_timing.xdc"
        with open(timings_sdc_filename, "w") as f:
            # Write timing constraints.
            f.write("# FPGA_GT_AFEREF 245.76Mhz\n")
            f.write("create_clock -period 4.069 -name fpga_gt_aferef_clk [get_ports afe79xx_serdes_x4_fpga_gt_aferef_p]\n\n")

            f.write("# FPGA_1PPS 245.76Mhz\n")
            f.write("create_clock -period 4.069*2 -name fpga_1pps_clk [get_ports FPGA_1PPS_p]\n\n")

            f.write("# FPGA_SYSREF 3.84Mhz\n")
            f.write("create_clock -period 260.416 -name fpga_sysref_clk [get_ports FPGA_SYSREF_p]\n\n")

            f.write("set_clock_groups -name afe_async1 -asynchronous -group [get_clocks fpga_1pps_clk]\n\n")
            f.write("set_clock_groups -name afe_async2 -asynchronous -group [get_clocks xcvr_top_inst_n_0]\n\n")
            f.write("set_clock_groups -name afe_async3 -asynchronous -group [get_clocks xcvr_top_inst_n_1]\n\n")
        platform.add_source(timings_sdc_filename)


        #platform.add_platform_command("source ./gateware/afe79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/gth.tcl")

        # Clock Domains.
        # --------------
        self.xcvr_rx_clock = ClockDomain()
        self.xcvr_tx_clock = ClockDomain()

        # create misc signals
        self.fpga_gt_aferef_n                               = Signal()  # GT CLOCK 245.76 MHZ
        self.fpga_gt_aferef_p                               = Signal()  # GT CLOCK 245.76 MHZ
        self.tiafe_jesd_plls_locked                         = Signal(2)
        self.fpga_grx_n                                     = Signal()  # input
        self.fpga_grx_p                                     = Signal()  # input
        self.fpga_gtx_n                                     = Signal()  # output
        self.fpga_gtx_p                                     = Signal()  # output
        self.tiafe_master_reset_n                           = Signal()  # GPO / Asynchronous master reset
        self.clk_wiz_clk_out1                               = Signal()  # / CLOCK 100.00
        self.afe7900_jesd_ip_top_0_xcvr_rx_clock            = Signal()
        self.fpga_sysclk_clk                                = Signal()  # / SYSCLK CLOCK 245.76
        self.tiafe_rx_sync_reset                            = Signal()  # GPO
        self.tiafe_cfg_rx_lane_enabled                      = Signal(4)  # GPO
        self.tiafe_cfg_rx_lane_polarity                     = Signal(4)  # GPO
        self.tiafe_cfg_rx_lane_map                          = Signal(16)  # GPO
        self.tiafe_rx_samples                               = Signal(256)  # # # # # # # # # # # # # # # # # # # # # # # # # # # # / SAMPLES
        self.tiafe_rx_samples_valid                         = Signal()
        self.tiafe_rx_samples_start_of_multiframe           = Signal()  # Start of Extended MultiBlock marker for first sample
        self.tiafe_jesd_rx_lane_buffer_overflow             = Signal(4)  # Elastic buffer overflow status Rx IP
        self.fpga_sysref_clk                                = Signal()  # / SYSREF   CLOCK 3.84
        self.tiafe_jesd_rx_sysref_realign_count             = Signal(4)  # / Rx SYSREF realignment counter
        self.tiafe_rx_clr_sysref_realign_count              = Signal()  # / input: Control to clear Rx SYSREF realignment counter
        self.tiafe_cfg_rx_buffer_release_delay              = Signal(10)  # input 10 bit: Lane buffer release delay control
        self.rx_lane_start_of_mblock                        = Signal(4)  # out[3:0] Start of multiblock sideband signals per lane = 64 b / 66b only)
        self.rx_lane_start_of_emblock                       = Signal(4)  # out[3:0] Start of extended multiblock sideband signals per lane(64 b / 66bonly)
        self.rx_lane_crc_error                              = Signal(4)  # out[3:0] CRC error sideband signal per lane(64b / 66bonly)
        self.tijesd_core_err                                = Signal(64)
        self.rx_lemc_pulse                                  = Signal()  # out        Rx IP Extended Multi-Block boundary pulse (64b / 66b only)
        self.afe7900_jesd_ip_top_0_xcvr_tx_clock            = Signal()  # Transceiver interface Tx IP clock
        self.tiafe_tx_sync_reset                            = Signal()  # GPO Application interface reset for Tx IP
        self.tiafe_cfg_tx_lane_enabled                      = Signal(4)  # GPO Lane enable control for Tx IP
        self.tiafe_cfg_tx_lane_polarity                     = Signal(4)  # GPO Lane polarity control for Tx IP
        self.tiafe_cfg_tx_lane_map                          = Signal(16)  # GPO Lane map control for Tx IP
        self.ControlLogic1_0_data_out                       = Signal(256)  # # # # # # # # # # # # # # # # # # # # # # # # # # # # / SAMPLES
        self.ControlLogic1_0_data_out_ready                 = Signal()  # # # # # # # # # # # # # # # # # # # # # # # # # # # # / SAMPLES
        self.tx_samples_start_of_emblock                    = Signal()  # out: Start of Extended MultiBlock marker for first sample
        self.tiafe_jesd_tx_sysref_realign_count             = Signal(4)  # Tx SYSREF realignment counter
        self.tiafe_tx_clr_sysref_realign_count              = Signal()  # GPO Control to clear Tx SYSREF realignment counter
        self.tx_lemc_pulse                                  = Signal()  # out: Tx IP Extended Multi - Block boundary pulse(64 b / 66bonly)
        self.tiafe_jesd_rx_lmfc_to_buffer_release_delay     = Signal(10)  # out 10 bit: Lane buffer release delay for 64b / 66b mode
        self.debug_nfo                                      = Signal(16)
        self.jesd_freerun_clk                               = Signal()

        self.rx_swap_iq                                     = Signal(4)
        self.tx_swap_iq                                     = Signal(4)

        self.DAC_SYNC = Signal(2)
        self.ADC_SYNC = Signal(2)

        self.comb += [
            self.xcvr_rx_clock.clk.eq(self.afe7900_jesd_ip_top_0_xcvr_rx_clock),
            self.xcvr_tx_clock.clk.eq(self.afe7900_jesd_ip_top_0_xcvr_tx_clock),
            pads.AFE_RESET.eq(self.reg00.fields.afe_reset),
            pads.AFE_TRST.eq(self.reg00.fields.afe_trst),
            pads.AFE_SLEEP.eq(self.reg00.fields.afe_sleep),

            #self.tiafe_master_reset_n.eq(self.core_ctrl.fields.afe_core_rst_n),

            #self.tiafe_rx_sync_reset.eq(self.rx_ctrl.fields.tiafe_rx_sync_reset),
            #self.tiafe_cfg_rx_lane_enabled.eq(self.rx_cfg0.fields.tiafe_cfg_rx_lane_enabled),
            #self.tiafe_cfg_rx_lane_polarity.eq(self.rx_cfg0.fields.tiafe_cfg_rx_lane_polarity),
            #self.tiafe_cfg_rx_lane_map.eq(self.rx_cfg1.fields.tiafe_cfg_rx_lane_map),
            #self.tiafe_cfg_rx_buffer_release_delay.eq(self.rx_cfg2.fields.tiafe_cfg_rx_buffer_release_delay),
            #self.tiafe_rx_clr_sysref_realign_count.eq(self.rx_ctrl.fields.rx_clr_sysref_realign_count),

            #self.tiafe_tx_sync_reset.eq(self.tx_ctrl.fields.tiafe_tx_sync_reset),
            #self.tiafe_cfg_tx_lane_enabled.eq(self.tx_cfg0.fields.tiafe_cfg_tx_lane_enabled),
            #self.tiafe_cfg_tx_lane_polarity.eq(self.tx_cfg0.fields.tiafe_cfg_tx_lane_polarity),
            #self.tiafe_cfg_tx_lane_map.eq(self.tx_cfg1.fields.tiafe_cfg_tx_lane_map),
            #self.tiafe_tx_clr_sysref_realign_count.eq(self.tx_ctrl.fields.tx_clr_sysref_realign_count),

            self.rx_status0.fields.jesd_rx_sysref_realign_count.eq(self.tiafe_jesd_rx_sysref_realign_count),
            self.tx_status0.fields.jesd_tx_sysref_realign_count.eq(self.tiafe_jesd_tx_sysref_realign_count),

            self.core_status0.fields.xcvr_plls_locked.eq(self.tiafe_jesd_plls_locked[1]),
            self.core_status0.fields.rx_all_lanes_locked.eq(self.tiafe_jesd_plls_locked[0]),


            self.ADC_SYNC.eq(0x0)


        ]


        self.specials += MultiReg(self.core_ctrl.fields.afe_core_rst_n, self.tiafe_master_reset_n, "fpga_1pps", 2,0)

        self.specials += MultiReg(self.rx_ctrl.fields.tiafe_rx_sync_reset, self.tiafe_rx_sync_reset, "fpga_1pps", 2,1)
        self.specials += MultiReg(self.rx_ctrl.fields.rx_clr_sysref_realign_count, self.tiafe_rx_clr_sysref_realign_count, "fpga_1pps", 2,0)

        self.specials += MultiReg(self.rx_cfg0.fields.tiafe_cfg_rx_lane_enabled, self.tiafe_cfg_rx_lane_enabled,"fpga_1pps", 2,0)
        self.specials += MultiReg(self.rx_cfg0.fields.tiafe_cfg_rx_lane_polarity, self.tiafe_cfg_rx_lane_polarity, "fpga_1pps", 2,0)
        self.specials += MultiReg(self.rx_cfg1.fields.tiafe_cfg_rx_lane_map, self.tiafe_cfg_rx_lane_map, "fpga_1pps", 2,0)
        self.specials += MultiReg(self.rx_cfg2.fields.tiafe_cfg_rx_buffer_release_delay, self.tiafe_cfg_rx_buffer_release_delay, "fpga_1pps", 2,0)
        self.specials += MultiReg(self.rx_cfg3.fields.swap_iq,self.rx_swap_iq, "fpga_1pps", 2, 0)

        self.specials += MultiReg(self.tx_ctrl.fields.tiafe_tx_sync_reset, self.tiafe_tx_sync_reset, "fpga_1pps", 2, 1)
        self.specials += MultiReg(self.tx_cfg0.fields.tiafe_cfg_tx_lane_enabled, self.tiafe_cfg_tx_lane_enabled, "fpga_1pps", 2, 0)
        self.specials += MultiReg(self.tx_cfg0.fields.tiafe_cfg_tx_lane_polarity, self.tiafe_cfg_tx_lane_polarity, "fpga_1pps", 2, 0)
        self.specials += MultiReg(self.tx_cfg1.fields.tiafe_cfg_tx_lane_map, self.tiafe_cfg_tx_lane_map, "fpga_1pps", 2, 0)
        self.specials += MultiReg(self.tx_ctrl.fields.tx_clr_sysref_realign_count, self.tiafe_tx_clr_sysref_realign_count, "fpga_1pps", 2, 0)
        self.specials += MultiReg(self.tx_cfg3.fields.swap_iq, self.tx_swap_iq, "fpga_1pps", 2, 0)



        self.specials += [Instance("IBUFDS",
            p_IOSTANDARD = "LVDS",
            i_I   = pads.DAC_SYNC_p[0],
            i_IB  = pads.DAC_SYNC_n[0],
            o_O   = self.DAC_SYNC[0],
        )]

        self.specials += [Instance("IBUFDS",
            p_IOSTANDARD = "LVDS",
            i_I   = pads.DAC_SYNC_p[1],
            i_IB  = pads.DAC_SYNC_n[1],
            o_O   = self.DAC_SYNC[1],
        )]

        self.specials += [Instance("OBUFDS",
            p_IOSTANDARD = "LVDS",
            o_O   = pads.ADC_SYNC_p[0],
            o_OB  = pads.ADC_SYNC_n[0],
            i_I   = self.ADC_SYNC[0],
        )]

        self.specials += [Instance("OBUFDS",
            p_IOSTANDARD = "LVDS",
            o_O   = pads.ADC_SYNC_p[1],
            o_OB  = pads.ADC_SYNC_n[1],
            i_I   = self.ADC_SYNC[1],
        )]


        ## Create streams
        #s_axis_datawidth = 64
        #s_axis_layout = [("data", max(1, s_axis_datawidth))]
        #s_axis_layout += [("keep", max(1, s_axis_datawidth//8))]
        ## adding reset along with data, assuming resets are not global
        #s_axis_layout += [("areset_n", 1)]
#
        #self.s_axis_iqsmpls = AXIStreamInterface(s_axis_datawidth, layout=s_axis_layout, clock_domain=s_clk_domain)
#
        #m_axis_datawidth = 64
        #m_axis_layout = [("data", max(1, m_axis_datawidth))]
        #m_axis_layout += [("keep", max(1, m_axis_datawidth//8))]
        ## adding reset along with data, assuming resets are not global
        #m_axis_layout += [("areset_n", 1)]
        #self.m_axis_iqpacket = AXIStreamInterface(m_axis_datawidth, layout=m_axis_layout, clock_domain=m_clk_domain)

        # Create params
        self.params_ios = dict()

        # Assign generics
        #self.params_ios.update(
        #)

        # Assign ports
        self.params_ios.update(
            i_xcvr_refclk_n                         = pads.fpga_gt_aferef_n, # GT CLOCK 245.76 MHZ
            i_xcvr_refclk_p                         = pads.fpga_gt_aferef_p, # GT CLOCK 245.76 MHZ
            o_xcvr_plls_locked                      = self.tiafe_jesd_plls_locked[1],
            i_xcvr_rx_n                             = pads.fpga_grx_n, # input
            i_xcvr_rx_p                             = pads.fpga_grx_p, # input
            o_xcvr_tx_n                             = pads.fpga_gtx_n, # output
            o_xcvr_tx_p                             = pads.fpga_gtx_p, # output
            i_master_reset_n                        = self.tiafe_master_reset_n, # GPO / Asynchronous master reset
            i_xcvr_freerun_clock                    = self.jesd_freerun_clk, # / CLOCK 100.00
            o_xcvr_rx_clock                         = self.afe7900_jesd_ip_top_0_xcvr_rx_clock,
            i_rx_sys_clock                          = ClockSignal("fpga_1pps"), # / SYSCLK CLOCK 245.76
            i_rx_sync_reset                         = self.tiafe_rx_sync_reset, # GPO
            i_cfg_rx_lane_enable                    = self.tiafe_cfg_rx_lane_enabled, # GPO
            i_cfg_rx_lane_polarity                  = self.tiafe_cfg_rx_lane_polarity, # GPO
            i_cfg_rx_lane_map                       = self.tiafe_cfg_rx_lane_map, # GPO
            o_rx_all_lanes_locked                   = self.tiafe_jesd_plls_locked[0], # ????
            o_rx_samples                            = afe_source.data, # # # # # # # # # # # # # # # # # # # # # # # # # # # # / SAMPLES
            o_rx_samples_valid                      = afe_source.valid,
            o_rx_samples_start_of_emblock           = self.tiafe_rx_samples_start_of_multiframe, # Start of Extended MultiBlock marker for first sample
            o_rx_lane_buffer_overflow               = self.tiafe_jesd_rx_lane_buffer_overflow,        # Elastic buffer overflow status Rx IP
            i_rx_sysref                             = ClockSignal("fpga_sysref"), # / SYSREF   CLOCK 3.84
            o_rx_sysref_realign_count               = self.tiafe_jesd_rx_sysref_realign_count, # / Rx SYSREF realignment counter
            i_rx_clr_sysref_realign_count           = self.tiafe_rx_clr_sysref_realign_count, # / input: Control to clear Rx SYSREF realignment counter
            i_cfg_rx_buffer_release_delay           = self.tiafe_cfg_rx_buffer_release_delay, # input 10 bit: Lane buffer release delay control
            # RX extra signals
            o_rx_lane_start_of_mblock               = self.rx_lane_start_of_mblock, # out[3:0] Start of multiblock sideband signals per lane = 64 b / 66b only)
            o_rx_lane_start_of_emblock              = self.rx_lane_start_of_emblock, # out[3:0] Start of extended multiblock sideband signals per lane(64 b / 66bonly)
            o_rx_lane_crc_error                     = self.rx_lane_crc_error, # out[3:0] CRC error sideband signal per lane(64b / 66bonly)
            o_rx_lane_invalid_header_err_count      = self.tijesd_core_err[0:16], # out[15:0] Count value for Block Header errors (per lane)
            o_rx_lane_invalid_eomb_err_count        = self.tijesd_core_err[16:32], # out[15:0] Count value for End of Multi-Block errors (per lane)
            o_rx_lane_invalid_eoemb_err_count       = self.tijesd_core_err[32:48], # out[15:0] Count value for End of Extended Multi-Block errors (per lane)
            o_rx_lane_crc_mismatch_err_count        = self.tijesd_core_err[48:64], # out[15:0] Count value for CRC mismatch errors (per lane)
            o_rx_lemc_pulse                         = self.rx_lemc_pulse, # out        Rx IP Extended Multi-Block boundary pulse (64b / 66b only)
            i_rx_clr_all_err_count                  = Constant(0, 4),    # input    Control signal to clear all error counters
            i_rx_lane_clr_invalid_header_err_count  = Constant(0, 4),    # input    Control signal to clear Block Header error count
            i_rx_lane_clr_invalid_eomb_err_count    = Constant(0, 4),    # input    Control signal to clear End of Multi-Block error count
            i_rx_lane_clr_invalid_eoemb_err_count   = Constant(0, 4),    # input    Control signal to clear End of Extended Multi-Block error count
            i_rx_lane_clr_crc_mismatch_err_count    = Constant(0, 4),    # input    Control signal to clear CRC mismatch error count

            # TX signals
            o_xcvr_tx_clock                         = self.afe7900_jesd_ip_top_0_xcvr_tx_clock, # Transceiver interface Tx IP clock
            i_tx_sys_clock                          = ClockSignal("fpga_1pps"), # / SYSCLK   CLOCK 245.76
            i_tx_sync_reset                         = self.tiafe_tx_sync_reset, # GPO Application interface reset for Tx IP
            i_cfg_tx_lane_enable                    = self.tiafe_cfg_tx_lane_enabled, # GPO Lane enable control for Tx IP
            i_cfg_tx_lane_polarity                  = self.tiafe_cfg_tx_lane_polarity, # GPO Lane polarity control for Tx IP
            i_cfg_tx_lane_map                       = self.tiafe_cfg_tx_lane_map, # GPO Lane map control for Tx IP
            i_tx_samples                            = afe_sink.data, # # # # # # # # # # # # # # # # # # # # # # # # # # # # / SAMPLES
            o_tx_samples_ready                      = afe_sink.ready, # # # # # # # # # # # # # # # # # # # # # # # # # # # # / SAMPLES
            o_tx_samples_start_of_emblock           = self.tx_samples_start_of_emblock, # out: Start of Extended MultiBlock marker for first sample
            i_tx_sysref                             = ClockSignal("fpga_sysref"),                                         # / SYSREF   CLOCK 3.84
            o_tx_sysref_realign_count               = self.tiafe_jesd_tx_sysref_realign_count, # Tx SYSREF realignment counter
            i_tx_clr_sysref_realign_count           = self.tiafe_tx_clr_sysref_realign_count, # GPO Control to clear Tx SYSREF realignment counter

            # TX EXTRA SIGNALS!!!!
            o_tx_lemc_pulse                         = self.tx_lemc_pulse, # out: Tx IP Extended Multi - Block boundary pulse(64 b / 66bonly)
            o_rx_lemc_to_buffer_release_delay       = self.tiafe_jesd_rx_lmfc_to_buffer_release_delay, # out 10 bit: Lane buffer release delay for 64b / 66b mode

            o_debug_nfo                             = self.debug_nfo,
        )

        # Create instance and assign params
        self.specials += Instance("afe79xx_jesd_ip_top", **self.params_ios)

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

        # Handle data signals
        # if demux == false, assign source and sink directly to afe
        if not demux:
            self.comb += [
                self.source.data.eq(afe_source.data),
                self.source.valid.eq(afe_source.valid),
                afe_sink.data.eq(self.sink.data),
                afe_sink.valid.eq(self.sink.valid),
            ]
        else:
            # -----------------------------------------
            # RX data path
            # Create async FIFOs for clock domain crossing (must be buffered=True to improve timing)
            rx_cdc = stream.AsyncFIFO([("data", 256)], 32, buffered=True)
            rx_cdc = ClockDomainsRenamer({"write": m_clk_domain, "read": double_clk_domain.name})(rx_cdc)
            self.rx_cdc = rx_cdc

            # Stream converter 256b to 128b
            rx_conv = ResetInserter()(
                ClockDomainsRenamer(double_clk_domain.name)(stream.Converter(256, 128)))
            rx_conv = stream.BufferizeEndpoints({"source": stream.DIR_SOURCE})(rx_conv)
            self.rx_conv = rx_conv

            # Rearange AFE RX data
            data_s0_raw = Signal(128)
            data_s1_raw = Signal(128)

            data_s0 = Signal(128)
            data_s1 = Signal(128)

            for j in range(4 * 2):
                # lower 16 bits
                self.comb += data_s0_raw[16*j:16*j+16].eq(afe_source.data[32*j:32*j+16])
                # upper 16 bits
                self.comb += data_s1_raw[16*j:16*j+16].eq(afe_source.data[32*j+16:32*j+32])
#

            # ------------------------------------------------------------
            # IQ Swap Mux (Per-channel control)
            # ------------------------------------------------------------
            # Define your custom mapping: index 'i' maps to this bit of rx_swap_iq
            # i=0 -> bit 3, i=1 -> bit 2, i=2 -> bit 0, i=3 -> bit 1
            # AFE channels are mapped CH4 -> A, CH3 -> B, CH1-> C, CH2->D
            swap_map = [2, 3, 1, 0]
            # Iterate over 4 channels (128 bits total / 32 bits per channel)
            for i in range(4):
                # Calculate slice indices
                lo = 32 * i
                hi = 32 * (i + 1)

                # Select the correct control bit using the lookup list
                swap_enable = self.rx_swap_iq[swap_map[i]]

                # --- Stream 0 ---
                # Extract the 32-bit I/Q pair
                ch_s0 = data_s0_raw[lo:hi]

                # Mux based on the specific bit 'i' of the control signal
                self.comb += data_s0[lo:hi].eq(Mux(swap_enable, swap_iq(ch_s0), ch_s0))

                # --- Stream 1 ---
                # Extract the 32-bit I/Q pair
                ch_s1 = data_s1_raw[lo:hi]

                # Mux based on the specific bit 'i' of the control signal
                self.comb += data_s1[lo:hi].eq(Mux(swap_enable, swap_iq(ch_s1), ch_s1))

            # Register after IQ mux and connect to rx_cdc
            self.sync.fpga_1pps += [
                # AFE -> CDC FIFO -> 256 to 128 conv -> source_demux0
                # CDC
                rx_cdc.sink.valid.eq(afe_source.valid),
                rx_cdc.sink.data[:128].eq(data_s1),
                rx_cdc.sink.data[128:256].eq(data_s0),
            ]


            # Connect RX streams
            self.comb += [
                ## AFE -> CDC FIFO -> 256 to 128 conv -> source_demux0
                ##CDC
                #rx_cdc.sink.valid.eq(afe_source.valid),
                #rx_cdc.sink.data[:128].eq(data_s1),
                #rx_cdc.sink.data[128:256].eq(data_s0),

                # Stream converter 256b to 128
                rx_conv.reset.eq(~self.rx_en),
                rx_conv.sink.valid.eq(rx_cdc.source.valid),
                rx_conv.sink.data.eq(rx_cdc.source.data),
                rx_cdc.source.ready.eq(rx_conv.sink.ready),
            ]
            # AFE bindings do not correspond to ABCD channels, channels need to be muxed to fit
            rx_conv_ch_mux_data = Signal(128)
            self.rx_conv_ch_mux_data = rx_conv_ch_mux_data
            self.comb += [
                rx_conv_ch_mux_data[64: 96].eq(rx_conv.source.data[0 : 32]), #CH 1 of AFE is CH C
                rx_conv_ch_mux_data[96:128].eq(rx_conv.source.data[32: 64]), #CH 2 of AFE is CH D
                rx_conv_ch_mux_data[32: 64].eq(rx_conv.source.data[64: 96]), #CH 3 of AFE is CH B
                rx_conv_ch_mux_data[0 : 32].eq(rx_conv.source.data[96:128]), #CH 4 of AFE is CH A
            ]

            endpoint_dict = {
                "source": DIR_SOURCE,  # Add output buffer to the 'source' endpoint
                "sink": DIR_SINK,      # Add input buffer to the 'sink' endpoint
            }
            RX_A_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="down",clock_domain=double_clk_domain.name))
            RX_B_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="down",clock_domain=double_clk_domain.name))
            RX_C_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="down",clock_domain=double_clk_domain.name))
            RX_D_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="down",clock_domain=double_clk_domain.name))
            self.RX_A_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(RX_A_RESAMPLER)
            self.RX_B_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(RX_B_RESAMPLER)
            self.RX_C_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(RX_C_RESAMPLER)
            self.RX_D_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(RX_D_RESAMPLER)
            self.comb += [
                self.RX_A_RESAMPLER.sink.data.eq(rx_conv_ch_mux_data[0 : 32]),
                self.RX_A_RESAMPLER.sink.valid.eq( rx_conv.source.valid),
                self.RX_A_RESAMPLER.reset.eq(~self.rx_en),
                rx_conv.source.ready.eq( self.RX_A_RESAMPLER.sink.ready),

                self.RX_B_RESAMPLER.sink.data.eq(rx_conv_ch_mux_data[32: 64]),
                self.RX_B_RESAMPLER.sink.valid.eq( rx_conv.source.valid),
                self.RX_B_RESAMPLER.reset.eq(~self.rx_en),
                # No Ready, handled by RX_A

                self.RX_C_RESAMPLER.sink.data.eq(rx_conv_ch_mux_data[64: 96]),
                self.RX_C_RESAMPLER.sink.valid.eq( rx_conv.source.valid),
                self.RX_C_RESAMPLER.reset.eq(~self.rx_en), #VHDL instances in resampler use active low reset
                # No Ready, handled by RX_A

                self.RX_D_RESAMPLER.sink.data.eq(rx_conv_ch_mux_data[96:128]),
                self.RX_D_RESAMPLER.sink.valid.eq( rx_conv.source.valid),
                self.RX_D_RESAMPLER.reset.eq(~self.rx_en), #VHDL instances in resampler use active low reset
                # No Ready, handled by RX_A
            ]

            # Transition from double_clk (491.52MHz) to demux_clk (500MHz) for LimeTop
            rx_out_fifo = stream.AsyncFIFO([("data", 128)], 64, buffered=True)
            rx_out_fifo = ClockDomainsRenamer({"write": double_clk_domain.name, "read": demux_clk_domain})(rx_out_fifo)
            self.rx_out_fifo = rx_out_fifo



            self.comb += [
                rx_out_fifo.sink.valid.eq( self.RX_A_RESAMPLER.source.valid),
                rx_out_fifo.sink.data.eq(Cat(
                    self.RX_A_RESAMPLER.source.data,
                    self.RX_B_RESAMPLER.source.data,
                    self.RX_C_RESAMPLER.source.data,
                    self.RX_D_RESAMPLER.source.data,
                )),
                self.RX_A_RESAMPLER.source.ready.eq( rx_out_fifo.sink.ready),
                self.RX_B_RESAMPLER.source.ready.eq( rx_out_fifo.sink.ready),
                self.RX_C_RESAMPLER.source.ready.eq( rx_out_fifo.sink.ready),
                self.RX_D_RESAMPLER.source.ready.eq( rx_out_fifo.sink.ready),

                rx_out_fifo.source.connect(self.source, keep={"valid", "ready", "data"}),
                self.source.keep.eq(0xFFFF),
            ]


            # -----------------------------------------
            # TX data path
            self.tx_en     = Signal()

            # Transition from demux_clk (500MHz) to double_clk (491.52MHz) for resamplers
            tx_in_fifo = stream.AsyncFIFO([("data", 128)], 64, buffered=True)
            tx_in_fifo = ClockDomainsRenamer({"write": demux_clk_domain, "read": double_clk_domain.name})(tx_in_fifo)
            self.tx_in_fifo = tx_in_fifo

            TX_A_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="up",clock_domain=double_clk_domain.name))
            TX_B_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="up",clock_domain=double_clk_domain.name))
            TX_C_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="up",clock_domain=double_clk_domain.name))
            TX_D_RESAMPLER = BufferizeEndpoints(endpoint_dict)(Resampler(soc,sample_width=16,stages=resampling_stages,direction="up",clock_domain=double_clk_domain.name))
            self.TX_A_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(TX_A_RESAMPLER)
            self.TX_B_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(TX_B_RESAMPLER)
            self.TX_C_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(TX_C_RESAMPLER)
            self.TX_D_RESAMPLER = ClockDomainsRenamer(double_clk_domain.name)(TX_D_RESAMPLER)

            self.comb += [
                self.sink.connect(tx_in_fifo.sink, keep={"valid", "ready", "data"}),

                self.TX_A_RESAMPLER.sink.valid.eq( tx_in_fifo.source.valid),
                self.TX_B_RESAMPLER.sink.valid.eq( tx_in_fifo.source.valid),
                self.TX_C_RESAMPLER.sink.valid.eq( tx_in_fifo.source.valid),
                self.TX_D_RESAMPLER.sink.valid.eq( tx_in_fifo.source.valid),

                self.TX_A_RESAMPLER.sink.data.eq(tx_in_fifo.source.data[0 : 32]),
                self.TX_B_RESAMPLER.sink.data.eq(tx_in_fifo.source.data[32: 64]),
                self.TX_C_RESAMPLER.sink.data.eq(tx_in_fifo.source.data[64: 96]),
                self.TX_D_RESAMPLER.sink.data.eq(tx_in_fifo.source.data[96:128]),

                tx_in_fifo.source.ready.eq( self.TX_A_RESAMPLER.sink.ready),

                self.TX_A_RESAMPLER.reset.eq(~self.tx_en),
                self.TX_B_RESAMPLER.reset.eq(~self.tx_en),
                self.TX_C_RESAMPLER.reset.eq(~self.tx_en),
                self.TX_D_RESAMPLER.reset.eq(~self.tx_en),
            ]

            self.Resampler_max_value = CSRStatus(size=4, description="Maximum divider value for resampling")
            self.comb += self.Resampler_max_value.status.eq(resampling_stages)

            tx_conv = stream.Converter(nbits_from=128, nbits_to=256)
            tx_conv = ClockDomainsRenamer(double_clk_domain.name)(tx_conv)
            self.tx_conv = tx_conv

            # Omit parts of Axi interface we don't use + data, because we handle that seperately
            # AFE bindings do not correspond to ABCD channels, channels need to be muxed to fit
            # IQ mux Logic: Mux(condition, swapped_data, normal_data)
            self.comb += [
                # -----------------------------------------------------------------
                # Channel A -> AFE CH 4 (Bits 96-128) | Controlled by tx_swap_iq[0]
                # -----------------------------------------------------------------
                tx_conv.sink.data[96:128].eq(Mux(self.tx_swap_iq[0],swap_iq(self.TX_A_RESAMPLER.source.data),self.TX_A_RESAMPLER.source.data)),
                # -----------------------------------------------------------------
                # Channel B -> AFE CH 3 (Bits 64-96) | Controlled by tx_swap_iq[1]
                # -----------------------------------------------------------------
                tx_conv.sink.data[64:96].eq(Mux(self.tx_swap_iq[1],swap_iq(self.TX_B_RESAMPLER.source.data),self.TX_B_RESAMPLER.source.data)),
                # -----------------------------------------------------------------
                # Channel C -> AFE CH 1 (Bits 0-32) | Controlled by tx_swap_iq[2]
                # -----------------------------------------------------------------
                tx_conv.sink.data[0:32].eq(Mux(self.tx_swap_iq[2],swap_iq(self.TX_C_RESAMPLER.source.data),self.TX_C_RESAMPLER.source.data)),
                # -----------------------------------------------------------------
                # Channel D -> AFE CH 2 (Bits 32-64) | Controlled by tx_swap_iq[3]
                # -----------------------------------------------------------------
                tx_conv.sink.data[32:64].eq(Mux(self.tx_swap_iq[3],swap_iq(self.TX_D_RESAMPLER.source.data),self.TX_D_RESAMPLER.source.data)),
            ]


            self.comb += [
                self.tx_conv.sink.valid.eq( self.TX_A_RESAMPLER.source.valid),
                self.TX_A_RESAMPLER.source.ready.eq( tx_conv.sink.ready),
                self.TX_B_RESAMPLER.source.ready.eq( tx_conv.sink.ready),
                self.TX_C_RESAMPLER.source.ready.eq( tx_conv.sink.ready),
                self.TX_D_RESAMPLER.source.ready.eq( tx_conv.sink.ready),
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
                cd_from        =double_clk_domain.name,
                cd_to          =s_clk_domain,
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

        if demux:
            self.flow_control_signals.m_clk += [
                rx_cdc.sink.valid,
                rx_cdc.sink.ready,
            ]
            self.flow_control_signals.s_clk += [
                self.tx_cdc.source.valid,
                self.flow_control_signals.s_clk[0], # afe_sink.ready
            ]
            self.flow_control_signals.double_clk = [
                rx_cdc.source.valid,
                rx_cdc.source.ready,
                rx_conv.sink.valid,
                rx_conv.sink.ready,
                rx_conv.source.valid,
                rx_conv.source.ready,
                self.RX_A_RESAMPLER.sink.valid,
                self.RX_A_RESAMPLER.sink.ready,
                self.RX_A_RESAMPLER.source.valid,
                self.RX_A_RESAMPLER.source.ready,
                self.rx_out_fifo.sink.valid,
                self.rx_out_fifo.sink.ready,

                self.tx_in_fifo.source.valid,
                self.tx_in_fifo.source.ready,
                self.TX_A_RESAMPLER.sink.valid,
                self.TX_A_RESAMPLER.sink.ready,
                self.TX_A_RESAMPLER.source.valid,
                self.TX_A_RESAMPLER.source.ready,
                self.tx_conv.sink.valid,
                self.tx_conv.sink.ready,
                self.tx_conv.source.valid,
                self.tx_conv.source.ready,
                self.tx_cdc.sink.valid,
                self.tx_cdc.sink.ready,
            ]
            self.flow_control_signals.demux_clk = [
                self.rx_out_fifo.source.valid,
                self.rx_out_fifo.source.ready,
                self.source.valid,
                self.source.ready,
                self.sink.valid,
                self.sink.ready,
                self.tx_in_fifo.sink.valid,
                self.tx_in_fifo.sink.ready,
            ]
        else:
            self.flow_control_signals.m_clk += [
                self.source.valid,
                self.source.ready,
            ]
            self.flow_control_signals.s_clk += [
                self.sink.valid,
                self.sink.ready,
            ]
