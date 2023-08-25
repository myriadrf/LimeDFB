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
      g_GT_TYPE                  : string  := "GTH"; -- GTH - Ultrascale+; GTP - Artix7;
      -- Control channel
      g_AXIS_CTRL_DWIDTH         : integer := 32;
      g_S_AXIS_CTRL_BUFFER_WORDS : integer := 16;
      g_M_AXIS_CTRL_BUFFER_WORDS : integer := 16;
      --Data chanel
      g_AXIS_DMA_DWIDTH          : integer := 128;
      g_S_AXIS_DMA_BUFFER_WORDS  : integer := 512;
      g_S_AXIS_DMA_TLAST         : string := "False"; --Set to "True" if tlast signal is present
      g_M_AXIS_DMA_BUFFER_WORDS  : integer := 512;
      --Aurora
      g_GT_LANES                 : integer := 1;
      g_GT_RXTX_DWIDTH           : integer := 32;
      g_GT_RX_BUFFER_WORDS       : integer := 2048;
      g_GT_TX_BUFFER_WORDS       : integer := 2048
   );
   port (
      clk_125              : in  std_logic;
      reset_n              : in  std_logic;
      user_clk_out         : out std_logic;
      -- Control RX
      s_axis_ctrl_clk      : in  std_logic;
      s_axis_ctrl_aresetn  : in  std_logic;
      s_axis_ctrl_wr       : in  std_logic;
      s_axis_ctrl_wrfull   : out std_logic;
      s_axis_ctrl_wdata    : in  std_logic_vector(g_AXIS_CTRL_DWIDTH-1 downto 0);
      --Control TX
      m_axis_ctrl_clk      : in  std_logic;
      m_axis_ctrl_rd       : in std_logic;
      m_axis_ctrl_rempty   : out  std_logic;
      m_axis_ctrl_rdata    : out std_logic_vector(g_AXIS_CTRL_DWIDTH-1 downto 0);
      --DMA RX
      s_axis_dma_clk       : in  std_logic;
      s_axis_dma_aresetn   : in  std_logic;
      s_axis_dma_tvalid    : in  std_logic;
      s_axis_dma_tready    : out std_logic;
      s_axis_dma_tdata     : in  std_logic_vector(g_AXIS_DMA_DWIDTH-1 downto 0);
      s_axis_dma_tlast     : in  std_logic;
      s_axis_dma_wrusedw   : out std_logic_vector(log2ceil(g_S_AXIS_DMA_BUFFER_WORDS) downto 0);
      --DMA TX
      m_axis_dma_clk       : in  std_logic;
      m_axis_dma_aresetn   : in  std_logic;
      m_axis_dma_tvalid    : out std_logic;
      m_axis_dma_tready    : in  std_logic;
      m_axis_dma_tdata     : out std_logic_vector(g_AXIS_DMA_DWIDTH-1 downto 0);
      m_axis_dma_tlast     : out std_logic;
      -- GT transceivers
      gt_refclk            : in  std_logic;
      gt_soft_reset_n      : in  std_logic;
      gt_lane_up           : out std_logic;
      aurora_gt_reset_out  : out std_logic;
      aurora_reset_out     : out std_logic;
      gt_rxp               : in  std_logic;
      gt_rxn               : in  std_logic;
      gt_txp               : out std_logic;
      gt_txn               : out std_logic
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

signal rx_decoder_ctrl_tvalid : std_logic;
signal rx_decoder_ctrl_tready : std_logic;
signal rx_decoder_ctrl_tdata  : std_logic_vector(511 downto 0);

signal tx_encoder_ctrl_tvalid : std_logic;
signal tx_encoder_ctrl_tready : std_logic;
signal tx_encoder_ctrl_tdata  : std_logic_vector(511 downto 0);

attribute MARK_DEBUG : string;
attribute MARK_DEBUG of reset_n           : signal is "TRUE";
attribute MARK_DEBUG of gt_soft_reset_n   : signal is "TRUE";
attribute MARK_DEBUG of aurora_lane_up    : signal is "TRUE";
attribute MARK_DEBUG of aurora_reset      : signal is "TRUE";
attribute MARK_DEBUG of aurora_gt_reset   : signal is "TRUE";

attribute KEEP : string;
attribute KEEP of reset_n         : signal is "TRUE";
attribute KEEP of gt_soft_reset_n : signal is "TRUE";
attribute KEEP of aurora_reset    : signal is "TRUE";
attribute KEEP of aurora_gt_reset : signal is "TRUE";

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
      g_M_AXIS_0_DWIDTH       => 512, --NOT CONFIGURABLE
      g_M_AXIS_0_BUFFER_WORDS => g_M_AXIS_CTRL_BUFFER_WORDS,
      g_M_AXIS_1_DWIDTH       => g_AXIS_DMA_DWIDTH,
      g_M_AXIS_1_BUFFER_WORDS => g_M_AXIS_DMA_BUFFER_WORDS
   )
   port map(
      --general data bus
      m_axis_0_aclk     => m_axis_ctrl_clk,
      m_axis_0_tvalid   => rx_decoder_ctrl_tvalid,
      m_axis_0_tready   => rx_decoder_ctrl_tready,
      m_axis_0_tdata    => rx_decoder_ctrl_tdata,
      m_axis_0_tlast    => open,
      m_axis_0_wrusedw  => m_axis_ctrl_wrusedw,     
      --AXI stream slave
      m_axis_1_aclk     => m_axis_dma_clk,
      m_axis_1_aresetn  => m_axis_dma_aresetn, 
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
-- For Control endpoint, Aurora->FPGA
-- ----------------------------------------------------------------------------
   inst2_A2F_C_FIFO : entity work.wr_control_buff
   -- Commented to use default values
      generic map(
   --      g_DEV_FAMILY         => g_DEV_FAMILY,
         g_BUFF_RWIDTH        => g_AXIS_CTRL_DWIDTH
   --      g_BUFF_RDUSEDW_WIDTH => c_H2F_C0_RDUSEDW_WIDTH     
      )
   port map(
      clk            => m_axis_ctrl_clk,
      reset_n        => aurora_lane_up,
      -- Control endpoint
      cntrl_valid    => rx_decoder_ctrl_tvalid,
      cntrl_data     => rx_decoder_ctrl_tdata,
      cntrl_ready    => rx_decoder_ctrl_tready,
      -- Control Buffer FIFO
      buff_rdclk     => m_axis_ctrl_clk,
      buff_rd        => m_axis_ctrl_rd,--m_axis_ctrl_tready,
      buff_rdata     => m_axis_ctrl_rdata,--m_axis_ctrl_tdata,
      buff_rempty    => m_axis_ctrl_rempty,
      buff_rdusedw   => open
   );

-- ----------------------------------------------------------------------------
-- For Control endpoint, FPGA->Aurora
-- ----------------------------------------------------------------------------
   inst3_F2A_C_FIFO : entity work.rd_control_buff
   -- Commented to use default values
   generic map(
--      g_DEV_FAMILY         => g_DEV_FAMILY,
      g_BUFF_WRWIDTH       => g_AXIS_CTRL_DWIDTH
--      g_BUFF_WRUSEDW_WIDTH => c_F2H_C0_WRUSEDW_WIDTH   
   )
   port map(
      clk            => s_axis_ctrl_clk,
      reset_n        => aurora_lane_up,
      -- Control endpoint
      cntrl_valid    => tx_encoder_ctrl_tvalid,
      cntrl_data     => tx_encoder_ctrl_tdata,
      cntrl_ready    => tx_encoder_ctrl_tready, 
      -- Control Buffer FIFO
      buff_wrdclk    => s_axis_ctrl_clk,
      buff_wr        => s_axis_ctrl_wr,--s_axis_ctrl_tvalid,
      buff_wrdata    => s_axis_ctrl_wdata,--s_axis_ctrl_tdata,
      buff_wrfull    => s_axis_ctrl_wrfull,
      buff_wrdusedw  => open
   );

-- ----------------------------------------------------------------------------
-- Receive CTRL and DATA and pack them to AURORA packets 
-- (CTRL RX / DMA RX) gt_rx_decoder (TX) -> (RX) AURORA
-- ----------------------------------------------------------------------------

   inst2_gt_tx_encoder : entity work.gt_tx_encoder
   generic map(
      g_PKT_HEADER_WIDTH      => 128,
      g_I_AXIS_DWIDTH         => 128,
      g_S_AXIS_0_DWIDTH       => 512, --NOT CONFIGURABLE
      g_S_AXIS_0_BUFFER_WORDS => g_S_AXIS_CTRL_BUFFER_WORDS,
      g_S_AXIS_1_DWIDTH       => g_AXIS_DMA_DWIDTH,
      g_S_AXIS_1_BUFFER_WORDS => g_S_AXIS_DMA_BUFFER_WORDS,
      g_S_AXIS_1_TLAST        => g_S_AXIS_DMA_TLAST,
      g_M_AXIS_DWIDTH         => g_GT_RXTX_DWIDTH,
      g_M_AXIS_BUFFER_WORDS   => g_GT_RX_BUFFER_WORDS
   )
   port map(
      --AXI stream slave
      s_axis_0_aclk     => s_axis_ctrl_clk,
      s_axis_0_aresetn  => s_axis_ctrl_aresetn,
      s_axis_0_tvalid   => tx_encoder_ctrl_tvalid,
      s_axis_0_tready   => tx_encoder_ctrl_tready,
      s_axis_0_tdata    => tx_encoder_ctrl_tdata, 
      s_axis_0_tlast    => '0',
      --AXI stream slave
      s_axis_1_aclk     => s_axis_dma_clk,
      s_axis_1_aresetn  => s_axis_dma_aresetn,
      s_axis_1_tvalid   => s_axis_dma_tvalid,
      s_axis_1_tready   => s_axis_dma_tready,
      s_axis_1_tdata    => s_axis_dma_tdata,
      s_axis_1_tlast    => s_axis_dma_tlast,
      s_axis_1_wrusedw  => s_axis_dma_wrusedw,
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
      soft_reset_n   => gt_soft_reset_n,
      -- GT reset out
      gt_reset       => aurora_gt_reset,
      reset          => aurora_reset
   );

   inst4_aurora: entity work.aurora_top
   generic map ( 
      g_GT_TYPE   => g_GT_TYPE
   )
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
      gt_refclk            => gt_refclk,
      lane_up              => aurora_lane_up,
      txp(0)               => gt_txp,
      txn(0)               => gt_txn,
      reset                => aurora_reset,      
      gt_reset             => aurora_gt_reset,
      rxp(0)               => gt_rxp,
      rxn(0)               => gt_rxn,
      init_clk_in          => clk_125,
      user_clk_out         => aurora_user_clk_out,
      
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
   
   user_clk_out <= aurora_user_clk_out;
   
   gt_lane_up           <= aurora_lane_up;
   aurora_gt_reset_out  <= aurora_gt_reset;
   aurora_reset_out     <= aurora_reset;

  
end arch;   


