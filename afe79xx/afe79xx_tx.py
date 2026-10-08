from migen import *

from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.axi import AXIStreamInterface


class AFE79xxTX(LiteXModule):
    def __init__(
        self,
        platform,
        sys_clk_freq=300e6,
        afe_sys_2x_cd="fpga_1pps_2x",
        afe_dsp_cd="fpga_1pps_dsp",
        with_dpd=False,
    ):

        self.sink = AXIStreamInterface(128, clock_domain=afe_dsp_cd if with_dpd else afe_sys_2x_cd)
        self.source = AXIStreamInterface(128, clock_domain=afe_sys_2x_cd)

        self.tx_en = Signal()

        from gateware.LimeDFB.dsp.interpolate_4ch.interpolate_4ch import Interpolate4ch
        self.interpolate = Interpolate4ch(platform, clk_domain=afe_sys_2x_cd, num_stages=3)

        interpolate_source = self.sink
        if with_dpd:
            from gateware.LimeDFB.dsp.tx_dsp_4ch.tx_dsp_4ch import TxDsp4Ch
            self.tx_dsp = tx_dsp = TxDsp4Ch(platform, sys_clk_freq=sys_clk_freq, clk_domain=afe_dsp_cd)

            self.comb += [self.tx_dsp.reset_n.eq(~ResetSignal(afe_dsp_cd)),
                        ]

            # sink -> tx_dsp
            self.comb += [
                self.tx_dsp.sink.data.eq(self.sink.data),
                self.tx_dsp.sink.valid.eq(self.sink.valid),
                self.sink.ready.eq(self.tx_dsp.sink.ready),
            ]

            self.dsp_cdc = stream.ClockDomainCrossing(
                layout         =[("data", 128)],
                cd_from        =afe_dsp_cd,
                cd_to          =afe_sys_2x_cd,
                buffered       =True,
                depth          =32
            )

            # tx_dsp -> dsp_cdc
            self.comb += [
                self.dsp_cdc.sink.data.eq(self.tx_dsp.source.data),
                self.dsp_cdc.sink.valid.eq(self.tx_dsp.source.valid),
                self.tx_dsp.source.ready.eq(self.dsp_cdc.sink.ready),
            ]
            interpolate_source = self.dsp_cdc.source

        self.comb += [
            self.interpolate.aresetn.eq(self.tx_en),
            self.interpolate.sink.data.eq(interpolate_source.data),
            self.interpolate.sink.valid.eq(interpolate_source.valid),
            interpolate_source.ready.eq(self.interpolate.sink.ready),
        ]

        tx_a_data = self.interpolate.source.data[0:32]

        if with_dpd:
            # ------------------------------------------------------------
            # QADPD on TX Channel A only, after interpolate
            # ------------------------------------------------------------
            from gateware.LimeDFB.dsp.DPD.src.adpd.qadpd import QADPD
            self.submodules.qadpd_a = QADPD(
                platform,
                n=4,
                m=2,
                mul_n=18,
                clk_domain=afe_sys_2x_cd,
            )

            # Channel A from interpolate:
            # bits [0:16]  = A I
            # bits [16:32] = A Q
            #
            # QADPD input is 14-bit, while interpolate output is 16-bit.
            # Use [2:16] to keep the signed MSBs and drop 2 LSBs.
            self.comb += [
                self.qadpd_a.reset_n.eq(self.tx_en),
                self.qadpd_a.reset_mem_n.eq(self.tx_en),

                # If QADPD config SPI is unused for now, tie these off.
                self.qadpd_a.sclk.eq(self.tx_dsp.sclk),
                self.qadpd_a.spi_ctrl.eq(self.tx_dsp.adpd_ctrl_reg),
                self.qadpd_a.spi_data.eq(self.tx_dsp.adpd_data_reg),

                self.qadpd_a.xpi.eq(self.interpolate.source.data[2:16]),
                self.qadpd_a.xpq.eq(self.interpolate.source.data[18:32]),
            ]

            # QADPD output is 18-bit. Convert back to 16-bit for TX stream.
            # Use [2:18] to keep signed MSBs and drop 2 LSBs.
            tx_a_data = Signal(32)
            self.comb += [
                tx_a_data[0:16].eq(self.qadpd_a.ypi[2:18]),
                tx_a_data[16:32].eq(self.qadpd_a.ypq[2:18]),
            ]

        # Signals used by DPD capture in top module
        self.tx_a_before_dpd = self.interpolate.source.data[0:32]
        self.tx_a_after_dpd = tx_a_data

        self.comb += [
            self.source.data[0:32].eq(tx_a_data),
            self.source.data[32:128].eq(self.interpolate.source.data[32:128]),
            self.source.valid.eq(self.interpolate.source.valid),
            self.interpolate.source.ready.eq(self.source.ready),
        ]