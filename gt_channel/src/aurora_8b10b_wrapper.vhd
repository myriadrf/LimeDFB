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

begin

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
         hard_err             => open, 
         soft_err             => open,
         frame_err            => open,
         channel_up           => open,
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
         tx_resetdone_out     => open,
         rx_resetdone_out     => open,
         link_reset_out       => open,
         init_clk_in          => init_clk_in,
         user_clk_out         => user_clk_out,
         pll_not_locked_out   => open,                                          
         sys_reset_out        => open,
         gt_refclk1           => gt_refclk,
         sync_clk_out         => open,
         gt_reset_out         => open,
         gt_powergood         => open
      );
   end generate gen_gth;
   
   
   lane_up <= lane_up_int;
   
   
end arch;   


