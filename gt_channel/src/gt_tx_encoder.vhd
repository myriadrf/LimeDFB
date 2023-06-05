-- ----------------------------------------------------------------------------
-- FILE:          gt_tx_encoder.vhd
-- DESCRIPTION:   Modules muxes control and data packets into one AXIS stream
-- DATE:          09:58 2023-05-11
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity gt_tx_encoder is
   generic(
      g_PKT_HEADER_WIDTH      : integer := 128;
      g_I_AXIS_DWIDTH         : integer := 128;
      g_S_AXIS_0_DWIDTH       : integer := 512;
      g_S_AXIS_0_BUFFER_WORDS : integer := 16;
      g_S_AXIS_1_DWIDTH       : integer := 128;
      g_S_AXIS_1_BUFFER_WORDS : integer := 512;
      g_S_AXIS_1_TLAST_PERIOD : integer := 62;
      g_M_AXIS_DWIDTH         : integer := 32;
      g_M_AXIS_BUFFER_WORDS   : integer := 1024
   );
   port (
      --AXI stream slave
      s_axis_0_aclk     : in  std_logic;
      s_axis_0_aresetn  : in  std_logic;
      s_axis_0_tvalid   : in  std_logic;
      s_axis_0_tready   : out std_logic;
      s_axis_0_tdata    : in  std_logic_vector(g_S_AXIS_0_DWIDTH-1 downto 0);
      s_axis_0_tlast    : in  std_logic;
      --AXI stream slave
      s_axis_1_aclk     : in  std_logic;
      s_axis_1_aresetn  : in  std_logic;
      s_axis_1_tvalid   : in  std_logic;
      s_axis_1_tready   : out std_logic;
      s_axis_1_tdata    : in  std_logic_vector(g_S_AXIS_1_DWIDTH-1 downto 0);
      s_axis_1_tlast    : in  std_logic;
      -- Control signals
      s_axis_0_arb_req_supress : in std_logic;
      s_axis_1_arb_req_supress : in std_logic;
      --AXI stream master
      m_axis_aclk       : in  std_logic;
      m_axis_aresetn    : in  std_logic;
      m_axis_tvalid     : out std_logic; 
      m_axis_tready     : in  std_logic;
      m_axis_tdata      : out std_logic_vector(g_M_AXIS_DWIDTH-1 downto 0);
      m_axis_tlast      : out std_logic
   );
end gt_tx_encoder;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of gt_tx_encoder is
--declare signals,  components here
signal axis_0_fifo_tdata      : std_logic_vector(g_S_AXIS_0_DWIDTH-1 downto 0);
signal axis_0_fifo_tlast      : std_logic;
signal axis_0_fifo_tready     : std_logic;
signal axis_0_fifo_tvalid     : std_logic;

signal axis_1_fifo_tdata      : std_logic_vector(g_S_AXIS_1_DWIDTH-1 downto 0);
signal axis_1_fifo_tlast      : std_logic;
signal axis_1_fifo_tready     : std_logic;
signal axis_1_fifo_tvalid     : std_logic;

signal ctrl_pkt_axis_tdata    : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal ctrl_pkt_axis_tlast    : std_logic;
signal ctrl_pkt_axis_tready   : std_logic;
signal ctrl_pkt_axis_tvalid   : std_logic;

signal s_data_pkt_axis_tdata  : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal s_data_pkt_axis_tlast  : std_logic;
signal s_data_pkt_axis_tready : std_logic;
signal s_data_pkt_axis_tvalid : std_logic;

signal m_data_pkt_axis_tdata  : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal m_data_pkt_axis_tlast  : std_logic;
signal m_data_pkt_axis_tready : std_logic;
signal m_data_pkt_axis_tvalid : std_logic;

signal pkt_axis_tdata         : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal pkt_axis_tlast         : std_logic;
signal pkt_axis_tready        : std_logic;
signal pkt_axis_tvalid        : std_logic;

signal pkt_axis_32b_tdata     : std_logic_vector(g_M_AXIS_DWIDTH-1 downto 0);
signal pkt_axis_32b_tlast     : std_logic;
signal pkt_axis_32b_tready    : std_logic;
signal pkt_axis_32b_tvalid    : std_logic;

begin
   
-- ----------------------------------------------------------------------------
-- Control packets
-- Optional FIFO buffer for s0_axis 
-- ----------------------------------------------------------------------------
   ADD_S0_AXIS_BUFFER : if g_S_AXIS_0_BUFFER_WORDS > 0 generate 
      inst1_axis_0_fifo: entity work.fifo_axis_wrap
      generic map(
         g_CLOCKING_MODE=> "independent_clock",
         g_FIFO_DEPTH   => g_S_AXIS_0_BUFFER_WORDS,
         g_TDATA_WIDTH  => g_S_AXIS_0_DWIDTH
      )
      port map(
         s_axis_aresetn => s_axis_0_aresetn,
         s_axis_aclk    => s_axis_0_aclk,
         s_axis_tvalid  => s_axis_0_tvalid,
         s_axis_tready  => s_axis_0_tready,
         s_axis_tdata   => s_axis_0_tdata,
         s_axis_tlast   => s_axis_0_tlast,
         m_axis_aclk    => m_axis_aclk,
         m_axis_tvalid  => axis_0_fifo_tvalid,
         m_axis_tready  => axis_0_fifo_tready,
         m_axis_tdata   => axis_0_fifo_tdata, 
         m_axis_tlast   => axis_0_fifo_tlast  
      );
   end generate ADD_S0_AXIS_BUFFER;
   
   --Bypass FIFO if g_S_AXIS_0_BUFFER_WORDS=0
   WITHOUT_S0_AXIS_BUFFER : if g_S_AXIS_0_BUFFER_WORDS = 0 generate 
      axis_0_fifo_tvalid  <= s_axis_0_tvalid;
      s_axis_0_tready     <= axis_0_fifo_tready;
      axis_0_fifo_tdata   <= s_axis_0_tdata;
      axis_0_fifo_tlast   <= s_axis_0_tlast;
   end generate WITHOUT_S0_AXIS_BUFFER;


   inst2: entity work.ctrl_pkt 
   generic map(
      g_CTRL_DWIDTH  => g_S_AXIS_0_DWIDTH,
      g_AXIS_DWIDTH  => g_I_AXIS_DWIDTH
   )
   port map(
      clk            => m_axis_aclk,
      reset_n        => m_axis_aresetn,
      ctrl_data      => axis_0_fifo_tdata,
      ctrl_valid     => axis_0_fifo_tvalid,
      ctrl_ready     => axis_0_fifo_tready,
      m_axis_tdata   => ctrl_pkt_axis_tdata,
      m_axis_tlast   => ctrl_pkt_axis_tlast,
      m_axis_tready  => ctrl_pkt_axis_tready,
      m_axis_tvalid  => ctrl_pkt_axis_tvalid
   );
   
-- ----------------------------------------------------------------------------
-- Data packets
-- Optional FIFO buffer for s1_axis 
-- ----------------------------------------------------------------------------
   ADD_S1_AXIS_BUFFER : if g_S_AXIS_1_BUFFER_WORDS > 0 generate 
      inst3_axis_1_fifo: entity work.fifo_axis_wrap
      generic map(
         g_CLOCKING_MODE=> "independent_clock",
         g_FIFO_DEPTH   =>  g_S_AXIS_1_BUFFER_WORDS,
         g_TDATA_WIDTH  =>  g_S_AXIS_1_DWIDTH
      )
      port map(
         s_axis_aresetn => s_axis_1_aresetn,
         s_axis_aclk    => s_axis_1_aclk,
         s_axis_tvalid  => s_axis_1_tvalid,
         s_axis_tready  => s_axis_1_tready,
         s_axis_tdata   => s_axis_1_tdata,
         s_axis_tlast   => s_axis_1_tlast,
         m_axis_aclk    => m_axis_aclk,
         m_axis_tvalid  => axis_1_fifo_tvalid,
         m_axis_tready  => axis_1_fifo_tready,
         m_axis_tdata   => axis_1_fifo_tdata, 
         m_axis_tlast   => axis_1_fifo_tlast  
      );
   end generate ADD_S1_AXIS_BUFFER;
   
   --Bypass FIFO if g_S_AXIS_1_BUFFER_WORDS=0
   WITHOUT_S1_AXIS_BUFFER : if g_S_AXIS_1_BUFFER_WORDS = 0 generate 
      axis_1_fifo_tvalid   <= s_axis_1_tvalid;
      s_axis_0_tready      <= axis_1_fifo_tready;
      axis_1_fifo_tdata    <= s_axis_1_tdata;
      axis_1_fifo_tlast    <= s_axis_1_tlast;
   end generate WITHOUT_S1_AXIS_BUFFER;
   
   
   inst4: entity work.axi4_tlast_gen
   generic map(
      g_DATA_WIDTH    => g_S_AXIS_1_DWIDTH,
      g_LAST_PERIOD   => g_S_AXIS_1_TLAST_PERIOD
   )
   port map(
   clk                => m_axis_aclk,
   reset_n            => m_axis_aresetn,
   axi_s_data         => axis_1_fifo_tdata,
   axi_s_ready        => axis_1_fifo_tready,
   axi_s_valid        => axis_1_fifo_tvalid,
   axi_m_data         => s_data_pkt_axis_tdata,
   axi_m_ready        => s_data_pkt_axis_tready,
   axi_m_valid        => s_data_pkt_axis_tvalid,
   axi_m_last         => s_data_pkt_axis_tlast
   );
   
   inst5: entity work.data_pkt
   generic map (
      g_PKT_HEADER_WIDTH   => g_PKT_HEADER_WIDTH,
      g_DATA_DWIDTH        => g_S_AXIS_1_DWIDTH,
      g_AXIS_DWIDTH        => g_I_AXIS_DWIDTH
   )
   port map(
      clk            => m_axis_aclk,
      reset_n        => m_axis_aresetn,
      s_axis_tdata   => s_data_pkt_axis_tdata,
      s_axis_tlast   => s_data_pkt_axis_tlast,
      s_axis_tready  => s_data_pkt_axis_tready,
      s_axis_tvalid  => s_data_pkt_axis_tvalid, 
      m_axis_tdata   => m_data_pkt_axis_tdata,
      m_axis_tlast   => m_data_pkt_axis_tlast,
      m_axis_tready  => m_data_pkt_axis_tready,
      m_axis_tvalid  => m_data_pkt_axis_tvalid 
   );
   
-- ----------------------------------------------------------------------------
-- Combine control and data packets into one AXIS stream
-- ----------------------------------------------------------------------------   
   inst6_axis_interconn : entity work.axis_interconnect_0
   PORT MAP (
      ACLK                 => m_axis_aclk,
      ARESETN              => m_axis_aresetn,
      
      S00_AXIS_ACLK        => m_axis_aclk,
      S00_AXIS_ARESETN     => m_axis_aresetn,
      S00_AXIS_TVALID      => ctrl_pkt_axis_tvalid,
      S00_AXIS_TREADY      => ctrl_pkt_axis_tready,
      S00_AXIS_TDATA       => ctrl_pkt_axis_tdata,
      S00_AXIS_TLAST       => ctrl_pkt_axis_tlast,
      
      S01_AXIS_ACLK        => m_axis_aclk,
      S01_AXIS_ARESETN     => m_axis_aresetn,
      S01_AXIS_TVALID      => m_data_pkt_axis_tvalid,
      S01_AXIS_TREADY      => m_data_pkt_axis_tready,
      S01_AXIS_TDATA       => m_data_pkt_axis_tdata,
      S01_AXIS_TLAST       => m_data_pkt_axis_tlast,
      
      M00_AXIS_ACLK        => m_axis_aclk,
      M00_AXIS_ARESETN     => m_axis_aresetn,
      M00_AXIS_TVALID      => pkt_axis_tvalid,
      M00_AXIS_TREADY      => pkt_axis_tready,
      M00_AXIS_TDATA       => pkt_axis_tdata,
      M00_AXIS_TLAST       => pkt_axis_tlast,
      
      S00_ARB_REQ_SUPPRESS => s_axis_0_arb_req_supress,
      S01_ARB_REQ_SUPPRESS => s_axis_1_arb_req_supress
   );
  
  
-- ----------------------------------------------------------------------------
-- Converting AXIS data width
-- ---------------------------------------------------------------------------- 
   inst7_axis_dwidth : entity work.axis_dwidth_128_to_32
   port map (
      aclk           => m_axis_aclk,
      aresetn        => m_axis_aresetn,
      s_axis_tvalid  => pkt_axis_tvalid,
      s_axis_tready  => pkt_axis_tready,
      s_axis_tdata   => pkt_axis_tdata,
      s_axis_tlast   => pkt_axis_tlast,
      m_axis_tvalid  => pkt_axis_32b_tvalid,
      m_axis_tready  => pkt_axis_32b_tready,
      m_axis_tdata   => pkt_axis_32b_tdata,
      m_axis_tlast   => pkt_axis_32b_tlast
   );
    
-- ----------------------------------------------------------------------------
-- Packet Buffering 
-- Optional FIFO buffer for m_axis 
-- ----------------------------------------------------------------------------
   ADD_M_AXIS_BUFFER : if g_M_AXIS_BUFFER_WORDS > 0 generate 
      inst1_m_axis_fifo: entity work.fifo_axis_wrap
      generic map(
         g_CLOCKING_MODE=> "independent_clock",
         g_FIFO_DEPTH   =>  g_M_AXIS_BUFFER_WORDS,
         g_TDATA_WIDTH  =>  g_M_AXIS_DWIDTH
      )
      port map(
         s_axis_aresetn => m_axis_aresetn,
         s_axis_aclk    => m_axis_aclk,
         s_axis_tvalid  => pkt_axis_32b_tvalid,
         s_axis_tready  => pkt_axis_32b_tready,
         s_axis_tdata   => pkt_axis_32b_tdata,
         s_axis_tlast   => pkt_axis_32b_tlast,
         m_axis_aclk    => m_axis_aclk,
         m_axis_tvalid  => m_axis_tvalid,
         m_axis_tready  => m_axis_tready,
         m_axis_tdata   => m_axis_tdata, 
         m_axis_tlast   => m_axis_tlast  
      );
   end generate ADD_M_AXIS_BUFFER;
   
   --Bypass FIFO if g_M_AXIS_BUFFER_WORDS=0
   BYPASS_M_AXIS_BUFFER : if g_M_AXIS_BUFFER_WORDS = 0 generate 
      m_axis_tvalid        <= pkt_axis_32b_tvalid;
      pkt_axis_32b_tready  <= m_axis_tready;
      m_axis_tdata         <= pkt_axis_32b_tdata;
      m_axis_tlast         <= pkt_axis_32b_tlast;
   end generate BYPASS_M_AXIS_BUFFER;
  
 
end arch;   


