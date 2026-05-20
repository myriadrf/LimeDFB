#
# This file is part of LimeSDR_GW.
#
# Copyright (c) 2024-2025 Lime Microsystems.
#
# SPDX-License-Identifier: Apache-2.0

from migen import *

from litex.gen import *

from litex.build.io import DDROutput

# LMS7002 CLK --------------------------------------------------------------------------------------

def LMS7002CLK(platform, vendor, pads=None, **kwargs):
    if vendor == "lattice":
        return LMS7002CLK_Lattice(platform, pads,  **kwargs)
    elif vendor == "altera":
        return LMS7002CLK_Altera(platform, pads,  **kwargs)
    elif vendor == "xilinx":
        return LMS7002CLK_Xilinx(platform, pads,  **kwargs)
    else:
        raise ValueError(f"Unsupported vendor: {vendor}")

class LMS7002CLKBase(LiteXModule):
    def __init__(self, platform, pads=None, **kwargs):
        # Configuration
        self.sel            = Signal() # 0 - fclk1 control, 1 - fclk2 control
        self.cflag          = Signal()
        self.direction      = Signal()
        self.loadn          = Signal()
        self.move           = Signal()

        self.rx_clk         = Signal()
        self.tx_clk         = Signal()

        # mini V1 only
        self.clk_ena        = Signal(4)
        self.drct_clk_en    = Signal(4)
        self.pll_locked     = Signal()
        self.smpl_cmp_en    = Signal()
        self.smpl_cmp_done  = Signal()
        self.smpl_cmp_error = Signal()
        self.smpl_cmp_cnt   = Signal(16)

        from gateware.lms7002_clk import ClkCfgRegs
        # Clocking control registers
        self.CLK_CTRL = ClkCfgRegs(use_status_regs=True)


class LMS7002CLK_Lattice(LMS7002CLKBase):
    def __init__(self, platform, pads=None, **kwargs):
        super().__init__(platform, pads, **kwargs)

        inst1_q = Signal()
        inst2_q = Signal()

        inst3_loadn      = Signal()
        inst3_move       = Signal()
        inst3_direction  = Signal()
        inst3_cflag      = Signal()

        inst4_loadn      = Signal()
        inst4_move       = Signal()
        inst4_direction  = Signal()
        inst4_cflag      = Signal()

        # Control logic.
        # --------------
        self.comb += [
            If(self.sel,
                inst3_loadn.eq(1),
                inst3_move.eq( 0),
                inst4_loadn.eq(self.loadn),
                inst4_move.eq( self.move),
                self.cflag.eq( inst4_cflag),
            ).Else(
                inst3_loadn.eq(self.loadn),
                inst3_move.eq( self.move),
                inst4_loadn.eq(1),
                inst4_move.eq( 0),
                self.cflag.eq( inst3_cflag),
            ),
            inst3_direction.eq(self.direction),
            inst4_direction.eq(self.direction),
        ]

        c0_global         = Signal()
        c2_global         = Signal()

        self.specials += [
            # Forwarded clock fclk1.
            # ----------------------
            DDROutput(
                clk = c0_global,
                i1  = 0,
                i2  = 1,
                o   = inst1_q
            ),

            # Forwarded clock fclk2.
            # ----------------------
            DDROutput(
                clk = c2_global,
                i1  = 0,
                i2  = 1,
                o   = inst2_q
            )
        ]
        self.comb += [
            self.tx_clk.eq(pads.MCLK1),
            self.rx_clk.eq(pads.MCLK2),
            c0_global.eq(pads.MCLK1),
            c2_global.eq(pads.MCLK2),
        ]

        self.specials += [
            Instance("DELAYF",
                p_DEL_VALUE = 1,
                p_DEL_MODE  = "USER_DEFINED",
                i_A         = inst1_q,
                i_LOADN     = inst3_loadn,
                i_MOVE      = inst3_move,
                i_DIRECTION = inst3_direction,
                o_Z         = pads.FCLK1,
                o_CFLAG     = inst3_cflag,
            ),
            Instance("DELAYF",
                p_DEL_VALUE = 1,
                p_DEL_MODE  = "USER_DEFINED",
                i_A         = inst2_q,
                i_LOADN     = inst4_loadn,
                i_MOVE      = inst4_move,
                i_DIRECTION = inst4_direction,
                o_Z         = pads.FCLK2,
                o_CFLAG     = inst4_cflag,
            ),
        ]

class LMS7002CLK_Altera(LMS7002CLKBase):
    def __init__(self, platform, pads=None,
        drct_c0_ndly   = 1,
        drct_c1_ndly   = 8,
        drct_c2_ndly   = 1,
        drct_c3_ndly   = 8,
        with_max10_pll = True,
        **kwargs):
        super().__init__(platform, pads, **kwargs)

        inst1_q = Signal()
        inst2_q = Signal()

        inst3_loadn      = Signal()
        inst3_move       = Signal()
        inst3_direction  = Signal()
        inst3_cflag      = Signal()

        inst4_loadn      = Signal()
        inst4_move       = Signal()
        inst4_direction  = Signal()
        inst4_cflag      = Signal()

        # Control logic.
        # --------------
        self.comb += [
            If(self.sel,
                inst3_loadn.eq(1),
                inst3_move.eq( 0),
                inst4_loadn.eq(self.loadn),
                inst4_move.eq( self.move),
                self.cflag.eq( inst4_cflag),
            ).Else(
                inst3_loadn.eq(self.loadn),
                inst3_move.eq( self.move),
                inst4_loadn.eq(1),
                inst4_move.eq( 0),
                self.cflag.eq( inst3_cflag),
            ),
            inst3_direction.eq(self.direction),
            inst4_direction.eq(self.direction),
        ]

        c0_global         = Signal()
        c2_global         = Signal()

        self.specials += [
            # Forwarded clock fclk1.
            # ----------------------
            DDROutput(
                clk = c0_global,
                i1  = 1,
                i2  = 0,
                o   = inst1_q
            ),

            # Forwarded clock fclk2.
            # ----------------------
            DDROutput(
                clk = c2_global,
                i1  = 1,
                i2  = 0,
                o   = inst2_q
            )
        ]
        self.comb += [
            self.tx_clk.eq(pads.MCLK1),
            self.rx_clk.eq(pads.MCLK2),
            pads.FCLK1.eq(                   inst1_q),
            pads.FCLK2.eq(                   inst2_q),
        ]

        if with_max10_pll:
            from gateware.max10_pll_top.max10_pll_top import MAX10PLLTop

            self.max10_pll = MAX10PLLTop(platform, pads,
                drct_c0_ndly = drct_c0_ndly,
                drct_c1_ndly = drct_c1_ndly,
                drct_c2_ndly = drct_c2_ndly,
                drct_c3_ndly = drct_c3_ndly,
            )

            # Control registers

            self.comb += [
                self.CLK_CTRL.PHCFG_ERR.status.eq   (self.max10_pll.phcfg_error),
                self.CLK_CTRL.PHCFG_DONE.status.eq  (self.max10_pll.phcfg_done),
                self.CLK_CTRL.PLLCFG_BUSY.status.eq (self.max10_pll.pllcfg_busy),
                self.CLK_CTRL.PLLCFG_DONE.status.eq (self.max10_pll.pllcfg_done),
                self.CLK_CTRL.PLL_LOCK.status.eq    (self.max10_pll.pll_lock),
                self.max10_pll.phcfg_tst.eq         (Constant(0)), # unused
                self.max10_pll.phcfg_mode.eq        (self.CLK_CTRL.PHCFG_MODE.storage),
                self.max10_pll.phcfg_updn.eq        (self.CLK_CTRL.PHCFG_UPDN.storage),
                self.max10_pll.cnt_ind.eq           (self.CLK_CTRL.CNT_IND.storage),
                self.max10_pll.pll_ind.eq           (self.CLK_CTRL.PLL_IND.storage),
                self.max10_pll.pllrst_start.eq      (self.CLK_CTRL.PLLRST_START.storage),
                self.max10_pll.phcfg_start.eq       (self.CLK_CTRL.PHCFG_START.storage),
                self.max10_pll.pllcfg_start.eq      (self.CLK_CTRL.PLLCFG_START.storage),
                self.max10_pll.cnt_phase.eq         (self.CLK_CTRL.CNT_PHASE.storage),
                self.max10_pll.chp_curr.eq          (Constant(0)), # unused
                self.max10_pll.pllcfg_vcodiv.eq     (self.CLK_CTRL.PLLCFG_VCODIV.storage),
                self.max10_pll.pllcfg_lf_res.eq     (Constant(0)), # unused
                self.max10_pll.pllcfg_lf_cap.eq     (Constant(0)), # unused
                self.max10_pll.m_odddiv.eq          (self.CLK_CTRL.M_ODD_DIV.storage),
                self.max10_pll.m_byp.eq             (self.CLK_CTRL.M_Div_BYP.storage),
                self.max10_pll.n_odddiv.eq          (self.CLK_CTRL.N_ODD_DIV.storage),
                self.max10_pll.n_byp.eq             (self.CLK_CTRL.N_Div_BYP.storage),
                self.max10_pll.c0_byp.eq            (self.CLK_CTRL.C0_Div_BYP.storage),
                self.max10_pll.c0_odddiv.eq         (self.CLK_CTRL.C0_ODDDIV.storage),
                self.max10_pll.c1_byp.eq            (self.CLK_CTRL.C1_Div_BYP.storage),
                self.max10_pll.c1_odddiv.eq         (self.CLK_CTRL.C1_ODDDIV.storage),
                self.max10_pll.c2_byp.eq            (self.CLK_CTRL.C2_Div_BYP.storage),
                self.max10_pll.c2_odddiv.eq         (self.CLK_CTRL.C2_ODDDIV.storage),
                self.max10_pll.c3_byp.eq            (self.CLK_CTRL.C3_Div_BYP.storage),
                self.max10_pll.c3_odddiv.eq         (self.CLK_CTRL.C3_ODDDIV.storage),
                self.max10_pll.c4_byp.eq            (self.CLK_CTRL.C4_Div_BYP.storage),
                self.max10_pll.c4_odddiv.eq         (self.CLK_CTRL.C4_ODDDIV.storage),
                self.max10_pll.n_cnt.eq             (self.CLK_CTRL.N_CNT.storage),
                self.max10_pll.m_cnt.eq             (self.CLK_CTRL.M_CNT.storage),
                self.max10_pll.c0_cnt.eq            (self.CLK_CTRL.C0_Div_CNT.storage),
                self.max10_pll.c1_cnt.eq            (self.CLK_CTRL.C1_Div_CNT.storage),
                self.max10_pll.c2_cnt.eq            (self.CLK_CTRL.C2_Div_CNT.storage),
                self.max10_pll.c3_cnt.eq            (self.CLK_CTRL.C3_Div_CNT.storage),
                self.max10_pll.c4_cnt.eq            (self.CLK_CTRL.C4_Div_CNT.storage),
                self.max10_pll.auto_phcfg_smpls.eq  (self.CLK_CTRL.Auto_PHcfg_smpls.storage),
                self.max10_pll.auto_phcfg_step.eq   (Constant(2)), # unused
            ]


            self.comb += [
                self.max10_pll.clk_ena.eq(       self.clk_ena),
                self.max10_pll.drct_clk_en.eq(   self.drct_clk_en),
                self.pll_locked.eq(              self.max10_pll.pll_locked),
                self.smpl_cmp_en.eq(             self.max10_pll.smpl_cmp_en),
                self.max10_pll.smpl_cmp_done.eq( self.smpl_cmp_done),
                self.max10_pll.smpl_cmp_error.eq(self.smpl_cmp_error),
                self.smpl_cmp_cnt.eq(            self.max10_pll.smpl_cmp_cnt),

                c0_global.eq(                    self.max10_pll.c0_global),
                self.tx_clk.eq(                  self.max10_pll.tx_clk),
                c2_global.eq(                    self.max10_pll.c2_global),
                self.rx_clk.eq(                  self.max10_pll.rx_clk),
            ]
        else:
            # TX.
            # ---
            drct_c0_dly_chain = Signal(drct_c0_ndly)
            c0_mux            = Signal()

            for i in range(drct_c0_ndly):
                self.specials += Instance("lcell",
                    i_in  = {True:pads.MCLK2, False:drct_c0_dly_chain[i-1]}[i==0],
                    o_out = drct_c0_dly_chain[i],
                )
            self.specials += [
                Instance("fiftyfivenm_clkctrl",
                    p_clock_type        = "Global Clock",
                    p_ena_register_mode = "falling edge",
                    p_lpm_type          = "fiftyfivenm_clkctrl",

                    i_inclk             = c0_mux,
                    i_clkselect         = Constant(0, 2),
                    i_ena               = self.clk_ena[0],
                    o_outclk            = c0_global,
                ),
            ]

            self.comb += [
                If(self.drct_clk_en[0],
                    c0_mux.eq(drct_c0_dly_chain[drct_c0_ndly-1]),
                ).Else(
                    c0_mux.eq(pads.MCLK2)
                ),
            ]

            # RX.
            # ---
            drct_c2_dly_chain = Signal(drct_c2_ndly)
            c2_mux            = Signal()

            for i in range(drct_c2_ndly):
                self.specials += Instance("lcell",
                    i_in  = {True:pads.MCLK2, False:drct_c2_dly_chain[i-1]}[i==0],
                    o_out = drct_c2_dly_chain[i],
                )
            self.specials += [
                Instance("fiftyfivenm_clkctrl",
                    p_clock_type        = "Global Clock",
                    p_ena_register_mode = "falling edge",
                    p_lpm_type          = "fiftyfivenm_clkctrl",

                    i_inclk             = c2_mux,
                    i_clkselect         = Constant(0, 2),
                    i_ena               = self.clk_ena[2],
                    o_outclk            = c2_global,
                ),
            ]
            self.comb += [
                If(self.drct_clk_en[2],
                    c2_mux.eq(drct_c2_dly_chain[drct_c2_ndly-1]),
                ).Else(
                    c2_mux.eq(pads.MCLK2),
                ),
            ]

class LMS7002CLK_Xilinx(LMS7002CLKBase):
    def __init__(self, platform, pads=None, **kwargs):
        super().__init__(platform, pads, **kwargs)
        from gateware.lms7002_clk import XilinxLmsMMCM
        from gateware.lms7002_clk import ClkMux
        from gateware.lms7002_clk import ClkDlyFxd

        # TX clk
        # Xilinx MMCM is used to support configurable interface frequencies >5NHz
        # Muxed and delayed clock version is used for interface frequencies <5MHz

        # Global TX CLock
        self.cd_txclk_global = ClockDomain()
        self.comb += self.cd_txclk_global.clk.eq(pads.MCLK1)

        # TX PLL.
        self.cd_txpll_clk_c0 = ClockDomain()
        self.cd_txpll_clk_c1 = ClockDomain()

        self.PLL0_TX = XilinxLmsMMCM(platform, speedgrade=-2, max_freq=122.88e6,
            mclk      = self.cd_txclk_global.clk,
            fclk      = self.cd_txpll_clk_c0.clk,
            logic_cd  = self.cd_txpll_clk_c1)

        #TX CLK C0 mux
        self.cd_txclk_c0_muxed = ClockDomain()
        self.txclk_mux         = ClkMux(
            i0  = self.cd_txpll_clk_c0.clk,
            i1  = self.cd_txclk_global.clk,
            o   = self.cd_txclk_c0_muxed.clk,
            sel = self.CLK_CTRL.DRCT_TXCLK_EN.storage)

        #TX CLK C1 delay
        self.cd_txclk_c1_dly = ClockDomain()
        self.txclk_c1_dlly   = ClkDlyFxd(i=self.cd_txclk_global.clk, o=self.cd_txclk_c1_dly.clk)

        #TX CLK C1 mux
        self.cd_txclk  = ClockDomain()
        self.txclk_mux_c1 = ClkMux(
            i0  = self.cd_txpll_clk_c1.clk,
            i1  = self.cd_txclk_c1_dly.clk,
            o   = self.cd_txclk.clk,
            sel = self.CLK_CTRL.DRCT_TXCLK_EN.storage)

        # Create clock groups (false paths) between sys clk and all clocks from TX interface tree
        platform.add_false_path_constraints(
            LiteXContext.top.crg.cd_sys.clk,
            self.cd_txclk_global.clk,
            self.cd_txpll_clk_c0.clk,
            self.cd_txpll_clk_c1.clk,
            self.cd_txclk_c0_muxed.clk,
            self.cd_txclk_c1_dly.clk,
            self.cd_txclk.clk,
        )

        self.comb += [
            self.tx_clk.eq(self.cd_txclk.clk),
            pads.FCLK1.eq(self.cd_txclk_c0_muxed.clk),
        ]

        # RX clk
        # Xilinx MMCM is used to support configurable interface frequencies >5NHz
        # Muxed and delayed clock version is used for interface frequencies <5MHz

        # Global RX CLock
        self.cd_rxclk_global = ClockDomain()
        self.comb += self.cd_rxclk_global.clk.eq(pads.MCLK2)

        # RX PLL.
        self.cd_rxpll_clk_c0 = ClockDomain()
        self.cd_rxpll_clk_c1 = ClockDomain()
        self.PLL1_RX         = XilinxLmsMMCM(platform, speedgrade=-2, max_freq=122.88e6,
            mclk     = self.cd_rxclk_global.clk,
            fclk     = self.cd_rxpll_clk_c0.clk,
            logic_cd = self.cd_rxpll_clk_c1)

        #RX CLK C0 mux
        self.cd_rxclk_c0_muxed = ClockDomain()
        self.rxclk_mux         = ClkMux(
            i0  = self.cd_rxpll_clk_c0.clk,
            i1  = self.cd_rxclk_global.clk,
            o   = self.cd_rxclk_c0_muxed.clk,
            sel = self.CLK_CTRL.DRCT_RXCLK_EN.storage)

        #RX CLK C1 delay
        self.cd_rxclk_c1_dly = ClockDomain()
        self.rxclk_c1_dlly   = ClkDlyFxd(i=self.cd_rxclk_global.clk, o=self.cd_rxclk_c1_dly.clk)

        #RX CLK C1 mux
        self.cd_rxclk  = ClockDomain()
        self.rxclk_mux_c1 = ClkMux(
            i0  = self.cd_rxpll_clk_c1.clk,
            i1  = self.cd_rxclk_c1_dly.clk,
            o   = self.cd_rxclk.clk,
            sel = self.CLK_CTRL.DRCT_RXCLK_EN.storage,
        )

        # Create clock groups (false paths) between sys clk and all clocks from RX interface tree
        platform.add_false_path_constraints(
            LiteXContext.top.crg.cd_sys.clk,
            self.cd_rxclk_global.clk,
            self.cd_rxpll_clk_c0.clk,
            self.cd_rxpll_clk_c1.clk,
            self.cd_rxclk_c0_muxed.clk,
            self.cd_rxclk_c1_dly.clk,
            self.cd_rxclk.clk,
        )

        self.comb += [
            self.rx_clk.eq(self.cd_rxclk.clk),
            pads.FCLK2.eq(self.cd_rxclk_c0_muxed.clk),
        ]
