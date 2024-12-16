from litex.soc.interconnect.csr import CSRStorage
from litex.soc.interconnect.csr import CSRStatus
from litex.gen import *

class singl_clk_with_ref_test(LiteXModule):
    def __init__(self, platform, test_clock_domain, ref_clock_domain):
        self.test_en = CSRStorage(size=1, reset=0,
                                  description= "1 - enable test, 0 - disable test")
        self.test_cnt = CSRStatus(size=23,
                                  description= "Number of cycles counted during test")
        self.test_complete = CSRStatus(size=1,
                                       description= "1 - test complete, 0 - test not complete")

        platform.add_source("./gateware/LimeDFB/self_test/singl_clk_with_ref_test.vhd")

        self.RESET_N = Signal()

        # Create params
        self.param_ios = dict()

        # Assign generics
        self.param_ios.update()

        # Assign ports
        self.param_ios.update(
            i_refclk = ClockSignal(ref_clock_domain),
            i_clk0 = ClockSignal(test_clock_domain),
            i_reset_n = self.RESET_N,
            i_test_en = self.test_en.storage,
            o_test_cnt0 = self.test_cnt.status,
            o_test_complete = self.test_complete.status
        )

        # Create instance and assign params
        self.specials += Instance("singl_clk_with_ref_test", **self.param_ios)