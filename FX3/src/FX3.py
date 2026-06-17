from litex.soc.interconnect.axi import AXIStreamInterface
from litex.soc.interconnect.stream import SyncFIFO, Endpoint
from migen import *
from litex.gen import *
from litex.soc.interconnect.csr import *
import math

from gateware.common import add_vhd2v_converter


#helper functions
def fifo_words_to_nbits(n_words: int, add_msb: bool) -> int:
    # math.log2 returns a float, ceil rounds it up to the next integer
    bits = math.ceil(math.log2(n_words))

    if add_msb:
        return bits + 1
    return bits

# FX3 ----------------------------------------------------------------------------------------------
# This module assumes that sys clk is actually FX3_PCLK. If that is not the case, please use a ClockDomainsRenamer and
# other appropriate CDC measures.

class FX3(LiteXModule):
    def __init__(self, platform, pads, vendor="altera",
                 EP01_size    = 4096,  # Stream PC->FPGA, FIFO size in bytes, same size for FX3_EP01_0 and FX3_EP01_1
                 EP01_0_rwidth= 32,   # Stream PC->FPGA, FIFO rd width, FIFO number - 0
                 EP01_1_rwidth= 32,    # Stream PC->FPGA, FIFO rd width, FIFO number - 1
                 EP81_size    = 16384, # Stream FPGA->PC, FIFO size in bytes
                 EP81_wwidth  = 32,    # Stream FPGA->PC, FIFO wr width
                 EP0F_size    = 1024,  # Control PC->FPGA, FIFO size in bytes
                 EP0F_rwidth  = 32,    # Control PC->FPGA, rd width
                 EP8F_size    = 1024,  # Control FPGA->PC, FIFO size in bytes
                 EP8F_wwidth  = 32,):  # Control FPGA->PC, wr width
        self.pads = pads
        self.platform = platform

        # FX3 data throughput is bottlenecked by 32 bit interface
        # no need to support other widths for now
        # rely on external modules to adapt the data width, if needed
        assert EP01_0_rwidth == 32, "EP01_0_rwidth values other than 32 bits are not supported yet"
        assert EP01_1_rwidth == 32, "EP01_1_rwidth values other than 32 bits are not supported yet"
        assert EP81_wwidth == 32, "EP81_wwidth values other than 32 bits are not supported yet"
        assert EP0F_rwidth == 32, "EP0F_rwidth values other than 32 bits are not supported yet"
        assert EP8F_wwidth == 32, "EP8F_wwidth values other than 32 bits are not supported yet"

        self.usb_speed   = Signal(reset=1) # 0 - USB2, 1 - USB3
        self.busy_out    = Signal()
        self.data_source_sel  = Signal()
        self.data_source0_clr = Signal()
        self.data_source1_clr = Signal()
        self.data_sink_clr    = Signal()
        self.ctrl_sink_clr    = Signal()

        self.data_sink = AXIStreamInterface(EP81_wwidth)
        self.data_source = AXIStreamInterface(EP01_0_rwidth)
        self.data_source_1 = AXIStreamInterface(EP01_1_rwidth)

        # Control Interface
        self._fifo_wdata = CSRStorage(32, description="FIFO Write Register.")
        self._fifo_rdata = CSRStatus(32, description="FIFO Read Register.")
        self._fifo_status = CSRStatus(description="FIFO Status Register.", fields=[
            CSRField("is_rdempty", size=1, offset=0, description="Read FIFO is empty."),
            CSRField("is_wrfull", size=1, offset=1, description="Write FIFO is full."),
        ])
        self._fifo_control = CSRStorage(description="FIFO Control Register.", fields=[
            CSRField("reset", size=1, offset=0, description="Reset Control (Active High)."),
        ])

        #internal variables
        ep01_0_rdusedw_width = fifo_words_to_nbits(EP01_size//(EP01_0_rwidth//8), add_msb=True)
        # ep01_1_rdusedw_width = fifo_words_to_nbits(EP01_size//(EP01_1_rwidth//8), add_msb=True)
        ep81_wrusedw_width   = fifo_words_to_nbits(EP81_size//(EP81_wwidth//8), add_msb=True)
        ep0f_rdusedw_width   = fifo_words_to_nbits(EP0F_size//(EP0F_rwidth//8), add_msb=True)
        ep8f_wrusedw_width   = fifo_words_to_nbits(EP8F_size//(EP8F_wwidth//8), add_msb=True)

        #internal signals
        self._faddr     = Signal(5)
        self._GPIF_busy = Signal()
        self._socket0_fifo_data  = Signal(32)
        self._socket0_fifo_usedw = Signal(ep01_0_rdusedw_width)
        self._socket0_fifo_wr    = Signal()
        self._payload_extract_sink_data    = Signal(32)
        self._payload_extract_sink_valid   = Signal()
        self._payload_extract_source_data  = Signal(32)
        self._payload_extract_source_valid = Signal()

        # FIFO's
        # # Host -> FPGA data FIFOs
        self.source_data_fifo_0 = ResetInserter()(SyncFIFO(
            layout=[("data", 32)],
            depth=EP01_size//(EP01_0_rwidth//8),
            buffered=True))
        self.source_data_fifo_1 = ResetInserter()(SyncFIFO(
            layout=[("data", 32)],
            depth=EP01_size//(EP01_1_rwidth//8),
            buffered=True))
        # # FPGA -> Host data FIFO
        self.sink_data_fifo = ResetInserter()(SyncFIFO(
            layout=[("data", 32)],
            depth=EP81_size//(EP81_wwidth//8),
            buffered=True))
        # # Host -> FPGA control FIFO
        self.source_ctrl_fifo = ResetInserter()(SyncFIFO(
            layout=[("data", 32)],
            depth=EP0F_size//(EP0F_rwidth//8),
            buffered=True))
        # # FPGA -> Host control FIFO
        self.sink_ctrl_fifo = ResetInserter()(SyncFIFO(
            layout=[("data", 32)],
            depth=EP8F_size//(EP8F_wwidth//8),
            buffered=True))

        # Host -> FPGA data fifo muxing
        self.comb +=[
            self.source_data_fifo_0.sink.data.eq(self._socket0_fifo_data),
            self._payload_extract_sink_data.eq(self._socket0_fifo_data),
            self.source_data_fifo_1.sink.data.eq(self._payload_extract_source_data),
            self.source_data_fifo_1.sink.valid.eq(self._payload_extract_source_valid),
            If(self.data_source_sel == 0,[
                self.source_data_fifo_0.sink.valid.eq(self._socket0_fifo_wr),
                self._payload_extract_sink_valid.eq(0),
                self._socket0_fifo_usedw.eq(self.source_data_fifo_0.level),
            ]).Else([
                self.source_data_fifo_0.sink.valid.eq(0),
                self._payload_extract_sink_valid.eq(self._socket0_fifo_wr),
                self._socket0_fifo_usedw.eq(self.source_data_fifo_1.level),
            ])
        ]

        # Connect fifos to sinks/sources
        self.comb += [
            self.data_sink.connect(self.sink_data_fifo.sink,omit=["keep","id","dest","user"]),
            self.source_data_fifo_0.source.connect(self.data_source,omit=["keep","id","dest","user"]),
            self.source_data_fifo_1.source.connect(self.data_source_1,omit=["keep","id","dest","user"]),
        ]

        # FIFO clear signals
        self.comb += [
            self.source_data_fifo_0.reset.eq(self.data_source0_clr),
            self.source_data_fifo_1.reset.eq(self.data_source1_clr),
            self.sink_data_fifo.reset.eq(self.data_sink_clr),
            self.sink_ctrl_fifo.reset.eq(self.ctrl_sink_clr | self._fifo_control.fields.reset),
            self.source_ctrl_fifo.reset.eq(self._fifo_control.fields.reset),
        ]

        # Control Interface logic
        self.comb += [
            # Host -> FPGA (CPU Reads)
            self.source_ctrl_fifo.source.ready.eq(self._fifo_rdata.we),
            self._fifo_rdata.status.eq(self.source_ctrl_fifo.source.data),
            self._fifo_status.fields.is_rdempty.eq(~self.source_ctrl_fifo.source.valid),

            # FPGA -> Host (CPU Writes)
            self.sink_ctrl_fifo.sink.data.eq(self._fifo_wdata.storage),
            self.sink_ctrl_fifo.sink.valid.eq(self._fifo_wdata.re),
            self._fifo_status.fields.is_wrfull.eq(~self.sink_ctrl_fifo.sink.ready),
        ]

        # Slave FIFO 5b Instance -------------------------------------------------------------------
        self.slaveFIFO5b = Instance("slaveFIFO5b",
            # Parameters
            p_num_of_sockets       = 4,
            p_data_width           = 32,
            p_data_dma_size        = 4096,
            p_control_dma_size     = 4096,
            p_data_pct_size        = 4096,
            p_control_pct_size     = 64,
            p_socket0_wrusedw_size = ep01_0_rdusedw_width,
            p_socket0_rdusedw_size = ep01_0_rdusedw_width,
            p_socket1_wrusedw_size = ep0f_rdusedw_width,
            p_socket1_rdusedw_size = ep0f_rdusedw_width,
            p_socket2_wrusedw_size = ep81_wrusedw_width,
            p_socket2_rdusedw_size = ep81_wrusedw_width,
            p_socket3_wrusedw_size = ep8f_wrusedw_width,
            p_socket3_rdusedw_size = ep8f_wrusedw_width,

            # Ports
            i_reset_n              = ~ResetSignal("sys"),
            i_clk                  = ClockSignal("sys"),
            o_clk_out              = Open(),
            i_usb_speed            = self.usb_speed,
            o_slcs                 = pads.ctl0,
            io_fdata               = pads.dq,
            o_faddr                = self._faddr,
            o_slrd                 = pads.ctl3,
            o_sloe                 = pads.ctl2,
            o_slwr                 = pads.ctl1,
            i_flaga                = pads.ctl4,
            i_flagb                = pads.ctl5,
            i_flagc                = Constant(0),
            i_flagd                = Constant(0),
            o_pktend               = pads.ctl7,
            o_EPSWITCH             = Open(),

            # Socket 0 (PC -> FPGA Data)
            i_socket0_fifo_reset_n = ~ResetSignal("sys"),
            o_socket0_fifo_data    = self._socket0_fifo_data,
            i_socket0_fifo_q       = Constant(0,32),
            i_socket0_fifo_wrusedw = self._socket0_fifo_usedw,
            i_socket0_fifo_rdusedw = Constant(0),
            o_socket0_fifo_wr      = self._socket0_fifo_wr,
            o_socket0_fifo_rd      = Open(),

            # Socket 1 (PC -> FPGA Control)
            i_socket1_fifo_reset_n = ~ResetSignal("sys"),
            o_socket1_fifo_data    = self.source_ctrl_fifo.sink.data,
            i_socket1_fifo_q       = Constant(0,32),
            i_socket1_fifo_wrusedw = self.source_ctrl_fifo.level,
            i_socket1_fifo_rdusedw = Constant(0),
            o_socket1_fifo_wr      = self.source_ctrl_fifo.sink.valid,
            o_socket1_fifo_rd      = Open(),

            # Socket 2 (FPGA -> PC Data)
            o_socket2_fifo_data    = Open(),
            i_socket2_fifo_q       = self.sink_data_fifo.source.data,
            i_socket2_fifo_wrusedw = Constant(0),
            i_socket2_fifo_rdusedw = self.sink_data_fifo.level,
            o_socket2_fifo_wr      = Open(),
            o_socket2_fifo_rd      = self.sink_data_fifo.source.ready,

            # Socket 3 (FPGA -> PC Control)
            o_socket3_fifo_data    = Open(),
            i_socket3_fifo_q       = self.sink_ctrl_fifo.source.data,
            i_socket3_fifo_wrusedw = Constant(0),
            i_socket3_fifo_rdusedw = self.sink_ctrl_fifo.level,
            o_socket3_fifo_wr      = Open(),
            o_socket3_fifo_rd      = self.sink_ctrl_fifo.source.ready,

            o_GPIF_busy            = self._GPIF_busy,
        )

        self.comb += [
            pads.ctl12.eq(self._faddr[0]),
            pads.ctl11.eq(self._faddr[1]),
            self.busy_out.eq(self._GPIF_busy | pads.ctl8)
        ]

        # Packet Payload Extract Instance ----------------------------------------------------------
        self.pct_payload_extrct = Instance("pct_payload_extrct",
            # Parameters
            p_data_w      = 32,
            p_header_size = 16,
            p_pct_size    = 4096,

            # Ports
            i_clk               = ClockSignal("sys"),
            i_reset_n           = ~ResetSignal("sys"),
            i_pct_data          = self._payload_extract_sink_data,
            i_pct_wr            = self._payload_extract_sink_valid,
            o_pct_payload_data  = self._payload_extract_source_data,
            o_pct_payload_valid = self._payload_extract_source_valid,
            o_pct_payload_dest  = Open(),
        )

        self.pct_payload_extrct_conv = add_vhd2v_converter(self.platform,
            instance = self.pct_payload_extrct,
            files    = ["gateware/LimeDFB/FX3/src/pct_payload_extrct.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.pct_payload_extrct)

        self.slaveFIFO5b_conv = add_vhd2v_converter(self.platform,
            instance = self.slaveFIFO5b,
            files    = ["gateware/LimeDFB/FX3/src/slaveFIFO5b.vhd"],
        )
        # Removed Instance to avoid multiple definition
        self._fragment.specials.remove(self.slaveFIFO5b)


        # Constraints
        if vendor == "altera":
            # 1. Timing Parameters
            fx3_period = 10.0
            fx3_tDS = 2.0
            fx3_tDH = 0.50
            fx3_tSU = 2.0
            fx3_tH = 0.5

            fx3_tCO_max = 8.0
            fx3_tCO_min = 1.0
            fx3_tCFLG_max = 8.0
            fx3_tCFLG_min = 1.0

            # 2. Calculated Delays
            fx3_d_in_max_dly   = fx3_tCO_max
            fx3_d_in_min_dly   = fx3_tCO_min
            fx3_ctl_in_max_dly = fx3_tCFLG_max
            fx3_ctl_in_min_dly = fx3_tCFLG_min

            fx3_d_out_max_dly   = fx3_tDS
            fx3_d_out_min_dly   = -fx3_tDH
            fx3_ctl_out_max_dly = fx3_tSU
            fx3_ctl_out_min_dly = -fx3_tH

            # 3. Construct SDC Commands
            sdc_commands = [
                # # Clocks
                # f"create_clock -period 1000.000 -name BRDG_SPI_SCLK [get_ports {{FX3_spi_clk}}]",
                # f"create_clock -period {fx3_period:.3f} -name FX3_PCLK [get_ports {{FX3_pclk}}]",
                f"create_clock -name FX3_PCLK_VIRT -period {fx3_period:.3f}",
                f"create_clock -name FX3_PCLK_VIRT_OUT -period {fx3_period:.3f}",

                # Input Constraints
                f"set_input_delay -clock [get_clocks FX3_PCLK_VIRT] -max {fx3_ctl_in_max_dly:.3f} [get_ports {{FX3_ctl4 FX3_ctl5 FX3_ctl8}}]",
                f"set_input_delay -clock [get_clocks FX3_PCLK_VIRT] -min {fx3_ctl_in_min_dly:.3f} [get_ports {{FX3_ctl4 FX3_ctl5 FX3_ctl8}}]",
                f"set_input_delay -clock [get_clocks FX3_PCLK_VIRT] -max {fx3_d_in_max_dly:.3f} [get_ports {{FX3_dq[*]}}]",
                f"set_input_delay -clock [get_clocks FX3_PCLK_VIRT] -min {fx3_d_in_min_dly:.3f} [get_ports {{FX3_dq[*]}}]",

                # Output Constraints
                f"set_output_delay -clock [get_clocks FX3_PCLK_VIRT_OUT] -max {fx3_ctl_out_max_dly:.3f} [get_ports {{FX3_ctl0 FX3_ctl1 FX3_ctl2 FX3_ctl3 FX3_ctl7 FX3_ctl11 FX3_ctl12}}]",
                f"set_output_delay -clock [get_clocks FX3_PCLK_VIRT_OUT] -min {fx3_ctl_out_min_dly:.3f} [get_ports {{FX3_ctl0 FX3_ctl1 FX3_ctl2 FX3_ctl3 FX3_ctl7 FX3_ctl11 FX3_ctl12}}]",
                f"set_output_delay -clock [get_clocks FX3_PCLK_VIRT_OUT] -max {fx3_d_out_max_dly:.3f} [get_ports {{FX3_dq[*]}}]",
                f"set_output_delay -clock [get_clocks FX3_PCLK_VIRT_OUT] -min {fx3_d_out_min_dly:.3f} [get_ports {{FX3_dq[*]}}]",

                # Exceptions
                f"set_false_path -to [get_ports {{FX3_ctl2}}]"
            ]

            # 4. Inject into the SDC generation flow
            for cmd in sdc_commands:
                platform.toolchain.additional_sdc_commands.append(cmd)
        else:
            raise ValueError("FX3: Unsupported FPGA vendor: {}. Constraints for this vendor not defined".format(vendor))

