# SPDX-License-Identifier: Apache-2.0
"""HostTCD acquisition path: channel RAM, CDC ownership and timestamp completions.

The VHDL datapath owns sample storage and IQ packing. This wrapper owns the
CSR ABI, asynchronous ownership queues, ordered child admission and retirement.
"""
from pathlib import Path

from migen import *
from migen.genlib.cdc import MultiReg
from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.axi.axi_stream import AXIStreamInterface
from litex.soc.interconnect.csr import CSRStatus, CSRStorage
from gateware.common import add_vhd2v_converter


class HostTCDRX(LiteXModule):
    def __init__(self, platform, fpgacfg_manager=None, rx_stream_en=None,
                 s_clk_domain="afe", m_clk_domain="sys", sink_width=128,
                 source_width=256, slot_samples=1024, slot_count=4,
                 completion_depth=256, command_depth=256, instantiate_rtl=True,
                 **unused):
        if sink_width != 128 or source_width != 256:
            raise ValueError("HostTCD RX requires four IQ16 channels and a 256-bit DMA")
        if slot_samples < 32 or slot_samples & (slot_samples - 1):
            raise ValueError("slot_samples must be a power of two, at least 32")
        if slot_count < 2 or slot_count & (slot_count - 1):
            raise ValueError("slot_count must be a power of two, at least two")
        if completion_depth < 2:
            raise ValueError("completion_depth must be at least two")
        if m_clk_domain != "sys":
            raise ValueError("HostTCD CSR/control domain must be sys")
        self.sink = AXIStreamInterface(128, clock_domain=s_clk_domain)
        self.source = AXIStreamInterface(256, clock_domain=m_clk_domain)
        self.smpl_nr_cnt = Signal(64)
        self.smpl_nr_cnt_out = Signal(64)
        self.smpl_cnt_en = Signal()
        self.tx_pct_loss_flg = Signal()
        self.pct_hdr_cap = Signal()
        self.rx_pct_fifo_aclrn_req = Signal()
        # Port-compatible with the legacy RX path, keeping the TX timer in the
        # acquisition domain. This timer is NOT reset by the software flush.
        self.comb += [self.smpl_nr_cnt_out.eq(self.smpl_nr_cnt), self.sink.ready.eq(1)]

        self.version = CSRStatus(32, name="version")
        self.flush = CSRStorage(1, reset=1, name="flush", description=
            "Hold at 1 while stopped to reset queues and apply configuration. Never flush an active DMA.")
        self.iq12 = CSRStorage(1, name="iq12", description="0=IQ16, 1=packed upper 12 bits of I and Q.")
        self.channel_map = CSRStorage(8, reset=0xe4, name="channel_map", description=
            "Four two-bit logical-to-physical channel indices. Must be a permutation.")
        self.epoch = CSRStorage(32, name="epoch", description="Software stream generation; change while flushed.")
        self.status = CSRStatus(5, name="status", description=
            "Bit0=flush acknowledged, bit1=capture active, bit2=fatal, bit3=bad map, bit4=flush blocked.")
        self.dropped = CSRStatus(32, name="dropped", description="Coherent live dropped-frame count, with CDC delay.")
        # Preserve published CSR names/offsets; each protocol "block" is one slot.
        self.slot_size = CSRStatus(32, name="block_samples")
        self.slot_bytes = CSRStatus(32, name="block_bytes")
        self.capacity = CSRStatus(32, name="metadata_capacity")
        self.level = CSRStatus(32, name="metadata_level")
        self.reserved = CSRStatus(32, name="metadata_reserved")
        self.snapshot = CSRStorage(1, name="snapshot")
        self.snapshot_valid = CSRStatus(1, name="snapshot_valid")
        self.record_words = CSRStatus(32, name="metadata_record_words")
        self.words = [CSRStatus(32, name=f"record_word{i}") for i in range(24)]
        for i, word in enumerate(self.words):
            setattr(self, f"record_word{i}", word)
        self.pop = CSRStorage(1, name="pop")
        self.irq_enable = CSRStorage(1, name="irq_enable")
        self.irq = Signal()
        self.fatal = Signal()
        self.flush_allowed = Signal(reset=1)
        self.soft_reset = soft_reset = Signal(reset=1)
        self.sync += If(self.flush_allowed, soft_reset.eq(self.flush.storage))
        self.active_iq12 = Signal()
        self.active_map = Signal(8, reset=0xe4)
        epoch = Signal(32)
        self.sync += If(soft_reset,
            self.active_iq12.eq(self.iq12.storage), self.active_map.eq(self.channel_map.storage),
            epoch.eq(self.epoch.storage))
        invalid_map = Signal()
        self.comb += invalid_map.eq(reduce_or([
            self.active_map[2*a:2*a+2] == self.active_map[2*b:2*b+2]
            for a in range(4) for b in range(a)]))
        flush_acq = Signal(reset=1)
        capture_acq = Signal()
        capture_request = Signal()
        capture_sys = Signal()
        flush_ack = Signal(reset=1)
        self.specials += [MultiReg(soft_reset, flush_acq, odomain=s_clk_domain),
            MultiReg(capture_request, capture_acq, odomain=s_clk_domain),
            MultiReg(flush_acq, flush_ack, odomain=m_clk_domain),
            MultiReg(capture_acq, capture_sys, odomain=m_clk_domain)]
        if rx_stream_en is None:
            rx_stream_en = Signal()
        self.comb += capture_request.eq(rx_stream_en & ~soft_reset & ~invalid_map & ~self.fatal)
        self.comb += [self.version.status.eq(2), self.record_words.status.eq(24), self.slot_size.status.eq(slot_samples),
            self.slot_bytes.status.eq(Mux(self.active_iq12, slot_samples*3, slot_samples*4)),
            self.capacity.status.eq(completion_depth),
            self.status.status.eq(Cat(flush_ack, capture_sys, self.fatal, invalid_map,
                self.flush.storage & ~self.flush_allowed & ~soft_reset)),
            self.rx_pct_fifo_aclrn_req.eq(~flush_ack)]

        slot_bits = max(1, (slot_count-1).bit_length())
        # Ownership metadata remains stable until the receiving side accepts it.
        self.ready_slots = ready_slots = ClockDomainsRenamer({"write": s_clk_domain, "read": m_clk_domain})(
            ResetInserter(["write", "read"])(stream.AsyncFIFO([
                ("slot", slot_bits), ("tick", 64), ("gap", 1)], max(4, slot_count))))
        self.released_slots = released = ClockDomainsRenamer({"write": m_clk_domain, "read": s_clk_domain})(
            ResetInserter(["write", "read"])(stream.AsyncFIFO([("slot", slot_bits)], max(4, slot_count))))
        self.comb += [ready_slots.reset_write.eq(flush_acq), ready_slots.reset_read.eq(soft_reset),
            released.reset_write.eq(soft_reset), released.reset_read.eq(flush_acq),
            released.source.ready.eq(~flush_acq)]
        drops = Signal(32)
        # Registered Gray counter: a coherent live statistic even if every RAM
        # slot is full and no further slot descriptors can be published.
        drops_gray = Signal(32)
        drops_gray_sys = Signal(32)
        sync_acq = getattr(self.sync, s_clk_domain)
        sync_acq += drops_gray.eq(drops ^ (drops >> 1))
        self.specials += MultiReg(drops_gray, drops_gray_sys, odomain=m_clk_domain)
        self.comb += self.dropped.status.eq(reduce_xor_shifts(drops_gray_sys))

        # Explicit signals permit the control wrapper to be simulated independently
        # of the VHDL memory/formatter; GHDL tests cover the real datapath.
        self.slot_command = slot_command = stream.Endpoint([
            ("slot", slot_bits), ("channel", 2), ("iq12", 1)])
        self.formatted = formatted = stream.Endpoint([("data", 256)])
        if instantiate_rtl:
            rtl = Instance("host_tcd_rx_buffer",
                p_SLOT_SAMPLES=slot_samples, p_SLOT_COUNT=slot_count,
                i_wr_clk=ClockSignal(s_clk_domain), i_wr_reset=ResetSignal(s_clk_domain),
                i_wr_flush=flush_acq, i_capture_enable=capture_acq,
                i_frame_valid=self.sink.valid, i_frame_data=self.sink.data,
                o_sample_tick=self.smpl_nr_cnt, o_dropped_frames=drops,
                o_slot_valid=ready_slots.sink.valid, i_slot_ready=ready_slots.sink.ready,
                o_slot_index=ready_slots.sink.slot, o_slot_tick=ready_slots.sink.tick,
                o_slot_gap=ready_slots.sink.gap,
                i_release_valid=released.source.valid & released.source.ready,
                i_release_slot=released.source.slot,
                i_rd_clk=ClockSignal(m_clk_domain), i_rd_reset=ResetSignal(m_clk_domain) | soft_reset,
                i_command_valid=slot_command.valid, o_command_ready=slot_command.ready,
                i_command_slot=slot_command.slot, i_command_channel=slot_command.channel,
                i_command_iq12=slot_command.iq12,
                o_source_valid=formatted.valid, i_source_ready=formatted.ready,
                o_source_data=formatted.data, o_source_last=formatted.last)
            self.rtl = add_vhd2v_converter(platform, rtl,
                files=[str(Path(__file__).with_name("host_tcd_rx_buffer.vhd"))],
                flatten_source=False)

        command_layout = [("channel", 2), ("channel_count", 5), ("length", 24), ("address", 64),
            # These field names match FPGAHostDescriptorTable's command ABI.
            ("channel_offset", 32), ("block_offset", 32), ("block_length", 24),
            ("channel_last", 1), ("block_last", 1), ("sequence", 32)]
        self.command = cmd = stream.Endpoint(command_layout)
        self.child_retired = Signal()
        # Native retirements carry only an end-of-parent tag. The separate record
        # queue holds one immutable summary per parent, published at final DMA
        # retirement rather than at command admission or payload formatting.
        self.associations = associations = ResetInserter()(stream.SyncFIFO([
            ("publish", 1)], command_depth, buffered=True))
        self.parent_records = parent_records = ResetInserter()(stream.SyncFIFO([
            ("record", 768)], 2, buffered=True))
        self.completions = completions = ResetInserter()(stream.SyncFIFO([
            ("record", 768)], completion_depth, buffered=True))
        self.output_fifo = output = ResetInserter()(stream.SyncFIFO([("data", 256)], 16, buffered=True))
        self.comb += [associations.reset.eq(soft_reset), parent_records.reset.eq(soft_reset), completions.reset.eq(soft_reset),
            output.reset.eq(soft_reset), output.source.connect(self.source, omit={"keep"}),
            self.source.keep.eq(0xffffffff), self.level.status.eq(completions.level),
            self.irq.eq(self.irq_enable.storage & (completions.source.valid | self.fatal))]
        credits = Signal(max=completion_depth+1)
        snapshot_valid = Signal()
        take_snapshot = self.snapshot.re & self.snapshot.storage & completions.source.valid
        pop = self.pop.re & self.pop.storage & snapshot_valid & completions.source.valid
        reserve = Signal()
        self.comb += [self.reserved.status.eq(credits), self.snapshot_valid.status.eq(snapshot_valid),
            completions.source.ready.eq(pop)]
        self.sync += [
            If(soft_reset,
                credits.eq(0), snapshot_valid.eq(0), self.fatal.eq(0)
            ).Else(
                If(reserve & ~pop, credits.eq(credits+1)).Elif(pop & ~reserve, credits.eq(credits-1)),
                If(take_snapshot,
                    snapshot_valid.eq(1),
                    *[w.status.eq(completions.source.record[32*i:32*(i+1)]) for i, w in enumerate(self.words)]),
                If(pop, snapshot_valid.eq(0)),
                If(self.child_retired & ~associations.source.valid, self.fatal.eq(1)),
                If(self.child_retired & associations.source.valid & associations.source.publish & ~completions.sink.ready,
                    self.fatal.eq(1)),
                If(self.child_retired & associations.source.valid & associations.source.publish & ~parent_records.source.valid,
                    self.fatal.eq(1))) ]
        self.comb += [
            associations.source.ready.eq(self.child_retired),
            parent_records.source.ready.eq(self.child_retired & associations.source.valid & associations.source.publish),
            completions.sink.valid.eq(parent_records.source.ready & parent_records.source.valid),
            completions.sink.record.eq(parent_records.source.record),
            self.pct_hdr_cap.eq(ready_slots.source.valid & ready_slots.source.ready)]

        remaining = Signal(24)
        last_channel = Signal()
        physical_channel = Signal(2)
        first_fragment = Signal()
        valid_command = Signal()
        checked_valid = Signal()
        checked_first = Signal()
        checked_channel = Signal(2)
        parent_addresses = [Signal(64) for _ in range(4)]
        parent_sequence = Signal(32)
        parent_channels = Signal(5)
        parent_mask = Signal(4)
        first_tick = Signal(64)
        last_tick = Signal(64)
        expected_tick = Signal(64)
        parent_samples = Signal(32)
        parent_bytes = Signal(32)
        parent_slots = Signal(32)
        gap_before = Signal()
        internal_gap = Signal()
        timestamp_error = Signal()
        first_gap_offset = Signal(32, reset=0xffffffff)
        channel_map = Array(self.active_map[2*i:2*i+2] for i in range(4))
        self.comb += [physical_channel.eq(channel_map[cmd.channel]),
            first_fragment.eq(cmd.channel_offset == cmd.block_offset),
            valid_command.eq((cmd.channel_count >= 1) & (cmd.channel_count <= 4) &
                (cmd.channel < cmd.channel_count) & (cmd.block_length == self.slot_bytes.status) &
                (cmd.length != 0) & ((cmd.length & 31) == 0) &
                (cmd.channel_offset >= cmd.block_offset) &
                (cmd.channel_offset + cmd.length <= cmd.block_offset + cmd.block_length))]
        record = Cat(epoch, parent_sequence,
            Cat(Constant(0, 8), self.active_iq12, Constant(0, 7), Constant(1, 1),
                gap_before, internal_gap, timestamp_error, Constant(0, 12)),
            self.active_map, Constant(0, 24), parent_channels, Constant(0, 27),
            parent_mask, Constant(0, 28), *parent_addresses,
            first_tick, last_tick, parent_samples, parent_bytes, parent_slots,
            Mux(internal_gap, first_gap_offset, parent_samples), first_gap_offset, Constant(0, 32))
        # No packet headers are inserted: every output byte is channel sample data.
        self.fsm = fsm = ResetInserter()(FSM(reset_state="CHECK_COMMAND"))
        self.comb += fsm.reset.eq(soft_reset)
        # Keep the FIFO head until admission. Register the 33-bit bounds check
        # before it fans out to command.ready, metadata RAM and slot records.
        fsm.act("CHECK_COMMAND",
            If(cmd.valid & ~soft_reset & ~self.fatal,
                NextValue(checked_valid, valid_command),
                NextValue(checked_first, first_fragment),
                NextValue(checked_channel, physical_channel),
                NextState("METADATA")))
        # Update summary registers once per command, separately from admission
        # enables. A held FIFO head must never count bytes or samples twice.
        fsm.act("METADATA",
            If(~checked_valid,
                NextValue(self.fatal, 1)
            ).Elif(ready_slots.source.valid,
                If(cmd.first,
                    NextValue(parent_sequence, cmd.sequence), NextValue(parent_channels, cmd.channel_count),
                    NextValue(parent_mask, 1 << checked_channel),
                    NextValue(gap_before, ready_slots.source.gap),
                    NextValue(internal_gap, 0), NextValue(timestamp_error, 0),
                    NextValue(first_gap_offset, 0xffffffff),
                    NextValue(first_tick, ready_slots.source.tick),
                    *[NextValue(a, 0) for a in parent_addresses]),
                If(cmd.channel_offset == 0,
                    *[If(cmd.channel == i, NextValue(a, cmd.address)) for i, a in enumerate(parent_addresses)],
                    If(~cmd.first, NextValue(parent_mask, parent_mask | (1 << checked_channel)))),
                If(cmd.channel == 0,
                    If(cmd.first, NextValue(parent_bytes, cmd.length))
                    .Else(NextValue(parent_bytes, parent_bytes + cmd.length)),
                    If(checked_first,
                        NextValue(last_tick, ready_slots.source.tick),
                        NextValue(expected_tick, ready_slots.source.tick + slot_samples),
                        If(cmd.first,
                            NextValue(parent_samples, slot_samples), NextValue(parent_slots, 1)
                        ).Else(
                            NextValue(parent_samples, parent_samples + slot_samples),
                            NextValue(parent_slots, parent_slots + 1),
                            If(ready_slots.source.gap | (ready_slots.source.tick != expected_tick),
                                NextValue(internal_gap, 1),
                                If(~internal_gap, NextValue(first_gap_offset, parent_samples))),
                            If((ready_slots.source.tick != expected_tick) & ~ready_slots.source.gap,
                                NextValue(timestamp_error, 1))))),
                NextState("COMMAND")))
        fsm.act("COMMAND",
            If(cmd.valid & ~soft_reset & ~self.fatal & ~invalid_map,
                If(~checked_valid,
                    NextValue(self.fatal, 1)
                ).Elif(ready_slots.source.valid & associations.sink.ready &
                        (~cmd.last | parent_records.sink.ready),
                    If((~cmd.first | (credits < completion_depth)) & (~checked_first | slot_command.ready),
                        cmd.ready.eq(1), associations.sink.valid.eq(1),
                        associations.sink.publish.eq(cmd.last),
                        parent_records.sink.valid.eq(cmd.last), parent_records.sink.record.eq(record),
                        slot_command.valid.eq(checked_first), slot_command.slot.eq(ready_slots.source.slot),
                        slot_command.channel.eq(checked_channel), slot_command.iq12.eq(self.active_iq12),
                        reserve.eq(cmd.first),
                        NextValue(remaining, cmd.length), NextValue(last_channel, cmd.block_last),
                        NextState("DATA")))))
        fsm.act("DATA",
            formatted.connect(output.sink, omit={"valid", "ready", "last", "first"}),
            output.sink.valid.eq(formatted.valid & ~self.fatal & ((remaining != 32) | ~last_channel | released.sink.ready)),
            formatted.ready.eq(output.sink.ready & ~self.fatal & ((remaining != 32) | ~last_channel | released.sink.ready)),
            If(output.sink.valid & output.sink.ready,
                NextValue(remaining, remaining-32),
                If(remaining == 32,
                    If(last_channel,
                        released.sink.valid.eq(1), released.sink.slot.eq(ready_slots.source.slot),
                        ready_slots.source.ready.eq(1)),
                    NextState("CHECK_COMMAND"))))


def reduce_or(expressions):
    value = Constant(0)
    for expression in expressions:
        value = value | expression
    return value


def reduce_xor_shifts(value):
    result = value
    for shift in (1, 2, 4, 8, 16):
        result = result ^ (result >> shift)
    return result
