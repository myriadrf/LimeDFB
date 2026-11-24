#
# This file is part of LimeSDR_GW.
#
# Copyright (c) 2024-2025 Lime Microsystems.
#
# SPDX-License-Identifier: Apache-2.0

"""
TX Path Top Module Structure:

    AXI Stream Input (sink_width)
    |
    v
    Input Buffer (CDC s_clk -> m_clk)
    |
    v
    Stream Converter (sink_width -> 128)
    |
    v
    lime_txpct_fifo
    |
    v
    Sample Padder (12->16 bit)
    |
    v
    Sample Unpacker
    |
    v
    AXI Stream Output (64)

"""

import math
from types import SimpleNamespace

from litex.soc.interconnect.stream import ClockDomainCrossing
from migen import *

from migen.genlib.cdc import MultiReg
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.gen import *

from litex.soc.interconnect.axi.axi_stream import AXIStreamInterface
from litex.soc.interconnect.csr            import CSRStatus, CSRStorage, CSRField
from litex.soc.interconnect                import stream

from gateware.common import *

# TX Path Top --------------------------------------------------------------------------------------

class TXPathTop(LiteXModule):
    cdc_stream_rst = False  # Board targets may enable it before building (see __init__).

    def __init__(self, platform, fpgacfg_manager=None,
        tx_stream_en=None,
        # TX parameters
        PCT_MAX_SIZE      = 4096,
        BUFF_COUNT        = 4,
        sink_width        = 128,
        rx_clk_domain     = "lms_rx",
        m_clk_domain      = "lms_tx",
        s_clk_domain      = "lms_tx",
        output4channels   = False,
        input_buff_size   = 512,
        cdc_stream_rst    = None,
        ):
        # cdc_stream_rst: reset both sides of the input_buff (s_clk -> m_clk) and smpl_nr_fifo
        # (rx_clk -> m_clk) AsyncFIFOs, gray pointers included, while the TX stream is disabled
        # (through an AsyncResetSynchronizer per domain). Otherwise these pointers are only reset
        # at configuration and an inconsistency survives every later stream. None = class default.
        if cdc_stream_rst is None:
            cdc_stream_rst = TXPathTop.cdc_stream_rst

        self.s_clk_domain = s_clk_domain
        self.m_clk_domain = m_clk_domain
        self.rx_clk_domain = rx_clk_domain
        #Input buffer acts as CDC, so a minimum of 4 depth is required to instantiate the async FIFO
        assert input_buff_size >= (sink_width*4), "TXPathTop input_buff_size must be greater than or equal to 4 sink cycles"

        assert fpgacfg_manager is not None
        tx_stream_en = fpgacfg_manager.rx_en if tx_stream_en is None else tx_stream_en

        self.platform          = platform

        self.source            = AXIStreamInterface(128 if output4channels else 64, clock_domain=m_clk_domain)
        self.sink              = AXIStreamInterface(sink_width, clock_domain=s_clk_domain)

        self.rx_sample_nr      = Signal(64)
        self.pct_loss_flg      = Signal()
        self.pct_loss_flg_clr  = Signal()

        self.tx_txant_en       = Signal()

        self.ext_reset_n       = Signal(reset=1)
        # ext_reset_n is driven from another clock domain (LimeSDR-USB: fpgacfg rx_en, sys).
        # Synchronise it into each domain that uses it (the legacy VHDL design released
        # its stream reset through sync_reg into the TX/RX clock domains).
        ext_reset_n_m      = Signal(reset=1)
        ext_reset_n_rx     = Signal(reset=1)
        self.specials += [
            MultiReg(self.ext_reset_n, ext_reset_n_m,  odomain=m_clk_domain,  reset=1),
            MultiReg(self.ext_reset_n, ext_reset_n_rx, odomain=rx_clk_domain, reset=1),
        ]

        self.pct_buff_cnt      = CSRStorage(8, reset_less=True,
            description="Extra packets to buffer before starting sync_dis streaming (0-255, clamped to BUFF_COUNT-1). Streaming also starts once the TX buffer cannot accept more data."
        )
        self.payload_buff_cnt  = CSRStorage(16, reset_less=True,
            description="Payload FIFO words (128-bit) to buffer before starting sync_dis streaming (0 = no gating, clamped to buffer size). Streaming also starts once the TX buffer cannot accept more data."
        )

        # # #

        # Signals.
        s_reset_n        = Signal()
        m_reset_n        = Signal()

        # Synchro
        rx_sample_nr_sync= Signal(64)
        ch_en            = Signal(4 if output4channels else 2)
        smpl_width       = Signal(2)
        synch_dis        = Signal()
        pct_buff_cnt     = Signal(8)
        payload_buff_cnt = Signal(16)

        pct_loss_flg_clr = Signal()

        data_pad_tvalid  = Signal()
        data_pad_tdata   = Signal(128)
        data_pad_tready  = Signal()
        data_pad_tlast   = Signal()

        # Input data buffer (sink_width bit)
        ib_cd_from, ib_cd_to = s_clk_domain, m_clk_domain
        if cdc_stream_rst and s_clk_domain != m_clk_domain:
            self.cd_txp_ib_w = ClockDomain()
            self.cd_txp_ib_r = ClockDomain()
            self.comb += [
                self.cd_txp_ib_w.clk.eq(ClockSignal(s_clk_domain)),
                self.cd_txp_ib_r.clk.eq(ClockSignal(m_clk_domain)),
            ]
            self.specials += [
                AsyncResetSynchronizer(self.cd_txp_ib_w, ~tx_stream_en | ResetSignal(s_clk_domain)),
                AsyncResetSynchronizer(self.cd_txp_ib_r, ~tx_stream_en | ResetSignal(m_clk_domain)),
            ]
            ib_cd_from, ib_cd_to = "txp_ib_w", "txp_ib_r"
        input_buff = ClockDomainCrossing(
            layout=[("data", sink_width)],
            cd_from  = ib_cd_from,
            cd_to    = ib_cd_to,
            depth    = int(input_buff_size/sink_width),
            buffered = True)
        self.input_buff = input_buff

        # AXI Slave sink_width -> 128 (must use m_axis_domain)
        conv_64_to_128      = ResetInserter()(ClockDomainsRenamer(m_clk_domain)(stream.Converter(sink_width, 128)))
        self.conv_64_to_128 = conv_64_to_128

        # FIFO before unpacker
        fifo_smpl_buff      = ResetInserter()(ClockDomainsRenamer(m_clk_domain)(stream.SyncFIFO([("data", 128)], 16, buffered=True)))
        self.fifo_smpl_buff = fifo_smpl_buff

        unpack_bypass       = Signal()

        # LiteScope probes
        self.smpl_width        = smpl_width
        self.unpack_bypass     = unpack_bypass
        self.conn_buf          = Signal()
        self.data_pad_tready   = data_pad_tready
        self.data_pad_tlast    = data_pad_tlast
        self.data_pad_tvalid   = data_pad_tvalid
        self.data_pad_tdata    = data_pad_tdata
        self.rx_sample_nr_sync = rx_sample_nr_sync

        self.s_reset_n = s_reset_n
        self.m_reset_n = m_reset_n

        # Clocks ----------------------------------------------------------------------------------
        # Sample NR FIFO (must be async with sink in RX_CLK, source iqsample, areset_n with iqpacket_areset_n)
        #TODO: check if reset is needed here
        self.cd_smpl_nr_fifo  = ClockDomain()
        snf_cd_to = m_clk_domain
        if cdc_stream_rst:
            self.cd_txp_snf_r = ClockDomain()
            self.comb += [
                self.cd_smpl_nr_fifo.clk.eq(ClockSignal(rx_clk_domain)),
                self.cd_txp_snf_r.clk.eq(ClockSignal(m_clk_domain)),
            ]
            self.specials += [
                AsyncResetSynchronizer(self.cd_smpl_nr_fifo, ~(tx_stream_en & self.ext_reset_n)),
                AsyncResetSynchronizer(self.cd_txp_snf_r,    ~(tx_stream_en & self.ext_reset_n) | ResetSignal(m_clk_domain)),
            ]
            snf_cd_to = "txp_snf_r"
        else:
            self.comb += [
                self.cd_smpl_nr_fifo.clk.eq(ClockSignal(rx_clk_domain)),
                self.cd_smpl_nr_fifo.rst.eq( (~(s_reset_n & ext_reset_n_rx))),
            ]
        smpl_nr_fifo          = stream.ClockDomainCrossing([("data", 64)],
            cd_from = "smpl_nr_fifo",
            cd_to   = snf_cd_to,
            depth   = 8,
        )
        self.smpl_nr_fifo     = smpl_nr_fifo

        self.p2d_wr_sink_ready = p2d_wr_sink_ready = Signal()

        self.comb += [
            conv_64_to_128.reset.eq(     ~m_reset_n),

            # smpl_nr_fifo
            smpl_nr_fifo.sink.data.eq(   self.rx_sample_nr),
            smpl_nr_fifo.sink.valid.eq(  smpl_nr_fifo.sink.ready),
            rx_sample_nr_sync.eq(        smpl_nr_fifo.source.data),
            smpl_nr_fifo.source.ready.eq(smpl_nr_fifo.source.valid | ~m_reset_n),

            # input_buff
            input_buff.sink.data.eq(     self.sink.data),
            input_buff.sink.last.eq(     0),
            input_buff.sink.valid.eq(    self.sink.valid & s_reset_n),
            self.sink.ready.eq(          input_buff.sink.ready & s_reset_n),

            conv_64_to_128.sink.data.eq( input_buff.source.data),
            conv_64_to_128.sink.last.eq( 0),
            conv_64_to_128.sink.valid.eq(input_buff.source.valid & m_reset_n),

            # Async fifo used by ClockDomainCrossing does not have a reset
            # Passing reset as a ready signal to clear out the fifo is a workaround
            input_buff.source.ready.eq(conv_64_to_128.sink.ready | ~m_reset_n),
            conv_64_to_128.source.ready.eq(p2d_wr_sink_ready | ~m_reset_n),
        ]

        pct_rd = Signal()
        pct_clear = Signal()
        pct_valid = Signal()
        pct_header = Signal(128)

        self.pct_rd = pct_rd
        self.pct_clear = pct_clear
        self.pct_valid = pct_valid
        self.pct_header = pct_header

        self.txpct_fifo_debug_packets_avail = Signal(math.ceil(math.log2(BUFF_COUNT))+1)
        self.txpct_fifo_debug_packets_reserved = Signal(math.ceil(math.log2(BUFF_COUNT))+1)
        self.txpct_fifo_debug_store_state = Signal(3)
        self.txpct_fifo_debug_read_state = Signal(2)
        self.txpct_fifo_debug_payload_used = Signal(math.ceil(math.log2(PCT_MAX_SIZE//16))+1)
        self.txpct_fifo_debug_payload_will_fit = Signal()

        self.lime_txpct_fifo = Instance("lime_txpct_fifo",
            # Parameters.
            p_g_MAX_FIFO_WORDS  = PCT_MAX_SIZE//16,
            p_g_MAX_PACKETS     = BUFF_COUNT,

            i_clk               = ClockSignal(m_clk_domain),
            i_rst               = ~m_reset_n,
            i_s_axis_tdata      = conv_64_to_128.source.data,
            i_s_axis_tvalid     = conv_64_to_128.source.valid,
            o_s_axis_tready     = p2d_wr_sink_ready,

            o_m_axis_tdata      = data_pad_tdata,
            o_m_axis_tvalid     = data_pad_tvalid,
            i_m_axis_tready     = data_pad_tready,

            i_pct_buff_cnt      = pct_buff_cnt,
            i_payload_buff_cnt  = payload_buff_cnt,
            i_pct_rd            = pct_rd,
            i_pct_clr           = pct_clear,
            o_pct_valid         = pct_valid,
            o_pct_header        = pct_header,

            o_debug_packets_avail    = self.txpct_fifo_debug_packets_avail,
            o_debug_packets_reserved = self.txpct_fifo_debug_packets_reserved,
            o_debug_store_state      = self.txpct_fifo_debug_store_state,
            o_debug_read_state       = self.txpct_fifo_debug_read_state,
            o_debug_payload_used     = self.txpct_fifo_debug_payload_used,
            o_debug_payload_will_fit = self.txpct_fifo_debug_payload_will_fit
        )

        self.lime_txpct_fifo_conv = add_vhd2v_converter(self.platform,
            instance = self.lime_txpct_fifo,
            files    = ["gateware/LimeDFB/lime_txpct_fifo/src/lime_txpct_fifo.vhd",
                        "gateware/LimeDFB/simple_dual_port_ram/src/simple_dual_port_ram.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.lime_txpct_fifo)


        self.comb += data_pad_tlast.eq(0)

        # Packet read/clear triggers
        sync_m_clk_domain = getattr(self.sync, m_clk_domain)

        sync_m_clk_domain += [
            # Default: one-clock pulses only.
            pct_rd.eq(0),
            pct_clear.eq(0),

            If(m_reset_n & ext_reset_n_m,
                If(pct_valid,
                    # VHDL pct_header(127 downto 64) == Migen pct_header[64:128]
                    If(rx_sample_nr_sync == pct_header[64:128],
                        pct_rd.eq(1)
                    ).Elif(rx_sample_nr_sync > pct_header[64:128],
                        pct_clear.eq(1)
                    )
                )
            )
        ]

        # Packet los flag act as sticky bit. In order to dessert it has to be cleared externally
        sync_m_clk_domain += [
            If(~m_reset_n | ~ext_reset_n_m,
                self.pct_loss_flg.eq(0),
            ).Elif(pct_loss_flg_clr,
                self.pct_loss_flg.eq(0),
            ).Elif(pct_valid & ~pct_rd & pct_clear,
                self.pct_loss_flg.eq(1),
            )
        ]


        # Pad 12 bit samples to 16 bit samples, bypass logic if no padding is needed
        self.sample_padder = Instance("sample_padder",
            # Clk/Reset.
            i_CLK           = ClockSignal(m_clk_domain), # m_axis_domain
            i_RESET_N       = ext_reset_n_m,             # Unconnected for XTRX

            # AXI Stream Slave.
            i_S_AXIS_TVALID = data_pad_tvalid,
            i_S_AXIS_TDATA  = data_pad_tdata,
            o_S_AXIS_TREADY = data_pad_tready,
            i_S_AXIS_TLAST  = data_pad_tlast,

            # AXI Stream Master.
            o_M_AXIS_TDATA  = fifo_smpl_buff.sink.data,
            o_M_AXIS_TVALID = fifo_smpl_buff.sink.valid,
            i_M_AXIS_TREADY = fifo_smpl_buff.sink.ready,
            o_M_AXIS_TLAST  = fifo_smpl_buff.sink.last,

            # Control.
            i_BYPASS        = unpack_bypass,
        )
        if not output4channels:
            self.sample_unpack = Instance("SAMPLE_UNPACK",
                # Clk/Reset.
                i_RESET_N       = ext_reset_n_m,             # Unconnected for XTRX
                i_AXIS_ACLK     = ClockSignal(m_clk_domain), # m_axis_domain
                i_AXIS_ARESET_N = m_reset_n,                 # m_axis_domain.a_reset_n

                # AXI Stream Master
                i_S_AXIS_TDATA  = fifo_smpl_buff.source.data,
                o_S_AXIS_TREADY = fifo_smpl_buff.source.ready,
                i_S_AXIS_TVALID = fifo_smpl_buff.source.valid,
                i_S_AXIS_TLAST  = fifo_smpl_buff.source.last,

                # AXI Stream Master
                o_M_AXIS_TDATA  = self.source.data,
                i_M_AXIS_TREADY = self.source.ready,
                o_M_AXIS_TVALID = self.source.valid,

                # Mode Settings.
                i_CH_EN         = ch_en,
            )
        else:
            from gateware.LimeDFB.tx_path_top.src.sample_unpack128 import sample_unpack128
            sample_unpack128_inst = ResetInserter()(ClockDomainsRenamer(m_clk_domain)(sample_unpack128()))
            self.sample_unpack = sample_unpack128_inst
            # Connect IO
            self.comb += [
                # Control signals
                self.sample_unpack.reset.eq(~ext_reset_n_m),
                self.sample_unpack.ch_en.eq(ch_en),
                # Input data
                self.sample_unpack.sink.data.eq(fifo_smpl_buff.source.data),
                self.sample_unpack.sink.valid.eq(fifo_smpl_buff.source.valid),
                self.fifo_smpl_buff.source.ready.eq(self.sample_unpack.sink.ready),
                # Output data
                self.source.data.eq(self.sample_unpack.source.data),
                self.source.valid.eq(self.sample_unpack.source.valid),
                self.sample_unpack.source.ready.eq(self.source.ready),
            ]

        self.specials += [
            MultiReg(tx_stream_en, s_reset_n, odomain=s_clk_domain),
            MultiReg(tx_stream_en, m_reset_n, odomain=m_clk_domain),
        ]

        self.specials += [
            MultiReg(fpgacfg_manager.ch_en,         ch_en,            odomain=m_clk_domain),
            MultiReg(fpgacfg_manager.smpl_width,    smpl_width,       odomain=m_clk_domain),
            MultiReg(fpgacfg_manager.synch_dis,     synch_dis,        odomain=m_clk_domain),
            MultiReg(self.pct_loss_flg_clr,         pct_loss_flg_clr, odomain=m_clk_domain),
            MultiReg(self.pct_buff_cnt.storage,     pct_buff_cnt,     odomain=m_clk_domain),
            MultiReg(self.payload_buff_cnt.storage, payload_buff_cnt, odomain=m_clk_domain),
        ]

        sync_m_clk_domain = getattr(self.sync, m_clk_domain)
        sync_m_clk_domain += [
            If(smpl_width == 0b00,
                unpack_bypass.eq(1),
            ).Else(
                unpack_bypass.eq(0),
            ),
        ]

        self.comb += [
            fifo_smpl_buff.reset.eq(~ext_reset_n_m),
            self.source.last.eq(0),
        ]


        self.sample_padder_conv = add_vhd2v_converter(self.platform,
            instance = self.sample_padder,
            files    = ["gateware/LimeDFB/tx_path_top/src/sample_padder.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.sample_padder)

        if not output4channels:
            self.sample_unpack_conv = add_vhd2v_converter(self.platform,
                instance = self.sample_unpack,
                files    = ["gateware/LimeDFB/tx_path_top/src/sample_unpack.vhd"],
            )
            # Removed Instance to avoid multiple definition
            self._fragment.specials.remove(self.sample_unpack)

        # Signal lists for debugging
        self.flow_control_signals = SimpleNamespace()
        self.flow_control_signals.m_clk = [
            m_reset_n,
            self.source.valid,
            self.source.ready,
            self.source.last,
            pct_buff_cnt,
            payload_buff_cnt,
            pct_rd,
            pct_valid,
            pct_clear,
            data_pad_tvalid,
            data_pad_tready,
            data_pad_tlast,
            conv_64_to_128.sink.valid,
            conv_64_to_128.sink.ready,
            conv_64_to_128.sink.last,
            conv_64_to_128.source.valid,
            conv_64_to_128.source.ready,
            conv_64_to_128.source.last,
            input_buff.source.valid,
            input_buff.source.ready,
            fifo_smpl_buff.sink.valid,
            fifo_smpl_buff.sink.ready,
            fifo_smpl_buff.sink.last,
            fifo_smpl_buff.source.valid,
            fifo_smpl_buff.source.ready,
            fifo_smpl_buff.source.last,
            smpl_nr_fifo.source.valid,
            smpl_nr_fifo.source.ready,
            p2d_wr_sink_ready,
            self.txpct_fifo_debug_store_state,
            self.txpct_fifo_debug_read_state,
            self.txpct_fifo_debug_payload_used,
            self.txpct_fifo_debug_payload_will_fit,
        ]

        self.flow_control_signals.s_clk = [
            s_reset_n,
            self.sink.valid,
            self.sink.ready,
            input_buff.sink.valid,
            input_buff.sink.ready,
        ]

        self.flow_control_signals.rx_clk = [
            smpl_nr_fifo.sink.valid,
            smpl_nr_fifo.sink.ready,
        ]
