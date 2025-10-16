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

# PPS Detector -------------------------------------------------------------------------------------

class PPSDetector(LiteXModule):
    def __init__(self, pps):
        self.pps_active = Signal()

        # # #

        # Instance.
        # ---------
        self.specials += Instance("pps_detector",
            # Clk/Rst.
            i_clk        = ClockSignal("sys"),
            i_reset      = ResetSignal("sys"),

            # PPS Input/Output.
            i_pps        = pps,
            o_pps_active = self.pps_active
        )

    def add_sources(self):
        from litex.gen import LiteXContext

        cdir = os.path.abspath(os.path.dirname(__file__))

        self.vhd2v_converter = VHD2VConverter(LiteXContext.platform,
            top_entity     = "pps_detector",
            params         = dict(
                p_CLK_FREQ_HZ = LiteXContext.top.sys_clk_freq,
                p_TOLERANCE   = 5000000,
            ),
            flatten_source = False,
            files          = [
                os.path.join(cdir, "pps_detector.vhd"),
            ]
        )
        self.vhd2v_converter._ghdl_opts.append("-fsynopsys")
