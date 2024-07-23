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
--! ['s_axi_tx', 
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=...=...=...=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=...=...=...=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x...=.=...=...=...=|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x...=.=...=...=...=|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" },
--! ], 
--! ['LMS_DIQ',
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=============|", data: ["AI(0)", "AQ(0)", "BI(0)", "BQ(0)", "AI(1)", "AQ(1)", "BI(1)", "BQ(1)", "AI(2)", "AQ(2)", "BI(2)", "BQ(2)"] },
--!]
--!],
--! 
--! "config" : { "hscale" : 1 },
--!  head:{
--!     text: ['tspan', 
--!           ['tspan', {'font-weight':'bold'}, 's_axis_tx bus timing (MIMO DDR mode, A and B channels enabled)']], 
--!     tick:0,
--!     every:2
--!   }}

-- s_axis_tx bus timing (MIMO DDR mode, A channel enabled)
--! { signal: [
--! ['s_axi_tx',
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=...=...=...=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=...=...=...=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x..................|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x..................|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" }, 
--! ], 
--! ['LMS_DIQ', 
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=============|", data: ["AI(0)", "AQ(0)", "0", "0", "AI(1)", "AQ(1)", "0", "0", "AI(2)", "AQ(2)", "0", "0"] },
--!]
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
--! ['s_axi_tx',
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x..................|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x..................|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x...=.=...=...=...=|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x...=.=...=...=...=|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" }, 
--! ], 
--! ['LMS_DIQ', 
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=============|", data: ["0", "0", "BI(0)", "BQ(0)", "0", "0", "BI(1)", "BQ(1)", "0", "0", "BI(2)", "BQ(2)"] },
--!]
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
--! ['s_axi_tx',
--!  { name: "s_axi_tx_aclk",  wave: "P......" , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1..........|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1........|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=.=.=.=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=.=.=.=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x............|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x............|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1........|" },
--! ], 
--! ['LMS_DIQ',  
--!  { name: "FCLK1",  wave: "HLHLHLHLHLHLHL"},
--!  { name: "ENABLE_IQSEL1", wave: "0......101010|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=======|", data: ["AI(0)", "AQ(0)", "AI(1)", "AQ(1)", "AI(2)", "AQ(2)", "AI(n)", "AQ(n)", "AI(2)", "AQ(2)", "BI(2)", "BQ(2)"] },
--!]
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
--! ['s_axi_tx',
--!  { name: "s_axi_tx_aclk",  wave: "P........." , period: 2},
--!  { name: "s_axi_tx_areset_n", wave: "0.1................|" },
--!  { name: "s_axi_tx_tvalid", wave: "0...1..............|" },
--!  { name: "s_axi_tx_tdata[63:48]",  wave: "x...=.=...=...=...=|", data: ["AI(0)", "AI(1)", "AI(2)", "AI(n)"] },
--!  { name: "s_axi_tx_tdata[47:32]",  wave: "x...=.=...=...=...=|", data: ["AQ(0)", "AQ(1)", "AQ(2)", "AQ(n)"] },
--!  { name: "s_axi_tx_tdata[31:16]",  wave: "x..................|", data: ["BI(0)", "BI(1)", "BI(2)", "BI(n)"] },
--!  { name: "s_axi_tx_tdata[15: 0]",  wave: "x..................|", data: ["BQ(0)", "BQ(1)", "BQ(2)", "BQ(n)"] },
--!  { name: "s_axi_tx_tready", wave: "0...1.0.1.0.1.0.1.0|" },  
--! ], 
--! ['LMS_DIQ', 
--!  { name: "FCLK1",  wave: "hLhLhLhLhLhLhLhLhLhL"},
--!  { name: "ENABLE_IQSEL1", wave: "0.......1.0.1.0.1.0|"},
--!  { name: "DIQ1[11:0]",  wave: "x.....=.=.=.=.=.=.=|", data: ["AI(0)", "AQ(0)", "AI(1)", "AQ(1)", "AI(2)", "AQ(2)", "AI(n)", "0"] },
--!]
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

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity lms7002_top is
   generic(
      g_VENDOR                   : string    := "XILINX";
      g_DEV_FAMILY               : string    := "Artix 7";  --! Device family
      g_IQ_WIDTH                 : integer   := 12;         --! IQ bus width
      g_S_AXIS_TX_FIFO_WORDS     : integer   := 16;         --! TX FIFO size in words
      g_M_AXIS_RX_FIFO_WORDS     : integer   := 16          --! RX FIFO size in words
   );
   port (  
      --! @virtualbus cfg @dir in Configuration bus
      CFG_TX_EN	            : in  std_logic;
      CFG_TRXIQ_PULSE       : in  std_logic;
      CFG_DDR_EN            : in  std_logic;
      CFG_MIMO_INT_EN       : in  std_logic;
      CFG_CH_EN	            : in  std_logic_vector(1 downto 0);
      CFG_LMS_TXEN	    : in  std_logic;
      CFG_LMS_TXRXEN_MUX_SEL: in  std_logic;
      CFG_LMS_RXEN	    : in  std_logic;
      CFG_LMS_RESET	    : in  std_logic;
      CFG_LMS_TXRXEN_INV    : in  std_logic;
      CFG_LMS_CORE_LDO_EN   : in  std_logic;
      CFG_LMS_TXNRX1	    : in  std_logic;
      CFG_LMS_TXNRX2	    : in  std_logic; --! Signals from FPGACFG registers @end
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
      m_axis_rx_tkeep      : out std_logic_vector(7 downto 0);    --! Received data byte qualifier
      m_axis_rx_tready     : in  std_logic;   
      m_axis_rx_tlast      : out std_logic;--! @end
      -- misc
      tx_active            : out std_logic;  --! TX antenna enable flag
      rx_active            : out std_logic   --! RX sample counter enable
   );
end lms7002_top;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of lms7002_top is
--declare signals,  components here
signal inst1_txant_en   : std_logic;
signal inst1_diq_h      : std_logic_vector(g_IQ_WIDTH downto 0);
signal inst1_diq_l      : std_logic_vector(g_IQ_WIDTH downto 0);

signal lms_txen_int     : std_logic;
signal lms_rxen_int     : std_logic;

signal inst3_diq_h      : std_logic_vector(g_IQ_WIDTH downto 0);
signal inst3_diq_l      : std_logic_vector(g_IQ_WIDTH downto 0);

signal axis_tx_tvalid   : std_logic;
signal axis_tx_tdata    : std_logic_vector(63 downto 0);
signal axis_tx_tready   : std_logic;
signal axis_tx_tlast    : std_logic;

signal axis_rx_tvalid   : std_logic;
signal axis_rx_tdata    : std_logic_vector(63 downto 0);
signal axis_rx_tkeep    : std_logic_vector(7 downto 0);
signal axis_rx_tready   : std_logic;
signal axis_rx_tlast    : std_logic;

signal mclk2_pll_out1   : std_logic;
signal mclk2_pll_out2   : std_logic;


begin
   
   
-- ----------------------------------------------------------------------------
-- TX interface
-- ----------------------------------------------------------------------------
   -- This FIFO is used for CDC between s_axis_aclk and clk clocks. 
   inst0_cdc_tx_fifo: entity work.fifo_axis_wrap
   generic map(
      g_CLOCKING_MODE   => "independent_clock",
      g_FIFO_DEPTH      => g_S_AXIS_TX_FIFO_WORDS,
      g_TDATA_WIDTH     => s_axis_tx_tdata'LENGTH
   )
   port map(
      s_axis_aresetn    => s_axis_tx_areset_n,
      s_axis_aclk       => s_axis_tx_aclk,
      s_axis_tvalid     => s_axis_tx_tvalid,
      s_axis_tready     => s_axis_tx_tready,
      s_axis_tdata      => s_axis_tx_tdata,
      s_axis_tlast      => s_axis_tx_tlast,
      m_axis_aclk       => MCLK1,
      m_axis_tvalid     => axis_tx_tvalid,
      m_axis_tready     => axis_tx_tready,
      m_axis_tdata      => axis_tx_tdata, 
      m_axis_tlast      => axis_tx_tlast        
   );


   -- Transmit module, converts axi stream to DIQ samples
   inst1_lms7002_tx : entity work.lms7002_tx
   generic map( 
      g_IQ_WIDTH           => g_IQ_WIDTH
   )
   port map(
      clk               => MCLK1,
      reset_n           => CFG_tx_en,
      --Mode settings
      mode              => '0'                           ,  -- JESD207: 1; TRXIQ: 0
      trxiqpulse        => CFG_trxiq_pulse      ,  -- trxiqpulse on: 1; trxiqpulse off: 0
      ddr_en            => CFG_ddr_en           ,  -- DDR: 1; SDR: 0
      mimo_en           => CFG_mimo_int_en      ,  -- SISO: 1; MIMO: 0
      ch_en             => CFG_ch_en(1 downto 0), --"01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B. 
      fidm              => '0',  -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.                 
      --Tx interface data 
      diq_h             => inst1_diq_h,
      diq_l             => inst1_diq_l,
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      s_axis_areset_n   => s_axis_tx_areset_n,
      s_axis_aclk       => s_axis_tx_aclk ,
      s_axis_tvalid     => axis_tx_tvalid ,
      s_axis_tdata      => axis_tx_tdata  ,
      s_axis_tready     => axis_tx_tready ,
      s_axis_tlast      => axis_tx_tlast   
   );
   
   
   -- Vendor specific double data rate IO instance
   inst2_lms7002_ddout : entity work.lms7002_ddout
   generic map( 
      dev_family     => g_DEV_FAMILY,
      iq_width       => g_IQ_WIDTH
   )
   port map(
      --input ports 
      clk            => MCLK1,
      reset_n        => CFG_tx_en,
      data_in_h      => inst1_diq_h,
      data_in_l      => inst1_diq_l,
      --output ports 
      txiq           => DIQ1,
      txiqsel        => ENABLE_IQSEL1
   ); 
   
   
-- ----------------------------------------------------------------------------
-- RX interface
-- ----------------------------------------------------------------------------


   --rx_pll_inst : entity work.rx_pll
   --port map(
      --clk_out1  => mclk2_pll_out1,
      --clk_out2  => mclk2_pll_out2,
      --resetn    => '1',
      --locked    => open, 
      --clk_in1   => MCLK2
   --);


   -- Vendor specific double data rate IO instance 
   inst3_lms7002_ddin : entity work.lms7002_ddin
   generic map( 
      g_VENDOR              => g_VENDOR,     -- Valid values: "ALTERA", "XILINX"
      g_DEV_FAMILY          => g_DEV_FAMILY, -- Reserved
      g_IQ_WIDTH            => g_IQ_WIDTH,
      g_INVERT_INPUT_CLOCKS => "ON"
   )
   port map(
      --input ports 
      clk             => MCLK2,
      reset_n         => CFG_tx_en,
      rxiq            => DIQ2,
      rxiqsel         => ENABLE_IQSEL2,
      --output ports 
      data_out_h      => inst3_diq_h,
      data_out_l      => inst3_diq_l
   );


   -- LMS7002 RX interface
   inst4_lms7002_rx : entity work.lms7002_rx
   generic map( 
      g_IQ_WIDTH           => g_IQ_WIDTH,
      g_M_AXIS_FIFO_WORDS  => g_M_AXIS_RX_FIFO_WORDS
   )
   port map(
      clk               => MCLK2,
      reset_n           => CFG_tx_en,
      --Mode settings
      mode              => '0'             ,  -- JESD207: 1; TRXIQ: 0
      trxiqpulse        => CFG_trxiq_pulse      ,  -- trxiqpulse on: 1; trxiqpulse off: 0
      ddr_en            => CFG_ddr_en           ,  -- DDR: 1; SDR: 0
      mimo_en           => CFG_mimo_int_en      ,  -- SISO: 1; MIMO: 0
      ch_en             => CFG_ch_en(1 downto 0),  -- "01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B. 
      fidm              => '0',  -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.                 
      --Tx interface data
      diq_h             => inst3_diq_h,
      diq_l             => inst3_diq_l,
      -- Transmit AXIS bus
      m_axis_areset_n   => '1',
      m_axis_aclk       => MCLK2,
      m_axis_tvalid     => axis_rx_tvalid,
      m_axis_tdata      => axis_rx_tdata ,
      m_axis_tkeep      => axis_rx_tkeep, 
      m_axis_tready     => axis_rx_tready,
      m_axis_tlast      => axis_rx_tlast 
   );
   
   
   -- Async FIFO for clock domain crossing between MCLK2 and m_axis_rx_aclk
   inst5_cdc_rx_fifo: entity work.fifo_axis_wrap
   generic map(
      g_CLOCKING_MODE   => "independent_clock",
      g_FIFO_DEPTH      => g_M_AXIS_RX_FIFO_WORDS,
      g_TDATA_WIDTH     => m_axis_rx_tdata'LENGTH
   )
   port map(
      s_axis_aresetn    => CFG_tx_en,
      s_axis_aclk       => MCLK2,
      s_axis_tvalid     => axis_rx_tvalid,
      s_axis_tready     => axis_rx_tready,
      s_axis_tdata      => axis_rx_tdata,
      s_axis_tkeep      => axis_rx_tkeep,
      s_axis_tlast      => axis_rx_tlast,
      m_axis_aclk       => m_axis_rx_aclk,
      m_axis_tvalid     => m_axis_rx_tvalid,
      m_axis_tready     => m_axis_rx_tready,
      m_axis_tdata      => m_axis_rx_tdata, 
      m_axis_tkeep      => m_axis_rx_tkeep,
      m_axis_tlast      => m_axis_rx_tlast        
   );

 
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------
   lms_txen_int <= CFG_LMS_TXEN when CFG_LMS_TXRXEN_MUX_SEL = '0' else inst1_txant_en;
   lms_rxen_int <= CFG_LMS_RXEN when CFG_LMS_TXRXEN_MUX_SEL = '0' else not inst1_txant_en;

 
   RESET       	<= CFG_LMS_RESET;
   TXEN        	<= lms_txen_int when CFG_LMS_TXRXEN_INV='0' else not lms_txen_int;
   RXEN        	<= lms_rxen_int when CFG_LMS_TXRXEN_INV='0' else not lms_rxen_int;
   CORE_LDO_EN 	<= CFG_LMS_CORE_LDO_EN;
   TXNRX1      	<= CFG_LMS_TXNRX1;
   TXNRX2      	<= CFG_LMS_TXNRX2;
   
   tx_active      <= inst1_txant_en;
   
   FCLK1        <= mclk2_pll_out1;
   
   
end arch;   
