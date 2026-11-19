# SPDX-License-Identifier: Apache-2.0
"""HostTCD TX block storage, IQ unpacking and CDC slot ownership.

A command describes one complete acquisition-sized block across its selected
channels. DMA bytes arrive in logical channel order, with no fragment padding.
The descriptor-to-block adapter is separate: command is not the child descriptor
interface. Playback metadata crosses intact; its ready handshake authorizes
playback. The downstream timed-release engine must drive that handshake.
"""
from pathlib import Path
from migen import *
from migen.genlib.cdc import MultiReg
from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.axi.axi_stream import AXIStreamInterface
from litex.soc.interconnect.csr import CSRStorage, CSRStatus
from gateware.common import add_vhd2v_converter


class HostTCDTX(LiteXModule):
    def __init__(self, platform, s_clk_domain="sys", m_clk_domain="afe",
                 slot_samples=1024, slot_count=4, instantiate_rtl=True):
        if s_clk_domain != "sys":
            raise ValueError("HostTCD TX control domain must be sys")
        if slot_samples < 32 or slot_samples & (slot_samples - 1):
            raise ValueError("slot_samples must be a power of two, at least 32")
        if slot_count < 2 or slot_count & (slot_count - 1):
            raise ValueError("slot_count must be a power of two, at least two")
        self.sink = AXIStreamInterface(256, clock_domain=s_clk_domain)
        self.source = AXIStreamInterface(128, clock_domain=m_clk_domain)
        self.version = CSRStatus(32, name="version")
        self.flush = CSRStorage(1, reset=1, name="flush")
        self.flush_allowed = Signal(reset=1)  # External DMA/playback quiescence interlock.
        self.soft_reset = soft_reset = Signal(reset=1)
        self.sync += If(self.flush_allowed, soft_reset.eq(self.flush.storage))
        self.reset_rd = reset_rd = Signal(reset=1)
        reset_ack = Signal(reset=1)
        self.specials += [MultiReg(soft_reset, reset_rd, odomain=m_clk_domain),
                          MultiReg(reset_rd, reset_ack, odomain=s_clk_domain)]
        self.status = CSRStatus(3, name="status", description=
            "Bit0=flush acknowledged, bit1=load active, bit2=invalid command.")
        self.block_samples = CSRStatus(32, name="block_samples")
        self.capacity = CSRStatus(32, name="slot_capacity")
        self.free = Signal(slot_count, reset=(1 << slot_count)-1)
        self.invalid = invalid = Signal()
        slot_bits = max(1, (slot_count-1).bit_length())
        metadata = [("slot", slot_bits), ("mask", 4), ("epoch", 32),
                    ("sequence", 32), ("start_tick", 64), ("timed", 1), ("parent_last", 1), ("parent_first", 1)]
        self.command = cmd = stream.Endpoint([
            ("channel_count", 3), ("channel_map", 8), ("iq12", 1)] + metadata[2:])
        self.ready_slots = ready = ClockDomainsRenamer({"write": s_clk_domain, "read": m_clk_domain})(
            ResetInserter(["write", "read"])(stream.AsyncFIFO(metadata, max(4, slot_count))))
        self.released_slots = released = ClockDomainsRenamer({"write": m_clk_domain, "read": s_clk_domain})(
            ResetInserter(["write", "read"])(stream.AsyncFIFO([("slot", slot_bits)], max(4, slot_count))))
        self.playback = playback = stream.Endpoint(metadata)
        self.comb += [ready.reset_write.eq(soft_reset), ready.reset_read.eq(reset_rd),
            released.reset_write.eq(reset_rd), released.reset_read.eq(soft_reset),
            released.source.ready.eq(~soft_reset),
            ready.source.connect(playback, omit={"valid", "ready"})]
        # Test-visible VHDL interfaces, as in HostTCDRX.
        self.load = load = stream.Endpoint([
            ("slot", slot_bits), ("channel_count", 3), ("channel_map", 8), ("iq12", 1)])
        self.loaded = loaded = stream.Endpoint([])
        self.play = play = stream.Endpoint([("slot", slot_bits), ("mask", 4)])
        self.unpacked = unpacked = stream.Endpoint([("data", 128)])
        self.release = release = stream.Endpoint([("slot", slot_bits)])
        self.received = Signal()  # One sys-clock pulse: entire block stored (not transmitted).
        selected = Signal(slot_bits)
        saved_channels = Signal(3, reset=1)
        saved_map = Signal(8)
        saved_iq12 = Signal()
        saved = {name:Signal(width) for name, width in metadata[2:]}
        mask = Signal(4)
        physical = [cmd.channel_map[2*i:2*i+2] for i in range(4)]
        duplicate = reduce_or([(physical[a] == physical[b]) &
            (cmd.channel_count > b) for a in range(4) for b in range(a+1, 4)])
        self.comb += invalid.eq((cmd.channel_count == 0) | (cmd.channel_count > 4) | duplicate)
        cmd_mask = Signal(4)
        self.comb += cmd_mask.eq(reduce_or([Mux(cmd.channel_count > i, 1 << physical[i], 0)
                                          for i in range(4)]))
        self.fsm = fsm = ResetInserter()(FSM(reset_state="IDLE"))
        self.comb += [fsm.reset.eq(soft_reset), self.version.status.eq(1),
            self.block_samples.status.eq(slot_samples), self.capacity.status.eq(slot_count),
            self.status.status.eq(Cat(reset_ack, ~fsm.ongoing("IDLE"), cmd.valid & invalid)),
            load.slot.eq(selected), load.channel_count.eq(saved_channels),
            load.channel_map.eq(saved_map), load.iq12.eq(saved_iq12),
            ready.sink.slot.eq(selected), ready.sink.mask.eq(mask),
            *[getattr(ready.sink, name).eq(value) for name, value in saved.items()],
            playback.valid.eq(ready.source.valid & play.ready & ~reset_rd),
            ready.source.ready.eq(playback.ready & play.ready & ~reset_rd),
            play.valid.eq(ready.source.valid & playback.ready & ~reset_rd),
            play.slot.eq(playback.slot), play.mask.eq(playback.mask),
            unpacked.connect(self.source, omit={"keep"}), self.source.keep.eq(0xffff),
            release.connect(released.sink),
        ]
        # ready may only be asserted when VHDL can accept a playback command.
        # Expose availability so a timed scheduler can safely authorize it.
        self.play_ready = play.ready
        fsm.act("IDLE",
            cmd.ready.eq(Array([self.free[i] for i in range(slot_count)])[selected] &
                         ~invalid & ~soft_reset & ~reset_ack),
            If(cmd.valid & cmd.ready,
                NextValue(saved_channels, cmd.channel_count), NextValue(saved_map, cmd.channel_map),
                NextValue(saved_iq12, cmd.iq12), NextValue(mask, cmd_mask),
                *[NextValue(value, getattr(cmd, name)) for name, value in saved.items()],
                NextState("LOAD")))
        fsm.act("LOAD", load.valid.eq(1), If(load.ready, NextState("DATA")))
        # sink routing stays separate so no DMA beat is consumed before load.
        self.dma_sink = dma_sink = AXIStreamInterface(256, clock_domain=s_clk_domain)
        self.comb += self.sink.connect(dma_sink, omit={"valid", "ready"})
        fsm.act("DATA", dma_sink.valid.eq(self.sink.valid), self.sink.ready.eq(dma_sink.ready), If(loaded.valid,
            loaded.ready.eq(1), self.received.eq(1), NextState("PUBLISH")))
        fsm.act("PUBLISH", ready.sink.valid.eq(1), If(ready.sink.ready,
            NextValue(selected, selected+1), NextState("IDLE")))
        # Clear-on-admission, set-on-release. Simultaneous operations retain both.
        self.sync += If(soft_reset, self.free.eq((1 << slot_count)-1), selected.eq(0)).Else(
            self.free.eq((self.free & ~Mux(cmd.valid & cmd.ready, 1 << selected, 0)) |
                Mux(released.source.valid & released.source.ready, 1 << released.source.slot, 0)))
        if instantiate_rtl:
            rtl = Instance("host_tcd_tx_buffer", p_SLOT_SAMPLES=slot_samples, p_SLOT_COUNT=slot_count,
                i_wr_clk=ClockSignal(s_clk_domain), i_wr_reset=ResetSignal(s_clk_domain)|soft_reset,
                i_load_valid=load.valid, o_load_ready=load.ready, i_load_slot=load.slot,
                i_load_channels=load.channel_count, i_load_map=load.channel_map, i_load_iq12=load.iq12,
                i_sink_valid=dma_sink.valid, o_sink_ready=dma_sink.ready, i_sink_data=dma_sink.data,
                o_done_valid=loaded.valid, i_done_ready=loaded.ready,
                i_rd_clk=ClockSignal(m_clk_domain), i_rd_reset=ResetSignal(m_clk_domain)|reset_rd,
                i_play_valid=play.valid, o_play_ready=play.ready, i_play_slot=play.slot, i_play_mask=play.mask,
                o_source_valid=unpacked.valid, i_source_ready=unpacked.ready,
                o_source_data=unpacked.data, o_source_last=unpacked.last,
                o_release_valid=release.valid, i_release_ready=release.ready, o_release_slot=release.slot)
            self.rtl = add_vhd2v_converter(platform, rtl,
                files=[str(Path(__file__).with_name("host_tcd_tx_buffer.vhd"))], flatten_source=False)


def reduce_or(expressions):
    value = Constant(0)
    for expression in expressions:
        value = value | expression
    return value
