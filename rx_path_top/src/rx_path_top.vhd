-- ----------------------------------------------------------------------------
-- FILE:          rx_path_top.vhd
-- DESCRIPTION:   describe file
-- DATE:          13:24 2024-05-15
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:     v2.0
-- ----------------------------------------------------------------------------

-- TerosHDL module description
--! Top module for packaging IQ samples received from lms7002 module into stream packets.
--!
--! Functionality:
--! - Pack IQ samples from s_axis_iqsmpls stream int Stream packets
--! - Store Stream packets into AXIS buffer.
--!
--!

-- WaveDrom timing diagrams

-- s_axis_tx bus timing (MIMO DDR mode, A and B channels enabled)
--! { signal: [
--! { name: "CLK",  wave: "P........" , period: 2},
--! { name: "RESET_N", wave: "0.1......|...|...." },
--! { name: "CFG_CH_EN[1:0]",  wave: "x.=......|=.=|....", data: ["0x3", "0x3", ""] },
--! { name: "CFG_PKT_SIZE[15:0]",  wave: "x.=......|=.=|....", data: ["0x100", "0x100", ""] },
--! ['S_AXIS_IQSMPLS',
--!  { name: "S_AXIS_IQSMPLS_ACLK",  wave: "P........" , period: 2},
--!  { name: "S_AXIS_IQSMPLS_ARESETN", wave: "0.1......|...|...." },
--!  { name: "S_AXIS_IQSMPLS_TVALID", wave: "0...1....|...|...." },
--!  { name: "S_AXIS_IQSMPLS_TDATA[63:48]",  wave: "x...=.=.=|=.=|....", data: ["AI(0)", "AI(n+5)", "", "AI(679)", "", "AI(5)"] },
--!  { name: "S_AXIS_IQSMPLS_TDATA[47:32]",  wave: "x...=.=.=|=.=|....", data: ["AQ(0)", "AQ(n+5)", "", "AQ(679)", "", "AQ(5)"] },
--!  { name: "S_AXIS_IQSMPLS_TDATA[31:16]",  wave: "x...=.=.=|=.=|....", data: ["BI(0)", "BI(n+5)", "", "BI(679)", "", "BI(5)"] },
--!  { name: "S_AXIS_IQSMPLS_TDATA[15: 0]",  wave: "x...=.=.=|=.=|....", data: ["BQ(0)", "BQ(n+5)", "", "BQ(679)", "", "BQ(5)"] },
--!  { name: "S_AXIS_IQSMPLS_TKEEP[7: 0]",  wave: "x...=...=|=.=|....", data: ["0xFF", "", "0xFF", ""] },
--!  { name: "S_AXIS_IQSMPLS_TREADY", wave: "0...1....|...|...." },
--!  { name: "S_AXIS_IQSMPLS_TLAST", wave: "0........|...|...." },
--! ],
--! { name: "SMPL_NR_OUT[63: 0]",  wave: "x...=.=.=|=.=|....", data: ["0", "n+5", "", "679", ""] },
--! ['M_AXIS_IQPACKET',
--!  { name: "M_AXIS_IQPACKET_ACLK",  wave: "P........" , period: 2},
--!  { name: "M_AXIS_IQPACKET_ARESETN", wave: "0.1..............." },
--!  { name: "M_AXIS_IQPACKET_TVALID", wave: "0.......1........." },
--!  { name: "M_AXIS_IQPACKET_TDATA[127:0]",  wave: "x.......=.=.=|=.=.", data: ["HDR", "PLD(0)", "", "PLD(254)", "",] },
--!  { name: "M_AXIS_IQPACKET_TKEEP[7: 0]",  wave: "x.......=...=|=...", data: ["0xFF", "", "0xFF"] },
--!  { name: "M_AXIS_IQPACKET_TREADY", wave: "0...1............." },
--!  { name: "M_AXIS_IQPACKETS_TLAST", wave: "0............|1.0." },
--! ]
--! ],
--!
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan',
--!           ['tspan', {'font-weight':'bold'}, 'rx_path_top module timing (MIMO DDR mode, A and B channels enabled, 4096B packet size)']],
--!     tick:0,
--!     every:2
--!   }}

-- ----------------------------------------------------------------------------
-- NOTES:
-- If S_AXIS_IQSMPLS_BUFFER or M_AXIS_IQPACKET_BUFFER are bypassed, respective bus
-- become synchronous to CLK clock domain
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use work.axis_pkg.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------

entity RX_PATH_TOP is
   generic (
      G_S_AXIS_IQSMPLS_BUFFER_WORDS    : integer := 16;
      G_M_AXIS_IQPACKET_BUFFER_WORDS   : integer := 512
   );
   port (
      CLK                     : in    std_logic;                     --! Sys clock
      RESET_N                 : in    std_logic;                     --! Sys active low reset
      --! @virtualbus S_AXIS_IQSMPLS @dir in AXI Stream Slave bus for IQ samples
      S_AXIS_IQSMPLS_ACLK     : in    std_logic;                     --!
      S_AXIS_IQSMPLS_ARESETN  : in    std_logic;                     --!
      S_AXIS_IQSMPLS_TVALID   : in    std_logic;                     --!
      S_AXIS_IQSMPLS_TREADY   : out   std_logic;                     --! Indicates when FIFO comes out of reset. Slave can allways accept data
      S_AXIS_IQSMPLS_TDATA    : in    std_logic_vector(63 downto 0); --!
      S_AXIS_IQSMPLS_TKEEP    : in    std_logic_vector(7 downto 0);  --!
      S_AXIS_IQSMPLS_TLAST    : in    std_logic;                     --! @end
      --! @virtualbus M_AXIS_IQPACKET @dir out AXI Stream Master bus for Stream packets
      M_AXIS_IQPACKET_ACLK    : in    std_logic;
      M_AXIS_IQPACKET_ARESETN : in    std_logic;
      M_AXIS_IQPACKET_TVALID  : out   std_logic;
      M_AXIS_IQPACKET_TREADY  : in    std_logic;
      M_AXIS_IQPACKET_TDATA   : out   std_logic_vector(127 downto 0);
      M_AXIS_IQPACKET_TKEEP   : out   std_logic_vector(15 downto 0);
      M_AXIS_IQPACKET_TLAST   : out   std_logic;                     --! @end
      -- Configuration ports
      --! @virtualbus CFG @dir in Configuration signals
      CFG_CH_EN               : in    std_logic_vector(1 downto 0);  --! Channel enable. 0- Channel Disabled, 1-Channel Enabled
      CFG_PKT_SIZE            : in    std_logic_vector(15 downto 0); --! Paket size in 128b words. Min=4, Max=256. @end
      --! @virtualbus SMPL_NR_IN @dir in Sample Nr. input
      SMPL_NR_EN              : in    std_logic;                     --! Enable sample number
      SMPL_NR_CLR             : in    std_logic;                     --! Cleas sample number
      SMPL_NR_LD              : in    std_logic;                     --! Load sample number
      SMPL_NR_IN              : in    std_logic_vector(63 downto 0); --! Sample Nr. when loading @end
      SMPL_NR_OUT             : out   std_logic_vector(63 downto 0); --! Sample Nr. output, synchronous to S_AXIS_IQSMPLS_ACLK
      --! @virtualbus TXFLAGS @dir in TX Flag capture
      TXFLAGS_PCT_LOSS        : in    std_logic;                     --! TX packet loss flag input
      TXFLAGS_PCT_LOSS_CLR    : in    std_logic                      --! TX packet loss flag clear @end
   );
end entity RX_PATH_TOP;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture ARCH of RX_PATH_TOP is

   -- declare signals,  components here
   signal axis_iqcombined              : t_AXI_STREAM(tdata( 63 downto 0), tkeep( 7 downto 0));
   signal axis_iqbitpacked             : t_AXI_STREAM(tdata( 63 downto 0), tkeep( 7 downto 0));
   signal axis_iq128                   : t_AXI_STREAM(tdata(127 downto 0), tkeep(15 downto 0));
   signal axis_iqsmpls_fifo            : t_AXI_STREAM(tdata(127 downto 0), tkeep(15 downto 0));
   signal axis_iqpacket_fifo           : t_AXI_STREAM(tdata(127 downto 0), tkeep(15 downto 0));
   signal axis_iqpacket_wr_data_count  : std_logic_vector(8 downto 0);

   signal sample_nr_counter            : unsigned(63 downto 0);
   signal bitpacked_sample_nr_counter  : unsigned(63 downto 0);

begin

   -- ----------------------------------------------------------------------------
   -- Sample counter dedicated for TX stream synchronization with RX
   -- ----------------------------------------------------------------------------
   SAMPLE_CNT_PROC : process (S_AXIS_IQSMPLS_ACLK, S_AXIS_IQSMPLS_ARESETN) is
   begin

      if (S_AXIS_IQSMPLS_ARESETN='0') then
         sample_nr_counter <= (others => '0');
      elsif (rising_edge(S_AXIS_IQSMPLS_ACLK)) then
         if (SMPL_NR_CLR='1') then
            sample_nr_counter <= (others => '0');
         elsif (SMPL_NR_LD='1') then
            sample_nr_counter <= unsigned(SMPL_NR_IN);
         elsif (S_AXIS_IQSMPLS_TVALID='1' and axis_iq128.tready='1') then
            sample_nr_counter <= sample_nr_counter + 1;
         end if;
      end if;

   end process SAMPLE_CNT_PROC;

   -- ----------------------------------------------------------------------------
   -- AXI Stream packager (removes null bytes from axi stream)
   -- Combine IQ samples into full 64bit bus
   -- In mimo Mode: AI AQ BI BQ
   -- In siso Mode: AI AQ AI AQ
   -- ----------------------------------------------------------------------------
   inst_iq_stream_combiner : entity work.iq_stream_combiner
      port map (
         CLK           => S_AXIS_IQSMPLS_ACLK,
         RESET_N       => S_AXIS_IQSMPLS_ARESETN,
         S_AXIS_TVALID => S_AXIS_IQSMPLS_TVALID AND axis_iq128.tready,
         S_AXIS_TREADY => open,
         S_AXIS_TDATA  => S_AXIS_IQSMPLS_TDATA,
         S_AXIS_TKEEP  => S_AXIS_IQSMPLS_TKEEP,
         M_AXIS_TVALID => axis_iqcombined.tvalid,
         M_AXIS_TDATA  => axis_iqcombined.tdata,
         M_AXIS_TKEEP  => axis_iqcombined.tkeep
      );

   -- ----------------------------------------------------------------------------
   -- Bit packer
   -- ----------------------------------------------------------------------------
   inst_bit_pack : entity work.bit_pack
      generic map (
         G_PORT_WIDTH    => 64,
         G_DISABLE_14BIT => false
      )
      port map (
         -- input ports
         CLK           => S_AXIS_IQSMPLS_ACLK,
         RESET_N       => S_AXIS_IQSMPLS_ARESETN,
         DATA_IN       => axis_iqcombined.tdata,
         DATA_IN_VALID => axis_iqcombined.tvalid,
         SAMPLE_WIDTH  => "10",
         -- output ports
         DATA_OUT       => axis_iqbitpacked.tdata,
         DATA_OUT_VALID => axis_iqbitpacked.tvalid,
         DATA_OUT_TLAST => axis_iqbitpacked.tlast
      );

   inst_axis_nto1_converter : entity work.axis_nto1_converter
      generic map (
         G_N_RATIO    => 2,
         G_DATA_WIDTH => 64
      )
      port map (
         ACLK     => S_AXIS_IQSMPLS_ACLK,
         ARESET_N => S_AXIS_IQSMPLS_ARESETN,
         -- AXIS Slave
         S_AXIS_TVALID => axis_iqbitpacked.tvalid,
         S_AXIS_TREADY => open,
         S_AXIS_TDATA  => axis_iqbitpacked.tdata,
         S_AXIS_TLAST  => axis_iqbitpacked.tlast,
         -- AXIS Master
         M_AXIS_TVALID => axis_iq128.tvalid,
         M_AXIS_TDATA  => axis_iq128.tdata,
         M_AXIS_TLAST  => axis_iq128.tlast
      );

   -- ----------------------------------------------------------------------------
   -- AXIS FIFO buffer for storing samples before packing into packets.
   -- It is neccesary to have it because we want to stall few cycles on continous IQ stream when
   -- packing header.
   -- Since data bus is converted from 64b to 128b, data2packets_fsm can safely buffer continous
   -- IQ stream.
   -- ----------------------------------------------------------------------------
   inst_axis_iqsmpls_fifo : entity work.fifo_axis_wrap
      generic map (
         G_CLOCKING_MODE => "independent_clock",
         G_FIFO_DEPTH    => G_S_AXIS_IQSMPLS_BUFFER_WORDS,
         G_TDATA_WIDTH   => 128
      )
      port map (
         S_AXIS_ARESETN => S_AXIS_IQSMPLS_ARESETN,
         S_AXIS_ACLK    => S_AXIS_IQSMPLS_ACLK,
         S_AXIS_TVALID  => axis_iq128.tvalid,
         S_AXIS_TREADY  => axis_iq128.tready,
         S_AXIS_TDATA   => axis_iq128.tdata,
         S_AXIS_TKEEP   => (others=>'1'),
         S_AXIS_TLAST   => axis_iq128.tlast,
         M_AXIS_ACLK    => CLK,
         M_AXIS_TVALID  => axis_iqsmpls_fifo.tvalid,
         M_AXIS_TREADY  => axis_iqsmpls_fifo.tready,
         M_AXIS_TDATA   => axis_iqsmpls_fifo.tdata,
         M_AXIS_TKEEP   => axis_iqsmpls_fifo.tkeep,
         M_AXIS_TLAST   => axis_iqsmpls_fifo.tlast
      );

   -- ----------------------------------------------------------------------------
   -- Sample counter dedicated for forming RX packets
   -- ----------------------------------------------------------------------------
   PACKET_SAMPLE_CNT_PROC : process (CLK, RESET_N) is
   begin

      if (RESET_N='0') then
         bitpacked_sample_nr_counter <= (others => '0');
      elsif (rising_edge(CLK)) then
         if (SMPL_NR_CLR='1') then
            bitpacked_sample_nr_counter <= (others => '0');
         elsif (SMPL_NR_LD='1') then
            bitpacked_sample_nr_counter <= unsigned(SMPL_NR_IN);
         elsif (axis_iqsmpls_fifo.tvalid='1' and axis_iqsmpls_fifo.tlast='1' and axis_iqsmpls_fifo.tready ='1') then
            -- If both channels are enabled in one frame we have packed 8 samples for each A and B channel
            if (CFG_CH_EN = "11") then
               bitpacked_sample_nr_counter <= bitpacked_sample_nr_counter + 8;
            else
               bitpacked_sample_nr_counter <= bitpacked_sample_nr_counter + 16;
            end if;
         end if;
      end if;

   end process PACKET_SAMPLE_CNT_PROC;

   inst_data2packets_fsm : entity work.data2packets_fsm
      port map (
         ACLK      => CLK,
         ARESET_N  => RESET_N,
         PCT_SIZE  => CFG_PKT_SIZE,
         PCT_HDR_0 => x"7766554433221100",
         PCT_HDR_1 => std_logic_vector(bitpacked_sample_nr_counter),
         -- AXIS Slave
         S_AXIS_TVALID => axis_iqsmpls_fifo.tvalid,
         S_AXIS_TREADY => axis_iqsmpls_fifo.tready,
         S_AXIS_TDATA  => axis_iqsmpls_fifo.tdata,
         S_AXIS_TLAST  => axis_iqsmpls_fifo.tlast,
         -- AXIS Master
         M_AXIS_TVALID      => axis_iqpacket_fifo.tvalid,
         M_AXIS_TREADY      => axis_iqpacket_fifo.tready,
         M_AXIS_TDATA       => axis_iqpacket_fifo.tdata,
         M_AXIS_TLAST       => axis_iqpacket_fifo.tlast,
         WR_DATA_COUNT_AXIS => axis_iqpacket_wr_data_count
      );

   -- ----------------------------------------------------------------------------
   -- IQ Packets
   -- Optional FIFO buffer for S_AXIS_IQPACKETS
   -- ----------------------------------------------------------------------------

   ADD_M_AXIS_IQPACKET_BUFFER : if G_M_AXIS_IQPACKET_BUFFER_WORDS > 0 generate

      inst_axis_iqpacket_fifo : entity work.fifo_axis_wrap
         generic map (
            G_CLOCKING_MODE       => "independent_clock",
            G_FIFO_DEPTH          => G_M_AXIS_IQPACKET_BUFFER_WORDS,
            G_TDATA_WIDTH         => 128,
            G_WR_DATA_COUNT_WIDTH => 9
         )
         port map (
            S_AXIS_ARESETN     => S_AXIS_IQSMPLS_ARESETN,
            S_AXIS_ACLK        => CLK,
            S_AXIS_TVALID      => axis_iqpacket_fifo.tvalid,
            S_AXIS_TREADY      => axis_iqpacket_fifo.tready,
            S_AXIS_TDATA       => axis_iqpacket_fifo.tdata,
            S_AXIS_TLAST       => axis_iqpacket_fifo.tlast,
            M_AXIS_ACLK        => M_AXIS_IQPACKET_ACLK,
            M_AXIS_TVALID      => M_AXIS_IQPACKET_TVALID,
            M_AXIS_TREADY      => M_AXIS_IQPACKET_TREADY,
            M_AXIS_TDATA       => M_AXIS_IQPACKET_TDATA,
            M_AXIS_TLAST       => M_AXIS_IQPACKET_TLAST,
            WR_DATA_COUNT_AXIS => axis_iqpacket_wr_data_count
         );

   end generate ADD_M_AXIS_IQPACKET_BUFFER;

   -- Bypass FIFO if G_M_AXIS_IQPACKET_BUFFER_WORDS=0

   WITHOUT_M_AXIS_IQPACKET_BUFFER : if G_M_AXIS_IQPACKET_BUFFER_WORDS = 0 generate
      M_AXIS_IQPACKET_TVALID    <= axis_iqpacket_fifo.tvalid;
      axis_iqpacket_fifo.tready <= M_AXIS_IQPACKET_TREADY;
      M_AXIS_IQPACKET_TDATA     <= axis_iqpacket_fifo.tdata;
      M_AXIS_IQPACKET_TLAST     <= axis_iqpacket_fifo.tlast;
   end generate WITHOUT_M_AXIS_IQPACKET_BUFFER;

   -- ----------------------------------------------------------------------------
   -- Output ports
   -- ----------------------------------------------------------------------------
   -- Connecting to FIFO because iq_stream_combiner, bit_pack, axis_nto1_converter
   -- are always ready to accept data after reset. FIFO needs some time to become ready
   -- after reset
   S_AXIS_IQSMPLS_TREADY <= axis_iq128.tready;

end architecture ARCH;







