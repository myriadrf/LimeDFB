import argparse
import numpy as np
import matplotlib.pyplot as plt
from migen import *
from migen.sim import *
from migen.sim import run_simulation as migen_run_simulation
from gateware.LimeDFB.Resampler.half_band_config import HalfBandConfig
from gateware.LimeDFB.Resampler.half_band_complex import ComplexStandardDecimator, ComplexStandardInterpolator

# 1. Stimulus Generation
def generate_stimulus(n_samples=2048, data_width=16):
    """
    Generate a complex test signal consisting of 10 combined complex sinusoids.
    Uses coherent frequencies to eliminate spectral leakage in the FFT.
    """
    fs = 1.0
    t = np.arange(n_samples)

    # Choose M (integer number of cycles) for each tone
    # For n_samples=2048, 61 cycles is roughly 0.03 normalized frequency.
    passband_cycles = [61, 143, 225, 307, 389]
    stopband_cycles = [635, 696, 758, 819, 881]

    # Calculate the exact coherent decimal frequencies
    passband_freqs = [m / n_samples for m in passband_cycles]
    stopband_freqs = [m / n_samples for m in stopband_cycles]
    
    all_freqs = passband_freqs + stopband_freqs
    
    # Complex signal: sum of complex sinusoids
    signal = np.zeros(n_samples, dtype=complex)
    for f in all_freqs:
        # I = cos, Q = sin -> exp(j*2*pi*f*t)
        signal += np.exp(1j * 2 * np.pi * f * t)
    
    # Scale to data_width range
    # The max amplitude of the sum of 10 tones is 10.
    # To be safe, we scale so the peak is around (2**(data_width-1) - 1) * 0.95.
    peak_val = (2**(data_width-1) - 1) * 0.95
    scale = peak_val / np.max(np.abs([signal.real, signal.imag]))
    signal *= scale
    
    # Return as integers
    return signal.real.astype(np.int64) + 1j * signal.imag.astype(np.int64)

# 2. Testbench Generators
def decimator_test_gen(dut, input_signal, output_list):
    """
    Generator for the Standard Decimator.
    Input: Complex array (long).
    Output: Decimated complex array (short).
    """
    n_input = len(input_signal)
    
    yield dut.source.ready.eq(1)
    
    # Provide inputs serially, respecting ready/valid handshaking.
    feed_index = 0
    while len(output_list) < n_input // 2:
        if feed_index < n_input:
            yield dut.sink.i.eq(int(input_signal[feed_index].real))
            yield dut.sink.q.eq(int(input_signal[feed_index].imag))
            yield dut.sink.valid.eq(1)
        else:
            yield dut.sink.i.eq(0)
            yield dut.sink.q.eq(0)
            # Send enough dummy valids to flush the pipeline.
            # For a decimator, we might need a few more cycles.
            yield dut.sink.valid.eq(1)
            
        yield
        
        # Sender: Check if data was accepted
        if (yield dut.sink.ready) and feed_index < n_input:
            feed_index += 1
            
        # Receiver: Concurrently check for outputs
        if (yield dut.source.valid):
            i_out = (yield dut.source.i)
            q_out = (yield dut.source.q)
            # Handle sign extension
            if i_out >= 2**(dut.config.data_width-1): i_out -= 2**dut.config.data_width
            if q_out >= 2**(dut.config.data_width-1): q_out -= 2**dut.config.data_width
            output_list.append(complex(i_out, q_out))

def interpolator_test_gen(dut, input_signal, output_list):
    """
    Generator for the Standard Interpolator.
    Input: Complex array (short).
    Output: Interpolated complex array (long).
    """
    n_input = len(input_signal)
    
    yield dut.source.ready.eq(1)
    
    # Provide inputs, respecting ready/valid handshaking.
    feed_index = 0
    while len(output_list) < n_input * 2:
        if feed_index < n_input:
            yield dut.sink.i.eq(int(input_signal[feed_index].real))
            yield dut.sink.q.eq(int(input_signal[feed_index].imag))
            yield dut.sink.valid.eq(1)
        else:
            yield dut.sink.i.eq(0)
            yield dut.sink.q.eq(0)
            # Send enough dummy valids to flush the pipeline.
            yield dut.sink.valid.eq(1)
            
        yield
        
        # Sender: Check if data was accepted
        if (yield dut.sink.ready) and feed_index < n_input:
            feed_index += 1
            
        # Receiver: Concurrently check for outputs
        if (yield dut.source.valid):
            i_out = (yield dut.source.i)
            q_out = (yield dut.source.q)
            # Handle sign extension
            if i_out >= 2**(dut.config.data_width-1): i_out -= 2**dut.config.data_width
            if q_out >= 2**(dut.config.data_width-1): q_out -= 2**dut.config.data_width
            output_list.append(complex(i_out, q_out))

# 3. FFT & Plotting Helper
def main():
    parser = argparse.ArgumentParser(description="Simulate Standard Half-Band filters with configurable widths.")
    parser.add_argument("--data-width", type=int, default=16, help="Data width in bits")
    parser.add_argument("--tap-width", type=int, default=16, help="Tap width in bits")
    args = parser.parse_args()

    fig, axes = plt.subplots(4, 2, figsize=(15, 20))
    fig.suptitle("Complex Standard Half-Band Modules Performance", fontsize=16)
    
    tests = [
        ("short", "decimator", axes[0, 0], axes[0, 1]),
        ("long",  "decimator", axes[1, 0], axes[1, 1]),
        ("short", "interpolator", axes[2, 0], axes[2, 1]),
        ("long",  "interpolator", axes[3, 0], axes[3, 1])
    ]
    
    for mode, mtype, ax_in, ax_out in tests:
        print(f"Simulating {mtype} ({mode}) with data_width={args.data_width}, tap_width={args.tap_width}...")
        config = HalfBandConfig(mode=mode, data_width=args.data_width, tap_width=args.tap_width)
        
        if mtype == "decimator":
            dut = ComplexStandardDecimator(config)
            stim = generate_stimulus(2048, data_width=args.data_width)
            out = []
            migen_run_simulation(dut, decimator_test_gen(dut, stim, out))
        else:
            dut = ComplexStandardInterpolator(config)
            # Use 1024 samples at low rate
            full_stim = generate_stimulus(2048, data_width=args.data_width)
            stim = full_stim[0::2]
            out = []
            migen_run_simulation(dut, interpolator_test_gen(dut, stim, out))

        # Plot Input FFT
        n_in = len(stim)
        win_in = np.blackman(n_in)
        fft_in = np.fft.fft(stim * win_in)
        mag_in = 20 * np.log10(np.abs(np.fft.fftshift(fft_in)) + 1e-12)
        f_in = np.linspace(-0.5, 0.5, n_in)
        ax_in.plot(f_in, mag_in, color='blue', alpha=0.7, label='Input')
        ax_in.set_title(f"{mtype.capitalize()} ({mode.capitalize()}) - Input")
        ax_in.grid(True)
        ax_in.set_ylim([0, 150])
        ax_in.set_xlim([-0.5, 0.5])
        ax_in.set_ylabel("Magnitude (dB)")

        if len(out) > 0:
            # Plot Output FFT
            n_out = len(out)
            win_out = np.blackman(n_out)
            fft_out = np.fft.fft(out * win_out)
            mag_out = 20 * np.log10(np.abs(np.fft.fftshift(fft_out)) + 1e-12)
            f_out = np.linspace(-0.5, 0.5, n_out)
            ax_out.plot(f_out, mag_out, color='red', alpha=0.7, label='Output')
            ax_out.set_title(f"{mtype.capitalize()} ({mode.capitalize()}) - Output")
            ax_out.grid(True)
            ax_out.set_ylim([0, 150])
            ax_out.set_xlim([-0.5, 0.5])
            ax_out.set_ylabel("Magnitude (dB)")
        else:
            print(f"Warning: No output for {mtype} ({mode})")
            ax_out.set_title(f"{mtype.capitalize()} ({mode.capitalize()}) - NO OUTPUT")

        if mtype == "interpolator" and mode == "long":
            ax_in.set_xlabel("Normalized Frequency")
            ax_out.set_xlabel("Normalized Frequency")

    plt.tight_layout(rect=[0, 0.03, 1, 0.95])
    plt.savefig("standard_half_band_sim_results.png")
    print("Simulation complete. Results saved to standard_half_band_sim_results.png")
    plt.show()

if __name__ == "__main__":
    main()
