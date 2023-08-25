-- ----------------------------------------------------------------------------
-- FILE:          aurora_8b10b_wrapper.vhd
-- DESCRIPTION:   Wrapper for aurora_8b10b IP core
-- DATE:          16:35 2023-06-02
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
entity aurora_8b10b_wrapper is
   generic(
      g_DEBUG     : string := "false";
      g_GT_TYPE   : string := "GTH"
   );
   port (
      s_axi_tx_tdata       : in  std_logic_vector ( 0 to 31 );
      s_axi_tx_tkeep       : in  std_logic_vector ( 0 to 3 );
      s_axi_tx_tvalid      : in  std_logic;
      s_axi_tx_tlast       : in  std_logic;
      s_axi_tx_tready      : out std_logic;
      m_axi_rx_tdata       : out std_logic_vector ( 0 to 31 );
      m_axi_rx_tkeep       : out std_logic_vector ( 0 to 3 );
      m_axi_rx_tvalid      : out std_logic;
      m_axi_rx_tlast       : out std_logic;
      s_axi_nfc_tx_tvalid  : in  std_logic;
      s_axi_nfc_tx_tdata   : in  std_logic_vector ( 0 to 3 );
      s_axi_nfc_tx_tready  : out std_logic;
      m_axi_nfc_rx_tvalid  : out std_logic;
      m_axi_nfc_rx_tdata   : out std_logic_vector ( 0 to 3 );
      s_axi_ufc_tx_tvalid  : in  std_logic;
      s_axi_ufc_tx_tdata   : in  std_logic_vector ( 0 to 2 );
      s_axi_ufc_tx_tready  : out std_logic;
      m_axi_ufc_rx_tdata   : out std_logic_vector ( 0 to 31 );
      m_axi_ufc_rx_tkeep   : out std_logic_vector ( 0 to 3 );
      m_axi_ufc_rx_tvalid  : out std_logic;
      m_axi_ufc_rx_tlast   : out std_logic;
      rxp                  : in  std_logic;
      rxn                  : in  std_logic;
      txp                  : out std_logic;
      txn                  : out std_logic;
      gt_refclk            : in  std_logic;
      lane_up              : out std_logic;
      user_clk_out         : out std_logic;
      gt_reset             : in  std_logic;
      reset                : in  std_logic;
      init_clk_in          : in  std_logic
   );
end aurora_8b10b_wrapper;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of aurora_8b10b_wrapper is

   signal lane_up_int      : std_logic;
   
   --debug signal
   signal ila_hard_err               : std_logic;
   signal ila_soft_err               : std_logic;
   signal ila_frame_err              : std_logic;
   signal ila_channel_up             : std_logic;
   signal ila_tx_lock                : std_logic;
   signal ila_tx_resetdone_out       : std_logic;
   signal ila_rx_resetdone_out       : std_logic;
   signal ila_link_reset_out         : std_logic;
   signal ila_pll_not_locked_out     : std_logic;
   signal ila_sys_reset_out          : std_logic;
   signal ila_gt_reset_out           : std_logic;
   signal ila_gt_powergood           : std_logic;
   signal ila_gt0_pll0refclklost_out : std_logic;  
   signal ila_quad1_common_lock_out  : std_logic; 
   signal ila_gt0_pll0outclk_out     : std_logic;
   signal ila_gt0_pll1outclk_out     : std_logic;
   signal ila_gt0_pll0outrefclk_out  : std_logic;
   signal ila_gt0_pll1outrefclk_out  : std_logic;  
   
begin

   --Optional debug instance
   gen_debug : if g_DEBUG = "TRUE" generate
      ila_inst0 : entity work.ila_20
      port map (
         clk      => init_clk_in               ,
         probe0   => ila_hard_err              ,
         probe1   => ila_soft_err              ,
         probe2   => ila_frame_err             ,
         probe3   => ila_channel_up            ,
         probe4   => lane_up_int               ,
         probe5   => ila_tx_lock               ,
         probe6   => ila_tx_resetdone_out      ,
         probe7   => ila_rx_resetdone_out      ,
         probe8   => ila_link_reset_out        ,
         probe9   => ila_pll_not_locked_out    ,
         probe10  => ila_sys_reset_out         ,
         probe11  => ila_gt_reset_out          ,
         probe12  => ila_gt_powergood          ,
         probe13  => ila_gt0_pll0refclklost_out,
         probe14  => ila_quad1_common_lock_out ,
         probe15  => '0',
         probe16  => '0',
         probe17  => '0',
         probe18  => '0',
         probe19  => '0'
      );
   end generate gen_debug;

   gen_gth : if g_GT_TYPE = "GTH" generate
      inst_aurora: entity work.aurora_8b10b_0
      port map (
         s_axi_tx_tdata       => s_axi_tx_tdata,     
         s_axi_tx_tkeep       => s_axi_tx_tkeep,     
         s_axi_tx_tlast       => s_axi_tx_tlast,     
         s_axi_tx_tvalid      => s_axi_tx_tvalid,    
         s_axi_tx_tready      => s_axi_tx_tready,    
         s_axi_nfc_tx_tvalid  => s_axi_nfc_tx_tvalid,
         s_axi_nfc_tx_tdata   => s_axi_nfc_tx_tdata, 
         s_axi_nfc_tx_tready  => s_axi_nfc_tx_tready,
         s_axi_ufc_tx_tvalid  => s_axi_ufc_tx_tvalid,
         s_axi_ufc_tx_tdata   => s_axi_ufc_tx_tdata, 
         s_axi_ufc_tx_tready  => s_axi_ufc_tx_tready,
         m_axi_rx_tdata       => m_axi_rx_tdata,     
         m_axi_rx_tkeep       => m_axi_rx_tkeep,     
         m_axi_rx_tlast       => m_axi_rx_tlast,     
         m_axi_rx_tvalid      => m_axi_rx_tvalid,    
         m_axi_ufc_rx_tdata   => m_axi_ufc_rx_tdata, 
         m_axi_ufc_rx_tkeep   => m_axi_ufc_rx_tkeep, 
         m_axi_ufc_rx_tlast   => m_axi_ufc_rx_tlast, 
         m_axi_ufc_rx_tvalid  => m_axi_ufc_rx_tvalid,
         hard_err             => ila_hard_err, 
         soft_err             => ila_soft_err,
         frame_err            => ila_frame_err,
         channel_up           => ila_channel_up,
         lane_up              => lane_up_int,
         txp                  => txp,
         txn                  => txn,
         reset                => reset,      
         gt_reset             => gt_reset,
         loopback             => "000",   -- 001: Near-End PCS Loopback, 010: Near-End PMA Loopback, 100: Far-End PMA Loopback, 110: Far-End PCS Loopback,
         rxp                  => rxp,
         rxn                  => rxn,
         gt0_drpaddr          => (others=>'0'),
         gt0_drpen            => '0',
         gt0_drpdi            => (others=>'0'),
         gt0_drprdy           => open,
         gt0_drpdo            => open,
         gt0_drpwe            => '0',
         power_down           => '0',
         tx_lock              => open,
         tx_resetdone_out     => ila_tx_resetdone_out,
         rx_resetdone_out     => ila_rx_resetdone_out,
         link_reset_out       => ila_link_reset_out,
         init_clk_in          => init_clk_in,
         user_clk_out         => user_clk_out,
         pll_not_locked_out   => ila_pll_not_locked_out,                                          
         sys_reset_out        => ila_sys_reset_out,
         gt_refclk1           => gt_refclk,
         sync_clk_out         => open,
         gt_reset_out         => ila_gt_reset_out,
         gt_powergood         => ila_gt_powergood
      );
   end generate gen_gth;
   
   gen_gtp : if g_GT_TYPE = "GTP" generate
      inst_aurora: entity work.aurora_8b10b_0
      port map (
         s_axi_tx_tdata          => s_axi_tx_tdata,     
         s_axi_tx_tkeep          => s_axi_tx_tkeep,     
         s_axi_tx_tlast          => s_axi_tx_tlast,     
         s_axi_tx_tvalid         => s_axi_tx_tvalid,    
         s_axi_tx_tready         => s_axi_tx_tready,    
         s_axi_nfc_tx_tvalid     => s_axi_nfc_tx_tvalid,
         s_axi_nfc_tx_tdata      => s_axi_nfc_tx_tdata, 
         s_axi_nfc_tx_tready     => s_axi_nfc_tx_tready,
         s_axi_ufc_tx_tvalid     => s_axi_ufc_tx_tvalid,
         s_axi_ufc_tx_tdata      => s_axi_ufc_tx_tdata, 
         s_axi_ufc_tx_tready     => s_axi_ufc_tx_tready,
         m_axi_rx_tdata          => m_axi_rx_tdata,     
         m_axi_rx_tkeep          => m_axi_rx_tkeep,     
         m_axi_rx_tlast          => m_axi_rx_tlast,     
         m_axi_rx_tvalid         => m_axi_rx_tvalid,    
         m_axi_ufc_rx_tdata      => m_axi_ufc_rx_tdata, 
         m_axi_ufc_rx_tkeep      => m_axi_ufc_rx_tkeep, 
         m_axi_ufc_rx_tlast      => m_axi_ufc_rx_tlast, 
         m_axi_ufc_rx_tvalid     => m_axi_ufc_rx_tvalid,
         m_axi_nfc_rx_tvalid     => open, 
         m_axi_nfc_rx_tdata      => open, 
         hard_err                => ila_hard_err  , 
         soft_err                => ila_soft_err  ,
         frame_err               => ila_frame_err ,
         channel_up              => ila_channel_up,
         lane_up                 => lane_up_int,
         txp                     => txp,
         txn                     => txn,
         reset                   => reset,      
         gt_reset                => gt_reset,
         loopback                => "000",   -- 001: Near-End PCS Loopback, 010: Near-End PMA Loopback, 100: Far-End PMA Loopback, 110: Far-End PCS Loopback,
         rxp                     => rxp,
         rxn                     => rxn,
         drpclk_in               => '0', 
         drpaddr_in              => (others=>'0'),
         drpen_in                => '0',
         drpdi_in                => (others=>'0'),
         drprdy_out              => open,
         drpdo_out               => open,
         drpwe_in                => '0',
         power_down              => '0',
         tx_lock                 => ila_tx_lock         ,
         tx_resetdone_out        => ila_tx_resetdone_out,
         rx_resetdone_out        => ila_rx_resetdone_out,
         link_reset_out          => ila_link_reset_out  ,
         init_clk_in             => init_clk_in,
         user_clk_out            => user_clk_out,
         pll_not_locked_out      => ila_pll_not_locked_out,
         sys_reset_out           => ila_sys_reset_out     ,
         gt_refclk1              => gt_refclk,
         sync_clk_out            => open,
         gt_reset_out            => ila_gt_reset_out,
         gt0_pll0refclklost_out  => ila_gt0_pll0refclklost_out,
         quad1_common_lock_out   => ila_quad1_common_lock_out,
         gt0_pll0outclk_out      => open,
         gt0_pll1outclk_out      => open,
         gt0_pll0outrefclk_out   => open,
         gt0_pll1outrefclk_out   => open 
      );
   end generate gen_gtp;
   
   
   lane_up <= lane_up_int;
   
   
end arch;   


