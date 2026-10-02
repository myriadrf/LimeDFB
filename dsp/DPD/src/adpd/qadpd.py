
from gateware.common import *

class QADPD(LiteXModule):
    def __init__(self, platform,
                 n=4, m=3, mul_n=18,
                 clk_domain="sys"):
        # QADPD data interface
        self.xpi = Signal(14)
        self.xpq = Signal(14)

        self.ypi = Signal(18)
        self.ypq = Signal(18)

        # SPI/control interface
        self.sclk = Signal()
        self.spi_ctrl = Signal(16)
        self.spi_data = Signal(16)

        # Active-low resets
        self.reset_n = Signal(reset=1)
        self.reset_mem_n = Signal(reset=1)

        self.qadpd_inst = Instance("QADPD",
            # Generics
            p_n=n,
            p_m=m,
            p_mul_n=mul_n,

            # Clocks / resets
            i_clk=ClockSignal(clk_domain),
            i_sclk=self.sclk,
            i_reset_n=self.reset_n,
            i_reset_mem_n=self.reset_mem_n,

            # Input samples
            i_xpi=self.xpi,
            i_xpq=self.xpq,

            # Output samples
            o_ypi=self.ypi,
            o_ypq=self.ypq,

            # SPI/config inputs
            i_spi_ctrl=self.spi_ctrl,
            i_spi_data=self.spi_data,
        )

        self.qadpd_inst_conv = add_vhd2v_converter(platform,
                                                        instance=self.qadpd_inst,
                                                        files=[
                                                            "gateware/LimeDFB/dsp/DPD/src/adpd/QADPD.vhd",
                                                            "gateware/LimeDFB/dsp/DPD/src/adpd/adder.vhd",],
                                                        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.qadpd_inst)