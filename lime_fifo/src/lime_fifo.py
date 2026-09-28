from migen import (
    log2_int, Signal, Module, ClockDomain, ClockSignal, ResetSignal,
    ClockDomainsRenamer, Memory, If, Cat, ResetInserter
)
from migen.genlib.cdc import GrayCounter, MultiReg
from migen.genlib.resetsync import AsyncResetSynchronizer
from migen.genlib.fifo import _FIFOInterface
from litex.soc.interconnect.stream import _FIFOWrapper


class LimeAsyncFIFO(Module, _FIFOInterface):
    """Asynchronous FIFO (first in, first out) with dual-domain occupancy reporting.

    Read and write interfaces are accessed from different clock domains,
    named `read` and `write`. Use `ClockDomainsRenamer` to rename to
    other names.

    {interface}
    """
    __doc__ = __doc__.format(interface=_FIFOInterface.__doc__)

    def __init__(self, width, depth):
        _FIFOInterface.__init__(self, width, depth)

        ###

        depth_bits = log2_int(depth, True)
        assert 2**depth_bits == depth, "FIFO depth must be a power of 2"

        self.reset = Signal()

        # Dedicated reset synchronizer clock domains for glitch-free cross-domain
        # reset assertion (asynchronous) and synchronous de-assertion.
        cd_write_rst = ClockDomain()
        cd_read_rst = ClockDomain()
        self.clock_domains += cd_write_rst, cd_read_rst
        self.comb += [
            cd_write_rst.clk.eq(ClockSignal("write")),
            cd_read_rst.clk.eq(ClockSignal("read")),
        ]
        self.specials += [
            AsyncResetSynchronizer(cd_write_rst, self.reset),
            AsyncResetSynchronizer(cd_read_rst, self.reset),
        ]
        self.reset_w = reset_w = cd_write_rst.rst
        self.reset_r = reset_r = cd_read_rst.rst

        produce = ClockDomainsRenamer("write")(ResetInserter()(GrayCounter(depth_bits + 1)))
        consume = ClockDomainsRenamer("read")(ResetInserter()(GrayCounter(depth_bits + 1)))
        self.submodules += produce, consume
        self.comb += [
            produce.reset.eq(reset_w),
            consume.reset.eq(reset_r),
            produce.ce.eq(self.writable & self.we),
            consume.ce.eq(self.readable & self.re)
        ]

        produce_rdomain = Signal(depth_bits + 1)
        produce.q.attr.add("no_retiming")
        self.specials += MultiReg(produce.q, produce_rdomain, "read")

        consume_wdomain = Signal(depth_bits + 1)
        consume.q.attr.add("no_retiming")
        self.specials += MultiReg(consume.q, consume_wdomain, "write")

        raw_writable = Signal()
        if depth_bits == 1:
            self.comb += raw_writable.eq((produce.q[-1] == consume_wdomain[-1])
                                         | (produce.q[-2] == consume_wdomain[-2]))
        else:
            self.comb += raw_writable.eq((produce.q[-1] == consume_wdomain[-1])
                                         | (produce.q[-2] == consume_wdomain[-2])
                                         | (produce.q[:-2] != consume_wdomain[:-2]))
        self.comb += self.writable.eq(~reset_w & raw_writable)
        self.comb += self.readable.eq(~reset_r & (consume.q != produce_rdomain))

        storage = Memory(self.width, depth)
        self.specials += storage
        wrport = storage.get_port(write_capable=True, clock_domain="write")
        self.specials += wrport
        self.comb += [
            wrport.adr.eq(produce.q_binary[:-1]),
            wrport.dat_w.eq(self.din),
            wrport.we.eq(produce.ce)
        ]
        rdport = storage.get_port(clock_domain="read")
        self.specials += rdport
        self.comb += [
            rdport.adr.eq(consume.q_next_binary[:-1]),
            self.dout.eq(rdport.dat_r)
        ]

        # Occupancy level signals for write and read clock domains
        self.write_level = Signal(depth_bits + 1)
        self.read_level = Signal(depth_bits + 1)

        self.consume_wdomain_bin = Signal(depth_bits + 1)
        # Convert synced Gray signal to binary
        self.comb += self.consume_wdomain_bin.eq(self.gray_to_binary(consume_wdomain))
        # Calculate write-domain occupancy (held to 0 during reset)
        self.comb += If(reset_w,
            self.write_level.eq(0)
        ).Else(
            self.write_level.eq(produce.q_binary - self.consume_wdomain_bin)
        )

        self.produce_rdomain_bin = Signal(depth_bits + 1)
        # Convert synced Gray signal to binary
        self.comb += self.produce_rdomain_bin.eq(self.gray_to_binary(produce_rdomain))
        # Calculate read-domain occupancy (held to 0 during reset)
        self.comb += If(reset_r,
            self.read_level.eq(0)
        ).Else(
            self.read_level.eq(self.produce_rdomain_bin - consume.q_binary)
        )

    @staticmethod
    def gray_to_binary(gray_signal):
        n = len(gray_signal)
        bits = []
        for i in reversed(range(n)):
            if not bits:
                bits.append(gray_signal[i])
            else:
                bits.append(bits[-1] ^ gray_signal[i])
        return Cat(*reversed(bits))


class LimeAsyncFIFOBuffered(Module, _FIFOInterface):
    """Pipelined output LimeAsyncFIFO with read-level compensation.

    Improves timing when it breaks due to sluggish clock-to-output
    delay in e.g. FPGA block RAMs. Increases latency by one cycle.
    Accurately compensates read_level to account for the buffered output word.
    """
    def __init__(self, width, depth):
        _FIFOInterface.__init__(self, width, depth)
        self.submodules.fifo = fifo = LimeAsyncFIFO(width, depth)

        self.reset = fifo.reset
        self.reset_w = fifo.reset_w
        self.reset_r = fifo.reset_r
        self.write_level = fifo.write_level

        self.writable = fifo.writable
        self.din = fifo.din
        self.we = fifo.we

        depth_bits = log2_int(depth, True)
        self.read_level = Signal(depth_bits + 1)
        self.comb += If(fifo.reset_r,
            self.read_level.eq(0)
        ).Else(
            self.read_level.eq(fifo.read_level + self.readable)
        )

        self.sync.read += \
            If(fifo.reset_r,
               self.readable.eq(0)
            ).Elif(self.re | ~self.readable,
                   self.dout.eq(fifo.dout),
                   self.readable.eq(fifo.readable)
            )
        self.comb += fifo.re.eq(self.re | ~self.readable)


class LimeStreamAsyncFIFO(_FIFOWrapper):
    """LiteX Stream Endpoint wrapper for LimeAsyncFIFOBuffered / LimeAsyncFIFO.

    Provides LiteX stream endpoints (`sink` and `source`) across clock domains
    with dual-domain occupancy tracking (`level_w` in the write domain and
    `level_r` in the read domain) and unified reset control.
    """
    def __init__(self, layout, depth=None, buffered=True):
        depth = 4 if depth is None else depth
        assert depth >= 4
        _FIFOWrapper.__init__(self,
            fifo_class = LimeAsyncFIFOBuffered if buffered else LimeAsyncFIFO,
            layout     = layout,
            depth      = depth
        )
        self.depth   = self.fifo.depth
        self.reset   = self.fifo.reset
        self.reset_w = self.fifo.reset_w
        self.reset_r = self.fifo.reset_r
        self.level_w = self.fifo.write_level
        self.level_r = self.fifo.read_level


# Aliases for backwards compatibility
AsyncFIFO = LimeAsyncFIFO
AsyncFIFOBuffered = LimeAsyncFIFOBuffered
StreamAsyncFIFO = LimeStreamAsyncFIFO
