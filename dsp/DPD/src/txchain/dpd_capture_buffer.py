from migen import *
from migen.genlib.cdc import MultiReg

from litex.gen import *
from litex.soc.interconnect.axi import *
from litex.soc.interconnect.axi.axi_lite import axi_lite_to_simple

class Mmap12ToAXILite32(LiteXModule):
    """
    128-bit memory write-side RAM exposed as 32-bit AXI-Lite mmap.

    CPU side:
        AXI-Lite, 32-bit, usually sys clock domain.

    Memory write side:
        128-bit write port, usually sample/high-speed clock domain.

    CPU address layout:

        base + 16*n + 0x0  -> mem_data[ 31:  0]
        base + 16*n + 0x4  -> mem_data[ 63: 32]
        base + 16*n + 0x8  -> mem_data[ 95: 64]
        base + 16*n + 0xc  -> mem_data[127: 96]

    One 128-bit memory row = four CPU-visible 32-bit words.
    """

    def __init__(self,
                 size=0x20000,
                 axi_domain="sys",
                 mem_domain="sys",
                 mem_addr_width=13,
                 mem_addr_shift=0,
                 mem_we_active_low=False):

        # Each 128-bit memory row is 16 bytes.
        assert size % 16 == 0

        row_depth = size // 16
        row_bits  = log2_int(row_depth)

        # Make sure selected memory address slice fits.
        assert mem_addr_shift + row_bits <= mem_addr_width

        # ---------------------------------------------------------------------
        # Public interfaces
        # ---------------------------------------------------------------------

        self.bus = AXILiteInterface(
            address_width = 32,
            data_width    = 32,
            clock_domain  = axi_domain,
        )

        self.mem_en   = Signal()
        self.mem_we   = Signal()
        self.mem_addr = Signal(mem_addr_width)
        self.mem_data = Signal(128)

        # ---------------------------------------------------------------------
        # Four 32-bit banks make one logical 128-bit row
        # ---------------------------------------------------------------------

        banks = [
            Memory(32, row_depth, name=f"mmap12_bank{i}")
            for i in range(4)
        ]

        cpu_ports = [
            mem.get_port(
                write_capable  = True,
                we_granularity = 8,
                mode           = WRITE_FIRST,
                clock_domain   = axi_domain,
            )
            for mem in banks
        ]

        mem_ports = [
            mem.get_port(
                write_capable  = True,
                we_granularity = 8,
                mode           = WRITE_FIRST,
                clock_domain   = mem_domain,
            )
            for mem in banks
        ]

        for mem, cpu_port, mem_port in zip(banks, cpu_ports, mem_ports):
            self.specials += mem, cpu_port, mem_port

        # ---------------------------------------------------------------------
        # AXI-Lite CPU side
        # ---------------------------------------------------------------------

        cpu_word_adr = Signal(row_bits + 2)
        cpu_row      = Signal(row_bits)
        cpu_lane     = Signal(2)

        cpu_dat_r = Signal(32)
        cpu_dat_w = Signal(32)
        cpu_we    = Signal(4)
        cpu_re    = Signal()

        # Synchronous RAM read data arrives one cycle after the read address.
        # Latch the selected 32-bit lane to keep the read-data mux aligned.
        cpu_lane_r = Signal(2)

        self.comb += [
            cpu_lane.eq(cpu_word_adr[0:2]),
            cpu_row.eq(cpu_word_adr[2:]),
        ]

        sync_axi = getattr(self.sync, axi_domain)
        sync_axi += [
            If(cpu_re,
                cpu_lane_r.eq(cpu_lane)
            )
        ]

        for i in range(4):
            self.comb += [
                cpu_ports[i].adr.eq(cpu_row),
                cpu_ports[i].dat_w.eq(cpu_dat_w),

                # Only selected 32-bit bank receives CPU byte-lane strobes.
                cpu_ports[i].we.eq(Mux(cpu_lane == i, cpu_we, 0)),
            ]

        self.comb += cpu_dat_r.eq(
            Array([p.dat_r for p in cpu_ports])[cpu_lane_r]
        )

        fsm, comb = axi_lite_to_simple(
            axi_lite   = self.bus,
            port_adr   = cpu_word_adr,
            port_dat_r = cpu_dat_r,
            port_dat_w = cpu_dat_w,
            port_re    = cpu_re,
            port_we    = cpu_we,
        )

        self.axi_lite_fsm = fsm
        self.comb += comb

        # ---------------------------------------------------------------------
        # Memory write side
        # ---------------------------------------------------------------------
        #
        # mem_addr_shift selects address unit conversion:
        #
        #   mem_addr_shift = 0  if mem_addr addresses 128-bit rows
        #   mem_addr_shift = 2  if mem_addr addresses 32-bit words
        #   mem_addr_shift = 4  if mem_addr addresses bytes
        #
        # mem_we_active_low:
        #
        #   False -> write when mem_en &  mem_we
        #   True  -> write when mem_en & ~mem_we
        # ---------------------------------------------------------------------

        mem_row = Signal(row_bits)
        mem_wr  = Signal()

        self.comb += mem_row.eq(
            self.mem_addr[mem_addr_shift:mem_addr_shift + row_bits]
        )

        if mem_we_active_low:
            self.comb += mem_wr.eq(self.mem_en & ~self.mem_we)
        else:
            self.comb += mem_wr.eq(self.mem_en & self.mem_we)

        for i in range(4):
            self.comb += [
                mem_ports[i].adr.eq(mem_row),
                mem_ports[i].dat_w.eq(self.mem_data[32*i:32*(i + 1)]),

                # Full 32-bit write into each bank when memory write is active.
                mem_ports[i].we.eq(Replicate(mem_wr, 4)),
            ]

class DPDCaptureBuffer(LiteXModule):
    def __init__(self,
                 platform,
                 size              = 0x20000,
                 axi_domain        = "sys",
                 clk_domain        = "sys",
                 data_width        = 128,
                 addr_width        = 13
                 ):

        assert data_width == 128
        assert size % 16 == 0

        # Control interface
        self.reset_n     = Signal(reset=1)
        self.start_write = Signal()
        self.full        = Signal()

        start_write_sync = Signal()



        # ---------------------------------------------------------------------
        # External sample inputs, expected to be synchronous to clk_domain.
        # ---------------------------------------------------------------------
        self.xpi = Signal(16)  # pre-DPD I
        self.xpq = Signal(16)  # pre-DPD Q

        self.ypi = Signal(16)  # post-DPD I
        self.ypq = Signal(16)  # post-DPD Q

        self.xi  = Signal(16)  # feedback/RX I
        self.xq  = Signal(16)  # feedback/RX Q


        # ---------------------------------------------------------------------
        # Sample capture module
        # ---------------------------------------------------------------------
        from gateware.LimeDFB.dsp.DPD.src.txchain.bram_write import BRAMWrite
        self.bram_write = BRAMWrite(platform, data_width, addr_width, clk_domain)

        self.comb += [
            self.bram_write.xpi.eq(self.xpi),
            self.bram_write.xpq.eq(self.xpq),

            self.bram_write.ypi.eq(self.ypi),
            self.bram_write.ypq.eq(self.ypq),

            self.bram_write.xi.eq(self.xi),
            self.bram_write.xq.eq(self.xq),

            self.bram_write.reset_n.eq(self.reset_n),
            self.bram_write.start_write.eq(start_write_sync),
        ]

        # Sync external signal to correct domains
        self.specials += MultiReg(i=self.start_write, o=start_write_sync, odomain=clk_domain)
        self.specials += MultiReg(i=self.bram_write.full, o=self.full, odomain=axi_domain)


        # ---------------------------------------------------------------------
        # MMAP RAM exposed to CPU
        # ---------------------------------------------------------------------

        self.ram_mmap = Mmap12ToAXILite32(
            size              = size,
            axi_domain        = axi_domain,
            mem_domain        = clk_domain,
            mem_addr_width    = addr_width,

            # Use 0 if mem_addrb already addresses 128-bit rows.
            # Use 2 if mem_addrb addresses 32-bit words.
            # Use 4 if mem_addrb addresses bytes.
            mem_addr_shift    = 0,

            # Check VHDL polarity.
            # If mem_web means "write enable bar", keep True.
            # If mem_web is active-high write enable, set False.
            mem_we_active_low = False,
        )

        # Expose AXI-Lite bus to SoC.
        self.mmap = self.ram_mmap.bus

        self.comb += [
            self.ram_mmap.mem_en.eq(self.bram_write.enb),
            self.ram_mmap.mem_we.eq(self.bram_write.web),
            self.ram_mmap.mem_addr.eq(self.bram_write.addrb),
            self.ram_mmap.mem_data.eq(self.bram_write.doutb),
        ]
