from migen import *

from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.axi import AXIStreamInterface


def negate_q(x):
    """
    Keep I unchanged and negate Q.

    Input/output format:
        [15:0]  = I
        [31:16] = Q
    """
    i = x[0:16]
    q = x[16:32]

    return Cat(i, -q)


def split_sample_times(src, sample_0, sample_1):
    """
    Split AFE-native 256-bit word into two 128-bit sample-time words.

    AFE input contains two consecutive sample times interleaved
    in 16-bit chunks:

        src[31:0]:
            [15:0]  -> sample_0[15:0]
            [31:16] -> sample_1[15:0]

        src[63:32]:
            [47:32] -> sample_0[31:16]
            [63:48] -> sample_1[31:16]

        ...

    Output:
        sample_0 = all channel data for time N
        sample_1 = all channel data for time N+1
    """
    logic = []

    for j in range(8):
        logic += [
            sample_0[16*j:16*j+16].eq(
                src[32*j:32*j+16]
            ),
            sample_1[16*j:16*j+16].eq(
                src[32*j+16:32*j+32]
            ),
        ]

    return logic


def apply_iq_swap(src, dst, swap_ctrl):
    """
    Apply IQ correction independently to each physical AFE channel.

    Physical AFE channel positions:
        index 0 -> AFE CH1
        index 1 -> AFE CH2
        index 2 -> AFE CH3
        index 3 -> AFE CH4

    Logical mapping:
        AFE CH4 -> A
        AFE CH3 -> B
        AFE CH1 -> C
        AFE CH2 -> D

    swap_ctrl:
        bit 0 -> logical A
        bit 1 -> logical B
        bit 2 -> logical C
        bit 3 -> logical D
    """

    # Physical channel index -> logical swap control bit.
    swap_map = [2, 3, 1, 0]

    logic = []

    for ch in range(4):
        lo = 32 * ch
        hi = 32 * (ch + 1)

        logic.append(
            dst[lo:hi].eq(
                Mux(
                    swap_ctrl[swap_map[ch]],
                    negate_q(src[lo:hi]),
                    src[lo:hi],
                )
            )
        )

    return logic


def remap_afe_channels(src, dst):
    """
    Convert physical AFE channel order into canonical logical ABCD order.

    Input:
        [31:0]    AFE CH1
        [63:32]   AFE CH2
        [95:64]   AFE CH3
        [127:96]  AFE CH4

    Output:
        [31:0]    logical A
        [63:32]   logical B
        [95:64]   logical C
        [127:96]  logical D

    Mapping:
        AFE CH4 -> A
        AFE CH3 -> B
        AFE CH1 -> C
        AFE CH2 -> D
    """
    return [
        dst[0:32].eq(src[96:128]),
        dst[32:64].eq(src[64:96]),
        dst[64:96].eq(src[0:32]),
        dst[96:128].eq(src[32:64]),
    ]


class AFE79xxRXFormatter(LiteXModule):
    """
    AFE79xx RX format adapter.

    Input:
        256-bit native AFE stream @ afe_sys_cd

    Output:
        128-bit canonical stream @ afe_data_2x_cd

    Canonical output format:
        [31:0]    Channel A
        [63:32]   Channel B
        [95:64]   Channel C
        [127:96]  Channel D

    Per-channel format:
        [15:0]  = I
        [31:16] = Q

    Pipeline:
        native AFE 256-bit
            -> split sample times
            -> IQ correction
            -> CDC
            -> 256-to-128 conversion
            -> AFE channel remap
            -> canonical ABCD 128-bit
    """

    def __init__(
        self,
        afe_data_cd,
        afe_data_2x_cd,
    ):
        # ---------------------------------------------------------------------
        # Interfaces
        # ---------------------------------------------------------------------

        self.sink = AXIStreamInterface(
            data_width=256,
            clock_domain=afe_data_cd,
        )

        self.source = AXIStreamInterface(
            data_width=128,
            clock_domain=afe_data_2x_cd,
        )

        self.enable = Signal(reset=1)

        # Logical channel control:
        # bit 0 -> A
        # bit 1 -> B
        # bit 2 -> C
        # bit 3 -> D
        self.swap_iq = Signal(4)

        # ---------------------------------------------------------------------
        # Split native AFE word into sample N / N+1
        # ---------------------------------------------------------------------

        sample_0_raw = Signal(128)
        sample_1_raw = Signal(128)

        self.comb += split_sample_times(
            self.sink.data,
            sample_0_raw,
            sample_1_raw,
        )

        # ---------------------------------------------------------------------
        # IQ correction
        # ---------------------------------------------------------------------

        sample_0 = Signal(128)
        sample_1 = Signal(128)

        self.comb += apply_iq_swap(
            sample_0_raw,
            sample_0,
            self.swap_iq,
        )

        self.comb += apply_iq_swap(
            sample_1_raw,
            sample_1,
            self.swap_iq,
        )

        # ---------------------------------------------------------------------
        # CDC:
        #
        #   256-bit @ afe_data_cd
        #       ->
        #   256-bit @ afe_data_2x_cd
        #
        # One FIFO word contains:
        #   [127:0]   sample N
        #   [255:128] sample N+1
        # ---------------------------------------------------------------------

        rx_cdc = stream.AsyncFIFO(
            [("data", 256)],
            depth=32,
            buffered=True,
        )

        rx_cdc = ClockDomainsRenamer({
            "write": afe_data_cd,
            "read":  afe_data_2x_cd,
        })(rx_cdc)

        self.rx_cdc = rx_cdc

        afe_sys_sync = getattr(self.sync, afe_data_cd)

        afe_sys_sync += [
            rx_cdc.sink.valid.eq(self.sink.valid),

            rx_cdc.sink.data[0:128].eq(
                sample_0
            ),

            rx_cdc.sink.data[128:256].eq(
                sample_1
            ),
        ]

        self.comb += [
            self.sink.ready.eq(rx_cdc.sink.ready),
        ]

        # ---------------------------------------------------------------------
        # 256 -> 128 conversion
        #
        # stream.Converter emits lower 128 bits first:
        #
        #   sample N
        #   sample N+1
        # ---------------------------------------------------------------------

        rx_conv = ResetInserter()(
            ClockDomainsRenamer(afe_data_2x_cd)(
                stream.Converter(
                    nbits_from=256,
                    nbits_to=128,
                )
            )
        )

        rx_conv = stream.BufferizeEndpoints({"source": stream.DIR_SOURCE})(rx_conv)
        self.rx_conv = rx_conv

        self.comb += [
            rx_conv.reset.eq(~self.enable),

            rx_conv.sink.data.eq(
                rx_cdc.source.data
            ),

            rx_conv.sink.valid.eq(
                rx_cdc.source.valid
            ),

            rx_cdc.source.ready.eq(
                rx_conv.sink.ready
            ),
        ]

        # ---------------------------------------------------------------------
        # Physical AFE channel order -> logical ABCD
        # ---------------------------------------------------------------------

        formatted_data = Signal(128)

        self.comb += remap_afe_channels(
            rx_conv.source.data,
            formatted_data,
        )

        # ---------------------------------------------------------------------
        # Output
        # ---------------------------------------------------------------------

        self.comb += [
            self.source.data.eq(
                formatted_data
            ),

            self.source.valid.eq(
                rx_conv.source.valid
            ),

            rx_conv.source.ready.eq(
                self.source.ready
            ),
        ]