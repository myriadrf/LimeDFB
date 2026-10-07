from litex.gen import LiteXModule

from gateware.LimeDFB.dsp.decimate_4ch.decimate4ch import Decimate4ch


class AFE79xxRX(LiteXModule):
    def __init__(self, platform, clk_domain="fpga_1pps_2x"):
        self.decimate = Decimate4ch(platform, clk_domain=clk_domain, num_stages=3)

        self.sink   = self.decimate.sink
        self.source = self.decimate.source
        self.enable = self.decimate.aresetn
