#!/usr/bin/env python3
#
# This file is part of LimeDFB.
#
# Copyright (c) 2024-2025 Lime Microsystems.
#
# SPDX-License-Identifier: Apache-2.0

from migen import *

from litex.gen import *

from litex.build.vhd2v_converter import *

from litex.soc.interconnect.csr import *

from litex.soc.interconnect import wishbone

# VCTCXO Tamer -------------------------------------------------------------------------------------

class VCTCXOTamer(LiteXModule):
    def __init__(self, enable, pps):
        self.status = CSRStatus()
        self.bus    = wishbone.Interface(data_width=32, adr_width=32)
        self.irq    = Signal()

        # Config.
        self.config_1s_target       = Signal(32)
        self.config_1s_tol          = Signal(32)
        self.config_10s_target      = Signal(32)
        self.config_10s_tol         = Signal(32)
        self.config_100s_target     = Signal(32)
        self.config_100s_tol        = Signal(32)

        # Status.
        self.status_1s_error        = Signal(32)
        self.status_10s_error       = Signal(32)
        self.status_100s_error      = Signal(32)
        self.status_dac_tuned_val   = Signal(16)
        self.status_accuracy        = Signal(4)
        self.status_state           = Signal(4)

        # # #

        # Status.
        # -------
        self.comb += self.status.status.eq(enable)

        # Instance.
        # ---------
        self.specials += Instance("vctcxo_tamer",
            # Clk/PPS Inputs.
            i_vctcxo_clock       = ClockSignal("rf"),
            i_tune_ref           = pps,

            # Wishbone Interface.
            i_wb_clk_i           = ClockSignal("sys"),
            i_wb_rst_i           = ResetSignal("sys"),
            i_wb_adr_i           = self.bus.adr,
            i_wb_dat_i           = self.bus.dat_w,
            o_wb_dat_o           = self.bus.dat_r,
            i_wb_we_i            = self.bus.we,
            i_wb_stb_i           = self.bus.stb,
            o_wb_ack_o           = self.bus.ack,
            i_wb_cyc_i           = self.bus.cyc,
            o_wb_int_o           = self.irq,

            # Configuration Inputs.
            i_PPS_1S_TARGET      = self.config_1s_target,
            i_PPS_1S_ERROR_TOL   = self.config_1s_tol,
            i_PPS_10S_TARGET     = self.config_10s_target,
            i_PPS_10S_ERROR_TOL  = self.config_10s_tol,
            i_PPS_100S_TARGET    = self.config_100s_target,
            i_PPS_100S_ERROR_TOL = self.config_100s_tol,

            # Status Output.
            o_pps_1s_error       = self.status_1s_error,
            o_pps_10s_error      = self.status_10s_error,
            o_pps_100s_error     = self.status_100s_error,
            o_accuracy           = self.status_accuracy,
            o_state              = self.status_state,
            o_dac_tuned_val      = self.status_dac_tuned_val
        )

    def add_sources(self):
        from litex.gen import LiteXContext

        cdir = os.path.abspath(os.path.dirname(__file__))

        self.vhd2v_converter = VHD2VConverter(LiteXContext.platform,
            top_entity     = "vctcxo_tamer",
            flatten_source = False,
            files          = [
                os.path.join(cdir, "edge_detector.vhd"),
                os.path.join(cdir, "handshake.vhd"),
                os.path.join(cdir, "pps_counter.vhd"),
                os.path.join(cdir, "reset_synchronizer.vhd"),
                os.path.join(cdir, "synchronizer.vhd"),
                os.path.join(cdir, "vctcxo_tamer.vhd"),
            ]
        )
