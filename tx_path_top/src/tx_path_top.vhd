-- ----------------------------------------------------------------------------
-- FILE:          tx_path_top.vhd
-- DESCRIPTION:   Top module for tx path
-- DATE:          June 25 2024
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

-- TerosHDL module description
--! Top module for unpacking stream packets, performing timestamp synchronisation if needed
--!
--! Functionality:
--! - Perform timestamp synchronisation
--! - Unpack stream packets
--! - Output the data in a format suitable for lms7002_top module

-- Wavedrom timing diagrams

--! { signal: [
--!    { name: "CLK",  wave: "P......." , period: 2},
--!    { name: "RESET_N", wave: "0.1......|...|.." },
--!    { name: "CFG_CH_EN[1:0]",  wave: "x.=......|...|..", data: ["0x3", "0x3", ""] },
--!    { name: "CFG_SAMPLE_WIDTH[1:0]",  wave: "x.=......|...|..", data: ["0x0", "0x0", ""] },
--!   
--!   
--!    ],
--!   
--!    "config" : { "hscale" : 1 },
--!     head:{
--!        text: ['tspan',
--!              ['tspan', {'font-weight':'bold'}, 'Control signals (MIMO mode, 4096B packet size, 16 bit sample width)']],
--!        tick:0,
--!        every:2
--!      }}

--! { signal: [
--!     { name: "S_AXIS_IQPACKET_ACLK",  wave: "P......." , period: 2},
--!     { name: "S_AXIS_IQPACKET_ARESETN", wave: "0.1........|...." },
--!     { name: "S_AXIS_IQPACKET_TVALID", wave: "0...1......|..0." },
--!     { name: "S_AXIS_IQPACKET_TREADY", wave: "0.....1....|...." },
--!     { name: "S_AXIS_IQPACKET_TDATA[127:0]",  wave: "x...=...=.=|=.x.", data: ["HDR", "PLD(0)", "", "PLD(254)", "",] },
--!     { name: "S_AXIS_IQPACKETS_TLAST", wave: "0..........|...." },
--!   
--!    ],
--!   
--!    "config" : { "hscale" : 1 },
--!     head:{
--!        text: ['tspan',
--!              ['tspan', {'font-weight':'bold'}, 'S_AXIS_IQPACKET timing (MIMO mode, 4096B packet size, 16 bit sample width)']],
--!        tick:0,
--!        every:2
--!      }}

--! { signal: [
--!     { name: "M_AXIS_IQSAMPLE_ACLK",  wave: "P......." , period: 2},
--!     { name: "M_AXIS_IQSAMPLE_ARESETN", wave: "0.1..|.....|...." },
--!     { name: "M_AXIS_IQSAMPLE_TVALID", wave: "0....|1....|...." },
--!     { name: "M_AXIS_IQSAMPLE_TREADY", wave: "0....|1....|...|" },
--!     { name: "M_AXIS_IQSAMPLE_TDATA[63:48]",  wave: "x....|=.=.=|=.=|", data: ["AI(0)", "AI(1)", "", "AI(509)", "", "AI(5)"] },
--!     { name: "M_AXIS_IQSAMPLE_TDATA[47:32]",  wave: "x....|=.=.=|=.=|", data: ["AQ(0)", "AQ(1)", "", "AQ(509)", "", "AQ(5)"] },
--!     { name: "M_AXIS_IQSAMPLE_TDATA[31:16]",  wave: "x....|=.=.=|=.=|", data: ["BI(0)", "BI(1)", "", "BI(509)", "", "BI(5)"] },
--!     { name: "M_AXIS_IQSAMPLE_TDATA[15: 0]",  wave: "x....|=.=.=|=.=|", data: ["BQ(0)", "BQ(1)", "", "BQ(509)", "", "BQ(5)"] },
--!     { name: "M_AXIS_IQSAMPLE_TLAST", wave: "0....|.....|...|" },
--!   
--!   
--!    ],
--!   
--!    "config" : { "hscale" : 1 },
--!     head:{
--!        text: ['tspan',
--!              ['tspan', {'font-weight':'bold'}, 'M_AXIS_IQSAMPLE timing (MIMO mode, 4096B packet size, 16 bit sample width)']],
--!        tick:0,
--!        every:2
--!      }}
    
    
  

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use work.axis_pkg.all;
   use work.tx_top_pkg.t_s_axis_tdata_array;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------

entity TX_PATH_TOP is
   generic (
      G_BUFF_COUNT  : integer := 4 --! Number of packet buffers to use. Recommended values are 2 or 4
   );
   port (
      RESET_N                       : in    std_logic;                                   --! Reset, active low
      --! @virtualbus s_axis_iqpacket @dir in AXIS bus for receiving packets
      S_AXIS_IQPACKET_ARESET_N      : in    std_logic;                                   --! S_AXIS interface active low reset
      S_AXIS_IQPACKET_ACLK          : in    std_logic;                                   --! S_AXIS interface clock
      S_AXIS_IQPACKET_TVALID        : in    std_logic;                                   --! S_AXIS interface data valid
      S_AXIS_IQPACKET_TDATA         : in    std_logic_vector(63 downto 0);               --! S_AXIS interface data
      S_AXIS_IQPACKET_TREADY        : out   std_logic;                                   --! S_AXIS interface data ready
      S_AXIS_IQPACKET_TLAST         : in    std_logic;                                   --! S_AXIS interface data last (unused) @end
      --! @virtualbus m_axis_iqsample @dir out AXIS bus for outputting IQ samples
      M_AXIS_IQSAMPLE_ARESET_N      : in    std_logic;                                   --! M_AXIS interface active low reset
      M_AXIS_IQSAMPLE_ACLK          : in    std_logic;                                   --! M_AXIS interface clock
      M_AXIS_IQSAMPLE_TVALID        : out   std_logic;                                   --! M_AXIS interface data valid
      M_AXIS_IQSAMPLE_TDATA         : out   std_logic_vector(63 downto 0);               --! M_AXIS interface data
      M_AXIS_IQSAMPLE_TREADY        : in    std_logic;                                   --! M_AXIS interface data ready
      M_AXIS_IQSAMPLE_TLAST         : out   std_logic;                                   --! M_AXIS interface data last (unused) @end

      RX_SAMPLE_NR                  : in    std_logic_vector(63 downto 0);               --! Sample number to use for timestamp sync
      RX_CLK                        : in    std_logic;                                   --! Clock that RX_SAMPLE_NR is generated with

      PCT_SYNC_DIS                  : in    std_logic;                                   --! Disable timestamp sync

      PCT_LOSS_FLG                  : out   std_logic;                                   --! Goes high when a packet is dropped due to outdated timestamp, stays high until PCT_LOSS_FLG_CLR is set
      PCT_LOSS_FLG_CLR              : in    std_logic;                                   --! Clears PCT_LOSS_FLG

      -- Mode settings
      CFG_CH_EN                     : in    std_logic_vector(1 downto 0);                --! Channel enable. "01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B.
      CFG_SAMPLE_WIDTH              : in    std_logic_vector(1 downto 0)                 --! Sample width. "10"-12bit, "00"-16bit;
   );
end entity TX_PATH_TOP;

architecture BEHAVIORAL of TX_PATH_TOP is

   signal axis_iqpacket_tvalid  : std_logic;
   signal axis_iqpacket_tready  : std_logic;
   signal axis_iqpacket_tdata   : std_logic_vector(127 downto 0);
   signal axis_iqpacket_tlast   : std_logic;

   signal p2d_wr_m_axis_areset_n             : std_logic;
   signal p2d_wr_m_axis_tvalid               : std_logic_vector(G_BUFF_COUNT - 1 downto 0);
   signal p2d_wr_m_axis_tdata                : std_logic_vector(127 downto 0);
   signal p2d_wr_m_axis_tready               : std_logic_vector(G_BUFF_COUNT - 1 downto 0);
   signal p2d_wr_m_axis_tlast                : std_logic_vector(G_BUFF_COUNT - 1 downto 0);
   signal p2d_wr_buf_empty                   : std_logic_vector(G_BUFF_COUNT - 1 downto 0);

   signal p2d_rd_s_axis_areset_n             : std_logic;
   signal p2d_rd_s_axis_buf_reset_n          : std_logic_vector(G_BUFF_COUNT - 1 downto 0);
   signal p2d_rd_s_axis_tvalid               : std_logic_vector(G_BUFF_COUNT - 1 downto 0);
   signal p2d_rd_s_axis_tdata                : T_S_AXIS_TDATA_ARRAY(G_BUFF_COUNT - 1 downto 0);
   signal p2d_rd_s_axis_tready               : std_logic_vector(G_BUFF_COUNT - 1 downto 0);
   signal p2d_rd_s_axis_tlast                : std_logic_vector(G_BUFF_COUNT - 1 downto 0);

   signal rx_sample_nr_reg                   : std_logic_vector(RX_SAMPLE_NR'left downto 0);
   signal rx_sample_nr_wr                    : std_logic;
   signal rx_sample_nr_rd                    : std_logic;
   signal pct_loss_flg_clr_reg               : std_logic;
   signal pct_loss_flg_clr_reg_reg           : std_logic;

   signal unpack_bypass                      : std_logic;   

   attribute async_reg                         : string;
   attribute async_reg of pct_loss_flg_clr_reg     : signal is "true";
   attribute async_reg of pct_loss_flg_clr_reg_reg : signal is "true";

   constant C_P2D_FIFO_USEDWW                : integer := 9;

   type T_USEDW_VECTOR is array(G_BUFF_COUNT - 1 downto 0) of std_logic_vector(C_P2D_FIFO_USEDWW - 1 downto 0);

   signal usedw_vector                       : T_USEDW_VECTOR;

   -- type t_axis_array is array (natural range <>) of t_AXI_STREAM(tdata(127 downto 0),tkeep(0 downto 0));

   type T_AXIS_ARRAY is array (G_BUFF_COUNT - 1 downto 0) of t_AXI_STREAM(tdata(127 downto 0), tkeep(0 downto 0));

   signal p2d_wr_axis                        : T_AXIS_ARRAY;
   signal p2d_rd_axis                        : T_AXIS_ARRAY;
   signal smpl_unpack_axis                   : t_AXI_STREAM(tdata(127 downto 0), tkeep(0 downto 0));
   signal smpl_buf_axis                      : t_AXI_STREAM(tdata(127 downto 0), tkeep(0 downto 0));
   signal data_pad_axis                      : t_AXI_STREAM(tdata(127 downto 0), tkeep(0 downto 0));
   
   COMPONENT axis_dwidth_converter_64_to_128
   PORT (
      aclk : IN STD_LOGIC;
      aresetn : IN STD_LOGIC;
      s_axis_tvalid : IN STD_LOGIC;
      s_axis_tready : OUT STD_LOGIC;
      s_axis_tdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      s_axis_tlast : IN STD_LOGIC;
      m_axis_tvalid : OUT STD_LOGIC;
      m_axis_tready : IN STD_LOGIC;
      m_axis_tdata : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
      m_axis_tlast : OUT STD_LOGIC 
   );
   END COMPONENT;
   	

begin

   CDC : process (M_AXIS_IQSAMPLE_ACLK, M_AXIS_IQSAMPLE_ARESET_N) is
   begin

      if (M_AXIS_IQSAMPLE_ARESET_N = '0') then
         pct_loss_flg_clr_reg     <= '0';
         pct_loss_flg_clr_reg_reg <= '0';
      elsif rising_edge(M_AXIS_IQSAMPLE_ACLK) then
         pct_loss_flg_clr_reg     <= PCT_LOSS_FLG_CLR;
         pct_loss_flg_clr_reg_reg <= pct_loss_flg_clr_reg;
      end if;

   end process CDC;

   rx_sample_nr_cdc : entity work.fifo_axis_wrap
      generic map (
         G_CLOCKING_MODE       => "independent_clock",
         G_PACKET_FIFO         => "false",
         G_FIFO_DEPTH          => 128,
         G_TDATA_WIDTH         => 64,
         G_RD_DATA_COUNT_WIDTH => 8,
         G_WR_DATA_COUNT_WIDTH => 8
      )
      port map (
         S_AXIS_ARESETN     => S_AXIS_IQPACKET_ARESET_N and RESET_N,
         S_AXIS_ACLK        => RX_CLK,
         S_AXIS_TVALID      => rx_sample_nr_wr,
         S_AXIS_TREADY      => rx_sample_nr_wr,
         S_AXIS_TDATA       => RX_SAMPLE_NR,
         S_AXIS_TLAST       => '0',
         M_AXIS_ACLK        => M_AXIS_IQSAMPLE_ACLK,
         M_AXIS_TVALID      => rx_sample_nr_rd,
         M_AXIS_TREADY      => rx_sample_nr_rd,
         M_AXIS_TDATA       => rx_sample_nr_reg,
         M_AXIS_TLAST       => open,
         ALMOST_EMPTY_AXIS  => open,
         ALMOST_FULL_AXIS   => open,
         RD_DATA_COUNT_AXIS => open,
         WR_DATA_COUNT_AXIS => open
      );


   axis_dwidth_converter_64_to_128_inst : axis_dwidth_converter_64_to_128
   port map(
      aclk           => S_AXIS_IQPACKET_ACLK,
      aresetn        => S_AXIS_IQPACKET_ARESET_N,
      s_axis_tvalid  => S_AXIS_IQPACKET_TVALID,
      s_axis_tready  => S_AXIS_IQPACKET_TREADY,
      s_axis_tdata   => S_AXIS_IQPACKET_TDATA,
      s_axis_tlast   => S_AXIS_IQPACKET_TLAST,
      m_axis_tvalid  => axis_iqpacket_tvalid,
      m_axis_tready  => axis_iqpacket_tready,
      m_axis_tdata   => axis_iqpacket_tdata,
      m_axis_tlast   => axis_iqpacket_tlast
   );

   inst0_pct2data_buf_wr : entity work.pct2data_buf_wr
      generic map (
         G_BUFF_COUNT => G_BUFF_COUNT
      )
      port map (
         AXIS_ACLK       => S_AXIS_IQPACKET_ACLK,
         S_AXIS_ARESET_N => S_AXIS_IQPACKET_ARESET_N,
         S_AXIS_TVALID   => axis_iqpacket_tvalid,
         S_AXIS_TDATA    => axis_iqpacket_tdata,
         S_AXIS_TREADY   => axis_iqpacket_tready,
         S_AXIS_TLAST    => axis_iqpacket_tlast,
         M_AXIS_ARESET_N => S_AXIS_IQPACKET_ARESET_N,
         M_AXIS_TVALID   => p2d_wr_m_axis_tvalid,
         M_AXIS_TDATA    => p2d_wr_m_axis_tdata,
         M_AXIS_TREADY   => p2d_wr_m_axis_tready,
         M_AXIS_TLAST    => p2d_wr_m_axis_tlast,
         BUF_EMPTY       => p2d_wr_buf_empty,
         RESET_N         => RESET_N
      );

   P2D_WR_LOOP : for i in 0 to G_BUFF_COUNT - 1 generate
      p2d_wr_buf_empty(i)     <= '0' when unsigned(usedw_vector(i))>0 else
                                 '1';
      p2d_wr_axis(i).tvalid   <= p2d_wr_m_axis_tvalid(i);
      p2d_wr_axis(i).tdata    <= p2d_wr_m_axis_tdata;
      p2d_wr_axis(i).tlast    <= p2d_wr_m_axis_tlast(i);
      p2d_wr_m_axis_tready(i) <= p2d_wr_axis(i).tready;
      p2d_wr_axis(i).tkeep    <= (others => '1');
   end generate P2D_WR_LOOP;

   ----------------------------------------------------------------------------
   -- Generated FIFO buffers
   ----------------------------------------------------------------------------

   GEN_FIFO : for i in 0 to G_BUFF_COUNT - 1 generate

      inst1_inst_fifo_axis_wrap : entity work.fifo_axis_wrap
         generic map (
            G_CLOCKING_MODE       => "independent_clock",
            G_PACKET_FIFO         => "true",
            G_FIFO_DEPTH          => 256,
            G_TDATA_WIDTH         => 128,
            G_RD_DATA_COUNT_WIDTH => C_P2D_FIFO_USEDWW,
            G_WR_DATA_COUNT_WIDTH => C_P2D_FIFO_USEDWW
         )
         port map (
            S_AXIS_ARESETN     => S_AXIS_IQPACKET_ARESET_N and p2d_rd_s_axis_buf_reset_n(i) and RESET_N,
            S_AXIS_ACLK        => S_AXIS_IQPACKET_ACLK,
            S_AXIS_TVALID      => p2d_wr_axis(i).tvalid,
            S_AXIS_TREADY      => p2d_wr_axis(i).tready,
            S_AXIS_TDATA       => p2d_wr_axis(i).tdata,
            S_AXIS_TLAST       => p2d_wr_axis(i).tlast,
            M_AXIS_ACLK        => M_AXIS_IQSAMPLE_ACLK,
            M_AXIS_TVALID      => p2d_rd_axis(i).tvalid,
            M_AXIS_TREADY      => p2d_rd_axis(i).tready,
            M_AXIS_TDATA       => p2d_rd_axis(i).tdata,
            M_AXIS_TLAST       => p2d_rd_axis(i).tlast,
            ALMOST_EMPTY_AXIS  => open,
            ALMOST_FULL_AXIS   => open,
            RD_DATA_COUNT_AXIS => open,
            WR_DATA_COUNT_AXIS => usedw_vector(i)
         );

   end generate GEN_FIFO;

   inst2_pct2data_buf_rd : entity work.pct2data_buf_rd
      generic map (
         G_BUFF_COUNT => G_BUFF_COUNT
      )
      port map (
         AXIS_ACLK          => M_AXIS_IQSAMPLE_ACLK,
         S_AXIS_ARESET_N    => M_AXIS_IQSAMPLE_ARESET_N,
         S_AXIS_BUF_RESET_N => p2d_rd_s_axis_buf_reset_n,
         S_AXIS_TVALID      => p2d_rd_s_axis_tvalid,
         S_AXIS_TDATA       => p2d_rd_s_axis_tdata,
         S_AXIS_TREADY      => p2d_rd_s_axis_tready,
         S_AXIS_TLAST       => p2d_rd_s_axis_tlast,
         M_AXIS_ARESET_N    => M_AXIS_IQSAMPLE_ARESET_N,
         M_AXIS_TVALID      => data_pad_axis.tvalid,
         M_AXIS_TDATA       => data_pad_axis.tdata,
         M_AXIS_TREADY      => data_pad_axis.tready,
         M_AXIS_TLAST       => data_pad_axis.tlast,
         RESET_N            => RESET_N,
         SYNCH_DIS          => PCT_SYNC_DIS,
         SAMPLE_NR          => rx_sample_nr_reg,
         PCT_LOSS_FLG       => PCT_LOSS_FLG,
         PCT_LOSS_FLG_CLR   => pct_loss_flg_clr_reg_reg
      );

   P2D_RD_LOOP : for i in 0 to G_BUFF_COUNT - 1 generate
      p2d_rd_s_axis_tvalid(i) <= p2d_rd_axis(i).tvalid;
      p2d_rd_s_axis_tdata(i)  <= p2d_rd_axis(i).tdata;
      p2d_rd_s_axis_tlast(i)  <= p2d_rd_axis(i).tlast;
      p2d_rd_axis(i).tready   <= p2d_rd_s_axis_tready(i);
      p2d_rd_axis(i).tkeep    <= (others => '1');
   end generate P2D_RD_LOOP;

-- ----------------------------------------------------------------------------
-- Pad 12 bit samples to 16 bit samples, bypass logic if no padding is needed 
-- ----------------------------------------------------------------------------
  unpack_bypass <= '1' when CFG_SAMPLE_WIDTH = "00" else '0';
  inst3_0_unpack_128_to_48 : entity work.sample_padder
  port map (
    --input ports 
    clk       		=> M_AXIS_IQSAMPLE_ACLK,
    reset_n   		=> RESET_N,
    --
    S_AXIS_TVALID	=> data_pad_axis.tvalid,
    S_AXIS_TDATA  => data_pad_axis.tdata,
    S_AXIS_TREADY => data_pad_axis.tready,
    S_AXIS_TLAST	=> data_pad_axis.tlast,
    --
    M_AXIS_TDATA  => smpl_buf_axis.tdata,
    M_AXIS_TVALID	=> smpl_buf_axis.tvalid,
    M_AXIS_TREADY => smpl_buf_axis.tready,
    M_AXIS_TLAST	=> smpl_buf_axis.tlast,
    --
    BYPASS			=> unpack_bypass
  );



   inst3_1_mini_sample_buffer : entity work.fifo_axis_wrap
   generic map (
      G_CLOCKING_MODE       => "common_clock",
      G_PACKET_FIFO         => "false",
      G_FIFO_DEPTH          => 16,
      G_TDATA_WIDTH         => 128,
      G_RD_DATA_COUNT_WIDTH => 5,
      G_WR_DATA_COUNT_WIDTH => 5
   )
   port map (
      S_AXIS_ARESETN     => RESET_N,
      S_AXIS_ACLK        => M_AXIS_IQSAMPLE_ACLK,
      S_AXIS_TVALID      => smpl_buf_axis.tvalid,
      S_AXIS_TREADY      => smpl_buf_axis.tready,
      S_AXIS_TDATA       => smpl_buf_axis.tdata,
      S_AXIS_TLAST       => smpl_buf_axis.tlast,
      M_AXIS_ACLK        => M_AXIS_IQSAMPLE_ACLK,
      M_AXIS_TVALID      => smpl_unpack_axis.tvalid,
      M_AXIS_TREADY      => smpl_unpack_axis.tready,
      M_AXIS_TDATA       => smpl_unpack_axis.tdata,
      M_AXIS_TLAST       => smpl_unpack_axis.tlast,
      ALMOST_EMPTY_AXIS  => open,
      ALMOST_FULL_AXIS   => open,
      RD_DATA_COUNT_AXIS => open,
      WR_DATA_COUNT_AXIS => open
   );

   

   inst3_sample_unpack : entity work.sample_unpack
      port map (
         RESET_N       => RESET_N,
         AXIS_ACLK     => M_AXIS_IQSAMPLE_ACLK,
         AXIS_ARESET_N => M_AXIS_IQSAMPLE_ARESET_N,
         S_AXIS_TDATA  => smpl_unpack_axis.tdata,
         S_AXIS_TREADY => smpl_unpack_axis.tready,
         S_AXIS_TVALID => smpl_unpack_axis.tvalid,
         S_AXIS_TLAST  => smpl_unpack_axis.tlast,
         M_AXIS_TDATA  => M_AXIS_IQSAMPLE_TDATA,
         M_AXIS_TREADY => M_AXIS_IQSAMPLE_TREADY,
         M_AXIS_TVALID => M_AXIS_IQSAMPLE_TVALID,
         CH_EN         => CFG_CH_EN
      );

   M_AXIS_IQSAMPLE_TLAST <= '0';

end architecture BEHAVIORAL;

