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

    TAPS_SHORT_DOUBLED = [x * 2 for x in TAPS_SHORT]
    TAPS_LONG_DOUBLED = [x * 2 for x in TAPS_LONG]

    def __init__(self, mode="short", data_width=16, tap_width=18, auto_scale=True):
            self.mode = mode
            self.data_width = data_width
            self.tap_width = tap_width

            # 1. Select the locked profile
            if mode == "short":
                raw_taps = self.TAPS_SHORT
                self.core_latency = 4
            elif mode == "long":
                raw_taps = self.TAPS_LONG
                self.core_latency = 5
            elif mode == "short_doubled":
                raw_taps = self.TAPS_SHORT_DOUBLED
                self.core_latency = 4
            elif mode == "long_doubled":
                raw_taps = self.TAPS_LONG_DOUBLED
                self.core_latency = 5
            else:
                raise ValueError("Mode must be 'short', 'long', 'short_doubled', or 'long_doubled'.")

            assert len(raw_taps) % 2 != 0, "Tap array length must be odd."

            # 2. Quantize to fixed-point integers (with Auto-Scaling to prevent overflow)
            if auto_scale:
                quantized_taps = self._get_safe_quantized_taps(raw_taps, tap_width)
            else:
                scale_factor = (1 << (tap_width - 1)) - 1
                quantized_taps = [int(round(t * scale_factor)) for t in raw_taps]
            self.quantized_taps = quantized_taps

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

    def _get_safe_quantized_taps(self, raw_taps, tap_width):
            """
            Dynamically finds the highest scale factor that guarantees the passband
            frequency response peak will never exceed the maximum integer boundary.
            """
            max_safe_val = (1 << (tap_width - 1)) - 1  # 32767 for 16-bit

            # Interpolators (doubled taps) have a theoretical full-filter gain of 2.0.
            # The hardware polyphase branches split this into two 1.0 gain filters.
            # Therefore, the full filter magnitude is allowed to safely reach double the limit.
            target_max = max_safe_val * 2 if "doubled" in self.mode else max_safe_val

            # Test frequencies across the passband (0 to 0.45 * pi for a half-band)
            omegas = [i * (0.45 * math.pi / 100.0) for i in range(101)]
            center_idx = len(raw_taps) // 2

            current_scale = max_safe_val

            while current_scale > 0:
                q_taps = [int(round(t * current_scale)) for t in raw_taps]

                # FAILSAFE: No individual tap coefficient can ever exceed the 16-bit limit.
                # (This protects the doubled center tap from rounding up to 32768)
                if any(abs(tap) > max_safe_val for tap in q_taps):
                    current_scale -= 1
                    continue

                # Find the maximum passband magnitude using the symmetric FIR formula
                max_mag = 0
                for w in omegas:
                    mag = q_taps[center_idx]
                    for i in range(center_idx):
                        if q_taps[i] != 0:
                            dist = center_idx - i
                            mag += 2 * q_taps[i] * math.cos(w * dist)

                    if abs(mag) > max_mag:
                        max_mag = abs(mag)

                # If our peak magnitude is safely within the targeted bounds, we are done!
                if max_mag <= target_max:
                    return q_taps

                # If it overflows the theoretical target, back the scale factor off by 1
                current_scale -= 1

            return q_taps

if __name__ == "__main__":
    import numpy as np
    import matplotlib.pyplot as plt
    from scipy import signal

    def plot_comparison(mode="short"):
        # 1. Generate both sets of taps
        cfg_base = HalfBandConfig(mode=mode, auto_scale=False)
        cfg_tuned = HalfBandConfig(mode=mode, auto_scale=True)

        taps_base = cfg_base.quantized_taps
        taps_tuned = cfg_tuned.quantized_taps

        # 2. Calculate Frequency Response (freqz)
        # worN=8192 gives us a high-resolution FFT
        w, h_base = signal.freqz(taps_base, worN=8192)
        w, h_tuned = signal.freqz(taps_tuned, worN=8192)

        # Convert frequencies to normalized Nyquist (0 to 1.0)
        w_norm = w / np.pi

        # Convert complex magnitude to Decibels (dB)
        # We normalize by the sum of the taps so 0 dB is exactly the DC gain
        HARDWARE_MAX = (1 << (cfg_base.tap_width - 1)) - 1
        mag_base_db = 20 * np.log10(np.abs(h_base) / HARDWARE_MAX)
        mag_tuned_db = 20 * np.log10(np.abs(h_tuned) / HARDWARE_MAX)

        # 3. Plotting
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8))
        fig.suptitle(f'Quantization Optimization: {mode.upper()} Profile', fontsize=16)

        # --- Top Plot: Full Spectrum ---
        ax1.plot(w_norm, mag_base_db, label='Base (Standard Rounding)', color='red', alpha=0.7)
        ax1.plot(w_norm, mag_tuned_db, label='Scaled (Max gain 1.0)', color='blue', alpha=0.7)
        ax1.set_title('Full Frequency Response (Stopband Attenuation)')
        ax1.set_ylabel('Magnitude (dB)')
        max_base = np.max(mag_base_db)
        min_base = np.min(mag_base_db)
        ax1.set_ylim(min_base - 5, max_base + 5)
        ax1.set_xlim(0, 1)
        ax1.grid(True, alpha=0.3)
        ax1.legend()

        # --- Bottom Plot: Zoomed Passband Ripple ---
        ax2.plot(w_norm, mag_base_db, label='Base Ripple', color='red')
        ax2.plot(w_norm, mag_tuned_db, label='Scaled Ripple', color='blue')
        ax2.set_title('Zoomed Passband (Ripple Distortion)')
        ax2.set_xlabel('Normalized Frequency (×π rad/sample)')
        ax2.set_ylabel('Magnitude (dB)')
        # Zoom in on the passband (0 to 0.45 Nyquist) and heavily restrict the Y-axis
        # Zoom in on the passband (0 to 0.45 Nyquist)
        pb_limit = 0.45
        ax2.set_xlim(0, pb_limit)

        # 1. Find the array indices that fall inside our 0 to 0.45 X-axis window
        pb_indices = np.where(w_norm <= pb_limit)[0]

        # 2. Find the absolute highest value inside that window for both arrays
        max_base = np.max(mag_base_db[pb_indices])
        max_tuned = np.max(mag_tuned_db[pb_indices])

        # 3. Pick the largest of the two and multiply by 2
        highest_displayed_val = max(max_base, max_tuned)
        dynamic_limit = highest_displayed_val * 2

        # 4. Apply the dynamic Y-axis limits
        # Add a tiny fallback just in case the filter is perfectly flat (0.0) so matplotlib doesn't crash
        if dynamic_limit == 0: dynamic_limit = 0.001
        ax2.set_ylim(-dynamic_limit, dynamic_limit)
        ax2.grid(True, alpha=0.5)
        ax2.legend()

        plt.tight_layout()
        plt.show()

    # Run the visualizer for the long filter
    plot_comparison(mode="long")