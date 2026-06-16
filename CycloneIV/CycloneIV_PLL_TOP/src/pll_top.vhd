-- ----------------------------------------------------------------------------
-- FILE:          pll_top.vhd
-- DESCRIPTION:   Top wrapper file for PLLs
-- DATE:          10:50 AM Wednesday, May 9, 2018
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
--NOTES:
-- ----------------------------------------------------------------------------
-- altera vhdl_input_version vhdl_2008
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity pll_top is
   generic(
      N_PLL                         : integer   := 2;
      -- TX pll parameters
      TXPLL_BANDWIDTH_TYPE          : STRING    := "AUTO";
      TXPLL_CLK0_DIVIDE_BY          : NATURAL   := 1;
      TXPLL_CLK0_DUTY_CYCLE         : NATURAL   := 50;
      TXPLL_CLK0_MULTIPLY_BY        : NATURAL   := 1;
      TXPLL_CLK0_PHASE_SHIFT        : STRING    := "0";
      TXPLL_CLK1_DIVIDE_BY          : NATURAL   := 1;
      TXPLL_CLK1_DUTY_CYCLE         : NATURAL   := 50;
      TXPLL_CLK1_MULTIPLY_BY        : NATURAL   := 1;
      TXPLL_CLK1_PHASE_SHIFT        : STRING    := "0";
      TXPLL_COMPENSATE_CLOCK        : STRING    := "CLK1";
      TXPLL_INCLK0_INPUT_FREQUENCY  : NATURAL   := 6250;
      TXPLL_INTENDED_DEVICE_FAMILY  : STRING    := "Cyclone IV E";
      TXPLL_OPERATION_MODE          : STRING    := "SOURCE_SYNCHRONOUS";
      TXPLL_SCAN_CHAIN_MIF_FILE     : STRING    := "ip/txpll/pll.mif";
      TXPLL_DRCT_C0_NDLY            : integer   := 1;
      TXPLL_DRCT_C1_NDLY            : integer   := 2;
      -- RX pll parameters
      RXPLL_BANDWIDTH_TYPE          : STRING    := "AUTO";
      RXPLL_CLK0_DIVIDE_BY          : NATURAL   := 1;
      RXPLL_CLK0_DUTY_CYCLE         : NATURAL   := 50;
      RXPLL_CLK0_MULTIPLY_BY        : NATURAL   := 1;
      RXPLL_CLK0_PHASE_SHIFT        : STRING    := "0";
      RXPLL_CLK1_DIVIDE_BY          : NATURAL   := 1;
      RXPLL_CLK1_DUTY_CYCLE         : NATURAL   := 50;
      RXPLL_CLK1_MULTIPLY_BY        : NATURAL   := 1;
      RXPLL_CLK1_PHASE_SHIFT        : STRING    := "0";
      RXPLL_COMPENSATE_CLOCK        : STRING    := "CLK1";
      RXPLL_INCLK0_INPUT_FREQUENCY  : NATURAL   := 6250;
      RXPLL_INTENDED_DEVICE_FAMILY  : STRING    := "Cyclone IV E";
      RXPLL_OPERATION_MODE          : STRING    := "SOURCE_SYNCHRONOUS";
      RXPLL_SCAN_CHAIN_MIF_FILE     : STRING    := "ip/pll/pll.mif";
      RXPLL_DRCT_C0_NDLY            : integer   := 1;
      RXPLL_DRCT_C1_NDLY            : integer   := 2

   );
   port (
      -- TX PLL ports
      txpll_inclk          : in  std_logic;
      txpll_reconfig_clk   : in  std_logic;
      txpll_logic_reset_n  : in  std_logic;
      txpll_clk_ena        : in  std_logic_vector(1 downto 0);
      txpll_drct_clk_en    : in  std_logic_vector(1 downto 0);
      txpll_c0             : out std_logic;
      txpll_c1             : out std_logic;
      txpll_locked         : out std_logic;
      --
      txpll_smpl_cmp_en    : out std_logic;
      txpll_smpl_cmp_done  : in  std_logic;
      txpll_smpl_cmp_error : in  std_logic;
      txpll_smpl_cmp_cnt   : out std_logic_vector(15 downto 0);
      -- RX pll ports
      rxpll_inclk          : in  std_logic;
      rxpll_reconfig_clk   : in  std_logic;
      rxpll_logic_reset_n  : in  std_logic;
      rxpll_clk_ena        : in  std_logic_vector(1 downto 0);
      rxpll_drct_clk_en    : in  std_logic_vector(1 downto 0); 
      rxpll_c0             : out std_logic;
      rxpll_c1             : out std_logic;
      rxpll_locked         : out std_logic;
      --
      rxpll_smpl_cmp_en    : out std_logic;      
      rxpll_smpl_cmp_done  : in  std_logic;
      rxpll_smpl_cmp_error : in  std_logic;
      rxpll_smpl_cmp_cnt   : out std_logic_vector(15 downto 0);
      -- pllcfg ports
      -- to pllcfg
      -- Status Inputs
      pllcfg_busy          : out std_logic;
      pllcfg_done          : out std_logic;
      phcfg_done           : out std_logic;
      phcfg_error          : out std_logic;
      -- PLL Lock flags
      pll_lock             : out std_logic_vector(15 downto 0);
      --  from pllcfg
      -- PLL Configuratioin Related
      phcfg_start       : in std_logic; --
      pllcfg_start      : in std_logic; --
      pllrst_start      : in std_logic; --
      phcfg_updn        : in std_logic; --
      cnt_ind           : in std_logic_vector(4 downto 0); --
      pll_ind           : in std_logic_vector(4 downto 0); --
      phcfg_mode        : in std_logic;
      phcfg_tst         : in std_logic;

      cnt_phase         : in std_logic_vector(15 downto 0); --
      chp_curr          : in std_logic_vector(2 downto 0); --
      pllcfg_vcodiv     : in std_logic; --
      pllcfg_lf_res     : in std_logic_vector(4 downto 0); -- (for Cyclone IV)
      pllcfg_lf_cap     : in std_logic_vector(1 downto 0); -- (for cyclone IV)

      m_odddiv          : in std_logic; --
      m_byp             : in std_logic; --
      n_odddiv          : in std_logic; --
      n_byp             : in std_logic; --

      c0_odddiv         : in std_logic; --
      c0_byp            : in std_logic; --
      c1_odddiv         : in std_logic; --
      c1_byp            : in std_logic; --
      c2_odddiv         : in std_logic; --
      c2_byp            : in std_logic; --
      c3_odddiv         : in std_logic; --
      c3_byp            : in std_logic; --
      c4_odddiv         : in std_logic; --
      c4_byp            : in std_logic; --
      n_cnt             : in std_logic_vector(15 downto 0); --
      m_cnt             : in std_logic_vector(15 downto 0); --
      c0_cnt            : in std_logic_vector(15 downto 0); --
      c1_cnt            : in std_logic_vector(15 downto 0); --
      c2_cnt            : in std_logic_vector(15 downto 0); --
      c3_cnt            : in std_logic_vector(15 downto 0); --
      c4_cnt            : in std_logic_vector(15 downto 0); --
      auto_phcfg_smpls  : in std_logic_vector(15 downto 0);
      auto_phcfg_step   : in std_logic_vector(15 downto 0)
      );
end pll_top;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of pll_top is
--declare signals,  components here
--inst0
signal inst0_pll_locked    : std_logic;
signal inst0_smpl_cmp_en   : std_logic;
signal inst0_busy          : std_logic;
signal inst0_dynps_done    : std_logic;
signal inst0_dynps_status  : std_logic;
signal inst0_rcnfig_status : std_logic;

--inst1
signal inst1_pll_locked    : std_logic;
signal inst1_smpl_cmp_en   : std_logic;
signal inst1_busy          : std_logic;
signal inst1_dynps_done    : std_logic;
signal inst1_dynps_status  : std_logic;
signal inst1_rcnfig_status : std_logic;

--inst2
signal inst2_pllcfg_busy      : std_logic_vector(N_PLL-1 downto 0);
signal inst2_pllcfg_done      : std_logic_vector(N_PLL-1 downto 0);
signal inst2_pll_lock         : std_logic_vector(N_PLL-1 downto 0);
signal inst2_phcfg_start      : std_logic_vector(N_PLL-1 downto 0);
signal inst2_pllcfg_start     : std_logic_vector(N_PLL-1 downto 0);
signal inst2_pllrst_start     : std_logic_vector(N_PLL-1 downto 0);
signal inst2_auto_phcfg_done  : std_logic_vector(N_PLL-1 downto 0);
signal inst2_auto_phcfg_err   : std_logic_vector(N_PLL-1 downto 0);
signal inst2_phcfg_mode       : std_logic;
signal inst2_phcfg_tst        : std_logic;
signal inst2_phcfg_updn       : std_logic;
signal inst2_cnt_ind          : std_logic_vector(4 downto 0);
signal inst2_cnt_phase        : std_logic_vector(15 downto 0);
signal inst2_pllcfg_data      : std_logic_vector(143 downto 0);
signal inst2_auto_phcfg_smpls : std_logic_vector(15 downto 0);
signal inst2_auto_phcfg_step  : std_logic_vector(15 downto 0);

signal internal_pllcfg_busy            : std_logic;
signal internal_pllcfg_done            : std_logic;

  
begin

-- ----------------------------------------------------------------------------
-- TX PLL instance
-- ----------------------------------------------------------------------------
tx_pll_top_inst0 : entity work.tx_pll_top
   generic map(
      bandwidth_type          => TXPLL_BANDWIDTH_TYPE,
      clk0_divide_by          => TXPLL_CLK0_DIVIDE_BY,
      clk0_duty_cycle         => TXPLL_CLK0_DUTY_CYCLE,
      clk0_multiply_by        => TXPLL_CLK0_MULTIPLY_BY,
      clk0_phase_shift        => TXPLL_CLK0_PHASE_SHIFT,
      clk1_divide_by          => TXPLL_CLK1_DIVIDE_BY,
      clk1_duty_cycle         => TXPLL_CLK1_DUTY_CYCLE,
      clk1_multiply_by        => TXPLL_CLK1_MULTIPLY_BY,
      clk1_phase_shift        => TXPLL_CLK1_PHASE_SHIFT,
      compensate_clock        => TXPLL_COMPENSATE_CLOCK,
      inclk0_input_frequency  => TXPLL_INCLK0_INPUT_FREQUENCY,
      intended_device_family  => TXPLL_INTENDED_DEVICE_FAMILY,
      operation_mode          => TXPLL_OPERATION_MODE,
      scan_chain_mif_file     => TXPLL_SCAN_CHAIN_MIF_FILE,
      drct_c0_ndly            => TXPLL_DRCT_C0_NDLY,
      drct_c1_ndly            => TXPLL_DRCT_C1_NDLY
   )
   port map(
   --PLL input 
   pll_inclk         => txpll_inclk,
   pll_areset        => inst2_pllrst_start(0),
   pll_logic_reset_n => txpll_logic_reset_n,
   inv_c0            => '0',
   c0                => txpll_c0, --muxed clock output
   c1                => txpll_c1, --muxed clock output
   pll_locked        => inst0_pll_locked,
   --Bypass control
   clk_ena           => txpll_clk_ena,       --clock output enable
   drct_clk_en       => txpll_drct_clk_en,   --1 - Direct clk, 0 - PLL clocks 
   --Reconfiguration ports
   rcnfg_clk         => txpll_reconfig_clk,
   rcnfig_areset     => inst2_pllrst_start(0),
   rcnfig_en         => inst2_pllcfg_start(0),
   rcnfig_data       => inst2_pllcfg_data,
   rcnfig_status     => inst0_rcnfig_status,
   --Dynamic phase shift ports
   dynps_areset_n    => not inst2_pllrst_start(0),
   dynps_mode        => inst2_phcfg_mode, -- 0 - manual, 1 - auto
   dynps_en          => inst2_phcfg_start(0),
   dynps_tst         => inst2_phcfg_tst,
   dynps_dir         => inst2_phcfg_updn,
   dynps_cnt_sel     => inst2_cnt_ind(2 downto 0),
   -- max phase steps in auto mode, phase steps to shift in manual mode
   dynps_phase       => inst2_cnt_phase(9 downto 0),
   dynps_step_size   => inst2_auto_phcfg_step(9 downto 0),
   dynps_busy        => open,
   dynps_done        => inst0_dynps_done,
   dynps_status      => inst0_dynps_status,
   --signals from sample compare module (required for automatic phase searching)
   smpl_cmp_en       => inst0_smpl_cmp_en,
   smpl_cmp_done     => txpll_smpl_cmp_done,
   smpl_cmp_error    => txpll_smpl_cmp_error,
   --Overall configuration PLL status
   busy              => inst0_busy   
   );
   
-- ----------------------------------------------------------------------------
-- RX PLL instance
-- ----------------------------------------------------------------------------
rx_pll_top_inst0 : entity work.rx_pll_top
   generic map(
      bandwidth_type          => RXPLL_BANDWIDTH_TYPE,
      clk0_divide_by          => RXPLL_CLK0_DIVIDE_BY,
      clk0_duty_cycle         => RXPLL_CLK0_DUTY_CYCLE,
      clk0_multiply_by        => RXPLL_CLK0_MULTIPLY_BY,
      clk0_phase_shift        => RXPLL_CLK0_PHASE_SHIFT,
      clk1_divide_by          => RXPLL_CLK1_DIVIDE_BY,
      clk1_duty_cycle         => RXPLL_CLK1_DUTY_CYCLE,
      clk1_multiply_by        => RXPLL_CLK1_MULTIPLY_BY,
      clk1_phase_shift        => RXPLL_CLK1_PHASE_SHIFT,
      compensate_clock        => RXPLL_COMPENSATE_CLOCK,
      inclk0_input_frequency  => RXPLL_INCLK0_INPUT_FREQUENCY,
      intended_device_family  => RXPLL_INTENDED_DEVICE_FAMILY,
      operation_mode          => RXPLL_OPERATION_MODE,
      scan_chain_mif_file     => RXPLL_SCAN_CHAIN_MIF_FILE,
      drct_c0_ndly            => RXPLL_DRCT_C0_NDLY,
      drct_c1_ndly            => RXPLL_DRCT_C1_NDLY
   )
   port map(
   --PLL input 
   pll_inclk         => rxpll_inclk,
   pll_areset        => inst2_pllrst_start(1),
   pll_logic_reset_n => rxpll_logic_reset_n,
   inv_c0            => '0',
   c0                => rxpll_c0, --muxed clock output
   c1                => rxpll_c1, --muxed clock output
   pll_locked        => inst1_pll_locked,
   --Bypass control
   clk_ena           => rxpll_clk_ena,       --clock output enable
   drct_clk_en       => rxpll_drct_clk_en,   --1 - Direct clk, 0 - PLL clocks 
   --Reconfiguration ports
   rcnfg_clk         => rxpll_reconfig_clk,
   rcnfig_areset     => inst2_pllrst_start(1),
   rcnfig_en         => inst2_pllcfg_start(1),
   rcnfig_data       => inst2_pllcfg_data,
   rcnfig_status     => inst1_rcnfig_status,
   --Dynamic phase shift ports
   dynps_areset_n    => not inst2_pllrst_start(1),
   dynps_mode        => inst2_phcfg_mode, -- 0 - manual, 1 - auto
   dynps_en          => inst2_phcfg_start(1),
   dynps_tst         => inst2_phcfg_tst,
   dynps_dir         => inst2_phcfg_updn,
   dynps_cnt_sel     => inst2_cnt_ind(2 downto 0),
   -- max phase steps in auto mode, phase steps to shift in manual mode
   dynps_phase       => inst2_cnt_phase(9 downto 0),
   dynps_step_size   => inst2_auto_phcfg_step(9 downto 0),
   dynps_busy        => open,
   dynps_done        => inst1_dynps_done,
   dynps_status      => inst1_dynps_status,
   --signals from sample compare module (required for automatic phase searching)
   smpl_cmp_en       => inst1_smpl_cmp_en,
   smpl_cmp_done     => rxpll_smpl_cmp_done,
   smpl_cmp_error    => rxpll_smpl_cmp_error,
   --Overall configuration PLL status
   busy              => inst1_busy   
   );

  
   internal_pllcfg_busy <= inst1_busy OR inst0_busy;
   internal_pllcfg_done <= not internal_pllcfg_busy;
   
   
-- ----------------------------------------------------------------------------
-- pllcfg_top instance
-- ----------------------------------------------------------------------------
   process(internal_pllcfg_busy)
      begin 
         inst2_pllcfg_busy <= (others=>'0');
         inst2_pllcfg_busy(0) <= internal_pllcfg_busy;
   end process;
   
   process(pllcfg_done) 
      begin 
         inst2_pllcfg_done <= (others=>'1');
         inst2_pllcfg_done(0) <= pllcfg_done;
   end process;
   
   inst2_pll_lock          <= inst1_pll_locked     & inst0_pll_locked;   
   inst2_auto_phcfg_done   <= inst1_dynps_done     & inst0_dynps_done; 
   inst2_auto_phcfg_err    <= inst1_dynps_status   & inst0_dynps_status;

   pll_ctrl_inst2 : entity work.pll_ctrl 
   generic map(
      n_pll	=> N_PLL
   )
   port map(
         -- Status Inputs
      pllcfg_busy       => inst2_pllcfg_busy,
      pllcfg_done       => inst2_pllcfg_done,
         -- PLL Lock flags
      pll_lock          => inst2_pll_lock,
         -- PLL Configuration Related
      phcfg_mode        => inst2_phcfg_mode,
      phcfg_tst         => inst2_phcfg_tst,
      phcfg_start       => inst2_phcfg_start,   --
      pllcfg_start      => inst2_pllcfg_start,  --
      pllrst_start      => inst2_pllrst_start,  --
      phcfg_updn        => inst2_phcfg_updn,
      cnt_ind           => inst2_cnt_ind,       --
      cnt_phase         => inst2_cnt_phase,     --
      pllcfg_data       => inst2_pllcfg_data,
      auto_phcfg_done   => inst2_auto_phcfg_done,
      auto_phcfg_err    => inst2_auto_phcfg_err,
      auto_phcfg_smpls  => inst2_auto_phcfg_smpls,
      auto_phcfg_step   => inst2_auto_phcfg_step,
      -- to pllcfg
      out_pllcfg_busy       => pllcfg_busy       ,
      out_pllcfg_done       => pllcfg_done       ,
      out_phcfg_done        => phcfg_done        ,
      out_phcfg_error       => phcfg_error       ,
      -- PLL Lock flags
      out_pll_lock          => pll_lock          ,
      --  from pllcfg
      -- PLL Configuration
      in_phcfg_start       => phcfg_start       ,
      in_pllcfg_start      => pllcfg_start      ,
      in_pllrst_start      => pllrst_start      ,
      in_phcfg_updn        => phcfg_updn        ,
      in_cnt_ind           => cnt_ind           ,
      in_pll_ind           => pll_ind           ,
      in_phcfg_mode        => phcfg_mode        ,
      in_phcfg_tst         => phcfg_tst         ,
      in_cnt_phase         => cnt_phase         ,
      in_chp_curr          => chp_curr          ,
      in_pllcfg_vcodiv     => pllcfg_vcodiv     ,
      in_pllcfg_lf_res     => pllcfg_lf_res     ,
      in_pllcfg_lf_cap     => pllcfg_lf_cap     ,
      in_m_odddiv          => m_odddiv          ,
      in_m_byp             => m_byp             ,
      in_n_odddiv          => n_odddiv          ,
      in_n_byp             => n_byp             ,
      in_c0_odddiv         => c0_odddiv         ,
      in_c0_byp            => c0_byp            ,
      in_c1_odddiv         => c1_odddiv         ,
      in_c1_byp            => c1_byp            ,
      in_c2_odddiv         => c2_odddiv         ,
      in_c2_byp            => c2_byp            ,
      in_c3_odddiv         => c3_odddiv         ,
      in_c3_byp            => c3_byp            ,
      in_c4_odddiv         => c4_odddiv         ,
      in_c4_byp            => c4_byp            ,
      in_n_cnt             => n_cnt             ,
      in_m_cnt             => m_cnt             ,
      in_c0_cnt            => c0_cnt            ,
      in_c1_cnt            => c1_cnt            ,
      in_c2_cnt            => c2_cnt            ,
      in_c3_cnt            => c3_cnt            ,
      in_c4_cnt            => c4_cnt            ,
      in_auto_phcfg_smpls  => auto_phcfg_smpls  ,
      in_auto_phcfg_step   => auto_phcfg_step

      );
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------  
txpll_locked         <= inst0_pll_locked;
txpll_smpl_cmp_en    <= inst0_smpl_cmp_en;
txpll_smpl_cmp_cnt   <= inst2_auto_phcfg_smpls;

rxpll_locked         <= inst1_pll_locked;
rxpll_smpl_cmp_en    <= inst1_smpl_cmp_en;
rxpll_smpl_cmp_cnt   <= inst2_auto_phcfg_smpls;


end arch;   


