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
    is_ssr = hasattr(dut.sink, "i_even")
    
    while idx < len(stim):
        if is_ssr:
            # SSR mode: 2 samples per clock
            if idx + 1 < len(stim):
                yield dut.sink.i_even.eq(int(stim[idx].real))
                yield dut.sink.q_even.eq(int(stim[idx].imag))
                yield dut.sink.i_odd.eq(int(stim[idx+1].real))
                yield dut.sink.q_odd.eq(int(stim[idx+1].imag))
                yield dut.sink.valid.eq(1)
            else:
                # Last sample if odd length (shouldn't happen with 8192)
                yield dut.sink.i_even.eq(int(stim[idx].real))
                yield dut.sink.q_even.eq(int(stim[idx].imag))
                yield dut.sink.i_odd.eq(0)
                yield dut.sink.q_odd.eq(0)
                yield dut.sink.valid.eq(1)
        else:
            # Standard mode: 1 sample per clock
            yield dut.sink.i.eq(int(stim[idx].real))
            yield dut.sink.q.eq(int(stim[idx].imag))
            yield dut.sink.valid.eq(1)
            
        yield
        
        if (yield dut.sink.ready) == 1:
            if is_ssr:
                idx += 2
            else:
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
            i_out = (yield dut.source.i)
            q_out = (yield dut.source.q)
            
            # Sign extension (assuming 16-bit for ResamplerNew default)
            data_width = 16
            if i_out >= 2**(data_width - 1): i_out -= 2**data_width
            if q_out >= 2**(data_width - 1): q_out -= 2**data_width
            
            output_list.append(complex(i_out, q_out))

# 4. Main
def main():
    stages_sweep = [1, 2, 3]
    ssr_modes = [False, True]
    
    fig, axes = plt.subplots(len(stages_sweep), 2, figsize=(15, 15))
    fig.suptitle("ResamplerNew Decimation Performance", fontsize=16)
    
    for row, stages in enumerate(stages_sweep):
        for col, ssr_mode in enumerate(ssr_modes):
            ax = axes[row, col]
            print(f"Simulating stages={stages}, ssr_mode={ssr_mode}...")
            
            dut = ResamplerNew(stages=stages, direction="down", ssr_mode=ssr_mode, filter_mode="long")
            stim = generate_stimulus(n_samples=8192)
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
            f_in = np.linspace(-0.5, 0.5, len(stim))
            
            # Output FFT
            win_out = np.blackman(len(output))
            fft_out = np.fft.fft(output * win_out)
            mag_out = 20 * np.log10(np.abs(np.fft.fftshift(fft_out)) + 1e-12)
            
            # Scale the Output FFT frequency x-axis by (1.0 / (2**stages))
            decimation_factor = 2**stages
            f_out = np.linspace(-0.5 / decimation_factor, 0.5 / decimation_factor, len(output))
            
            ax.plot(f_in, mag_in, color='blue', alpha=0.5, label='Input')
            ax.plot(f_out, mag_out, color='red', alpha=0.8, label='Output')
            
            ax.set_title(f"Stages={stages}, SSR={ssr_mode}")
            ax.grid(True)
            ax.set_xlim([-0.5, 0.5])
            ax.set_ylim([0, 160])
            ax.set_ylabel("Magnitude (dB)")
            if row == len(stages_sweep) - 1:
                ax.set_xlabel("Normalized Frequency (relative to Input Fs)")
            ax.legend()

    plt.tight_layout(rect=[0, 0.03, 1, 0.95])
    plt.savefig("resampler_decimation_results.png")
    print("Simulation complete. Results saved to resampler_decimation_results.png")
    plt.show()

if __name__ == "__main__":
    main()
