# HostTCD TX sample buffers

`src/host_tcd_tx_buffer.vhd` implements the sample RAM and IQ unpacker.
`src/host_tcd_tx.py` wraps it as `HostTCDTX`, with asynchronous ownership queues
and a block metadata interface, following the HostTCD RX organization.

The default storage is four slots of 1024 samples in each of four physical
channel banks: 64 KiB total. Each bank has eight 32-bit RAM lanes. Unpacking
writes up to eight samples per processing clock; playback reads one simultaneous
four-channel IQ16 frame per output clock. Unselected physical channels output
zero. IQ12 components are restored to their acquired 16-bit scale by appending
four zero bits. RAM contents are not reset.

## Interfaces

- `command`, in `sys`: one complete block, with `channel_count` (1–4),
  `channel_map` (two bits per logical destination), `iq12`, `epoch`, `sequence`,
  `start_tick` (64 bits), `timed`, and `parent_last`.
- `sink`, in `sys`: 256-bit DMA data. Supply one full block for each selected
  logical destination in order: 4096 bytes/channel for IQ16 or 3072 for IQ12.
  Fragment boundaries do not restart packing; `last`/`keep` are not used.
  No partial beat or partial block is supported.
- `playback`, in the output domain: a completed slot with physical channel mask
  and the command's metadata. Its valid/ready handshake authorizes playback.
  The caller decides when to assert ready; this wrapper does not compare ticks.
- `source`, in the output domain: 128-bit simultaneous A/B/C/D IQ16 frames,
  with `last` on the block's final frame. Valid/data/last remain stable on stalls.
- `received`, in `sys`: pulse when an entire block has been stored, before it
  has necessarily played. This is not a parent completion or buffer reuse event.

Slots become unavailable at command acceptance. The write side publishes them
only after all selected channels are loaded. Playback returns ownership through
a separate asynchronous FIFO after the last output frame is accepted. A full
buffer pool stalls command admission rather than overwriting samples.

`flush` defaults to one. Deassert it and wait for status bit 0 to clear before
submitting commands. Before asserting flush, stop DMA traffic and playback;
set `flush_allowed` from the external quiescence interlock. Reset both clock
domains together. Flushing discards slot ownership and pending data and must not
be used to abort outstanding PCIe reads.

The block command is distinct from native DMA fragment commands. The integrated
`HostTCD_trx` engine in LimeSDR_GW's `gateware/host_tcd_tx.py` groups fragments,
calculates block ticks, prefetches samples and controls timed output. HiperSDR
selects it with `--with-host-tcd-tx`. See `tools/tests/HOSTTCD_TX.md` in the
parent repository for configuration, completion records and stop/drain handling.

## Validation

From the LimeSDR_GW repository root, run the project interpreter with:

```sh
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH=deps/litex:deps/migen:deps/litepcie:deps/litescope:. \
/usr/bin/python3.12 -m unittest discover -s tools/tests -p 'test_host_tcd_tx.py' -v
```

The GHDL testbench covers 32/1024 samples, IQ16/IQ12, channel mapping, unselected
channels, asynchronous clocks, stalls, reset, and slot reuse. Migen tests cover
metadata crossing, slot exhaustion, release and invalid mappings. A separate
check exercises GHDL VHDL-to-Verilog synthesis conversion.

Vivado 2022.2 out-of-context synthesis on `xcau15p-ffvb676-2-i` infers 32 RAMB18
primitives for the default sample RAM. This confirms RAM inference, not timing
closure or board-level operation.
