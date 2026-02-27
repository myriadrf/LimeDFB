import numpy as np
import matplotlib.pyplot as plt
from migen import *
from migen.sim import *
from gateware.LimeDFB.Resampler.ResamplerNew import ResamplerNew

# 1. Stimulus Generation
def generate_stimulus(n_samples=8192, data_width=16):
    """
    Generate a frequency comb of 20 evenly spaced coherent tones.
    This allows us to see the exact cutoff points of each decimation stage.
    """
    t = np.arange(n_samples)

    # Generate 20 evenly spaced integer cycle counts
    # Start at 100 cycles (low freq), end at 3900 cycles (near Nyquist)
    num_tones = 20
    cycles = np.linspace(100, 3900, num_tones).astype(int)

    # Calculate the exact coherent decimal frequencies
    freqs = cycles / n_samples

    # Complex signal: sum of complex sinusoids
    signal = np.zeros(n_samples, dtype=complex)
    for f in freqs:
        signal += np.exp(1j * 2 * np.pi * f * t)
    
    # Scale to 90% of the maximum 16-bit signed integer range
    max_val = (2**(data_width - 1)) - 1
    peak_val = np.max(np.abs([signal.real, signal.imag]))
    scale = (max_val * 0.90) / peak_val
    signal *= scale

    return signal.real.astype(np.int64) + 1j * signal.imag.astype(np.int64)

# 2. Sender Generator
def sender(dut, stim, status):
    idx = 0
    while idx < len(stim):
        # Since the input to an interpolator is always Standard mode (1 sample per cycle)
        yield dut.sink.i.eq(int(stim[idx].real))
        yield dut.sink.q.eq(int(stim[idx].imag))
        yield dut.sink.valid.eq(1)
        yield
        if (yield dut.sink.ready) == 1:
            idx += 1
                
    yield dut.sink.valid.eq(0)
    # Flush the pipeline
    for _ in range(200):
        yield
    # Signal completion
    status["done"] = True
    return

# 3. Receiver Generator
def receiver(dut, output_list, status):
    while not status["done"]:
        yield dut.source.ready.eq(1)
        yield
        if (yield dut.source.valid) == 1:
            # Check if hasattr(dut.source, "i_even") to determine if the output is SSR or Standard.
            if hasattr(dut.source, "i_even"):
                # SSR: read i_even, q_even, i_odd, q_odd, sign extend all four, 
                # and append two complex numbers sequentially to output_list (Even first, then Odd).
                i_even = (yield dut.source.i_even)
                q_even = (yield dut.source.q_even)
                i_odd = (yield dut.source.i_odd)
                q_odd = (yield dut.source.q_odd)
                
                # Sign extension (assuming 16-bit for ResamplerNew default)
                data_width = 16
                if i_even >= 2**(data_width - 1): i_even -= 2**data_width
                if q_even >= 2**(data_width - 1): q_even -= 2**data_width
                if i_odd >= 2**(data_width - 1): i_odd -= 2**data_width
                if q_odd >= 2**(data_width - 1): q_odd -= 2**data_width
                
                output_list.append(complex(i_even, q_even))
                output_list.append(complex(i_odd, q_odd))
            else:
                # Standard: read i and q, sign extend, and append one complex number to output_list.
                i_out = (yield dut.source.i)
                q_out = (yield dut.source.q)
                
                # Sign extension
                data_width = 16
                if i_out >= 2**(data_width - 1): i_out -= 2**data_width
                if q_out >= 2**(data_width - 1): q_out -= 2**data_width
                
                output_list.append(complex(i_out, q_out))

# 4. Main
def main():
    stages_sweep = [1, 2, 3]
    ssr_modes = [False, True]
    
    fig, axes = plt.subplots(len(stages_sweep), len(ssr_modes), figsize=(15, 15))
    fig.suptitle("ResamplerNew Interpolation Performance", fontsize=16)
    
    for row, stages in enumerate(stages_sweep):
        for col, ssr_mode in enumerate(ssr_modes):
            ax = axes[row, col]
            print(f"Simulating stages={stages}, ssr_mode={ssr_mode}...")
            
            dut = ResamplerNew(stages=stages, direction="up", ssr_mode=ssr_mode, filter_mode="long")
            stim = generate_stimulus(n_samples=2048)
            output = []
            status = {"done": False}
            
            run_simulation(dut, [sender(dut, stim, status), receiver(dut, output, status)])
            
            if not output:
                print(f"Warning: No output for stages={stages}, ssr_mode={ssr_mode}")
                ax.set_title(f"Stages={stages}, SSR={ssr_mode} - NO OUTPUT")
                continue

            # Plotting
            # Input FFT
            win_in = np.blackman(len(stim))
            fft_in = np.fft.fft(stim * win_in)
            mag_in = 20 * np.log10(np.abs(np.fft.fftshift(fft_in)) + 1e-12)
            # The X-axis for the Input FFT should be scaled to represent its fraction of the final Output sample rate: 
            # f_in = np.linspace(-0.5 / (2**stages), 0.5 / (2**stages), len(stim))
            f_in = np.linspace(-0.5 / (2**stages), 0.5 / (2**stages), len(stim))
            
            # Output FFT
            win_out = np.blackman(len(output))
            fft_out = np.fft.fft(output * win_out)
            mag_out = 20 * np.log10(np.abs(np.fft.fftshift(fft_out)) + 1e-12)
            # The Output FFT X-axis remains [-0.5, 0.5].
            f_out = np.linspace(-0.5, 0.5, len(output))
            
            ax.plot(f_in, mag_in, color='red', alpha=0.5, label='Input (scaled)')
            ax.plot(f_out, mag_out, color='blue', alpha=0.8, label='Output')
            
            ax.set_title(f"Stages={stages}, SSR={ssr_mode}")
            ax.grid(True)
            ax.set_xlim([-0.5, 0.5])
            ax.set_ylim([0, 160])
            ax.set_ylabel("Magnitude (dB)")
            if row == len(stages_sweep) - 1:
                ax.set_xlabel("Normalized Frequency (relative to Output Fs)")
            ax.legend()

    plt.tight_layout(rect=[0, 0.03, 1, 0.95])
    plt.savefig("resampler_interpolation_results.png")
    print("Simulation complete. Results saved to resampler_interpolation_results.png")
    plt.show()

if __name__ == "__main__":
    main()
