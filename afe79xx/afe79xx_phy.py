#!/usr/bin/env python3
import os

from migen import *
from migen.genlib.cdc import MultiReg

from litex.soc.interconnect.axi import AXIStreamInterface

from gateware.common import *


class AFE79xxPHY(LiteXModule):
    """AFE79xx JESD204C/physical-interface wrapper.

    This module owns the TI JESD IP instance, device pins, JESD clocks/resets,
    lane configuration/status and the native 256-bit RX/TX sample interfaces.

    Sample formatting, logical A/B/C/D channel mapping, IQ swapping and DSP are
    intentionally outside this module.
    """

    def __init__(self, platform, pads, afe_data_cd,
                 reg00, core_ctrl,
                 rx_ctrl, rx_cfg0, rx_cfg1, rx_cfg2, rx_status0,
                 tx_ctrl, tx_cfg0, tx_cfg1, tx_status0,
                 core_status0):
        self.platform = platform

        # Native JESD application-side sample interfaces.
        self.source = AXIStreamInterface(256, clock_domain=afe_data_cd)
        self.sink   = AXIStreamInterface(256, clock_domain=afe_data_cd)

        self._add_platform_sources()
        self._add_timing_constraints()

        # Transceiver clocks exposed for constraints/debugging.
        self.xcvr_rx_clock = ClockDomain()
        self.xcvr_tx_clock = ClockDomain()

        # JESD/AFE control and status signals.
        self.tiafe_jesd_plls_locked                     = Signal(2)
        self.tiafe_master_reset_n                       = Signal()
        self.afe7900_jesd_ip_top_0_xcvr_rx_clock        = Signal()
        self.tiafe_rx_sync_reset                        = Signal()
        self.tiafe_cfg_rx_lane_enabled                  = Signal(4)
        self.tiafe_cfg_rx_lane_polarity                 = Signal(4)
        self.tiafe_cfg_rx_lane_map                      = Signal(16)
        self.tiafe_rx_samples_start_of_multiframe       = Signal()
        self.tiafe_jesd_rx_lane_buffer_overflow         = Signal(4)
        self.tiafe_jesd_rx_sysref_realign_count         = Signal(4)
        self.tiafe_rx_clr_sysref_realign_count          = Signal()
        self.tiafe_cfg_rx_buffer_release_delay          = Signal(10)
        self.rx_lane_start_of_mblock                    = Signal(4)
        self.rx_lane_start_of_emblock                   = Signal(4)
        self.rx_lane_crc_error                          = Signal(4)
        self.tijesd_core_err                            = Signal(64)
        self.rx_lemc_pulse                              = Signal()

        self.afe7900_jesd_ip_top_0_xcvr_tx_clock        = Signal()
        self.tiafe_tx_sync_reset                        = Signal()
        self.tiafe_cfg_tx_lane_enabled                  = Signal(4)
        self.tiafe_cfg_tx_lane_polarity                 = Signal(4)
        self.tiafe_cfg_tx_lane_map                      = Signal(16)
        self.tx_samples_start_of_emblock                = Signal()
        self.tiafe_jesd_tx_sysref_realign_count         = Signal(4)
        self.tiafe_tx_clr_sysref_realign_count          = Signal()
        self.tx_lemc_pulse                              = Signal()
        self.tiafe_jesd_rx_lmfc_to_buffer_release_delay = Signal(10)
        self.debug_nfo                                  = Signal(16)
        self.jesd_freerun_clk                           = Signal()

        self.DAC_SYNC = Signal(2)
        self.ADC_SYNC = Signal(2)

        self.comb += [
            self.xcvr_rx_clock.clk.eq(self.afe7900_jesd_ip_top_0_xcvr_rx_clock),
            self.xcvr_tx_clock.clk.eq(self.afe7900_jesd_ip_top_0_xcvr_tx_clock),

            pads.AFE_RESET.eq(reg00.fields.afe_reset),
            pads.AFE_TRST.eq(reg00.fields.afe_trst),
            pads.AFE_SLEEP.eq(reg00.fields.afe_sleep),

            rx_status0.fields.jesd_rx_sysref_realign_count.eq(
                self.tiafe_jesd_rx_sysref_realign_count),
            tx_status0.fields.jesd_tx_sysref_realign_count.eq(
                self.tiafe_jesd_tx_sysref_realign_count),

            core_status0.fields.xcvr_plls_locked.eq(self.tiafe_jesd_plls_locked[1]),
            core_status0.fields.rx_all_lanes_locked.eq(self.tiafe_jesd_plls_locked[0]),

            self.ADC_SYNC.eq(0x0),
        ]

        # CSR/control clock-domain crossings.
        self.specials += MultiReg(
            core_ctrl.fields.afe_core_rst_n,
            self.tiafe_master_reset_n,
            afe_data_cd, 2, 0)

        self.specials += MultiReg(
            rx_ctrl.fields.tiafe_rx_sync_reset,
            self.tiafe_rx_sync_reset,
            afe_data_cd, 2, 1)
        self.specials += MultiReg(
            rx_ctrl.fields.rx_clr_sysref_realign_count,
            self.tiafe_rx_clr_sysref_realign_count,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            rx_cfg0.fields.tiafe_cfg_rx_lane_enabled,
            self.tiafe_cfg_rx_lane_enabled,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            rx_cfg0.fields.tiafe_cfg_rx_lane_polarity,
            self.tiafe_cfg_rx_lane_polarity,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            rx_cfg1.fields.tiafe_cfg_rx_lane_map,
            self.tiafe_cfg_rx_lane_map,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            rx_cfg2.fields.tiafe_cfg_rx_buffer_release_delay,
            self.tiafe_cfg_rx_buffer_release_delay,
            afe_data_cd, 2, 0)

        self.specials += MultiReg(
            tx_ctrl.fields.tiafe_tx_sync_reset,
            self.tiafe_tx_sync_reset,
            afe_data_cd, 2, 1)
        self.specials += MultiReg(
            tx_cfg0.fields.tiafe_cfg_tx_lane_enabled,
            self.tiafe_cfg_tx_lane_enabled,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            tx_cfg0.fields.tiafe_cfg_tx_lane_polarity,
            self.tiafe_cfg_tx_lane_polarity,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            tx_cfg1.fields.tiafe_cfg_tx_lane_map,
            self.tiafe_cfg_tx_lane_map,
            afe_data_cd, 2, 0)
        self.specials += MultiReg(
            tx_ctrl.fields.tx_clr_sysref_realign_count,
            self.tiafe_tx_clr_sysref_realign_count,
            afe_data_cd, 2, 0)

        # AFE synchronization pins.
        self.specials += Instance(
            "IBUFDS",
            p_IOSTANDARD = "LVDS",
            i_I           = pads.DAC_SYNC_p[0],
            i_IB          = pads.DAC_SYNC_n[0],
            o_O           = self.DAC_SYNC[0],
        )
        self.specials += Instance(
            "IBUFDS",
            p_IOSTANDARD = "LVDS",
            i_I           = pads.DAC_SYNC_p[1],
            i_IB          = pads.DAC_SYNC_n[1],
            o_O           = self.DAC_SYNC[1],
        )
        self.specials += Instance(
            "OBUFDS",
            p_IOSTANDARD = "LVDS",
            o_O           = pads.ADC_SYNC_p[0],
            o_OB          = pads.ADC_SYNC_n[0],
            i_I           = self.ADC_SYNC[0],
        )
        self.specials += Instance(
            "OBUFDS",
            p_IOSTANDARD = "LVDS",
            o_O           = pads.ADC_SYNC_p[1],
            o_OB          = pads.ADC_SYNC_n[1],
            i_I           = self.ADC_SYNC[1],
        )

        # TI AFE79xx JESD204C IP.
        params_ios = dict(
            i_xcvr_refclk_n                         = pads.fpga_gt_aferef_n,
            i_xcvr_refclk_p                         = pads.fpga_gt_aferef_p,
            o_xcvr_plls_locked                      = self.tiafe_jesd_plls_locked[1],
            i_xcvr_rx_n                             = pads.fpga_grx_n,
            i_xcvr_rx_p                             = pads.fpga_grx_p,
            o_xcvr_tx_n                             = pads.fpga_gtx_n,
            o_xcvr_tx_p                             = pads.fpga_gtx_p,
            i_master_reset_n                        = self.tiafe_master_reset_n,
            i_xcvr_freerun_clock                    = self.jesd_freerun_clk,
            o_xcvr_rx_clock                         = self.afe7900_jesd_ip_top_0_xcvr_rx_clock,

            i_rx_sys_clock                          = ClockSignal(afe_data_cd),
            i_rx_sync_reset                         = self.tiafe_rx_sync_reset,
            i_cfg_rx_lane_enable                    = self.tiafe_cfg_rx_lane_enabled,
            i_cfg_rx_lane_polarity                  = self.tiafe_cfg_rx_lane_polarity,
            i_cfg_rx_lane_map                       = self.tiafe_cfg_rx_lane_map,
            o_rx_all_lanes_locked                   = self.tiafe_jesd_plls_locked[0],
            o_rx_samples                            = self.source.data,
            o_rx_samples_valid                      = self.source.valid,
            o_rx_samples_start_of_emblock           = self.tiafe_rx_samples_start_of_multiframe,
            o_rx_lane_buffer_overflow               = self.tiafe_jesd_rx_lane_buffer_overflow,
            i_rx_sysref                             = ClockSignal("fpga_sysref"),
            o_rx_sysref_realign_count               = self.tiafe_jesd_rx_sysref_realign_count,
            i_rx_clr_sysref_realign_count           = self.tiafe_rx_clr_sysref_realign_count,
            i_cfg_rx_buffer_release_delay           = self.tiafe_cfg_rx_buffer_release_delay,
            o_rx_lane_start_of_mblock               = self.rx_lane_start_of_mblock,
            o_rx_lane_start_of_emblock              = self.rx_lane_start_of_emblock,
            o_rx_lane_crc_error                     = self.rx_lane_crc_error,
            o_rx_lane_invalid_header_err_count      = self.tijesd_core_err[0:16],
            o_rx_lane_invalid_eomb_err_count        = self.tijesd_core_err[16:32],
            o_rx_lane_invalid_eoemb_err_count       = self.tijesd_core_err[32:48],
            o_rx_lane_crc_mismatch_err_count        = self.tijesd_core_err[48:64],
            o_rx_lemc_pulse                         = self.rx_lemc_pulse,
            i_rx_clr_all_err_count                  = Constant(0, 4),
            i_rx_lane_clr_invalid_header_err_count  = Constant(0, 4),
            i_rx_lane_clr_invalid_eomb_err_count    = Constant(0, 4),
            i_rx_lane_clr_invalid_eoemb_err_count   = Constant(0, 4),
            i_rx_lane_clr_crc_mismatch_err_count    = Constant(0, 4),

            o_xcvr_tx_clock                         = self.afe7900_jesd_ip_top_0_xcvr_tx_clock,
            i_tx_sys_clock                          = ClockSignal(afe_data_cd),
            i_tx_sync_reset                         = self.tiafe_tx_sync_reset,
            i_cfg_tx_lane_enable                    = self.tiafe_cfg_tx_lane_enabled,
            i_cfg_tx_lane_polarity                  = self.tiafe_cfg_tx_lane_polarity,
            i_cfg_tx_lane_map                       = self.tiafe_cfg_tx_lane_map,
            i_tx_samples                            = self.sink.data,
            o_tx_samples_ready                      = self.sink.ready,
            o_tx_samples_start_of_emblock           = self.tx_samples_start_of_emblock,
            i_tx_sysref                             = ClockSignal("fpga_sysref"),
            o_tx_sysref_realign_count               = self.tiafe_jesd_tx_sysref_realign_count,
            i_tx_clr_sysref_realign_count           = self.tiafe_tx_clr_sysref_realign_count,
            o_tx_lemc_pulse                         = self.tx_lemc_pulse,
            o_rx_lemc_to_buffer_release_delay       = self.tiafe_jesd_rx_lmfc_to_buffer_release_delay,
            o_debug_nfo                             = self.debug_nfo,
        )

        self.specials += Instance("afe79xx_jesd_ip_top", **params_ios)

    def _add_platform_sources(self):
        for source in [
            "./gateware/AFE79xx/afe79xx_jesd_ip_top.v",
            "./gateware/AFE79xx/afe79xx_ti_ip_top.v",
            "./gateware/AFE79xx/afe79xx_xcvr_top.v",
            "./gateware/AFE79xx/afe79xx_xcvr_wrapper.sv",
            "./gateware/AFE79xx/TI_IP_core_66b64/TI_204c_IP_6664.svp",
        ]:
            self.platform.add_source(source)

        ip_path = os.path.abspath(
            "./gateware/AFE79xx/ip/gth_uscale_64b66b_xcvr_xcau15p/"
            "gth_uscale_64b66b_xcvr_xcau15p.xci"
        )

        self.platform.toolchain.project_commands += [
            f"import_ip {ip_path}",
            "upgrade_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p]",
            "synth_ip [get_ips gth_uscale_64b66b_xcvr_xcau15p] -force",
            "set hipersdr_44xx_defines {{GT_XCVR_NAME=gth_uscale_64b66b_xcvr_xcau15p}}",
            "set_property verilog_define $hipersdr_44xx_defines [get_filesets sources_1]",
            "get_ips",
        ]

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
