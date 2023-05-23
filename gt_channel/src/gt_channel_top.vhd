-- ----------------------------------------------------------------------------
-- FILE:          gt_channel_top.vhd
-- DESCRIPTION:   Top wrapper file for GT transceiver channel with AURORA 8b10b
-- DATE:          10:16 2023-05-17
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
entity gt_channel_top is
   generic(
      -- Control channel
      g_AXIS_CTRL_DWIDTH         : integer := 512;
      g_S_AXIS_CTRL_BUFFER_WORDS : integer := 16;
      g_M_AXIS_CTRL_BUFFER_WORDS : integer := 16;
      --Data chanel
      g_AXIS_DMA_DWIDTH          : integer := 128;
      g_S_AXIS_DMA_BUFFER_WORDS  : integer := 512;
      g_M_AXIS_DMA_BUFFER_WORDS  : integer := 512;
      --Aurora
      g_GT_LANES                 : integer := 1;
      g_GT_RXTX_DWIDTH           : integer := 32;
      g_GT_RX_BUFFER_WORDS       : integer := 2048;
      g_GT_TX_BUFFER_WORDS       : integer := 2048
   );
   port (
      clk            : in  std_logic;
      clk_125        : in  std_logic;
      reset_n        : in  std_logic;
      -- Control RX
      s_axis_ctrl_clk    : in  std_logic;
      s_axis_ctrl_aresetn: in  std_logic;
      s_axis_ctrl_tvalid : in  std_logic;
      s_axis_ctrl_tready : out std_logic;
      s_axis_ctrl_tdata  : in  std_logic_vector(g_AXIS_CTRL_DWIDTH-1 downto 0);
      s_axis_ctrl_tlast  : in  std_logic;
      --Control TX
      m_axis_ctrl_clk    : in  std_logic;
      m_axis_ctrl_tvalid : out std_logic;
      m_axis_ctrl_tready : in  std_logic;
      m_axis_ctrl_tdata  : out std_logic_vector(g_AXIS_CTRL_DWIDTH-1 downto 0);
      m_axis_ctrl_tlast  : out std_logic;
      --DMA RX
      s_axis_dma_clk    : in  std_logic;
      s_axis_dma_aresetn: in  std_logic;
      s_axis_dma_tvalid : in  std_logic;
      s_axis_dma_tready : out std_logic;
      s_axis_dma_tdata  : in  std_logic_vector(g_AXIS_DMA_DWIDTH-1 downto 0);
      s_axis_dma_tlast  : in  std_logic;
      --DMA TX
      m_axis_dma_clk    : in  std_logic;
      m_axis_dma_tvalid : out std_logic;
      m_axis_dma_tready : in  std_logic;
      m_axis_dma_tdata  : out std_logic_vector(g_AXIS_DMA_DWIDTH-1 downto 0);
      m_axis_dma_tlast  : out std_logic;
      -- GT transceivers
      gt_refclk     : in  std_logic;
      gt_rxp        : in  std_logic;
      gt_rxn        : in  std_logic;
      gt_txp        : out std_logic;
      gt_txn        : out std_logic
   );
end gt_channel_top;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of gt_channel_top is
--declare signals,  components here
signal aurora_axis_tx_tvalid  : std_logic;
signal aurora_axis_tx_tready  : std_logic;
signal aurora_axis_tx_tdata   : std_logic_vector(g_GT_RXTX_DWIDTH-1 downto 0);
signal aurora_axis_tx_tlast   : std_logic;

signal aurora_axis_rx_tvalid  : std_logic;
signal aurora_axis_rx_tready  : std_logic;
signal aurora_axis_rx_tdata   : std_logic_vector(g_GT_RXTX_DWIDTH-1 downto 0);
signal aurora_axis_rx_tlast   : std_logic;

signal aurora_user_clk_out    : std_logic;
signal aurora_gt_reset        : std_logic;
signal aurora_reset           : std_logic;
signal aurora_lane_up         : std_logic;

signal m_axis_ctrl_wrusedw    : std_logic_vector(log2ceil(g_M_AXIS_CTRL_BUFFER_WORDS) downto 0);
signal m_axis_dma_wrusedw     : std_logic_vector(log2ceil(g_M_AXIS_DMA_BUFFER_WORDS) downto 0);
signal aurora_axis_wrusedw    : std_logic_vector(log2ceil(g_GT_RX_BUFFER_WORDS) downto 0);

signal aurora_top_ctrl_usedw  : std_logic_vector(31 downto 0); 
signal aurora_top_data_usedw  : std_logic_vector(31 downto 0);
signal aurora_top_bufr_usedw  : std_logic_vector(31 downto 0);
signal aurora_top_ctrl_wr_stop: std_logic;
signal aurora_top_data_wr_stop: std_logic;

begin
-- ----------------------------------------------------------------------------
-- Receive AURORA packets and decode them to CTRL and DATA
-- AURORA (TX) -> (RX) gt_rx_decoder (CTRL TX / DMA TX)
-- ----------------------------------------------------------------------------
   inst1_gt_rx_decoder : entity work.gt_rx_decoder
   generic map(
      g_PKT_HEADER_WIDTH      => 128,
      g_I_AXIS_DWIDTH         => 128,
      g_S_AXIS_DWIDTH         => g_GT_RXTX_DWIDTH,
      g_S_AXIS_BUFFER_WORDS   => g_GT_TX_BUFFER_WORDS,
      g_M_AXIS_0_DWIDTH       => g_AXIS_CTRL_DWIDTH,
      g_M_AXIS_0_BUFFER_WORDS => g_M_AXIS_CTRL_BUFFER_WORDS,
      g_M_AXIS_1_DWIDTH       => g_AXIS_DMA_DWIDTH,
      g_M_AXIS_1_BUFFER_WORDS => g_M_AXIS_DMA_BUFFER_WORDS
   )
   port map(
      clk               => clk,
      reset_n           => reset_n,
      --general data bus
      m_axis_0_aclk     => m_axis_ctrl_clk,
      m_axis_0_tvalid   => m_axis_ctrl_tvalid,
      m_axis_0_tready   => m_axis_ctrl_tready,
      m_axis_0_tdata    => m_axis_ctrl_tdata,
      m_axis_0_tlast    => m_axis_ctrl_tlast,
      m_axis_0_wrusedw  => m_axis_ctrl_wrusedw,     
      --AXI stream slave
      m_axis_1_aclk     => m_axis_dma_clk,
      m_axis_1_tvalid   => m_axis_dma_tvalid,
      m_axis_1_tready   => m_axis_dma_tready,
      m_axis_1_tdata    => m_axis_dma_tdata,
      m_axis_1_tlast    => m_axis_dma_tlast,
      m_axis_1_wrusedw  => m_axis_dma_wrusedw,
      --AXI stream master
      s_axis_aclk       => aurora_user_clk_out,
      s_axis_aresetn    => aurora_lane_up,
      s_axis_tvalid     => aurora_axis_rx_tvalid,
      s_axis_tready     => aurora_axis_rx_tready,
      s_axis_tdata      => aurora_axis_rx_tdata,
      s_axis_tlast      => aurora_axis_rx_tlast,
      s_axis_wrusedw    => aurora_axis_wrusedw
   );

-- ----------------------------------------------------------------------------
-- Receive CTRL and DATA and pack them to AURORA packets 
-- (CTRL RX / DMA RX) gt_rx_decoder (TX) -> (RX) AURORA
-- ----------------------------------------------------------------------------
  inst2_gt_tx_encoder : entity work.gt_tx_encoder
   generic map(
      g_PKT_HEADER_WIDTH      => 128,
      g_I_AXIS_DWIDTH         => 128,
      g_S_AXIS_0_DWIDTH       => g_AXIS_CTRL_DWIDTH,
      g_S_AXIS_0_BUFFER_WORDS => g_S_AXIS_CTRL_BUFFER_WORDS,
      g_S_AXIS_1_DWIDTH       => g_AXIS_DMA_DWIDTH,
      g_S_AXIS_1_BUFFER_WORDS => g_S_AXIS_DMA_BUFFER_WORDS,
      g_M_AXIS_DWIDTH         => g_GT_RXTX_DWIDTH,
      g_M_AXIS_BUFFER_WORDS   => g_GT_RX_BUFFER_WORDS
   )
   port map(
      --AXI stream slave
      s_axis_0_aclk     => s_axis_ctrl_clk,
      s_axis_0_aresetn  => s_axis_ctrl_aresetn,
      s_axis_0_tvalid   => s_axis_ctrl_tvalid,
      s_axis_0_tready   => s_axis_ctrl_tready,
      s_axis_0_tdata    => s_axis_ctrl_tdata, 
      s_axis_0_tlast    => s_axis_ctrl_tlast,
      --AXI stream slave
      s_axis_1_aclk     => s_axis_dma_clk,
      s_axis_1_aresetn  => s_axis_dma_aresetn,
      s_axis_1_tvalid   => s_axis_dma_tvalid,
      s_axis_1_tready   => s_axis_dma_tready,
      s_axis_1_tdata    => s_axis_dma_tdata,
      s_axis_1_tlast    => s_axis_dma_tlast,
      --Control (synchronours to m_axis_aclk)
      s_axis_0_arb_req_supress => aurora_top_ctrl_wr_stop,
      s_axis_1_arb_req_supress => aurora_top_data_wr_stop,
      --AXI stream master
      m_axis_aclk       => aurora_user_clk_out,
      m_axis_aresetn    => aurora_lane_up, 
      m_axis_tvalid     => aurora_axis_tx_tvalid,
      m_axis_tready     => aurora_axis_tx_tready,
      m_axis_tdata      => aurora_axis_tx_tdata,
      m_axis_tlast      => aurora_axis_tx_tlast
   );
   
-- ----------------------------------------------------------------------------
-- Aurora core 
-- ----------------------------------------------------------------------------
   inst3_gt_reset : entity work.gt_reset
   port map(
      init_clk       => clk_125,
      user_clk       => aurora_user_clk_out,
      hard_reset_n   => reset_n,
      soft_reset_n   => reset_n,
      -- GT reset out
      gt_reset       => aurora_gt_reset,
      reset          => aurora_reset
   );

   inst4_aurora: entity work.aurora_top
   port map (
      s_axi_tx_tdata       => aurora_axis_tx_tdata, 
      s_axi_tx_tkeep       => (others=>'1'), --not used 
      s_axi_tx_tlast       => aurora_axis_tx_tlast,
      s_axi_tx_tvalid      => aurora_axis_tx_tvalid,
      s_axi_tx_tready      => aurora_axis_tx_tready,
      m_axi_rx_tdata       => aurora_axis_rx_tdata ,
      m_axi_rx_tkeep       => open,
      m_axi_rx_tlast       => aurora_axis_rx_tlast,
      m_axi_rx_tvalid      => aurora_axis_rx_tvalid,
      hard_err             => open,
      soft_err             => open,
      frame_err            => open,
      channel_up           => open,
      lane_up              => aurora_lane_up,
      txp                  => gt_txp,
      txn                  => gt_txn,
      reset                => aurora_reset,      
      gt_reset             => aurora_gt_reset,
      loopback             => "000",   -- 001: Near-End PCS Loopback, 010: Near-End PMA Loopback, 100: Far-End PMA Loopback, 110: Far-End PCS Loopback,
      rxp                  => gt_rxp,
      rxn                  => gt_rxn,
      gt0_drpaddr          => (others=>'0'),
      gt0_drpen            => '0',
      gt0_drpdi            => (others=>'0'),
      gt0_drprdy           => open,
      gt0_drpdo            => open,
      gt0_drpwe            => '0',
      power_down           => '0',
      tx_lock              => open,
      tx_resetdone_out     => open,
      rx_resetdone_out     => open,
      link_reset_out       => open,
      init_clk_in          => clk_125,
      user_clk_out         => aurora_user_clk_out,
      pll_not_locked_out   => open,                                          
      sys_reset_out        => open,
      gt_refclk1           => gt_refclk,
      sync_clk_out         => open,
      gt_reset_out         => open,
      gt_powergood         => open,
	  
	  data_fifo_usedw      => aurora_top_data_usedw,
	  ctrl_fifo_usedw      => aurora_top_ctrl_usedw,
	  bufr_fifo_usedw      => aurora_top_bufr_usedw,
	  data_fifo_stopwr     => aurora_top_data_wr_stop,
	  ctrl_fifo_stopwr     => aurora_top_ctrl_wr_stop,
	  ufc_misc_signals_in  => (others => '0'),
	  ufc_misc_signals_out => open
   );   
   
   aurora_top_data_usedw(31 downto m_axis_dma_wrusedw'LEFT+1 ) <= (others => '0');
   aurora_top_data_usedw(m_axis_dma_wrusedw'LEFT downto 0    ) <= m_axis_dma_wrusedw;
   aurora_top_ctrl_usedw(31 downto m_axis_ctrl_wrusedw'LEFT+1) <= (others => '0');
   aurora_top_ctrl_usedw(m_axis_ctrl_wrusedw'LEFT downto 0   ) <= m_axis_ctrl_wrusedw;
   aurora_top_bufr_usedw(31 downto aurora_axis_wrusedw'LEFT+1) <= (others => '0');
   aurora_top_bufr_usedw(aurora_axis_wrusedw'LEFT downto 0   ) <= aurora_axis_wrusedw;

  
end arch;   


