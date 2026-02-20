"""Resampler gateware module.

This module implements a parameterizable I/Q resampling chain using vendor-agnostic
half-band filters (HB1 for interpolation, HB2D for decimation). It exposes a
LiteX stream Endpoint input/output (I and Q packed) as well as separated I/Q
endpoints internally, and allows selecting the output tap via a CSR mux.

Behavior is preserved with respect to the original implementation; only
documentation and readability have been improved.
"""
from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.csr import CSRStorage
from migen import Signal, Instance
from migen.fhdl.structure import Constant, ClockSignal, ResetSignal, Case, Replicate, If, Array
from migen import Cat
from migen.genlib.cdc import MultiReg

# Width of the stage-select CSR and synchronizer
STAGE_SEL_BITS = 4


class Resampler(LiteXModule):
    """I/Q Resampler composed of HB1 (interpolation) or HB2D (decimation) stages.

    Args:
        soc: SoC/platform object, used to add required VHDL sources once.
        sample_width: Bit-width of I and Q samples at the external interface.
        stages: Number of half-band stages to cascade (max 9).
        direction: 'up' for interpolation, 'down' for decimation.
        clock_domain: Clock domain name for the filter chain and CSR sync.
    """
    def __init__(self,
                 soc,
                 sample_width=16,  # Width of input/output samples
                 stages=1,  # Resampling stages
                 direction=None,  # Resampling direction (upsampling or downsampling)
                 clock_domain="sys"
                 ):

        assert direction in ["up", "down"]
        assert stages <= 9 #The largest resampling filter is 9 stages, limited by hb1/hb2 clkdiv

        self.sink = stream.Endpoint([("data", sample_width*2)])
        self.source = stream.Endpoint([("data", sample_width*2)])

        self.sink_I = stream.Endpoint([("data", sample_width)])
        self.sink_Q = stream.Endpoint([("data", sample_width)])
        self.source_I = stream.Endpoint([("data", sample_width)])
        self.source_Q = stream.Endpoint([("data", sample_width)])
        filter_width = 18
        self.adjusted_sink_I = stream.Endpoint([("data", filter_width)])
        self.adjusted_sink_Q = stream.Endpoint([("data", filter_width)])
        self.adjusted_source_I = stream.Endpoint([("data", filter_width)])
        self.adjusted_source_Q = stream.Endpoint([("data", filter_width)])

        self.reset = Signal(reset=0)
        self.reset_internal = Signal()
        # HB1/HB2D modules have a reset port that looks like an active high reset
        # but is actually an active low reset. So we need to invert the reset signal.
        self.comb += self.reset_internal.eq(~(self.reset | ResetSignal(clock_domain)))

        # Handle sinks and sources

        # Dynamically adjust data width
        self._connect_with_adjustment(self.sink_I, self.adjusted_sink_I, sample_width, filter_width)
        self._connect_with_adjustment(self.sink_Q, self.adjusted_sink_Q, sample_width, filter_width)
        self._connect_with_adjustment(self.adjusted_source_I, self.source_I, filter_width, sample_width)
        self._connect_with_adjustment(self.adjusted_source_Q, self.source_Q, filter_width, sample_width)
        # Split/Merge sinks and sources
        self.comb += [
            # SINK
            self.sink_I.data.eq(self.sink.data[0:sample_width]),
            self.sink_I.valid.eq(self.sink.valid),
            self.sink.ready.eq(self.sink_I.ready),

            self.sink_Q.data.eq(self.sink.data[sample_width:sample_width*2]),
            self.sink_Q.valid.eq(self.sink.valid),
            #No separate ready for Q sink, it's always ready when I is ready

            # SOURCE
            self.source.data.eq(Cat(self.source_I.data, self.source_Q.data)),
            self.source.valid.eq(self.source_I.valid),
            self.source_I.ready.eq(self.source.ready),
            self.source_Q.ready.eq(self.source.ready),
        ]

        # Parameters
        self.sample_width = sample_width
        cases = {}

        out_mux_sync = Signal(STAGE_SEL_BITS)
        out_mux_sync_reg = Signal(STAGE_SEL_BITS)
        self.out_mux = CSRStorage(size=STAGE_SEL_BITS, reset=0,
                                  description="Select which resampling stage should be used as output")
        self.specials += MultiReg(self.out_mux.storage,      out_mux_sync,            odomain=clock_domain)
        out_mux_changed = Signal()
        domain = getattr(self.sync, clock_domain)
        domain += [
            out_mux_sync_reg.eq(out_mux_sync),
            If(out_mux_sync != out_mux_sync_reg, out_mux_changed.eq(1)).Else(out_mux_changed.eq(0))
        ]

        # # #
        # ------------------------------------------------------------------
        # Avoid adding sources multiple times.
        # Check if the attribute is present, if not, add it and add sources.
        if not hasattr(soc, "Resampler_present"):
            base = "gateware/LimeDFB/Resampler/filters/src/"
            soc.platform.add_source(base + "clkdiv.vhd")
            soc.platform.add_source(base + "hb1.vhd")
            soc.platform.add_source(base + "hb1e.vhd")
            soc.platform.add_source(base + "hb1o.vhd")
            soc.platform.add_source(base + "csec.vhd")
            soc.platform.add_source(base + "csdm26x4.vhd")
            soc.platform.add_source(base + "ta26.vhd")
            soc.platform.add_source(base + "tt.vhd")
            soc.platform.add_source(base + "hb2d.vhd")
            soc.platform.add_source(base + "hb2e.vhd")
            soc.platform.add_source(base + "hb2o.vhd")
            soc.platform.add_source(base + "add26.vhd")

            # TODO: Add verilog converter flow that would work with shared vhdl sources
            #       Possibly a source library and some checking should be used to ensure
            #       that sources get added directly if vhdl supported and converted and used as libraries
            #       otherwise.
            #       TL;DR - add support for platforms that don't support vhdl sources.
            soc.Resampler_present = True
        # ------------------------------------------------------------------
        # Bypass if zero stages
        if stages == 0:
            self.comb += self.sink.connect(self.source)
            # self.comb += self.sink_I.connect(self.source_I)
            # self.comb += self.sink_Q.connect(self.source_Q)
        else:
            self.filter_sinks_I = {}
            self.filter_sinks_Q = {}
            self.filter_sources_I = {}
            self.filter_sources_Q = {}
            self.up_n_valuesLUT = Array(range(stages))
            self.up_n_values = {}
    # ----------------- Cycle start -------------
            for i in range(stages):
                # Pre-create endpoints
                self.filter_sinks_I[i] = stream.Endpoint([("data", filter_width)])
                self.filter_sinks_Q[i] = stream.Endpoint([("data", filter_width)])
                self.filter_sources_I[i] = stream.Endpoint([("data", filter_width)])
                self.filter_sources_Q[i] = stream.Endpoint([("data", filter_width)])
                # Interpolation n values need to be dynamic, because the output tap has to have
                # n value of 0
                self.up_n_valuesLUT[i] = Signal(8)
                self.up_n_valuesLUT[i] = Constant(2 ** (stages - 1 - i) - 1, 8)
                self.up_n_values[i] = Signal(8)


            for i in range(stages):
    # ----------------- DOWN DIRECTION FILTERS -------------------------------------
                if direction == "down":
                    # ----------------- CONNECT FILTERS TOGETHER -------------------------
                    if i == 0:
                        cases[0] = [
                           self.adjusted_sink_I.connect(self.adjusted_source_I),
                           self.adjusted_sink_Q.connect(self.adjusted_source_Q),
                        ]
                        self.comb += [
                            self.adjusted_sink_I.connect(self.filter_sinks_I[0],omit={"valid"}),
                            self.adjusted_sink_Q.connect(self.filter_sinks_Q[0],omit={"valid"}),
                        ]
                    else:
                        self.comb += [
                            self.filter_sources_I[i - 1].connect(self.filter_sinks_I[i],omit={"valid", "ready"}),
                            self.filter_sources_Q[i - 1].connect(self.filter_sinks_Q[i],omit={"valid", "ready"}),
                        ]
                    # ----------------- CREATE CASES FOR MUXING -------------------------
                    # Create cases for muxing
                    cases[i+1] = [
                        self.filter_sources_I[i].connect(self.adjusted_source_I),
                        self.filter_sources_Q[i].connect(self.adjusted_source_Q),
                    ]

                    # Decimation filter
                    filter_yen   = Signal()
                    filter_sleep = Signal()
                    filter_oen   = Signal()
                    filter_inst = Instance("hb2d",
                                      i_xi1=self.filter_sinks_I[i].data,
                                      i_xq1=self.filter_sinks_Q[i].data,
                                      i_n=Constant((2 ** i) - 1, 8),
                                      i_sleep=filter_sleep,
                                      i_clk=ClockSignal(clock_domain),
                                      i_reset=self.reset_internal,
                                      o_yen=filter_yen,
                                      o_oen=filter_oen,
                                      o_yi1=self.filter_sources_I[i].data,
                                      o_yq1=self.filter_sources_Q[i].data,
                                      )
                    self.comb += [
                        ## I endpoint used as main for control signal
                        # use yen to control output valid
                        self.filter_sources_I[i].valid.eq(filter_yen),
                        self.filter_sinks_I[i].ready.eq(filter_oen),
                        self.filter_sources_Q[i].valid.eq(filter_yen),
                        self.filter_sinks_Q[i].ready.eq(filter_oen),
                        # sleep all stages if either endpoint can't do exchange
                        filter_sleep.eq((~(self.source.ready & self.sink.valid)) | out_mux_changed),
                    ]
                    # self.add_module(f"filter{i}",filter)
                    # Equivalent to add_module, done this way to create dynamically named instances
                    # add_module wants to work on modules, not instances
                    setattr(self, f"filter_{i}", filter_inst)

                # -----------------  UP  DIRECTION FILTERS -------------------------------------
                elif direction == "up":
                    # ----------------- CONNECT FILTERS TOGETHER -------------------------
                    if i == 0:
                        cases[0] = [
                           self.adjusted_sink_I.connect(self.adjusted_source_I),
                           self.adjusted_sink_Q.connect(self.adjusted_source_Q),
                        ]
                        # Make sure all filters are always connected to proper sinks
                        # Using .connect to maintain code consistency
                        self.comb += [
                            self.adjusted_sink_I.connect(self.filter_sinks_I[0],omit={"valid"}),
                            self.adjusted_sink_Q.connect(self.filter_sinks_Q[0],omit={"valid"}),
                        ]
                    else:
                        self.comb += [
                            self.filter_sources_I[i - 1].connect(self.filter_sinks_I[i],omit={"valid", "ready"}),
                            self.filter_sources_Q[i - 1].connect(self.filter_sinks_Q[i],omit={"valid", "ready"}),
                        ]

                    # ----------------- CREATE CASES FOR MUXING -------------------------
                    # Create cases for muxing
                    cases[i+1] = [
                        self.filter_sources_I[i].connect(self.adjusted_source_I),
                        self.filter_sources_Q[i].connect(self.adjusted_source_Q),
                    ]

                    filter_xen = Signal()
                    filter_sleep = Signal()
                    filter_oen = Signal()
                    filter_unused = Signal()


                    lut_index = Signal(max=stages*2)
                    domain = getattr(self.sync, clock_domain)
                    domain += [
                        lut_index.eq((stages + i - out_mux_sync)),
                        If(lut_index >= stages,[
                            filter_unused.eq(1),
                            self.up_n_values[i].eq(0),
                        ]).Else([
                            filter_unused.eq(0),
                            self.up_n_values[i].eq(self.up_n_valuesLUT[lut_index]),
                        ]),
                    ]

                    filter_inst = Instance("hb1",
                                      i_xi1=self.filter_sinks_I[i].data,
                                      i_xq1=self.filter_sinks_Q[i].data,
                                      # i_n=self.up_n_valuesLUT[stages-out_mux_sync],
                                      i_n=self.up_n_values[i],
                                      i_sleep=filter_sleep,
                                      i_delay=Constant(0),
                                      i_clk=ClockSignal(clock_domain),
                                      i_reset=self.reset_internal,
                                      i_bypass=Constant(0),
                                      o_xen=filter_xen,
                                      o_oen=filter_oen,
                                      o_yi1=self.filter_sources_I[i].data,
                                      o_yq1=self.filter_sources_Q[i].data
                                      )
                    self.comb += [
                        ## I endpoint used as main for control signal
                        # sleep all stages if either endpoint can't do exchange
                        filter_sleep.eq((~(self.source.ready & self.sink.valid)) | out_mux_changed | filter_unused),
                        # Use xen to control input ready
                        self.filter_sinks_I[i].ready.eq(filter_xen),
                        self.filter_sources_I[i].valid.eq(filter_oen),
                        self.filter_sinks_Q[i].ready.eq(filter_xen),
                        self.filter_sources_Q[i].valid.eq(filter_oen),
                    ]
                    # Equivalent to add_module, done this way to create dynamically named instances
                    # add_module wants to work on modules, not instances
                    setattr(self, f"filter_{i}", filter_inst)


            # ----------------- MUXING -------------------------------------
            # default value is bypass
            cases["default"] = cases[0]

            self.comb += [
                Case(out_mux_sync, cases),
            ]


    def _connect_with_adjustment(self, source_ep, sink_ep, source_width, sink_width):
        """Connect two stream endpoints, adjusting sample width as needed.

        This preserves handshake semantics (valid/ready) and applies either
        sign-extension (when widening) or truncation of LSBs (when narrowing),
        matching the original behavior.

        Args:
            source_ep: Upstream stream.Endpoint providing data.
            sink_ep: Downstream stream.Endpoint consuming data.
            source_width: Bit width of source_ep.data.
            sink_width: Bit width of sink_ep.data.
        """
        # Connect control signals
        self.comb += [
            sink_ep.valid.eq(source_ep.valid),
            source_ep.ready.eq(sink_ep.ready)
        ]

        # Adjust data width
        if source_width == sink_width:
            # Same width, direct connection
            self.comb += sink_ep.data.eq(source_ep.data)
        elif source_width < sink_width:
            sign_bit = source_ep.data[source_width - 1]
            padding = Replicate(sign_bit, sink_width - source_width)
            # Do Sign extension
            # Migen's Cat places first argument in LSB side of concatenation
            self.comb += [
                sink_ep.data.eq(Cat(source_ep.data, padding)),
            ]
        else:
            # Truncate by removing MSB's (reverse of sign extension)
            self.comb += sink_ep.data.eq(source_ep.data[:sink_width])
