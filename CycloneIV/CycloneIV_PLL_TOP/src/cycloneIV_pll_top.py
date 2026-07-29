#
# This file is part of LimeSDR_GW.
#
# Copyright (c) 2024-2025 Lime Microsystems.
#
# SPDX-License-Identifier: Apache-2.0

from migen import *

from litex.gen import *

from litex.soc.interconnect.csr import *

# CycloneIV PLL Top ------------------------------------------------------------------------------------

class CycloneIVPLLTop(LiteXModule):
    def __init__(self, platform, pads,
        ):

        self.platform    = platform
        #
        # self.c0_global   = Signal()
        # self.c2_global   = Signal()
        self.rx_clk      = Signal()
        self.tx_clk      = Signal()
        # self.pll_locked  = Signal()

        # fpgacfg
        self.clk_ena     = Signal(4)
        self.drct_clk_en = Signal(4)

        # smpl cmp
        self.smpl_cmp_en_rx = Signal()
        self.smpl_cmp_en_tx = Signal()
        self.smpl_cmp_en    = Signal()
        self.comb += self.smpl_cmp_en.eq(self.smpl_cmp_en_rx | self.smpl_cmp_en_tx)

        self.smpl_cmp_done  = Signal()
        self.smpl_cmp_error = Signal()
        self.smpl_cmp_cnt   = Signal(16)

        # # #

        self.phcfg_error      = Signal()
        self.phcfg_done       = Signal()
        self.pllcfg_busy      = Signal()
        self.pllcfg_done      = Signal()
        self.pll_lock         = Signal(16)
        self.phcfg_tst        = Signal()
        self.phcfg_mode       = Signal()
        self.phcfg_updn       = Signal()
        self.cnt_ind          = Signal(5)
        self.pll_ind          = Signal(5)
        self.pllrst_start     = Signal()
        self.phcfg_start      = Signal()
        self.pllcfg_start     = Signal()
        self.cnt_phase        = Signal(16)
        self.chp_curr         = Signal(3)
        self.pllcfg_vcodiv    = Signal()
        self.pllcfg_lf_res    = Signal(5)
        self.pllcfg_lf_cap    = Signal(2)
        self.m_odddiv         = Signal()
        self.m_byp            = Signal()
        self.n_odddiv         = Signal()
        self.n_byp            = Signal()
        self.c0_byp           = Signal()
        self.c0_odddiv        = Signal()
        self.c1_byp           = Signal()
        self.c1_odddiv        = Signal()
        self.c2_byp           = Signal()
        self.c2_odddiv        = Signal()
        self.c3_byp           = Signal()
        self.c3_odddiv        = Signal()
        self.c4_byp           = Signal()
        self.c4_odddiv        = Signal()
        self.n_cnt            = Signal(16)
        self.m_cnt            = Signal(16)
        self.c0_cnt           = Signal(16)
        self.c1_cnt           = Signal(16)
        self.c2_cnt           = Signal(16)
        self.c3_cnt           = Signal(16)
        self.c4_cnt           = Signal(16)
        self.auto_phcfg_smpls = Signal(16)
        self.auto_phcfg_step  = Signal(16)

        # Signals.
        # --------
        platform.add_period_constraint(pads.MCLK1, 1e9/122.88e6)
        platform.add_period_constraint(pads.MCLK2, 1e9/122.88e6)

        # pll_top instance.
        # -----------------
        self.specials += Instance("pll_top",
        # Skipping parameters, because they all match the defaults
          i_txpll_inclk          = pads.MCLK1,
          i_txpll_reconfig_clk   = ClockSignal("sys"),
          i_txpll_logic_reset_n  = ~ResetSignal("sys"),
          i_txpll_clk_ena        = self.clk_ena[0:2],
          i_txpll_drct_clk_en    = self.drct_clk_en[0],
          o_txpll_c0             = pads.FCLK1,
          o_txpll_c1             = self.tx_clk,
          o_txpll_locked         = Open(),# Already exposed via o_pll_lock[0], avoid duplicating
          #
          o_txpll_smpl_cmp_en    = self.smpl_cmp_en_tx,
          i_txpll_smpl_cmp_done  = self.smpl_cmp_done,
          i_txpll_smpl_cmp_error = self.smpl_cmp_error,
          o_txpll_smpl_cmp_cnt   = Open(),# Actually same signal internally as o_rxpll_smpl_cmp_cnt, avoid duplicating
          # RX pll ports
          i_rxpll_inclk          = pads.MCLK2,
          i_rxpll_reconfig_clk   = ClockSignal("sys"),
          i_rxpll_logic_reset_n  = ~ResetSignal("sys"),
          i_rxpll_clk_ena        = self.clk_ena[2:4],
          i_rxpll_drct_clk_en    = self.drct_clk_en[1],
          o_rxpll_c0             = pads.FCLK2,
          o_rxpll_c1             = self.rx_clk,
          o_rxpll_locked         = Open(),# Already exposed via o_pll_lock[1], avoid duplicating
          #
          o_rxpll_smpl_cmp_en    = self.smpl_cmp_en_rx,
          i_rxpll_smpl_cmp_done  = self.smpl_cmp_done,
          i_rxpll_smpl_cmp_error = self.smpl_cmp_error,
          o_rxpll_smpl_cmp_cnt   = self.smpl_cmp_cnt,
          # from to_pllcfg
          o_pllcfg_busy          = self.pllcfg_busy,
          o_pllcfg_done          = self.pllcfg_done,
          o_phcfg_done           = self.phcfg_done,
          o_phcfg_error          = self.phcfg_error,
          o_pll_lock             = self.pll_lock,
          # from from_pllcfg
          i_phcfg_start          = self.phcfg_start,
          i_pllcfg_start         = self.pllcfg_start,
          i_pllrst_start         = self.pllrst_start,
          i_phcfg_updn           = self.phcfg_updn,
          i_cnt_ind              = self.cnt_ind,
          i_pll_ind              = self.pll_ind,
          i_phcfg_mode           = self.phcfg_mode,
          i_phcfg_tst            = self.phcfg_tst,

          i_cnt_phase            = self.cnt_phase,
          i_chp_curr             = self.chp_curr,
          i_pllcfg_vcodiv        = self.pllcfg_vcodiv,
          i_pllcfg_lf_res        = self.pllcfg_lf_res,
          i_pllcfg_lf_cap        = self.pllcfg_lf_cap,

          i_m_odddiv             = self.m_odddiv,
          i_m_byp                = self.m_byp,
          i_n_odddiv             = self.n_odddiv,
          i_n_byp                = self.n_byp,

          i_c0_odddiv            = self.c0_odddiv,
          i_c0_byp               = self.c0_byp,
          i_c1_odddiv            = self.c1_odddiv,
          i_c1_byp               = self.c1_byp,
          i_c2_odddiv            = self.c2_odddiv,
          i_c2_byp               = self.c2_byp,
          i_c3_odddiv            = self.c3_odddiv,
          i_c3_byp               = self.c3_byp,
          i_c4_odddiv            = self.c4_odddiv,
          i_c4_byp               = self.c4_byp,
          i_n_cnt                = self.n_cnt,
          i_m_cnt                = self.m_cnt,
          i_c0_cnt               = self.c0_cnt,
          i_c1_cnt               = self.c1_cnt,
          i_c2_cnt               = self.c2_cnt,
          i_c3_cnt               = self.c3_cnt,
          i_c4_cnt               = self.c4_cnt,
          i_auto_phcfg_smpls     = self.auto_phcfg_smpls,
          i_auto_phcfg_step      = self.auto_phcfg_step

        )

        self.add_sources(platform)

    def add_sources(self, platform):
        pll_top_files = [
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_ctrl.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_top.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/tx_pll_top.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/rx_pll_top.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/config_ctrl.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_reconfig_status.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_reconfig_module.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_ps_fsm.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_ps_top.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/src/pll_ps.vhd",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/ip/pll_reconfig_module/pll_reconfig_module.vhd"
        ]

        for file in pll_top_files:
            platform.add_source(file)

        pll_top_ips = [
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/ip/pll_reconfig_module/pll_reconfig_module.qip",
            "gateware/LimeDFB/CycloneIV/CycloneIV_PLL_TOP/ip/clkctrl/clkctrl.qsys",
        ]

        for file in pll_top_ips:
            platform.add_ip(file)
