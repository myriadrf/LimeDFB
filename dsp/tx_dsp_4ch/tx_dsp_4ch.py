#!/usr/bin/env python3
from litex.soc.interconnect.stream import Endpoint, BufferizeEndpoints, DIR_SOURCE, DIR_SINK
from types import SimpleNamespace
from migen import *
from litex.soc.interconnect.axi import *
from litex.soc.interconnect.csr import *


from litescope import LiteScopeAnalyzer
from migen.genlib.cdc import MultiReg

class TxDsp4Ch(LiteXModule):
    def __init__(self, platform, clk_domain="sys"):
        self.sink = AXIStreamInterface(128, clock_domain=clk_domain)
        self.source = AXIStreamInterface(128, clock_domain=clk_domain)


        # A depth-2 SyncFIFO acts as a perfect register slice for streams
        self.fifo = stream.SyncFIFO([("data", 128)], depth=16, buffered=True)
        self.fifo = ClockDomainsRenamer(clk_domain)(self.fifo)

        self.comb += [
            # Sink to FIFO
            self.sink.ready.eq(self.fifo.sink.ready),
            self.fifo.sink.valid.eq(self.sink.valid),
            self.fifo.sink.data.eq(self.sink.data),

            # FIFO to Source
            self.source.valid.eq(self.fifo.source.valid),
            self.source.data.eq(self.fifo.source.data),
            self.fifo.source.ready.eq(self.source.ready),
        ]


