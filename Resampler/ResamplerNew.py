from migen import *
from litex.gen import LiteXModule
from litex.soc.interconnect import stream

from gateware.LimeDFB.Resampler.half_band_complex import (
    ComplexSSRDecimator, ComplexSSRInterpolator,
    ComplexStandardDecimator, ComplexStandardInterpolator
)
from gateware.LimeDFB.Resampler.half_band_config import HalfBandConfig

class ResamplerNew(LiteXModule):
    def __init__(self, sample_width=16, stages=1, direction="up", filter_mode="short", ssr_mode=False):
        # 1. Signature check
        assert direction in ["up", "down"], "Direction must be 'up' or 'down'"
        assert stages > 0, "ResamplerNew requires at least 1 stage. Use external routing for bypass."

        # 2. Top-Level Stream Endpoints
        self.mux_sel = Signal(4)
        std_layout = [("i", sample_width), ("q", sample_width)]
        ssr_layout = [
            ("i_even", sample_width), ("q_even", sample_width),
            ("i_odd", sample_width),  ("q_odd", sample_width)
        ]

        if ssr_mode:
            if direction == "down":
                sink_layout = ssr_layout
                source_layout = std_layout
            else: # up
                sink_layout = std_layout
                source_layout = ssr_layout
        else:
            sink_layout = std_layout
            source_layout = std_layout

        self.sink   = stream.Endpoint(sink_layout)
        self.source = stream.Endpoint(source_layout)

        # 3. Filter Instantiation
        config = HalfBandConfig(mode=filter_mode, data_width=sample_width, tap_width=16)
        self.filters = []

        for i in range(stages):
            if direction == "down":
                if ssr_mode and i == 0:
                    fltr = ComplexSSRDecimator(config)
                else:
                    fltr = ComplexStandardDecimator(config)
            else: # up
                if ssr_mode and i == stages - 1:
                    fltr = ComplexSSRInterpolator(config)
                else:
                    fltr = ComplexStandardInterpolator(config)
            
            # Use setattr to register as submodule
            setattr(self, f"filter_{i}", fltr)
            self.filters.append(fltr)

        # 4. Routing Logic
        def connect_data(src, dst):
            if hasattr(src, "i_even") and hasattr(dst, "i_even"):
                return [
                    dst.i_even.eq(src.i_even),
                    dst.q_even.eq(src.q_even),
                    dst.i_odd.eq(src.i_odd),
                    dst.q_odd.eq(src.q_odd),
                ]
            else:
                return [
                    dst.i.eq(src.i),
                    dst.q.eq(src.q),
                ]

        if direction == "down":
            # Input Injection: sink is permanently connected to filter 0
            self.comb += [
                self.filters[0].sink.valid.eq(self.sink.valid),
                self.sink.ready.eq(self.filters[0].sink.ready),
                connect_data(self.sink, self.filters[0].sink)
            ]

            # Cascading data connections (static)
            for i in range(stages - 1):
                self.comb += connect_data(self.filters[i].source, self.filters[i+1].sink)

            # Output & Backpressure MUX
            # Default values to avoid latches/loops
            self.comb += self.source.valid.eq(0)
            for fltr in self.filters:
                self.comb += fltr.source.ready.eq(0)
            for i in range(1, stages):
                self.comb += self.filters[i].sink.valid.eq(0)
            self.comb += connect_data(self.filters[0].source, self.source) # Default data

            cases = {}
            for i in range(stages):
                mux_val = i + 1
                case_logic = [
                    self.source.valid.eq(self.filters[i].source.valid),
                    self.filters[i].source.ready.eq(self.source.ready)
                ] + connect_data(self.filters[i].source, self.source)
                # Cascading for active stages
                for k in range(i):
                    case_logic += [
                        self.filters[k+1].sink.valid.eq(self.filters[k].source.valid),
                        self.filters[k].source.ready.eq(self.filters[k+1].sink.ready)
                    ]
                # Freeze unused downstream
                if i < stages - 1:
                    case_logic += [self.filters[i+1].sink.valid.eq(0)]
                cases[mux_val] = case_logic

            cases["default"] = cases[1]
            self.comb += Case(self.mux_sel, cases)

        else: # direction == "up"
            # Output Tap: self.source is permanently connected to the last stage
            self.comb += [
                self.source.valid.eq(self.filters[-1].source.valid),
                self.filters[-1].source.ready.eq(self.source.ready),
                connect_data(self.filters[-1].source, self.source)
            ]

            # Cascading data connections (static)
            for i in range(stages - 1):
                self.comb += connect_data(self.filters[i].source, self.filters[i+1].sink)

            # Input MUX
            # Default values
            self.comb += self.sink.ready.eq(0)
            for fltr in self.filters:
                self.comb += fltr.sink.valid.eq(0)
            for i in range(stages - 1):
                self.comb += self.filters[i].source.ready.eq(0)
            self.comb += connect_data(self.sink, self.filters[0].sink) # Default data injection

            cases = {}
            for i in range(stages):
                mux_val = i + 1
                inject_idx = stages - mux_val
                case_logic = [
                    self.filters[inject_idx].sink.valid.eq(self.sink.valid),
                    self.sink.ready.eq(self.filters[inject_idx].sink.ready)
                ] + connect_data(self.sink, self.filters[inject_idx].sink)
                # Cascading for active stages
                for k in range(inject_idx, stages - 1):
                    case_logic += [
                        self.filters[k+1].sink.valid.eq(self.filters[k].source.valid),
                        self.filters[k].source.ready.eq(self.filters[k+1].sink.ready)
                    ]
                cases[mux_val] = case_logic

            cases["default"] = cases[1]
            self.comb += Case(self.mux_sel, cases)
