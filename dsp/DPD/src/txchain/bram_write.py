from gateware.common import *


class BRAMWrite(LiteXModule):
    def __init__(self, platform,
                 data_width=128,
                 addr_width=15,
                 clk_domain="sys"):

        # Control interface
        self.reset_n     = Signal(reset=1)
        self.start_write = Signal()
        self.full        = Signal()

        # Input data ports
        self.xpi = Signal(16)
        self.xpq = Signal(16)
        self.ypi = Signal(16)
        self.ypq = Signal(16)
        self.xi  = Signal(16)
        self.xq  = Signal(16)

        # Memory control ports
        self.web   = Signal()
        self.enb   = Signal()
        self.addrb = Signal(addr_width)
        self.doutb = Signal(data_width)

        self.bram_write_inst = Instance("bram_write",
            # Generics
            p_DATA_WIDTH=data_width,
            p_ADDR_WIDTH=addr_width,

            # Clocks / resets / control
            i_clk=ClockSignal(clk_domain),
            i_reset_n=self.reset_n,
            i_start_write=self.start_write,
            o_full=self.full,

            # Input samples
            i_xpi=self.xpi,
            i_xpq=self.xpq,
            i_ypi=self.ypi,
            i_ypq=self.ypq,
            i_xi=self.xi,
            i_xq=self.xq,

            # Memory control outputs
            o_web=self.web,
            o_enb=self.enb,
            o_addrb=self.addrb,
            o_doutb=self.doutb,
        )

        self.bram_write_inst_conv = add_vhd2v_converter(
            platform,
            instance=self.bram_write_inst,
            files=[
                "gateware/LimeDFB/dsp/DPD/src/txchain/bram_write.vhd",
            ],
        )

        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.bram_write_inst)