-- ----------------------------------------------------------------------------
-- FILE:          gt_rx_decoder.vhd
-- DESCRIPTION:   Decodes received packets into control and data streams
-- DATE:          14:55 2023-05-11
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_functions.log2ceil;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity gt_rx_decoder is
   generic(
      g_PKT_HEADER_WIDTH      : integer := 128;
      g_I_AXIS_DWIDTH         : integer := 128;
      g_S_AXIS_DWIDTH         : integer := 32;
      g_S_AXIS_BUFFER_WORDS   : integer := 2048;   -- If 0 - buffer is not added
      g_M_AXIS_0_DWIDTH       : integer := 512;    -- Only 512 valid value
      g_M_AXIS_0_BUFFER_WORDS : integer := 16;
      g_M_AXIS_1_DWIDTH       : integer := 128;
      g_M_AXIS_1_BUFFER_WORDS : integer := 512
   );
   port (
      clk               : in  std_logic;
      reset_n           : in  std_logic;
      --AXI stream master 0
      m_axis_0_aclk     : in  std_logic;
      m_axis_0_tvalid   : out std_logic;
      m_axis_0_tready   : in  std_logic;
      m_axis_0_tdata    : out std_logic_vector(g_M_AXIS_0_DWIDTH-1 downto 0);
      m_axis_0_tlast    : out std_logic;
      m_axis_0_wrusedw  : out std_logic_vector(log2ceil(g_M_AXIS_0_BUFFER_WORDS) downto 0);
      --AXI stream master 1
      m_axis_1_aclk     : in  std_logic;
      m_axis_1_tvalid   : out std_logic;
      m_axis_1_tready   : in  std_logic;
      m_axis_1_tdata    : out std_logic_vector(g_M_AXIS_1_DWIDTH-1 downto 0);
      m_axis_1_tlast    : out std_logic;
      m_axis_1_wrusedw  : out std_logic_vector(log2ceil(g_M_AXIS_1_BUFFER_WORDS) downto 0);
      --AXI stream slave
      s_axis_aclk    : in  std_logic;
      s_axis_aresetn : in  std_logic;
      s_axis_tvalid  : in  std_logic; 
      s_axis_tready  : out std_logic;
      s_axis_tdata   : in  std_logic_vector(g_S_AXIS_DWIDTH-1 downto 0);
      s_axis_tlast   : in  std_logic;
      s_axis_wrusedw : out std_logic_vector(log2ceil(g_S_AXIS_BUFFER_WORDS) downto 0)
   );
end gt_rx_decoder;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of gt_rx_decoder is
--declare signals,  components here

signal axis_32b_tvalid  : std_logic;
signal axis_32b_tready  : std_logic;
signal axis_32b_tdata   : std_logic_vector(g_S_AXIS_DWIDTH-1 downto 0);
signal axis_32b_tlast   : std_logic;

signal axis_128b_tvalid : std_logic;
signal axis_128b_tready : std_logic;
signal axis_128b_tdata  : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal axis_128b_tlast  : std_logic;

signal axis_0_128b_unpkd_tvalid    : std_logic;
signal axis_0_128b_unpkd_tready    : std_logic;
signal axis_0_128b_unpkd_tdata     : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal axis_0_128b_unpkd_tlast     : std_logic;

signal axis_1_128b_unpkd_tvalid    : std_logic;
signal axis_1_128b_unpkd_tready    : std_logic;
signal axis_1_128b_unpkd_tdata     : std_logic_vector(g_I_AXIS_DWIDTH-1 downto 0);
signal axis_1_128b_unpkd_tlast     : std_logic;

signal axis_0_512b_unpkd_tvalid    : std_logic;
signal axis_0_512b_unpkd_tready    : std_logic;
signal axis_0_512b_unpkd_tdata     : std_logic_vector(g_M_AXIS_0_DWIDTH-1 downto 0);
signal axis_0_512b_unpkd_tlast     : std_logic;


begin

-- ----------------------------------------------------------------------------
-- Optional FIFO buffer for s_axis 
-- ----------------------------------------------------------------------------
   ADD_S_AXIS_BUFFER : if g_S_AXIS_BUFFER_WORDS > 0 generate 
      inst1_s_axis_fifo: entity work.fifo_axis_wrap
      generic map(
         g_CLOCKING_MODE         => "independent_clock",
         g_FIFO_DEPTH            => g_S_AXIS_BUFFER_WORDS,
         g_TDATA_WIDTH           => g_S_AXIS_DWIDTH,
         g_WR_DATA_COUNT_WIDTH   => log2ceil(g_S_AXIS_BUFFER_WORDS)+1 
      )
      port map(
         s_axis_aresetn       => s_axis_aresetn,
         s_axis_aclk          => s_axis_aclk,
         s_axis_tvalid        => s_axis_tvalid,
         s_axis_tready        => s_axis_tready,
         s_axis_tdata         => s_axis_tdata,
         s_axis_tlast         => s_axis_tlast,
         m_axis_aclk          => s_axis_aclk,
         m_axis_tvalid        => axis_32b_tvalid,
         m_axis_tready        => axis_32b_tready,
         m_axis_tdata         => axis_32b_tdata, 
         m_axis_tlast         => axis_32b_tlast, 
         wr_data_count_axis   => s_axis_wrusedw         
      );
   end generate ADD_S_AXIS_BUFFER;
   
   WITHOUT_S_AXIS_BUFFER : if g_S_AXIS_BUFFER_WORDS = 0 generate 
      axis_32b_tvalid   <= s_axis_tvalid;
      s_axis_tready     <= axis_32b_tready;
      axis_32b_tdata    <= s_axis_tdata;
      axis_32b_tlast    <= s_axis_tlast;
      s_axis_wrusedw    <= (others=>'0');
   end generate WITHOUT_S_AXIS_BUFFER;
   
-- ----------------------------------------------------------------------------
-- Converting AXIS data width
-- ----------------------------------------------------------------------------
   inst1_axis_dwidth : entity work.axis_dwidth_32_to_128
   port map (
      aclk           => s_axis_aclk,
      aresetn        => s_axis_aresetn,
      s_axis_tvalid  => axis_32b_tvalid,
      s_axis_tready  => axis_32b_tready,
      s_axis_tdata   => axis_32b_tdata,
      s_axis_tlast   => axis_32b_tlast,
      m_axis_tvalid  => axis_128b_tvalid,
      m_axis_tready  => axis_128b_tready,
      m_axis_tdata   => axis_128b_tdata,
      m_axis_tkeep   => open,
      m_axis_tlast   => axis_128b_tlast
   );
  
-- ----------------------------------------------------------------------------
-- Decoding packets. 
-- Note that at this point it is not expected to encounter any backpresure. 
-- Flow control should be handled at transceiver level
-- ----------------------------------------------------------------------------  
   inst3_rx_decoder : entity work.rx_decoder
   generic map(
      g_PKT_HEADER_WIDTH   => g_PKT_HEADER_WIDTH,
      g_S_AXIS_DWIDTH      => g_I_AXIS_DWIDTH,
      g_M_AXIS_DWIDTH      => g_I_AXIS_DWIDTH
   )
   port map(
      clk               => s_axis_aclk,
      reset_n           => s_axis_aresetn,
      --general data bus
      m_axis_0_tvalid   => axis_0_128b_unpkd_tvalid,
      m_axis_0_tready   => axis_0_128b_unpkd_tready,
      m_axis_0_tdata    => axis_0_128b_unpkd_tdata,
      m_axis_0_tlast    => axis_0_128b_unpkd_tlast,
      --AXI stream slave
      m_axis_1_tvalid   => axis_1_128b_unpkd_tvalid,
      m_axis_1_tready   => axis_1_128b_unpkd_tready,
      m_axis_1_tdata    => axis_1_128b_unpkd_tdata,
      m_axis_1_tlast    => axis_1_128b_unpkd_tlast,
      --AXI stream master
      s_axis_tvalid     => axis_128b_tvalid,
      s_axis_tready     => axis_128b_tready,
      s_axis_tdata      => axis_128b_tdata,
      s_axis_tlast      => axis_128b_tlast
   );
   
   
-- ----------------------------------------------------------------------------
-- Unpacked data width conversion and buffering for axis0
-- ----------------------------------------------------------------------------
   inst4_axis_dwidth : entity work.axis_dwidth_128_to_512
   port map (
      aclk           => s_axis_aclk,
      aresetn        => s_axis_aresetn,
      s_axis_tvalid  => axis_0_128b_unpkd_tvalid,
      s_axis_tready  => axis_0_128b_unpkd_tready,
      s_axis_tdata   => axis_0_128b_unpkd_tdata,
      s_axis_tlast   => axis_0_128b_unpkd_tlast,
      m_axis_tvalid  => axis_0_512b_unpkd_tvalid,
      m_axis_tready  => axis_0_512b_unpkd_tready,
      m_axis_tdata   => axis_0_512b_unpkd_tdata,
      m_axis_tkeep   => open,
      m_axis_tlast   => axis_0_512b_unpkd_tlast
  );

   ADD_M_AXIS_0_BUFFER : if g_M_AXIS_0_BUFFER_WORDS > 0 generate
      inst5_m0_axis_fifo: entity work.fifo_axis_wrap
      generic map(
         g_CLOCKING_MODE         => "independent_clock",
         g_FIFO_DEPTH            => g_M_AXIS_0_BUFFER_WORDS,
         g_TDATA_WIDTH           => g_M_AXIS_0_DWIDTH,
         g_WR_DATA_COUNT_WIDTH   => log2ceil(g_M_AXIS_0_BUFFER_WORDS)+1 
      )
      port map(
         s_axis_aresetn       => s_axis_aresetn,
         s_axis_aclk          => s_axis_aclk,
         s_axis_tvalid        => axis_0_512b_unpkd_tvalid,
         s_axis_tready        => axis_0_512b_unpkd_tready,
         s_axis_tdata         => axis_0_512b_unpkd_tdata,
         s_axis_tlast         => axis_0_512b_unpkd_tlast,
         m_axis_aclk          => m_axis_0_aclk,
         m_axis_tvalid        => m_axis_0_tvalid,
         m_axis_tready        => m_axis_0_tready,
         m_axis_tdata         => m_axis_0_tdata, 
         m_axis_tlast         => m_axis_0_tlast,
         wr_data_count_axis   => m_axis_0_wrusedw         
      );
   end generate ADD_M_AXIS_0_BUFFER;
   
   WITHOUT_M_AXIS_0_BUFFER : if g_M_AXIS_0_BUFFER_WORDS = 0 generate 
      m_axis_0_tvalid            <= axis_0_512b_unpkd_tvalid;
      axis_0_512b_unpkd_tready   <= m_axis_0_tready;
      m_axis_0_tdata             <= axis_0_512b_unpkd_tdata;
      m_axis_0_tlast             <= axis_0_512b_unpkd_tlast;
      m_axis_0_wrusedw           <= (others=>'0');
   end generate WITHOUT_M_AXIS_0_BUFFER;    
 
-- ----------------------------------------------------------------------------
-- Unpacked data Buffering for axis1
-- ----------------------------------------------------------------------------
   ADD_M_AXIS_1_BUFFER : if g_M_AXIS_1_BUFFER_WORDS > 0 generate
      inst6_m1_axis_fifo: entity work.fifo_axis_wrap
      generic map(
         g_CLOCKING_MODE         => "independent_clock",
         g_FIFO_DEPTH            => g_M_AXIS_1_BUFFER_WORDS,
         g_TDATA_WIDTH           => g_M_AXIS_1_DWIDTH,
         g_WR_DATA_COUNT_WIDTH   => log2ceil(g_M_AXIS_1_BUFFER_WORDS)+1
      )
      port map(
         s_axis_aresetn       => s_axis_aresetn,
         s_axis_aclk          => s_axis_aclk,
         s_axis_tvalid        => axis_1_128b_unpkd_tvalid,
         s_axis_tready        => axis_1_128b_unpkd_tready,
         s_axis_tdata         => axis_1_128b_unpkd_tdata,
         s_axis_tlast         => axis_1_128b_unpkd_tlast,
         m_axis_aclk          => m_axis_1_aclk,
         m_axis_tvalid        => m_axis_1_tvalid,
         m_axis_tready        => m_axis_1_tready,
         m_axis_tdata         => m_axis_1_tdata,
         m_axis_tlast         => m_axis_1_tlast,
         wr_data_count_axis   => m_axis_1_wrusedw
      );
   end generate ADD_M_AXIS_1_BUFFER;
   
   WITHOUT_M_AXIS_1_BUFFER : if g_M_AXIS_1_BUFFER_WORDS = 0 generate 
      m_axis_1_tvalid            <= axis_1_128b_unpkd_tvalid;
      axis_1_128b_unpkd_tready   <= m_axis_1_tready;
      m_axis_1_tdata             <= axis_1_128b_unpkd_tdata;
      m_axis_1_tlast             <= axis_1_128b_unpkd_tlast;
      m_axis_1_wrusedw           <= (others=>'0');
   end generate WITHOUT_M_AXIS_1_BUFFER;
     
end arch;   


