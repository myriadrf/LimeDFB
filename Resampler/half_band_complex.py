from migen import *
from litex.soc.interconnect import stream
from gateware.LimeDFB.Resampler.half_band_config import HalfBandConfig
from gateware.LimeDFB.Resampler.half_band_core import HalfBandCore

class ComplexSSRDecimator(Module):
    def __init__(self, config: HalfBandConfig):
        self.config = config
        # Layouts
        sink_layout = [
            ("i_even", config.data_width),
            ("q_even", config.data_width),
            ("i_odd", config.data_width),
            ("q_odd", config.data_width)
        ]
        source_layout = [
            ("i", config.data_width),
            ("q", config.data_width)
        ]

        # Interface
        self.sink = stream.Endpoint(sink_layout)
        self.source = stream.Endpoint(source_layout)

        # Instantiation
        self.submodules.core_i = core_i = HalfBandCore(config, is_decimator=True)
        self.submodules.core_q = core_q = HalfBandCore(config, is_decimator=True)

        core_enable = Signal()
        self.comb += core_enable.eq(self.sink.valid & self.source.ready)

        # Routing (Sink to Cores)
        self.comb += [
            core_i.enable.eq(core_enable),
            core_q.enable.eq(core_enable),
            core_i.in_0.eq(self.sink.i_even),
            core_i.in_1.eq(self.sink.i_odd),
            core_q.in_0.eq(self.sink.q_even),
            core_q.in_1.eq(self.sink.q_odd),
            self.sink.ready.eq(self.source.ready)
        ]

        # Output Math (Cores to Source)
        self.comb += [
            self.source.i.eq(core_i.out_0 + core_i.out_1),
            self.source.q.eq(core_q.out_0 + core_q.out_1)
        ]

        # Valid Signal Delay
        valid_delay = [Signal() for _ in range(config.core_latency)]
        self.sync += If(core_enable,
            valid_delay[0].eq(self.sink.valid),
            [valid_delay[i].eq(valid_delay[i-1]) for i in range(1, config.core_latency)]
        )
        self.comb += self.source.valid.eq(valid_delay[-1])


class ComplexSSRInterpolator(Module):
    def __init__(self, config: HalfBandConfig):
        self.config = config
        # Layouts
        sink_layout = [
            ("i", config.data_width),
            ("q", config.data_width)
        ]
        source_layout = [
            ("i_even", config.data_width),
            ("q_even", config.data_width),
            ("i_odd", config.data_width),
            ("q_odd", config.data_width)
        ]

        # Interface
        self.sink = stream.Endpoint(sink_layout)
        self.source = stream.Endpoint(source_layout)

        # Instantiation
        self.submodules.core_i = core_i = HalfBandCore(config, is_decimator=False)
        self.submodules.core_q = core_q = HalfBandCore(config, is_decimator=False)

        core_enable = Signal()
        self.comb += core_enable.eq(self.sink.valid & self.source.ready)

        # Routing (Sink to Cores - Fan-out)
        self.comb += [
            core_i.enable.eq(core_enable),
            core_q.enable.eq(core_enable),
            core_i.in_0.eq(self.sink.i),
            core_i.in_1.eq(self.sink.i),
            core_q.in_0.eq(self.sink.q),
            core_q.in_1.eq(self.sink.q),
            self.sink.ready.eq(self.source.ready)
        ]

        # Output Math (Cores to Source)
        self.comb += [
            self.source.i_even.eq(core_i.out_0),
            self.source.i_odd.eq(core_i.out_1),
            self.source.q_even.eq(core_q.out_0),
            self.source.q_odd.eq(core_q.out_1)
        ]

        # Valid Signal Delay
        valid_delay = [Signal() for _ in range(config.core_latency)]
        self.sync += If(core_enable,
            valid_delay[0].eq(self.sink.valid),
            [valid_delay[i].eq(valid_delay[i-1]) for i in range(1, config.core_latency)]
        )
        self.comb += self.source.valid.eq(valid_delay[-1])

class ComplexStandardDecimator(Module):
    def __init__(self, config: HalfBandConfig):
        self.config = config
        # Layouts
        layout = [
            ("i", config.data_width),
            ("q", config.data_width)
        ]

        # Interface
        self.sink = stream.Endpoint(layout)
        self.source = stream.Endpoint(layout)

        # Submodules
        self.submodules.core_i = core_i = HalfBandCore(config, is_decimator=True)
        self.submodules.core_q = core_q = HalfBandCore(config, is_decimator=True)

        # Logic (The Commutator)
        phase = Signal()
        i_held = Signal((config.data_width, True))
        q_held = Signal((config.data_width, True))

        self.sync += If(self.sink.valid & self.source.ready,
            phase.eq(~phase),
            If(phase == 0,
                i_held.eq(self.sink.i),
                q_held.eq(self.sink.q)
            )
        )

        core_enable = Signal()
        self.comb += [
            core_enable.eq(self.sink.valid & self.source.ready & (phase == 1)),
            core_i.enable.eq(core_enable),
            core_q.enable.eq(core_enable),
            core_i.in_0.eq(i_held),
            core_i.in_1.eq(self.sink.i),
            core_q.in_0.eq(q_held),
            core_q.in_1.eq(self.sink.q),
            self.sink.ready.eq(self.source.ready)
        ]

        # Valid Tracking
        latency = config.core_latency
        valid_delay = [Signal() for _ in range(latency)]
        self.sync += If(core_enable,
            valid_delay[0].eq(self.sink.valid),
            [valid_delay[i].eq(valid_delay[i-1]) for i in range(1, latency)]
        )

        # Output
        self.comb += [
            self.source.valid.eq(valid_delay[-1] & core_enable),
            self.source.i.eq(core_i.out_0 + core_i.out_1),
            self.source.q.eq(core_q.out_0 + core_q.out_1)
        ]


class ComplexStandardInterpolator(Module):
    def __init__(self, config: HalfBandConfig):
        self.config = config
        # Layouts
        layout = [
            ("i", config.data_width),
            ("q", config.data_width)
        ]

        # Interface
        self.sink = stream.Endpoint(layout)
        self.source = stream.Endpoint(layout)

        # Submodules
        self.submodules.core_i = core_i = HalfBandCore(config, is_decimator=False)
        self.submodules.core_q = core_q = HalfBandCore(config, is_decimator=False)

        # Serialization (Continuous)
        i_odd_held = Signal((config.data_width, True))
        q_odd_held = Signal((config.data_width, True))
        transmitting_odd = Signal()

        # Logic
        pipeline_enable = Signal()
        self.comb += pipeline_enable.eq(~transmitting_odd & self.source.ready)

        core_enable = Signal()
        self.comb += [
            core_enable.eq(self.sink.valid & pipeline_enable),
            core_i.enable.eq(pipeline_enable),
            core_q.enable.eq(pipeline_enable),
            core_i.in_0.eq(self.sink.i),
            core_i.in_1.eq(self.sink.i),
            core_q.in_0.eq(self.sink.q),
            core_q.in_1.eq(self.sink.q),
            self.sink.ready.eq(pipeline_enable)
        ]

        # Valid Tracking
        latency = config.core_latency
        valid_delay = [Signal() for _ in range(latency)]
        self.sync += If(pipeline_enable,
            valid_delay[0].eq(self.sink.valid),
            [valid_delay[i].eq(valid_delay[i-1]) for i in range(1, latency)]
        )

        core_ready_pulse = Signal()
        self.comb += core_ready_pulse.eq(valid_delay[-1] & core_enable)

        self.sync += [
            If(core_ready_pulse & self.source.ready,
                i_odd_held.eq(core_i.out_1),
                q_odd_held.eq(core_q.out_1),
                transmitting_odd.eq(1)
            ).Elif(transmitting_odd & self.source.ready,
                transmitting_odd.eq(0)
            )
        ]

        self.comb += [
            If(core_ready_pulse & self.source.ready,
                self.source.i.eq(core_i.out_0),
                self.source.q.eq(core_q.out_0),
                self.source.valid.eq(1)
            ).Elif(transmitting_odd & self.source.ready,
                self.source.i.eq(i_odd_held),
                self.source.q.eq(q_odd_held),
                self.source.valid.eq(1)
            ).Else(
                self.source.i.eq(0),
                self.source.q.eq(0),
                self.source.valid.eq(0)
            )
        ]


if __name__ == "__main__":
    config = HalfBandConfig(mode="short")
    
    decimator_ssr = ComplexSSRDecimator(config)
    interpolator_ssr = ComplexSSRInterpolator(config)
    decimator_std = ComplexStandardDecimator(config)
    interpolator_std = ComplexStandardInterpolator(config)
    
    print("All modules instantiated successfully.")
