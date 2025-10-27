#!/usr/bin/env python3
from litex.soc.interconnect.stream import Endpoint
from migen import *
from litex.soc.interconnect.axi import *
from litex.soc.interconnect.csr import *


from litescope import LiteScopeAnalyzer
from migen.genlib.cdc import MultiReg


class NCO8lut(LiteXModule):
    def __init__(self, platform, m_clk_domain="sys", with_debug=False):


        # Add CSRs
        self.reg00  = CSRStorage(fields=[
            CSRField("nrst",size=1, offset=0, reset=1, description="Active low reset"),
            CSRField("en",  size=1, offset=1, reset=1, description="Active high enable"),
        ])

        self.reg01  = CSRStorage(fields=[
            CSRField("mode",        size=1, offset=0, reset=0, description="NCO mode: 0 when NCO, 1 when DC"),
            CSRField("fcw",         size=2, offset=1, reset=1, description="Frequency control word"),
            CSRField("swapiq",      size=1, offset=3, reset=0, description="Swap I and Q channels"),
            CSRField("ldi",         size=1, offset=4, reset=0, description="Load output registers when rising edge with di and dq"),
            CSRField("ldq",         size=1, offset=5, reset=0, description="Load output registers when rising edge with di and dq"),
            CSRField("fullscaleo",  size=1, offset=6, reset=1, description="Set to 1 if want full scale output. Set to 0 for -6dB (default)."),

        ])

        self.reg02  = CSRStorage(fields=[
            CSRField("diq",   size=16, offset=0, reset=0, description="Data to be loaded to output registers"),
        ])


        self.source = AXIStreamInterface(128, clock_domain=m_clk_domain)


        # Add sources
        platform.add_source("./gateware/LimeDFB/dsp/nco_8lut/src/bcla4b.vhd")
        platform.add_source("./gateware/LimeDFB/dsp/nco_8lut/src/nco_8lut.vhd")



        # Clock Domains.
        # --------------

        # create misc signals
        nrst        = Signal()
        en          = Signal()
        swapiq      = Signal()
        mode        = Signal()  # Frequency control word
        newnco      = Signal()
        ldi         = Signal()
        ldq         = Signal()
        diq         = Signal(16)
        fcw         = Signal(2)
        fullscaleo  = Signal()

        yi          = Signal(16)
        yq          = Signal(16)


        self.specials += MultiReg(self.reg00.fields.nrst,       nrst, m_clk_domain, 2, 0)
        self.specials += MultiReg(self.reg00.fields.en,         en, m_clk_domain, 2, 1)

        self.specials += MultiReg(self.reg01.fields.mode,       mode, m_clk_domain, 2, 0)
        self.specials += MultiReg(self.reg01.fields.fcw,        fcw, m_clk_domain, 2,1)
        self.specials += MultiReg(self.reg01.fields.swapiq,     swapiq, m_clk_domain, 2, 0)
        self.specials += MultiReg(self.reg01.fields.ldi,        ldi, m_clk_domain, 2, 0)
        self.specials += MultiReg(self.reg01.fields.ldq,        ldq, m_clk_domain, 2, 0)
        self.specials += MultiReg(self.reg01.fields.fullscaleo, fullscaleo, m_clk_domain, 2, 1)

        self.specials += MultiReg(self.reg02.fields.diq, diq, m_clk_domain, 2, 0)


        # Create params
        self.params_ios = dict()

        # Assign generics
        #self.params_ios.update(
        #)

        # Assign ports
        self.params_ios.update(
            i_clk        = ClockSignal(m_clk_domain),
            i_nrst       = nrst,
            i_en         = en,
            i_swapiq     = swapiq,
            i_mode       = mode,
            i_newnco     = newnco,
            i_ldi        = ldi,
            i_ldq        = ldq,
            i_diq        = diq,
            i_fcw        = fcw,
            i_fullscaleo = fullscaleo,
            o_yi         = yi,
            o_yq         = yq,

        )

        # Create instance and assign params
        self.specials += Instance("nco_8lut", **self.params_ios)


        self.comb += [
            newnco.eq(self.source.ready),
            self.source.valid.eq(nrst),
            # Lower data bits
            self.source.data[0:16].eq(yi),
            # Upper data bits
            self.source.data[16:32].eq(yq),

            self.source.data[32:].eq(0),
        ]

        # LiteScope example.
        # ------------------
        # Setup LiteScope Analyzer to capture some of the AXI-Lite MMAP signals.
        if with_debug:
            analyzer_signals = [
            ]

            self.analyzer = LiteScopeAnalyzer(analyzer_signals,
                depth        = 512,
                clock_domain = m_clk_domain,
                register     = True,
                csr_csv      = "nco8lut_analyzer.csv"
            )

