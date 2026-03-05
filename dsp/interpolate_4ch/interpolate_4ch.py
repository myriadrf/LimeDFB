#!/usr/bin/env python3
import os

from migen import *
from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStorage
from litex.soc.interconnect.axi import AXIStreamInterface
from litex.soc.interconnect import stream


class AXIStreamRegisterSlice(LiteXModule):
    """
    Cuts combinatorial timing paths for both forward (valid/data)
    and backward (ready) signals to ensure 500MHz closure.
    """

    def __init__(self, data_width, clk_domain="sys"):
        self.sink = AXIStreamInterface(data_width, clock_domain=clk_domain)
        self.source = AXIStreamInterface(data_width, clock_domain=clk_domain)

        # A depth-2 SyncFIFO acts as a perfect register slice for streams
        self.fifo = stream.SyncFIFO([("data", data_width)], depth=2, buffered=True)
        self.fifo = ClockDomainsRenamer(clk_domain)(self.fifo)

        self.comb += [
            # Sink to FIFO
            self.sink.ready.eq(self.fifo.sink.ready),
            self.fifo.sink.valid.eq(self.sink.valid),
            self.fifo.sink.data.eq(self.sink.data),

            # FIFO to Source
            self.source.valid.eq(self.fifo.source.valid),
            self.source.data.eq(self.fifo.source.data),
            self.fifo.source.ready.eq(self.source.ready),
        ]


class _InterpolatorStage(LiteXModule):
    """
    One FIR interpolator stage (internal format preserved):
      - S_AXIS_DATA: 192-bit (8 lanes * 24-bit padded, 18-bit payload per lane)
      - M_AXIS_DATA: 192-bit (same)
    No truncation/clipping here (quantize once at the end).
    """
    def __init__(self, platform, clk_domain="sys", instance_name="fir_interp_0"):
        self.sink    = AXIStreamInterface(192, clock_domain=clk_domain)
        self.source  = AXIStreamInterface(192, clock_domain=clk_domain)
        self.aresetn = Signal()

        self._fir_m_axis = AXIStreamInterface(192, clock_domain=clk_domain)

        params_ios = dict(
            i_aresetn=self.aresetn,
            i_aclk=ClockSignal(clk_domain),

            # S_AXIS_DATA (192)
            i_s_axis_data_tvalid=self.sink.valid,
            o_s_axis_data_tready=self.sink.ready,
            i_s_axis_data_tdata=self.sink.data,

            # M_AXIS_DATA (192)
            o_m_axis_data_tvalid=self._fir_m_axis.valid,
            i_m_axis_data_tready=self._fir_m_axis.ready,
            o_m_axis_data_tdata=self._fir_m_axis.data,
        )

        self.specials += Instance("fir_compiler_interpolate", name=instance_name, **params_ios)

        # Passthrough
        self.comb += [
            self.source.valid.eq(self._fir_m_axis.valid),
            self.source.data.eq(self._fir_m_axis.data),
            self._fir_m_axis.ready.eq(self.source.ready),
        ]


class Interpolate4ch(LiteXModule):
    def __init__(self, platform, clk_domain="sys"):
        # External: 8x int16 packed => 128-bit (Q1.15)
        self.sink   = AXIStreamInterface(128, clock_domain=clk_domain)
        self.source = AXIStreamInterface(128, clock_domain=clk_domain)

        self.aresetn = Signal()

        self.stage_count = CSRStorage(3, reset=0, description="Number of active interpolator stages (0..4).")

        # Keep register space compatibility
        self.blank0 = CSRStorage(1, reset=0, description="Blank")
        self.blank1 = CSRStorage(1, reset=0, description="Blank")
        self.blank2 = CSRStorage(1, reset=0, description="Blank")

        # FIR IP now configured per your screenshot:
        #   Input:  18 bits, frac 15
        #   Output: 19 bits, frac 15
        #   Rounding: Convergent to Even
        #   AXIS in/out: 192
        xci_path = os.path.abspath("./gateware/LimeDFB/dsp/interpolate_4ch/ip/fir_compiler_interpolate.xci")
        platform.toolchain.project_commands.append(f"import_ip {xci_path}")
        platform.toolchain.project_commands.append("upgrade_ip [get_ips fir_compiler_interpolate]")
        platform.toolchain.project_commands.append("synth_ip [get_ips fir_compiler_interpolate] -force")
        platform.toolchain.project_commands.append("get_ips")

        # Internal 192-bit boundaries
        self.interpolator_stages = []
        self.boundaries = [AXIStreamInterface(192, clock_domain=clk_domain) for _ in range(5)]
        self.mux_outs   = []

        # Build 4 stages
        for i in range(4):
            st = _InterpolatorStage(platform, clk_domain=clk_domain, instance_name=f"fir_interp_{i}")
            self.interpolator_stages.append(st)
            setattr(self.submodules, f"interpolator_stage_{i}", st)
            self.comb += st.aresetn.eq(self.aresetn)

        # ---------------------------------------------------------------------
        # Input adapter: 128-bit int16 -> 192-bit lane packing
        #
        # FIR input is 18-bit signed Q1.15.
        # We sign-extend 16->18 and place into lane24[0:18], clear lane24[18:24].
        # ---------------------------------------------------------------------
        self.comb += [
            self.boundaries[0].valid.eq(self.sink.valid),
            self.sink.ready.eq(self.boundaries[0].ready),
        ]

        for i in range(8):
            x16   = self.sink.data[i*16:(i+1)*16]
            lane24 = self.boundaries[0].data[i*24:(i+1)*24]

            x18 = Signal(18)
            self.comb += x18.eq(Cat(x16, Replicate(x16[15], 2)))  # sign-extend 16->18

            self.comb += [
                lane24[0:18].eq(x18),
                lane24[18:24].eq(0),
            ]

        # ---------------------------------------------------------------------
        # Pipelined Cascade with dynamic stage_count (192-bit)
        # ---------------------------------------------------------------------
        stage_en = [Signal() for _ in range(4)]
        for i in range(4):
            self.comb += stage_en[i].eq(self.stage_count.storage > i)

        for i in range(4):
            upstream = self.boundaries[i]
            st       = self.interpolator_stages[i]

            mux_out = AXIStreamInterface(192, clock_domain=clk_domain)
            self.mux_outs.append(mux_out)

            reg_slice = AXIStreamRegisterSlice(192, clk_domain=clk_domain)
            setattr(self.submodules, f"pipe_slice_{i}", reg_slice)

            self.comb += [
                reg_slice.sink.valid.eq(mux_out.valid),
                reg_slice.sink.data.eq(mux_out.data),
                mux_out.ready.eq(reg_slice.sink.ready),

                self.boundaries[i + 1].valid.eq(reg_slice.source.valid),
                self.boundaries[i + 1].data.eq(reg_slice.source.data),
                reg_slice.source.ready.eq(self.boundaries[i + 1].ready),
            ]

            self.comb += [
                st.sink.valid.eq(0),
                st.sink.data.eq(0),
                st.source.ready.eq(0),
            ]

            self.comb += If(stage_en[i],
                st.sink.valid.eq(upstream.valid),
                st.sink.data.eq(upstream.data),
                upstream.ready.eq(st.sink.ready),

                mux_out.valid.eq(st.source.valid),
                mux_out.data.eq(st.source.data),
                st.source.ready.eq(mux_out.ready),
            ).Else(
                mux_out.valid.eq(upstream.valid),
                mux_out.data.eq(upstream.data),
                upstream.ready.eq(mux_out.ready),
            )

        # ---------------------------------------------------------------------
        # Output adapter: 192-bit (19-bit payload/lane) -> 128-bit int16 (Q1.15)
        #
        # FIR output is 19-bit signed Q1.15. External is 16-bit signed Q1.15.
        # Keep bits [15:0] (no right shift). Saturate if upper bits [18:16]
        # are not sign-extension of bit15.
        #
        # Assumes payload is LSB-aligned: lane24[0:19]. If your IP MSB-aligns
        # the payload, adjust the slice accordingly.
        # ---------------------------------------------------------------------
        out192 = self.boundaries[4]
        self.comb += [
            self.source.valid.eq(out192.valid),
            out192.ready.eq(self.source.ready),
        ]

        for i in range(8):
            lane24 = out192.data[i * 24:(i + 1) * 24]
            sample19 = Signal(19)
            self.comb += sample19.eq(lane24[0:19])

            sign_w = sample19[18]
            out16 = sample19[0:16]

            # Define overflow as a Signal so it can be used in the If() block
            ovf = Signal()
            self.comb += ovf.eq(
                (sample19[17] ^ sign_w) |
                (sample19[16] ^ sign_w) |
                (sample19[15] ^ sign_w)
            )

            clipped16 = Signal(16)
            self.comb += If(ovf,
                            If(sign_w == 0,
                               clipped16.eq(0x7FFF)
                               ).Else(
                                clipped16.eq(0x8000)
                            )
                            ).Else(
                clipped16.eq(out16)
            )

            self.comb += self.source.data[i * 16:(i + 1) * 16].eq(clipped16)
