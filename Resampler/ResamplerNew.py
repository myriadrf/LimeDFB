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

        # 4. Daisy Chaining (Straight Pipeline)
        for i in range(stages):
            # Determine source and destination for this connection
            if i == 0:
                src = self.sink
            else:
                src = self.filters[i-1].source
            dst = self.filters[i].sink

            # Connect data signals based on layout
            if hasattr(src, "i_even") and hasattr(dst, "i_even"):
                self.comb += [
                    dst.i_even.eq(src.i_even),
                    dst.q_even.eq(src.q_even),
                    dst.i_odd.eq(src.i_odd),
                    dst.q_odd.eq(src.q_odd),
                ]
            else:
                self.comb += [
                    dst.i.eq(src.i),
                    dst.q.eq(src.q),
                ]
            self.comb += dst.valid.eq(src.valid)
            self.comb += src.ready.eq(dst.ready)

        # Connect the last filter to the top-level source
        src = self.filters[-1].source
        dst = self.source
        if hasattr(src, "i_even") and hasattr(dst, "i_even"):
            self.comb += [
                dst.i_even.eq(src.i_even),
                dst.q_even.eq(src.q_even),
                dst.i_odd.eq(src.i_odd),
                dst.q_odd.eq(src.q_odd),
            ]
        else:
            self.comb += [
                dst.i.eq(src.i),
                dst.q.eq(src.q),
            ]
        self.comb += dst.valid.eq(src.valid)
        self.comb += src.ready.eq(dst.ready)

        # 5. Filter Submodules already registered via setattr
