from migen import *
from gateware.LimeDFB.Resampler.half_band_config import HalfBandConfig
import math

class HalfBandCore(Module):
    def __init__(self, config: HalfBandConfig, is_decimator: bool = False):
        # Inputs and Outputs (Migen Signals)
        self.enable = Signal(reset=1)
        self.in_0 = Signal((config.data_width, True))
        self.in_1 = Signal((config.data_width, True))

        self.out_0 = Signal((config.data_width, True))
        self.out_1 = Signal((config.data_width, True))

        # --- Path 0 (H0 - The Symmetric FIR) ---
        # h0_taps are the even-indexed taps.
        # Let's say original taps are [t0, 0, t2, 0, t4, 0, t6, 0.5, t6, 0, t4, 0, t2, 0, t0]
        # Then h0_taps = [t0, t2, t4, t6, t6, t4, t2, t0]
        # The symmetric pairs are (t0, t0), (t2, t2), (t4, t4), (t6, t6).
        # The number of unique coefficients is len(h0_taps) // 2.
        
        num_h0_taps = len(config.h0_taps)
        unique_taps = config.h0_taps[:num_h0_taps // 2]
        num_unique = len(unique_taps)
        
        # Delay line for Path 0
        # We need enough samples for all h0 taps.
        delay_line = [Signal((config.data_width, True)) for _ in range(num_h0_taps)]
        self.sync += If(self.enable,
            delay_line[0].eq(self.in_0),
            [delay_line[i].eq(delay_line[i-1]) for i in range(1, num_h0_taps)]
        )

        # Symmetric Pre-Adders (x[n] + x[N-1-n])
        # Register the output of every pre-adder.
        # Width should grow by 1 bit to accommodate the sum.
        pre_adder_outputs = [Signal((config.data_width + 1, True)) for _ in range(num_unique)]
        for i in range(num_unique):
            # i matches the first half, (num_h0_taps - 1 - i) matches the second half
            self.sync += If(self.enable, pre_adder_outputs[i].eq(delay_line[i] + delay_line[num_h0_taps - 1 - i]))

        # Multipliers
        # Multiply each registered pre-adder output by its corresponding fixed-point tap.
        # Register the output of every multiplier.
        # Width: (data_width + 1) + tap_width
        multiplier_outputs = [Signal((config.data_width + 1 + config.tap_width, True)) for _ in range(num_unique)]
        for i in range(num_unique):
            self.sync += If(self.enable, multiplier_outputs[i].eq(pre_adder_outputs[i] * unique_taps[i]))

        # Adder Tree
        # Sum all the registered multiplier outputs using a pipelined adder tree.
        # Register the result of each addition stage.
        
        def build_adder_tree(inputs):
            if len(inputs) == 1:
                return inputs[0], 0
            
            next_stage_inputs = []
            num_pairs = len(inputs) // 2
            for i in range(num_pairs):
                # Calculate bit growth for this stage
                res_width = inputs[2*i].nbits + 1
                res = Signal((res_width, True))
                self.sync += If(self.enable, res.eq(inputs[2*i] + inputs[2*i+1]))
                next_stage_inputs.append(res)
            
            # If odd number of inputs, pass the last one to the next stage through a register
            if len(inputs) % 2 == 1:
                res_width = inputs[-1].nbits
                res = Signal((res_width, True))
                self.sync += If(self.enable, res.eq(inputs[-1]))
                next_stage_inputs.append(res)
            
            res_signal, depth = build_adder_tree(next_stage_inputs)
            return res_signal, depth + 1

        raw_out_0, adder_tree_depth = build_adder_tree(multiplier_outputs)
        
        # Pipeline delay calculation for Path 0:
        # Stage 1: Pre-adder (1 clock)
        # Stage 2: Multiplier (1 clock)
        # Stage 3...: Adder Tree (adder_tree_depth clocks)
        path0_latency = 1 + 1 + adder_tree_depth
        
        # --- Path 1 (H1 - The Center Tap) ---

        # 1. ALGORITHMIC DELAY: Align in_1 with the center of the H0 window
        # H0 has an inherent 1-cycle input register, so we need exactly 5 cycles here:
        if is_decimator:
            h1_algorithmic_delay = (num_h0_taps // 2) + 1
        else:
            h1_algorithmic_delay = (num_h0_taps // 2)

        in_1_delay = [Signal((config.data_width, True)) for _ in range(h1_algorithmic_delay)]

        self.sync += If(self.enable,
            in_1_delay[0].eq(self.in_1),
            [in_1_delay[i].eq(in_1_delay[i-1]) for i in range(1, h1_algorithmic_delay)]
        )

        # 2. MULTIPLIER
        # Multiply the DELAYED in_1 by config.h1_center_tap.
        h1_multiplier_output = Signal((config.data_width + config.tap_width, True))
        self.sync += If(self.enable, h1_multiplier_output.eq(in_1_delay[-1] * config.h1_center_tap))

        # 3. COMPUTATIONAL PADDING (Junie's original padding logic)
        num_padding_regs = path0_latency - 1
        
        path1_pipeline = [h1_multiplier_output]
        for i in range(num_padding_regs):
            reg = Signal((config.data_width + config.tap_width, True))
            self.sync += If(self.enable, reg.eq(path1_pipeline[-1]))
            path1_pipeline.append(reg)
        
        raw_out_1 = path1_pipeline[-1]
        
        # --- Bit Truncation (Final Stage) ---
        # Shift both raw signals right by config.tap_width - 1
        # Truncate/slice them back to config.data_width bits.
        
        shift_amount = config.tap_width - 1
        
        # Combined shifted and sliced signals
        # Use + True to indicate signed slice if necessary, but Signal(..., True) handles it.
        # Shift right (arithmetic shift)
        
        self.comb += [
            self.out_0.eq((raw_out_0 >> shift_amount)[:config.data_width]),
            self.out_1.eq((raw_out_1 >> shift_amount)[:config.data_width])
        ]

        # Comments explicitly stating the pipeline delay
        # Calculated Path 0 latency: {} clock cycles.
        #   - Pre-adder: 1 cycle
        #   - Multiplier: 1 cycle
        #   - Adder Tree: {} cycles
        # Added {} padding registers to Path 1 to match Path 0 latency.
        self.latency_info = f"""
        Path 0 Latency Breakdown:
          - Pre-adder stage: 1 cycle
          - Multiplier stage: 1 cycle
          - Adder tree: {adder_tree_depth} cycles
          - Total Path 0 Latency: {path0_latency} cycles
        Path 1 Alignment:
          - Multiplier stage: 1 cycle
          - Padding registers: {num_padding_regs} cycles
          - Total Path 1 Latency: {1 + num_padding_regs} cycles
        """

if __name__ == "__main__":
    # Test compilation and output some information
    from gateware.LimeDFB.Resampler.half_band_config import HalfBandConfig
    config = HalfBandConfig(mode="short")
    core = HalfBandCore(config)
    
    print(core.latency_info)
    
    # Check if signals are created correctly
    print(f"data_width: {config.data_width}")
    print(f"h0_taps: {config.h0_taps}")
    print(f"h1_center_tap: {config.h1_center_tap}")
    
    # Verifying I/O
    print(f"in_0 width: {len(core.in_0)}")
    print(f"out_0 width: {len(core.out_0)}")
