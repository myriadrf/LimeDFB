from migen import *

from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.axi import AXIStreamInterface
from litex.soc.interconnect.stream import Endpoint


def swap_iq(x):
    i1 = x[0:16]
    q1 = x[16:32]
    q1_neg = -q1

    return Cat(i1, q1_neg)


class AFE79xxTXFormatter(LiteXModule):
    def __init__(
        self,
        afe_sys_cd="fpga_1pps",
        afe_sys_2x_cd="fpga_1pps_2x",
    ):

        self.sink   = AXIStreamInterface(128, clock_domain=afe_sys_2x_cd)
        self.source = AXIStreamInterface(256, clock_domain=afe_sys_cd)

        self.tx_en     = Signal()
        self.tx_swap_iq = Signal(4)

        tx_conv = stream.Converter(nbits_from=128, nbits_to=256)
        tx_conv = ClockDomainsRenamer(afe_sys_2x_cd)(tx_conv)
        self.tx_conv = tx_conv


        # Omit parts of Axi interface we don't use + data, because we handle that seperately
        # AFE bindings do not correspond to ABCD channels, channels need to be muxed to fit
        # IQ mux Logic: Mux(condition, swapped_data, normal_data)
        self.comb += [
            # -----------------------------------------------------------------
            # Channel A -> AFE CH 4 (Bits 96-128) | Controlled by tx_swap_iq[0]
            # -----------------------------------------------------------------
            tx_conv.sink.data[96:128].eq(Mux(self.tx_swap_iq[0],swap_iq(self.sink.data[0:32]),self.sink.data[0:32])),
            # -----------------------------------------------------------------
            # Channel B -> AFE CH 3 (Bits 64-96) | Controlled by tx_swap_iq[1]
            # -----------------------------------------------------------------
            tx_conv.sink.data[64:96].eq(Mux(self.tx_swap_iq[1],swap_iq(self.sink.data[32:64]),self.sink.data[32:64])),
            # -----------------------------------------------------------------
            # Channel C -> AFE CH 1 (Bits 0-32) | Controlled by tx_swap_iq[2]
            # -----------------------------------------------------------------
            tx_conv.sink.data[0:32].eq(Mux(self.tx_swap_iq[2],swap_iq(self.sink.data[64:96]),self.sink.data[64:96])),
            # -----------------------------------------------------------------
            # Channel D -> AFE CH 2 (Bits 32-64) | Controlled by tx_swap_iq[3]
            # -----------------------------------------------------------------
            tx_conv.sink.data[32:64].eq(Mux(self.tx_swap_iq[3],swap_iq(self.sink.data[96:128]),self.sink.data[96:128])),
        ]


        self.comb += [
            self.tx_conv.sink.valid.eq(self.sink.valid),
            self.sink.ready.eq(tx_conv.sink.ready),
        ]


        self.tx_interleaved = Endpoint([("data", 256)])
        # self.tx_conv.source.connect(self.tx_interleaved,omit={"data"})
        self.comb += [
            self.tx_interleaved.valid.eq(self.tx_conv.source.valid),
            self.tx_conv.source.ready.eq(self.tx_interleaved.ready),
        ]

        # self.tx_conv.source.data[0:128] holds AI0, AQ0, BI0 ...
        # self.tx_conv.source.data[128:256] holds AI1, AQ1, BI1 ...
        # self.tx_interleaved.data should hold AI0, AI1, AQ0, AQ1, BI0, BI1 ...
        for j in range(4 * 2):
            # lower 16 bits from data_s0
            self.comb += self.tx_interleaved.data[32*j:32*j+16].eq(self.tx_conv.source.data[16*j:16*j+16])
            # upper 16 bits from data_s1
            self.comb += self.tx_interleaved.data[32*j+16:32*j+32].eq(self.tx_conv.source.data[16*j+128:16*j+16+128])

        self.tx_cdc = stream.ClockDomainCrossing(
            layout         =[("data", 256)],
            cd_from        =afe_sys_2x_cd,
            cd_to          =afe_sys_cd,
            buffered       =True,
            depth          =32
        )

        self.comb += [
            self.tx_interleaved.connect(self.tx_cdc.sink),

            self.source.data.eq(self.tx_cdc.source.data),
            self.source.valid.eq(self.tx_cdc.source.valid),

            # If in reset, assert ready to 'clear out' everything
            self.tx_cdc.source.ready.eq(self.source.ready | ~self.tx_en)
        ]