import math

class HalfBandConfig:
    # Hardcoded text-book half-band taps
    TAPS_SHORT = [
        -0.00164032, 0, 0.0138855, 0, -0.0630875, 0, 0.300842, 
        0.5, 
        0.300842, 0, -0.0630875, 0, 0.0138855, 0, -0.00164032
    ]
    
    TAPS_LONG = [
        -4.673e-05, 0, 0.000392914, 0, -0.00181007, 0, 0.00600147, 0, 
        -0.0160789, 0, 0.0378866, 0, -0.0882454, 0, 0.3119, 
        0.5, 
        0.3119, 0, -0.0882454, 0, 0.0378866, 0, -0.0160789, 0, 
        0.00600147, 0, -0.00181007, 0, 0.000392914, 0, -4.673e-05
    ]

    def __init__(self, mode="short", data_width=16, tap_width=16):
        self.mode = mode
        self.data_width = data_width
        self.tap_width = tap_width

        # 1. Select the locked profile
        if mode == "short":
            raw_taps = self.TAPS_SHORT
            self.core_latency = 4  # 1 (pre-add) + 1 (mult) + 2 (adder tree)
        elif mode == "long":
            raw_taps = self.TAPS_LONG
            self.core_latency = 5  # 1 (pre-add) + 1 (mult) + 3 (adder tree)
        else:
            raise ValueError("Mode must be 'short' or 'long'.")

        assert len(raw_taps) % 2 != 0, "Tap array length must be odd."

        # 2. Quantize to fixed-point integers
        scale_factor = (1 << (tap_width - 1)) - 1
        quantized_taps = [int(round(t * scale_factor)) for t in raw_taps]

        # 3. Polyphase Separation
        self.h0_taps = []
        self.h1_center_tap = 0
        
        center_index = len(quantized_taps) // 2

        for i, tap in enumerate(quantized_taps):
            if i % 2 == 0:
                self.h0_taps.append(tap)
            else:
                if i == center_index:
                    self.h1_center_tap = tap
                else:
                    assert tap == 0, f"Odd tap at index {i} must be 0 in a half-band filter."

if __name__ == "__main__":
    # Quick sanity check
    config_short = HalfBandConfig(mode="short")
    print(f"Short Filter Latency: {config_short.core_latency} cycles")
    
    config_long = HalfBandConfig(mode="long")
    print(f"Long Filter Latency: {config_long.core_latency} cycles")
    print(f"Long Filter Center Tap: {config_long.h1_center_tap}")