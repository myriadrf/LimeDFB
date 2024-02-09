-- ----------------------------------------------------------------------------
-- FILE:          lms7002_top.vhd
-- DESCRIPTION:   Top file for LMS7002M IC
-- DATE:          9:16 AM Wednesday, August 29, 2018
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:     v2 - Updated with AXIS interface
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
-- TerosHDL module description
--! Top module for LMS7002M IC.
--!
--! Functionality:
--! - Transmit IQ samples trough s_axi_tx AXI Stream bus
--! - Receive IQ samples from m_axi_rx AXI Stream bus
--!
--! LimeLight digital modes implemented:
--! - TRXIQ PULSE
--! - MIMO DDR
--! - SISO DDR
--! - SISO SDR
--!

-- WaveDrom timing diagrams

-- s_axis_tx bus timing (MIMO DDR mode, A and B channels enabled)
--! { signal: [
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=...=...=...=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=...=...=...=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x...=.=...=...=...=|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x...=.=...=...=...=|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" }, 
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=============|", data: ["AI(0)", "AQ(0)", "BI(0)", "BQ(0)", "AI(1)", "AQ(1)", "BI(1)", "BQ(1)", "AI(2)", "AQ(2)", "BI(2)", "BQ(2)"] },
--! ],
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan', 
--!           ['tspan', {'font-weight':'bold'}, 's_axis_tx bus timing (MIMO DDR mode, A and B channels enabled)']], 
--!     tick:0,
--!     every:2
--!   }}

-- s_axis_tx bus timing (MIMO DDR mode, A channel enabled)
--! { signal: [
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=...=...=...=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=...=...=...=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x..................|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x..................|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" },  
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=============|", data: ["AI(0)", "AQ(0)", "0", "0", "AI(1)", "AQ(1)", "0", "0", "AI(2)", "AQ(2)", "0", "0"] },
--! ],
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan', 
--!           ['tspan', {'font-weight':'bold'}, 's_axis_tx bus timing (MIMO DDR mode, A channel enabled)']], 
--!     tick:0,
--!     every:2
--!   }}

-- s_axis_tx bus timing (MIMO DDR mode, B channel enabled)
--! { signal: [
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x..................|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x..................|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x...=.=...=...=...=|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x...=.=...=...=...=|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" }, 
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=============|", data: ["0", "0", "BI(0)", "BQ(0)", "0", "0", "BI(1)", "BQ(1)", "0", "0", "BI(2)", "BQ(2)"] },
--! ],
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan', 
--!           ['tspan', {'font-weight':'bold'}, 's_axis_tx bus timing (MIMO DDR mode, B channel enabled)']], 
--!     tick:0,
--!     every:2
--!   }}

-- s_axis_tx bus timing (SISO DDR mode)
--! { signal: [
--!  { name: "s_axi_tx_aclk",  wave: "P......" , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1..........|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1........|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=.=.=.=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=.=.=.=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x............|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x............|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1........|" }, 
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0......101010|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=======|", data: ["AI(0)", "AQ(0)", "AI(1)", "AQ(1)", "AI(2)", "AQ(2)", "AI(n)", "AQ(n)", "AI(2)", "AQ(2)", "BI(2)", "BQ(2)"] },
--! ],
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan', 
--!           ['tspan', {'font-weight':'bold'}, 's_axis_tx bus timing (SISO DDR mode)']], 
--!     tick:0,
--!     every:2
--!   }}

-- s_axis_tx bus timing (SISO SDR mode)
--! { signal: [
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=...=...=...=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=...=...=...=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x..................|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x..................|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" },  
--!  { name: "FCLK1",  wave: "hLhLhLhLhLhLhLhLhLhL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=.=.=.=.=.=.=|", data: ["AI(0)", "AQ(0)", "AI(1)", "AQ(1)", "AI(2)", "AQ(2)", "AI(n)", "0"] },
--! ],
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan', 
--!           ['tspan', {'font-weight':'bold'}, 's_axis_tx bus timing (SISO SDR mode)']], 
--!     tick:0,
--!     every:2
--!   }}
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fpgacfg_pkg.all;
use work.tstcfg_pkg.all;
use work.memcfg_pkg.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity lms7002_top is
   generic(
      g_DEV_FAMILY               : string    := "Artix 7";  --! Device family
      g_IQ_WIDTH                 : integer   := 12;         --! IQ bus width
      g_S_AXIS_TX_FIFO_WORDS     : integer   := 16          --! TX FIFO size in words
   );
   port (  
      --! @virtualbus cfg @dir in Configuration bus
      from_fpgacfg         : in  t_FROM_FPGACFG;   --! Signals from FPGACFG registers
      from_tstcfg          : in  t_FROM_TSTCFG;    --! Signals from TSTCFG registers
      from_memcfg          : in  t_FROM_MEMCFG;    --! Signals from MEMCFG registers @end
      --! @virtualbus LMS_PORT1 @dir out interface
      MCLK1                : in  std_logic;  --! TX interface clock
      FCLK1                : out std_logic;  --! TX interface feedback clock
      DIQ1                 : out std_logic_vector(g_IQ_WIDTH-1 downto 0); --! DIQ1 data bus
      ENABLE_IQSEL1        : out std_logic;  --! IQ select flag for DIQ1 data
      TXNRX1               : out std_logic;  --! LMS_PORT1 direction select @end
      --! @virtualbus LMS_PORT2 @dir in interface
      MCLK2                : in  std_logic;  --! RX interface clock
      FCLK2                : out std_logic;  --! RX interface feedback clock
      DIQ2                 : in  std_logic_vector(g_IQ_WIDTH-1 downto 0); --! DIQ2 data bus
      ENABLE_IQSEL2        : in  std_logic;  --! IQ select flag for DIQ2 data
      TXNRX2               : out std_logic;  --! LMS_PORT2 direction select @end
      --! @virtualbus LMS_MISC @dir out LMS miscellaneous control ports
      RESET                : out std_logic;  --! LMS hardware reset, active low
      TXEN                 : out std_logic;  --! TX hard power off
      RXEN                 : out std_logic;  --! RX hard power off
      CORE_LDO_EN          : out std_logic;  --! LMS internal LDO enable control @end
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      s_axis_tx_areset_n   : in  std_logic;  --! TX interface active low reset
      s_axis_tx_aclk       : in  std_logic;  --! TX FIFO write clock
      s_axis_tx_tvalid     : in  std_logic;  --! TX FIFO write request
      s_axis_tx_tdata      : in  std_logic_vector(63 downto 0); --! TX FIFO data
      s_axis_tx_tready     : out std_logic;  --! TX FIFO write full 
      s_axis_tx_tlast      : in  std_logic;  --! @end
      --! @virtualbus m_axis_rx @dir out Receive AXIS bus
      m_axis_rx_areset_n   : in  std_logic;  --! RX interface active low reset
      m_axis_rx_aclk       : in  std_logic;  --! RX FIFO read clock
      m_axis_rx_tvalid     : out std_logic;  --! Received data from DIQ2 port valid signal
      m_axis_rx_tdata      : out std_logic_vector(63 downto 0);   --! Received data from DIQ2 port 
      m_axis_rx_tready     : in  std_logic;   
      m_axis_rx_tlast      : out std_logic;--! @end
      -- misc
      tx_active            : out std_logic;  --! TX antenna enable flag
      rx_active            : out std_logic;  --! RX sample counter enable
      rx_diq_h             : out std_logic_vector(g_IQ_WIDTH downto 0); --! Output of Direct capture on rising edge of DIQ2 port 
      rx_diq_l             : out std_logic_vector(g_IQ_WIDTH downto 0)  --! Output of Direct capture on falling edge of DIQ2 port
   );
end lms7002_top;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of lms7002_top is
--declare signals,  components here
signal inst2_diq_h : std_logic_vector (g_IQ_WIDTH downto 0); 
signal inst2_diq_l : std_logic_vector (g_IQ_WIDTH downto 0); 

signal rx_smpl_cmp_start_sync    : std_logic;
--inst0
signal inst0_reset_n             : std_logic;

--inst1
signal inst1_fifo_0_reset_n      : std_logic;
signal inst1_fifo_1_reset_n      : std_logic;
signal inst1_clk_2x_reset_n      : std_logic;
signal inst1_txant_en            : std_logic;

signal int_mode                  : std_logic;    
signal int_trxiqpulse            : std_logic;   
signal int_ddr_en                : std_logic;
signal int_mimo_en               : std_logic;
signal int_ch_en                 : std_logic_vector(1 downto 0);
signal int_fidm                  : std_logic;


signal lms_txen_int        : std_logic;
signal lms_rxen_int        : std_logic;

signal debug_tx_ptrn_en    : std_logic;

--attribute mark_debug    : string;
--attribute keep          : string;
--attribute mark_debug of debug_tx_ptrn_en     : signal is "true";
 
begin


   --sync_reg0 : entity work.sync_reg 
   --port map(MCLK2, rx_reset_n, from_fpgacfg.rx_en, inst0_reset_n);
   
     
    
-- ----------------------------------------------------------------------------
-- RX interface
-- ----------------------------------------------------------------------------
--inst0_diq2fifo : entity work.diq2fifo
--generic map( 
--   dev_family           => g_DEV_FAMILY,
--   iq_width             => g_IQ_WIDTH,
--   invert_input_clocks  => g_INV_INPUT_CLK
--)
--port map(
--   clk            => MCLK2,
--   reset_n        => inst0_reset_n,
--   test_ptrn_en   => from_fpgacfg.rx_ptrn_en,
--   --Mode settings
--   mode           => from_fpgacfg.mode,         -- JESD207: 1; TRXIQ: 0
--   trxiqpulse     => from_fpgacfg.trxiq_pulse,  -- trxiqpulse on: 1; trxiqpulse off: 0
--   ddr_en         => from_fpgacfg.ddr_en,       -- DDR: 1; SDR: 0
--   mimo_en        => from_fpgacfg.mimo_int_en,  -- SISO: 1; MIMO: 0
--   ch_en          => from_fpgacfg.ch_en(1 downto 0),  --"01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B. 
--   fidm           => '0',  -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.
--   --Rx interface data 
--   DIQ            => DIQ2,
--   fsync          => ENABLE_IQSEL2,
--   --fifo ports 
--   fifo_wfull     => '0',
--   fifo_wrreq     => rx_data_valid,
--   fifo_wdata     => rx_data,
--   --sample compare
--   smpl_cmp_start => rx_smpl_cmp_start_sync,
--   smpl_cmp_length=> rx_smpl_cmp_length,
--   smpl_cmp_done  => rx_smpl_cmp_done,
--   smpl_cmp_err   => rx_smpl_cmp_err,
--   -- sample counter enable
--   smpl_cnt_en    => rx_smpl_cnt_en,
--   diq_h          => open,
--   diq_l          => open,
--   cap_en         => '0'
--);
   
-- ----------------------------------------------------------------------------
-- TX interface
-- ----------------------------------------------------------------------------
   inst0_lms7002_tx : entity work.lms7002_tx
   generic map( 
      g_DEV_FAMILY         => g_DEV_FAMILY,
      g_IQ_WIDTH           => g_IQ_WIDTH,
      g_S_AXIS_FIFO_WORDS  => g_S_AXIS_TX_FIFO_WORDS
   )
   port map(
      clk               => MCLK1,
      reset_n           => from_fpgacfg.tx_en,
      from_fpgacfg      => from_fpgacfg,
      --Mode settings
      mode              => from_fpgacfg.mode             ,  -- JESD207: 1; TRXIQ: 0
      trxiqpulse        => from_fpgacfg.trxiq_pulse      ,  -- trxiqpulse on: 1; trxiqpulse off: 0
      ddr_en            => from_fpgacfg.ddr_en           ,  -- DDR: 1; SDR: 0
      mimo_en           => from_fpgacfg.mimo_int_en      ,  -- SISO: 1; MIMO: 0
      ch_en             => from_fpgacfg.ch_en(1 downto 0), --"01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B. 
      fidm              => '0',  -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.                 
      --Tx interface data 
      DIQ               => DIQ1,
      fsync             => ENABLE_IQSEL1,
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      s_axis_areset_n   => s_axis_tx_areset_n,
      s_axis_aclk       => s_axis_tx_aclk    ,
      s_axis_tvalid     => s_axis_tx_tvalid  ,
      s_axis_tdata      => s_axis_tx_tdata   ,
      s_axis_tready     => s_axis_tx_tready  ,
      s_axis_tlast      => s_axis_tx_tlast   
   );

-- FIFO buffer for s_axis_tx
-- This FIFO is used for CDC between s_axis_tx_aclk and MCLK1 clocks. 
--   inst1_s_axis_fifo: entity work.fifo_axis_wrap
--   generic map(
--      g_CLOCKING_MODE   => "independent_clock",
--      g_FIFO_DEPTH      => g_S_AXIS_TX_FIFO_WORDS,
--      g_TDATA_WIDTH     => s_axis_tx_tdata'LENGTH
--   )
--   port map(
--      s_axis_aresetn    => s_axis_tx_areset_n,
--      s_axis_aclk       => s_axis_tx_aclk,
--      s_axis_tvalid     => s_axis_tx_tvalid,
--      s_axis_tready     => s_axis_tx_tready,
--      s_axis_tdata      => s_axis_tx_tdata,
--      s_axis_tlast      => s_axis_tx_tlast,
--      m_axis_aclk       => MCLK1,
--      m_axis_tvalid     => axis_tx_fifo_tvalid,
--      m_axis_tready     => axis_tx_fifo_tready,
--      m_axis_tdata      => axis_tx_fifo_tdata, 
--      m_axis_tlast      => axis_tx_fifo_tlast        
--   );
   
   
   
   
   -- Internal DIQ mode settings for TX interface
   -- (Workaround for WFM player)
--   int_mode       <= from_fpgacfg.mode                when from_fpgacfg.wfm_play = '0' else '0';
--   int_trxiqpulse <= from_fpgacfg.trxiq_pulse         when from_fpgacfg.wfm_play = '0' else '0';
--   int_ddr_en     <= from_fpgacfg.ddr_en              when from_fpgacfg.wfm_play = '0' else '1';
--   int_mimo_en    <= from_fpgacfg.mimo_int_en         when from_fpgacfg.wfm_play = '0' else '1';
--   int_ch_en      <= from_fpgacfg.ch_en(1 downto 0)   when from_fpgacfg.wfm_play = '0' else "11";

   int_mode       <= from_fpgacfg.mode             ;
   int_trxiqpulse <= from_fpgacfg.trxiq_pulse      ;
   int_ddr_en     <= from_fpgacfg.ddr_en           ;
   int_mimo_en    <= from_fpgacfg.mimo_int_en      ;
   int_ch_en      <= from_fpgacfg.ch_en(1 downto 0);

--inst1_lms7002_tx : entity work.lms7002_tx
--generic map( 
--   g_DEV_FAMILY            => g_DEV_FAMILY,
--   g_IQ_WIDTH              => g_IQ_WIDTH,
--   g_SMPL_FIFO_0_WRUSEDW   => g_TX_SMPL_FIFO_0_WRUSEDW,
--   g_SMPL_FIFO_0_DATAW     => g_TX_SMPL_FIFO_0_DATAW,
--   g_SMPL_FIFO_1_WRUSEDW   => g_TX_SMPL_FIFO_1_WRUSEDW,
--   g_SMPL_FIFO_1_DATAW     => g_TX_SMPL_FIFO_1_DATAW
--   )
--port map(
--   clk                  => MCLK1,
--   reset_n              => tx_reset_n,
--   clk_2x               => MCLK1_2x,
--   clk_2x_reset_n       => inst1_clk_2x_reset_n,
--   mem_reset_n          => mem_reset_n,
--   from_memcfg          => from_memcfg,
--   from_fpgacfg         => from_fpgacfg,
--   
--   --Mode settings
--   mode                 => int_mode,      -- JESD207: 1; TRXIQ: 0
--   trxiqpulse           => int_trxiqpulse,-- trxiqpulse on: 1; trxiqpulse off: 0
--   ddr_en               => int_ddr_en,    -- DDR: 1; SDR: 0
--   mimo_en              => int_mimo_en,   -- SISO: 0; MIMO: 1
--   ch_en                => int_ch_en,     --"01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B. 
--   fidm                 => '0', -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.
--   --TX testing
--   test_ptrn_en         => from_fpgacfg.tx_ptrn_en,
--   test_ptrn_I          => from_tstcfg.TX_TST_I,
--   test_ptrn_Q          => from_tstcfg.TX_TST_Q,
--   test_cnt_en          => from_fpgacfg.tx_cnt_en,
--   txant_cyc_before_en  => from_fpgacfg.txant_pre,
--   txant_cyc_after_en   => from_fpgacfg.txant_post,
--   txant_en             => inst1_txant_en,                 
--   --Tx interface data 
--   DIQ                  => DIQ1,
--   fsync                => ENABLE_IQSEL1,
--   -- Source select
--   tx_src_sel           => from_fpgacfg.wfm_play,  -- 0 - FIFO, 1 - diq_h/diq_l
--   --TX sample FIFO ports 
--   fifo_0_wrclk         => tx_fifo_0_wrclk,
--   fifo_0_reset_n       => inst1_fifo_0_reset_n,
--   fifo_0_wrreq         => tx_fifo_0_wrreq,
--   fifo_0_data          => tx_fifo_0_data,
--   fifo_0_wrfull        => tx_fifo_0_wrfull,
--   fifo_0_wrusedw       => tx_fifo_0_wrusedw,
--   fifo_1_wrclk         => tx_fifo_1_wrclk,
--   fifo_1_reset_n       => inst1_fifo_1_reset_n,
--   fifo_1_wrreq         => tx_fifo_1_wrreq,
--   fifo_1_data          => tx_fifo_1_data,
--   fifo_1_wrfull        => tx_fifo_1_wrfull,
--   fifo_1_wrusedw       => tx_fifo_1_wrusedw
--   
--   
--);
      
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------
   lms_txen_int <= from_fpgacfg.LMS1_TXEN when from_fpgacfg.LMS_TXRXEN_MUX_SEL = '0' else inst1_txant_en;
   lms_rxen_int <= from_fpgacfg.LMS1_RXEN when from_fpgacfg.LMS_TXRXEN_MUX_SEL = '0' else not inst1_txant_en;

 
   RESET       	<= from_fpgacfg.LMS1_RESET;
   TXEN        	<= lms_txen_int when from_fpgacfg.LMS_TXRXEN_INV='0' else not lms_txen_int;
   RXEN        	<= lms_rxen_int when from_fpgacfg.LMS_TXRXEN_INV='0' else not lms_rxen_int;
   CORE_LDO_EN 	<= from_fpgacfg.LMS1_CORE_LDO_EN;
   TXNRX1      	<= from_fpgacfg.LMS1_TXNRX1;
   TXNRX2      	<= from_fpgacfg.LMS1_TXNRX2;
   
   tx_active      <= inst1_txant_en;
   
   
end arch;   