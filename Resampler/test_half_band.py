from migen import *
from migen.sim import run_simulation
from gateware.LimeDFB.Resampler.half_band_config import HalfBandConfig
from gateware.LimeDFB.Resampler.half_band_core import HalfBandCore

def testbench_generator(core, config, results):
    # Max positive value for signed input
    max_val = (2**(config.data_width - 1)) - 1
    
    # Stimulus: Impulse Response
    # Clock Cycle 0: Yield maximum value into BOTH core.in_0 and core.in_1
    yield core.in_0.eq(max_val)
    yield core.in_1.eq(max_val)
    
    # Read outputs and store them (Cycle 0)
    out0 = yield core.out_0
    out1 = yield core.out_1
    results.append((0, out0, out1))
    yield
    
    # Clock Cycles 1 through 25: Yield 0 into both inputs
    for cycle in range(1, 26):
        yield core.in_0.eq(0)
        yield core.in_1.eq(0)
        
        # Read outputs and store them
        out0 = yield core.out_0
        out1 = yield core.out_1
        results.append((cycle, out0, out1))
        yield

if __name__ == "__main__":
    # Define sample taps (same as in half_band_core.py main)
    config = HalfBandConfig(mode="short")
    core = HalfBandCore(config)
    
    results = []
    
    # Run Simulation
    run_simulation(core, testbench_generator(core, config, results))
    
    # Print a nicely formatted side-by-side table
    print(f"{'Cycle':<10} | {'out_0':<10} | {'out_1':<10}")
    print("-" * 35)
    for cycle, out0, out1 in results:
        # Convert signed values if they appear as unsigned in yield (Migen simulation behavior)
        if out0 >= 2**(config.data_width - 1):
            out0 -= 2**config.data_width
        if out1 >= 2**(config.data_width - 1):
            out1 -= 2**config.data_width
            
        print(f"{cycle:<10} | {out0:<10} | {out1:<10}")

    print("\nLatency Information from Core:")
    print(core.latency_info)
