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


class _DecimatorStage(LiteXModule):
    """One FIR decimator stage (18-bit -> 16-bit with signed saturation/clipping)"""

    def __init__(self, platform, clk_domain="sys", instance_name="fir0"):
        self.sink    = AXIStreamInterface(128, clock_domain=clk_domain)
        self.source  = AXIStreamInterface(128, clock_domain=clk_domain)
        self.aresetn = Signal()

        self._fir_m_axis = AXIStreamInterface(192, clock_domain=clk_domain)

        params_ios = dict(
            i_aresetn=self.aresetn,
            i_aclk=ClockSignal(clk_domain),
            i_s_axis_data_tvalid=self.sink.valid,
            o_s_axis_data_tready=self.sink.ready,
            i_s_axis_data_tdata=self.sink.data,
            o_m_axis_data_tvalid=self._fir_m_axis.valid,
            i_m_axis_data_tready=self._fir_m_axis.ready,
            o_m_axis_data_tdata=self._fir_m_axis.data,
        )

        self.specials += Instance("fir_compiler_decimate", name=instance_name, **params_ios)

        # Handshake passthrough
        self.comb += [
            self.source.valid.eq(self._fir_m_axis.valid),
            self._fir_m_axis.ready.eq(self.source.ready),
        ]

        # Repack + clip each of 8 lanes
        for i in range(8):
            lane24   = self._fir_m_axis.data[i*24:(i+1)*24]
            sample18 = lane24[0:18]      # bits [17:0]
            sign     = sample18[17]
            overflow = sample18[16]
            out16    = sample18[1:17]    # bits [16:1] (your extraction)

            clipped16 = Signal(16)

            # If sign bit and next MSB disagree => overflow => saturate
            self.comb += If(sign ^ overflow,
                If(sign == 0,
                    clipped16.eq(0x7FFF)   # +32767
                ).Else(
                    clipped16.eq(0x8000)   # -32768
                )
            ).Else(
                clipped16.eq(out16)
            )

            self.comb += self.source.data[i*16:(i+1)*16].eq(clipped16)


class Decimate4ch(LiteXModule):
    def __init__(self, platform, clk_domain="sys"):
        self.sink = AXIStreamInterface(128, clock_domain=clk_domain)
        self.source = AXIStreamInterface(128, clock_domain=clk_domain)
        self.aresetn = Signal()
        # Stage count config
        self.stage_count = CSRStorage(3, reset=0, description="Number of active decimator stages (0..4).")

        # Dumb workaround to have same register space as previuos implementation
        self.blank0 = CSRStorage(1, reset=0, description="Blank")
        self.blank1 = CSRStorage(1, reset=0, description="Blank")
        self.blank2 = CSRStorage(1, reset=0, description="Blank")

        xci_path = os.path.abspath("./gateware/LimeDFB/dsp/decimate_4ch/ip/fir_compiler_decimate.xci")
        platform.toolchain.project_commands.append(f"import_ip {xci_path}")
        platform.toolchain.project_commands.append("upgrade_ip [get_ips fir_compiler_decimate]")
        platform.toolchain.project_commands.append("synth_ip [get_ips fir_compiler_decimate] -force")
        platform.toolchain.project_commands.append("get_ips")

        # ---------------------------------------------------------------------
        # Expose Stages and Boundaries as Class Attributes for Debugging
        # ---------------------------------------------------------------------
        self.decimator_stages = []
        self.boundaries = [AXIStreamInterface(128, clock_domain=clk_domain) for _ in range(5)]
        self.mux_outs = [] # To tap into the combinatorial output of each bypass mux

        # Build 4 stages
        for i in range(4):
            st = _DecimatorStage(platform, clk_domain=clk_domain, instance_name=f"fir{i}")
            self.decimator_stages.append(st)
            # Use setattr to give the submodule a precise name in the generated Verilog
            setattr(self.submodules, f"decimator_stage_{i}", st)
            self.comb += st.aresetn.eq(self.aresetn)

        # ---------------------------------------------------------------------
        # Pipelined Cascade with dynamic stage_count
        # ---------------------------------------------------------------------

        self.comb += [
            self.boundaries[0].valid.eq(self.sink.valid),
            self.boundaries[0].data.eq(self.sink.data),
            self.sink.ready.eq(self.boundaries[0].ready),
        ]

        stage_en = [Signal() for _ in range(4)]
        for i in range(4):
            self.comb += stage_en[i].eq(self.stage_count.storage > i)

        # Wire each stage with bypass mux and pipeline register slice
        for i in range(4):
            upstream = self.boundaries[i]
            st = self.decimator_stages[i]

            # Internal interface representing the combinational output of the mux
            mux_out = AXIStreamInterface(128, clock_domain=clk_domain)
            self.mux_outs.append(mux_out)

            # Instantiate the pipeline slice for this boundary
            reg_slice = AXIStreamRegisterSlice(128, clk_domain=clk_domain)
            setattr(self.submodules, f"pipe_slice_{i}", reg_slice)

            # Connect mux_out to the register slice, and the register slice to the downstream boundary
            self.comb += [
                reg_slice.sink.valid.eq(mux_out.valid),
                reg_slice.sink.data.eq(mux_out.data),
                mux_out.ready.eq(reg_slice.sink.ready),

                self.boundaries[i + 1].valid.eq(reg_slice.source.valid),
                self.boundaries[i + 1].data.eq(reg_slice.source.data),
                reg_slice.source.ready.eq(self.boundaries[i + 1].ready),
            ]

            # Default-safe idles for the stage (overridden when enabled)
            self.comb += [
                st.sink.valid.eq(0),
                st.sink.data.eq(0),
                st.source.ready.eq(0),
            ]

            self.comb += If(stage_en[i],
                            # Feed stage from upstream
                            st.sink.valid.eq(upstream.valid),
                            st.sink.data.eq(upstream.data),
                            upstream.ready.eq(st.sink.ready),

                            # Stage output goes to combinational mux_out
                            mux_out.valid.eq(st.source.valid),
                            mux_out.data.eq(st.source.data),
                            st.source.ready.eq(mux_out.ready),
                            ).Else(
                # Bypass directly to combinational mux_out
                mux_out.valid.eq(upstream.valid),
                mux_out.data.eq(upstream.data),
                upstream.ready.eq(mux_out.ready),
            )

        # Final pipelined boundary drives the top-level source
        self.comb += [
            self.source.valid.eq(self.boundaries[4].valid),
            self.source.data.eq(self.boundaries[4].data),
            self.boundaries[4].ready.eq(self.source.ready),
        ]
