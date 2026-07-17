#
# This file is part of LimeSDR_GW.
#
# Copyright (c) 2024-2025 Lime Microsystems.
#
# SPDX-License-Identifier: Apache-2.0

import os

from migen import *
from migen.genlib.cdc       import MultiReg
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.build.vhd2v_converter import VHD2VConverter

from litex.gen import *

from litex.soc.interconnect                import stream
from litex.soc.interconnect.axi.axi_stream import AXIStreamInterface
from litex.soc.interconnect.csr            import *

from gateware.common                                  import add_vhd2v_converter

from gateware.LimeDFB.lms7002.src.lms7002_ddin  import LMS7002DDIN
from gateware.LimeDFB.lms7002.src.lms7002_ddout import LMS7002DDOUT
from gateware.LimeDFB.lms7002.src.lms7002_clk   import LMS7002CLK

# LMS7002 Top --------------------------------------------------------------------------------------

class LMS7002Top(LiteXModule):
    def __init__(self, platform, vendor, family, pads=None,
        fpgacfg_manager      = None,
        diq_width            = 12,
        invert_input_clock   = False,
        s_clk_domain         = "lms_tx",
        s_axis_tx_fifo_words = 8,
        m_clk_domain         = "lms_rx",
        m_axis_rx_fifo_words = 16,
        one_chnl            = False,
        with_txiq_mux       = False,
        ):

        assert pads            is not None
        assert fpgacfg_manager is not None

        self.source            = AXIStreamInterface(64, clock_domain=m_clk_domain)
        self.sink              = AXIStreamInterface(64, clock_domain=s_clk_domain)

        if with_txiq_mux:
            self.wfm_sink_l = Signal(13)
            self.wfm_sink_h = Signal(13)

            self.txiq_mux_sel = CSRStorage(size=1, description="TXIQ MUX selection, 0 - TX, 1 - WFM")
            self.txiq_mux_sel_sync = txiq_mux_sel_sync = Signal(1)
            self.specials += MultiReg(self.txiq_mux_sel.storage,      txiq_mux_sel_sync,      odomain="lms_tx")

        self.platform          = platform

        self.pads                = pads

        self.smpl_cnt_en      = Signal() # To rx_path

        # CSR --------------------------------------------------------------------------------------
        # LMS Ctrl GPIO
        self._lms_ctr_gpio = CSRStorage(size=4, description="LMS Control GPIOs.")

        # fpgacfg
        self.lms1              = CSRStorage(fields=[         # 19
            CSRField("ss",             size=1, offset=0, reset=1),
            CSRField("reset",          size=1, offset=1, reset=1),
            CSRField("core_ldo_en",    size=1, offset=2, reset=0),
            CSRField("txnrx1",         size=1, offset=3, reset=1),
            CSRField("txnrx2",         size=1, offset=4, reset=0),
            CSRField("txen",           size=1, offset=5, reset=1),
            CSRField("rxen",           size=1, offset=6, reset=1),
            # FIXME: not sure
            CSRField("txrxen_mux_sel", size=1, offset=7, reset=0),
            CSRField("txrxen_inv",     size=1, offset=8, reset=0),

        ])

        # # #

        # Clock Domains.
        # --------------
        self.cd_lms_rx = ClockDomain()
        self.cd_lms_tx = ClockDomain()

        # Signals.
        # --------

        self.rx_reset_n     = Signal()

        rx_test_data_h      = Signal(diq_width + 1)
        rx_test_data_l      = Signal(diq_width + 1)
        self.rx_diq2_h_mux  = Signal(diq_width + 1)
        self.rx_diq2_l_mux  = Signal(diq_width + 1)

        rx_ptrn_en          = Signal()

        rx_mode             = Signal()
        rx_trxiqpulse       = Signal()
        rx_ddr_en           = Signal()
        rx_mimo_en          = Signal()
        rx_ch_en            = Signal(2)

        tx_reset_n          = Signal()

        tx_ptrn_en          = Signal()

        tx_mode             = Signal()
        tx_trxiqpulse       = Signal()
        tx_ddr_en           = Signal()
        tx_mimo_en          = Signal()
        tx_ch_en            = Signal(2)
        tx_diq_h            = Signal(diq_width + 1)
        tx_diq_l            = Signal(diq_width + 1)
        tx_test_data_h      = Signal(diq_width + 1)
        tx_test_data_l      = Signal(diq_width + 1)

        tx_tst_ptrn_h       = Signal(diq_width + 1)
        tx_tst_ptrn_l       = Signal(diq_width + 1)
        tx_mux_sel          = Signal()
        tx_tst_data_en      = Signal()
        self.txant_en       = txant_en = Signal()

        self.smpl_cmp_en    = smpl_cmp_en         = Signal()
        self.smpl_cmp_done  = smpl_cmp_done       = Signal()
        self.smpl_cmp_error = smpl_cmp_error      = Signal()
        smpl_cmp_cnt        = Signal(16)
        rx_smpl_cmp_length  = Signal(16)


        # Clocks.
        # -------
        self.lms7002_clk = LMS7002CLK(platform, vendor, family, pads)
        self.comb += [
            self.cd_lms_tx.clk.eq(self.lms7002_clk.tx_clk),
            self.cd_lms_rx.clk.eq(self.lms7002_clk.rx_clk),
            # Configuration
            self.lms7002_clk.sel.eq(      Constant(0, 1)), # 0 - fclk1 control, 1 - fclk2 control
            self.lms7002_clk.direction.eq(Constant(0, 1)),
            # mini v1
            self.lms7002_clk.clk_ena.eq(    fpgacfg_manager.clk_ena),
            self.lms7002_clk.drct_clk_en.eq(Replicate(fpgacfg_manager.drct_clk_en[0], 4)),
        ]

        # TX Path (DIQ1).
        # ------------------------------------------------------------------------------------------
        self.lms7002_ddout = ClockDomainsRenamer("lms_tx")(LMS7002DDOUT(platform, vendor, 12, pads))
        self.tx_cdc        = stream.AsyncFIFO([("data", 64)], depth=s_axis_tx_fifo_words, buffered=False)
        self.tx_cdc        = ClockDomainsRenamer({"write" : s_clk_domain, "read" : "lms_tx"})(self.tx_cdc)

        self.lms7002_tx = Instance("LMS7002_TX",
            # Parameters.
            p_G_IQ_WIDTH      = diq_width,

            # Clk/Reset.
            i_CLK             = ClockSignal("lms_tx"),
            i_RESET_N         = tx_reset_n,

            # Mode settings
            i_MODE            = tx_mode,
            i_TRXIQPULSE      = tx_trxiqpulse,
            i_DDR_EN          = tx_ddr_en,
            i_MIMO_EN         = tx_mimo_en,
            i_CH_EN           = tx_ch_en,
            i_FIDM            = Constant(0, 1),

            # Tx interface data.
            o_DIQ_H             = tx_diq_h,
            o_DIQ_L             = tx_diq_l,

            # AXI Stream Slave Interface.
            i_S_AXIS_ARESET_N = Constant(0, 1), # Unused
            i_S_AXIS_ACLK     = Constant(0, 1), # Unused
            i_S_AXIS_TVALID   = self.tx_cdc.source.valid,
            i_S_AXIS_TDATA    = self.tx_cdc.source.data,
            o_S_AXIS_TREADY   = self.tx_cdc.source.ready,
            i_S_AXIS_TLAST    = self.tx_cdc.source.last,
        )


        # TX activity indication
        # ----------------------
        self.tx_ant_en = Signal()

        self.edge_delay = Instance("edge_delay",
            i_clk       = ClockSignal("lms_tx"),
            i_reset_n   = tx_reset_n,
            i_rise_dly  = fpgacfg_manager.txant_pre,
            i_fall_dly  = fpgacfg_manager.txant_post,
            i_d         = self.tx_cdc.source.valid,
            o_q         = self.tx_ant_en,
        )


        # test_data_dd.
        # -------------
        self.tx_test_data_dd = Instance("test_data_dd",
            # Clk/Reset.
            i_clk       = ClockSignal("lms_tx"),
            i_reset_n   = ~ResetSignal("lms_tx"),
            # Mode Settings.
            i_fr_start  = Constant(0, 1), # External Frame ID mode. Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.
            i_mimo_en   = Constant(1,1),

            # Output.
            o_data_h    = tx_test_data_h,
            o_data_l    = tx_test_data_l,
        )

        # txiq_tst_ptrn.
        # --------------
        txiq_tst_ptrn_params = dict()
        txiq_tst_ptrn_params.update(
            # Parameters.
            p_diq_width = diq_width,

            # Clk/Reset.
            i_clk       = ClockSignal("lms_tx"),
            i_reset_n   = tx_ptrn_en,

            # Output.
            o_diq_h     = tx_tst_ptrn_h,
            o_diq_l     = tx_tst_ptrn_l,
        )

        self.txiq_tst_ptrn = Instance("txiq_tst_ptrn", **txiq_tst_ptrn_params)

        self.specials += MultiReg(fpgacfg_manager.rx_en, tx_reset_n, odomain="lms_tx")

        self.specials += [
            MultiReg(fpgacfg_manager.tx_ptrn_en,      tx_ptrn_en,      odomain="lms_tx"),
            MultiReg(fpgacfg_manager.tx_cnt_en,       tx_tst_data_en,  odomain="lms_tx"),
            MultiReg(fpgacfg_manager.wfm_play,        tx_mux_sel,      odomain="lms_tx"),
            MultiReg(fpgacfg_manager.mode,            tx_mode,         odomain="lms_tx"),
            MultiReg(fpgacfg_manager.trxiq_pulse,     tx_trxiqpulse,   odomain="lms_tx"),
            MultiReg(fpgacfg_manager.ddr_en,          tx_ddr_en,       odomain="lms_tx"),
            MultiReg(fpgacfg_manager.mimo_int_en,     tx_mimo_en,      odomain="lms_tx"),
            MultiReg(fpgacfg_manager.ch_en,           tx_ch_en,        odomain="lms_tx"),
        ]

        # RX path (DIQ2). --------------------------------------------------------------------------
        self.lms7002_ddin = ClockDomainsRenamer("lms_rx")(LMS7002DDIN(platform, vendor, 12, pads, invert_input_clock))

        self.rx_cdc = stream.ClockDomainCrossing([("data", 64), ("keep", 64 // 8)],
            cd_from = "lms_rx",
            cd_to   = m_clk_domain,
            depth   = m_axis_rx_fifo_words,
        )

        # lms7002_rx.
        # -----------
        smpl_cmp_params = dict()
        smpl_cmp_params.update(
            # Parameters.
            p_smpl_width    = diq_width,
            p_one_chnl      = one_chnl,

            # Clk/Reset.
            i_clk           = ClockSignal("lms_rx"),
            i_reset_n       = smpl_cmp_en,

            # DIQ bus.
            i_diq_h         = self.lms7002_ddin.rx_diq2_h,
            i_diq_l         = self.lms7002_ddin.rx_diq2_l,

            # Control signals
            i_cmp_start     = smpl_cmp_en,
            i_cmp_length    = rx_smpl_cmp_length,
            o_cmp_done      = smpl_cmp_done,
            o_cmp_error     = smpl_cmp_error,
            i_cmp_AI        = Constant(0xAAA, diq_width),
            i_cmp_AQ        = Constant(0x555, diq_width),
            i_cmp_BI        = Constant(0xAAA, diq_width),
            i_cmp_BQ        = Constant(0x555, diq_width),
        )
        # Debug Signals
        self.DEBUG_IQ_ERR = Signal()
        self.DEBUG_AI_ERR = Signal()
        self.DEBUG_AQ_ERR = Signal()
        self.DEBUG_BI_ERR = Signal()
        self.DEBUG_BQ_ERR = Signal()

        smpl_cmp_params.update(
            o_DEBUG_IQ_ERR = self.DEBUG_IQ_ERR,
            o_DEBUG_AI_ERR = self.DEBUG_AI_ERR,
            o_DEBUG_AQ_ERR = self.DEBUG_AQ_ERR,
            o_DEBUG_BI_ERR = self.DEBUG_BI_ERR,
            o_DEBUG_BQ_ERR = self.DEBUG_BQ_ERR,
        )

        self.smpl_cmp = Instance("smpl_cmp", **smpl_cmp_params)

        # test_data_dd.
        # -------------
        self.rx_test_data_dd = Instance("test_data_dd",
            # Clk/Reset.
            i_clk       = ClockSignal("lms_rx"),
            i_reset_n   = self.rx_reset_n,
            # Mode Settings.
            i_fr_start  = Constant(0, 1), # External Frame ID mode. Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.
            i_mimo_en   = rx_mimo_en,     # SISO: 1; MIMO: 0

            # Output.
            o_data_h    = rx_test_data_h,
            o_data_l    = rx_test_data_l,
        )

        rx_cdc_sink_valid = Signal()

        self.lms7002_rx = Instance("lms7002_rx",
            # Parameters.
            p_g_IQ_WIDTH          = diq_width,
            p_g_M_AXIS_FIFO_WORDS = 16,

            # Clock/Reset.
            i_clk                 = ClockSignal("lms_rx"),
            i_reset_n             = self.rx_reset_n,

            # Mode settings
            i_trxiqpulse          = rx_trxiqpulse,
            i_ddr_en              = rx_ddr_en,
            i_mimo_en             = rx_mimo_en,
            i_ch_en               = rx_ch_en,
            i_fidm                = Constant(0, 1),
            # Tx interface data
            i_diq_h               = self.rx_diq2_h_mux,
            i_diq_l               = self.rx_diq2_l_mux,

            # AXI Stream Master Interface.
            i_m_axis_areset_n     = Constant(1, 1),
            i_m_axis_aclk         = ClockSignal("lms_rx"),
            o_m_axis_tvalid       = rx_cdc_sink_valid,
            o_m_axis_tdata        = self.rx_cdc.sink.data,
            o_m_axis_tkeep        = self.rx_cdc.sink.keep,
            i_m_axis_tready       = self.rx_cdc.sink.ready,
            o_m_axis_tlast        = self.rx_cdc.sink.last
        )

        self.specials += MultiReg(fpgacfg_manager.rx_en, self.rx_reset_n, odomain="lms_rx"),

        self.specials += [
            MultiReg(fpgacfg_manager.rx_ptrn_en,      rx_ptrn_en,      odomain="lms_rx"),
            MultiReg(fpgacfg_manager.mode,            rx_mode,         odomain="lms_rx"),
            MultiReg(fpgacfg_manager.trxiq_pulse,     rx_trxiqpulse,   odomain="lms_rx"),
            MultiReg(fpgacfg_manager.ddr_en,          rx_ddr_en,       odomain="lms_rx"),
            MultiReg(fpgacfg_manager.mimo_int_en,     rx_mimo_en,      odomain="lms_rx"),
            MultiReg(fpgacfg_manager.ch_en,           rx_ch_en,        odomain="lms_rx"),
        ]
        self.comb += rx_smpl_cmp_length.eq(smpl_cmp_cnt)

        # Delay control module.
        # ---------------------
        self.comb += [
            smpl_cmp_en.eq(                    self.lms7002_clk.smpl_cmp_en),
            self.lms7002_clk.smpl_cmp_done.eq( smpl_cmp_done),
            self.lms7002_clk.smpl_cmp_error.eq(smpl_cmp_error),
            smpl_cmp_cnt.eq(                   self.lms7002_clk.smpl_cmp_cnt),
        ]

        # Logic.
        # ------
        self.comb += [
            self.sink.connect(self.tx_cdc.sink, keep=["data", "ready", "last", "valid"]),
            # lms7002_rx
            self.rx_cdc.source.connect(self.source),
            self.rx_cdc.sink.valid.eq(rx_cdc_sink_valid),
            If(~self.rx_reset_n,
               self.rx_cdc.source.ready.eq(1),
               self.source.valid.eq(0),
               self.rx_cdc.sink.valid.eq(0),
            ),
            # Pads.
            self.pads.CORE_LDO_EN.eq(self.lms1.fields.core_ldo_en),
            self.pads.TXNRX1.eq(     self.lms1.fields.txnrx1),
        ]

        # Lattice does not do direct clock control, but instead delays input/output signals
        # The logic needs access to both clk control signals AND ddio, so it lives here
        if vendor == "lattice":
            self.comb += [
            #     TX Delay control
            self.lms7002_ddout.data_direction.eq(0),
            If(self.lms7002_clk.delay_ctrl_sel == 0b01,
                self.lms7002_ddout.data_loadn.eq(self.lms7002_clk.inst1_delayf_loadn),
                self.lms7002_ddout.data_move.eq (self.lms7002_clk.inst1_delayf_move),
            ).Else(
                self.lms7002_ddout.data_loadn.eq(1),
                self.lms7002_ddout.data_move.eq (0),
            ),
            #     RX Delay control
            self.lms7002_ddin.data_direction.eq(Constant(0, 1)),
            If(self.lms7002_clk.delay_ctrl_sel == 0b11,
                self.lms7002_ddin.data_loadn.eq(self.lms7002_clk.inst1_delayf_loadn),
                self.lms7002_ddin.data_move.eq (self.lms7002_clk.inst1_delayf_move),
            ).Else(
                self.lms7002_ddin.data_loadn.eq(1),
                self.lms7002_ddin.data_move.eq (0),
            ),
            ]

        self.comb += [
            self.rx_diq2_h_mux.eq(self.lms7002_ddin.rx_diq2_h),
            self.rx_diq2_l_mux.eq(self.lms7002_ddin.rx_diq2_l),
        ]

        self.sync.lms_rx += [
            # Sample counter.
            If(~rx_mimo_en & rx_ddr_en,
                self.smpl_cnt_en.eq(1)
            ).Else(
                self.smpl_cnt_en.eq(~self.smpl_cnt_en)
            ),
            If(~smpl_cmp_en & ~self.rx_reset_n,
                self.smpl_cnt_en.eq(0),
            )
        ]

        if with_txiq_mux == False:
            self.comb += [
                If(tx_ptrn_en,
                    self.lms7002_ddout.tx_diq1_h.eq(tx_tst_ptrn_h),
                    self.lms7002_ddout.tx_diq1_l.eq(tx_tst_ptrn_l),
                ).Else(
                    self.lms7002_ddout.tx_diq1_h.eq(tx_diq_h),
                    self.lms7002_ddout.tx_diq1_l.eq(tx_diq_l),
                )
            ]
        else:
            self.mux0_reg_l = mux0_reg_l = Signal(13)
            self.mux0_reg_h = mux0_reg_h = Signal(13)
            self.mux1_reg_l = mux1_reg_l = Signal(13)
            self.mux1_reg_h = mux1_reg_h = Signal(13)
            self.mux2_reg_l = mux2_reg_l = Signal(13)
            self.mux2_reg_h = mux2_reg_h = Signal(13)
            sync_s_clk_domain = getattr(self.sync, s_clk_domain)

            sync_s_clk_domain += [
                If(txiq_mux_sel_sync,[
                    mux0_reg_l.eq(self.wfm_sink_l),
                    mux0_reg_h.eq(self.wfm_sink_h)
                ]).Else([
                    mux0_reg_l.eq(tx_diq_l),
                    mux0_reg_h.eq(tx_diq_h)
                ]),

                If(tx_ptrn_en,[
                    mux1_reg_l.eq(tx_tst_ptrn_l),
                    mux1_reg_h.eq(tx_tst_ptrn_h)
                ]).Else([
                    mux1_reg_l.eq(mux0_reg_l),
                    mux1_reg_h.eq(mux0_reg_h)
                ]),

                If(tx_tst_data_en,[
                    mux2_reg_l.eq(tx_test_data_l),
                    mux2_reg_h.eq(tx_test_data_h)
                ]).Else([
                    mux2_reg_l.eq(mux1_reg_l),
                    mux2_reg_h.eq(mux1_reg_h)
                ])
            ]

            self.comb += [
                    self.lms7002_ddout.tx_diq1_h.eq(mux2_reg_h),
                    self.lms7002_ddout.tx_diq1_l.eq(mux2_reg_l)
            ]



        # LMS Controls.
        lms_txen = Signal()
        lms_rxen = Signal()
        txant_en = Signal()
        self.comb += [
            self.pads.TXNRX2.eq(self.lms1.fields.txnrx2),
            self.pads.RESET.eq( self.lms1.fields.reset),
            If(self.lms1.fields.txrxen_mux_sel,
                lms_txen.eq(txant_en),
                lms_rxen.eq(~txant_en),
            ).Else(
                lms_txen.eq(self.lms1.fields.txen),
                lms_rxen.eq(self.lms1.fields.rxen),
            ),
            If(self.lms1.fields.txrxen_inv,
               self.pads.TXEN.eq(~lms_txen),
               self.pads.RXEN.eq(~lms_rxen),
            ).Else(
               self.pads.TXEN.eq(lms_txen),
               self.pads.RXEN.eq(lms_rxen),
            )
        ]

        self.specials += AsyncResetSynchronizer(self.cd_lms_rx, ResetSignal("sys"))
        self.specials += AsyncResetSynchronizer(self.cd_lms_tx, ResetSignal("sys"))

        # TX.
        # ---

        # LMS7002_TX
        self.lms7002_tx_conv = add_vhd2v_converter(self.platform,
            instance = self.lms7002_tx,
            files    = ["gateware/LimeDFB/lms7002/src/lms7002_tx.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.lms7002_tx)

        # LMS7002_TX
        self.edge_delay_conv = add_vhd2v_converter(self.platform,
            instance = self.edge_delay,
            files    = ["gateware/LimeDFB/lms7002/src/edge_delay.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.edge_delay)

        # TX test_data_dd.
        self.tx_test_data_dd_conv = add_vhd2v_converter(self.platform,
            instance = self.tx_test_data_dd,
            files    = ["gateware/LimeDFB/lms7002/src/test_data_dd.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.tx_test_data_dd)

        # txiq_tst_ptrn.
        txiq_tst_ptrn_files = [
            # "gateware/LimeDFB/lms7002/src/mini_txiq_tst_ptrn.vhd",
            "gateware/LimeDFB/lms7002/src/txiq_tst_ptrn.vhd",
            "gateware/LimeDFB/general/sync_reg.vhd",
            "gateware/LimeDFB/general/bus_sync_reg.vhd",
        ]

        self.txiq_tst_ptrn_conv = add_vhd2v_converter(self.platform,
            instance = self.txiq_tst_ptrn,
            files    = txiq_tst_ptrn_files,
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.txiq_tst_ptrn)

        # RX.
        # ---

        # Smpl CMP.
        self.smpl_cmp_conv = add_vhd2v_converter(self.platform,
            instance = self.smpl_cmp,
            files    = ["gateware/LimeDFB/lms7002/src/smpl_cmp_xtrx.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.smpl_cmp)

        # RX test_data_dd.
        self.rx_test_data_dd_conv = add_vhd2v_converter(self.platform,
            instance = self.rx_test_data_dd,
            files    = ["gateware/LimeDFB/lms7002/src/test_data_dd.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.rx_test_data_dd)

        # LMS7002RX.
        self.lms7002_rx_conv = add_vhd2v_converter(self.platform,
            instance = self.lms7002_rx,
            files    = ["gateware/LimeDFB/lms7002/src/lms7002_rx.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.lms7002_rx)
