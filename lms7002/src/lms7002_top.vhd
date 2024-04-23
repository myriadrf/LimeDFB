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
--! ]
--! ],
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
--! ]
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
--! ]
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
--! ]
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
--! ]
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

entity LMS7002_TOP is
   generic (
      G_VENDOR                   : string    := "XILINX";
      G_DEV_FAMILY               : string    := "Artix 7";  --! Device family
      G_IQ_WIDTH                 : integer   := 12;         --! IQ bus width
      G_S_AXIS_TX_FIFO_WORDS     : integer   := 16;         --! TX FIFO size in words
      G_M_AXIS_RX_FIFO_WORDS     : integer   := 16          --! RX FIFO size in words
   );
   port (
      --! @virtualbus cfg @dir in Configuration bus
      FROM_FPGACFG         : in    t_FROM_FPGACFG;                            --! Signals from FPGACFG registers
      FROM_TSTCFG          : in    t_FROM_TSTCFG;                             --! Signals from TSTCFG registers
      FROM_MEMCFG          : in    t_FROM_MEMCFG;                             --! Signals from MEMCFG registers @end
      --! @virtualbus LMS_PORT1 @dir out interface
      MCLK1                : in    std_logic;                                 --! TX interface clock
      FCLK1                : out   std_logic;                                 --! TX interface feedback clock
      DIQ1                 : out   std_logic_vector(G_IQ_WIDTH - 1 downto 0); --! DIQ1 data bus
      ENABLE_IQSEL1        : out   std_logic;                                 --! IQ select flag for DIQ1 data
      TXNRX1               : out   std_logic;                                 --! LMS_PORT1 direction select @end
      --! @virtualbus LMS_PORT2 @dir in interface
      MCLK2                : in    std_logic;                                 --! RX interface clock
      FCLK2                : out   std_logic;                                 --! RX interface feedback clock
      DIQ2                 : in    std_logic_vector(G_IQ_WIDTH - 1 downto 0); --! DIQ2 data bus
      ENABLE_IQSEL2        : in    std_logic;                                 --! IQ select flag for DIQ2 data
      TXNRX2               : out   std_logic;                                 --! LMS_PORT2 direction select @end
      --! @virtualbus LMS_MISC @dir out LMS miscellaneous control ports
      RESET                : out   std_logic;                                 --! LMS hardware reset, active low
      TXEN                 : out   std_logic;                                 --! TX hard power off
      RXEN                 : out   std_logic;                                 --! RX hard power off
      CORE_LDO_EN          : out   std_logic;                                 --! LMS internal LDO enable control @end
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      S_AXIS_TX_ARESET_N   : in    std_logic;                                 --! TX interface active low reset
      S_AXIS_TX_ACLK       : in    std_logic;                                 --! TX FIFO write clock
      S_AXIS_TX_TVALID     : in    std_logic;                                 --! TX FIFO write request
      S_AXIS_TX_TDATA      : in    std_logic_vector(63 downto 0);             --! TX FIFO data
      S_AXIS_TX_TREADY     : out   std_logic;                                 --! TX FIFO write full
      S_AXIS_TX_TLAST      : in    std_logic;                                 --! @end
      --! @virtualbus m_axis_rx @dir out Receive AXIS bus
      M_AXIS_RX_ARESET_N   : in    std_logic;                                 --! RX interface active low reset
      M_AXIS_RX_ACLK       : in    std_logic;                                 --! RX FIFO read clock
      M_AXIS_RX_TVALID     : out   std_logic;                                 --! Received data from DIQ2 port valid signal
      M_AXIS_RX_TDATA      : out   std_logic_vector(63 downto 0);             --! Received data from DIQ2 port
      M_AXIS_RX_TREADY     : in    std_logic;
      M_AXIS_RX_TLAST      : out   std_logic;                                 --! @end
      -- misc
      TX_ACTIVE            : out   std_logic;                                 --! TX antenna enable flag
      RX_ACTIVE            : out   std_logic                                  --! RX sample counter enable
   );
end entity LMS7002_TOP;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture ARCH of LMS7002_TOP is

   -- declare signals,  components here
   signal inst1_txant_en   : std_logic;
   signal inst1_diq_h      : std_logic_vector(G_IQ_WIDTH downto 0);
   signal inst1_diq_l      : std_logic_vector(G_IQ_WIDTH downto 0);

   signal lms_txen_int     : std_logic;
   signal lms_rxen_int     : std_logic;

   signal inst3_diq_h      : std_logic_vector(G_IQ_WIDTH downto 0);
   signal inst3_diq_l      : std_logic_vector(G_IQ_WIDTH downto 0);

   signal axis_tx_tvalid   : std_logic;
   signal axis_tx_tdata    : std_logic_vector(63 downto 0);
   signal axis_tx_tready   : std_logic;
   signal axis_tx_tlast    : std_logic;

   signal axis_rx_tvalid   : std_logic;
   signal axis_rx_tdata    : std_logic_vector(63 downto 0);
   signal axis_rx_tready   : std_logic;
   signal axis_rx_tlast    : std_logic;

begin

   -- ----------------------------------------------------------------------------
   -- TX interface
   -- ----------------------------------------------------------------------------
   -- This FIFO is used for CDC between s_axis_aclk and clk clocks.
   inst0_cdc_tx_fifo : entity work.fifo_axis_wrap
      generic map (
         G_CLOCKING_MODE => "independent_clock",
         G_FIFO_DEPTH    => G_S_AXIS_TX_FIFO_WORDS,
         G_TDATA_WIDTH   => S_AXIS_TX_TDATA'LENGTH
      )
      port map (
         S_AXIS_ARESETN => S_AXIS_TX_ARESET_N,
         S_AXIS_ACLK    => S_AXIS_TX_ACLK,
         S_AXIS_TVALID  => S_AXIS_TX_TVALID,
         S_AXIS_TREADY  => S_AXIS_TX_TREADY,
         S_AXIS_TDATA   => S_AXIS_TX_TDATA,
         S_AXIS_TLAST   => S_AXIS_TX_TLAST,
         M_AXIS_ACLK    => MCLK1,
         M_AXIS_TVALID  => axis_tx_tvalid,
         M_AXIS_TREADY  => axis_tx_tready,
         M_AXIS_TDATA   => axis_tx_tdata,
         M_AXIS_TLAST   => axis_tx_tlast
      );

   -- Transmit module, converts axi stream to DIQ samples
   inst1_lms7002_tx : entity work.lms7002_tx
      generic map (
         G_IQ_WIDTH => G_IQ_WIDTH
      )
      port map (
         CLK          => MCLK1,
         RESET_N      => from_fpgacfg.tx_en,
         FROM_FPGACFG => FROM_FPGACFG,
         -- Mode settings
         MODE       => from_fpgacfg.mode,
         TRXIQPULSE => from_fpgacfg.trxiq_pulse,
         DDR_EN     => from_fpgacfg.ddr_en,
         MIMO_EN    => from_fpgacfg.mimo_int_en,
         CH_EN      => from_fpgacfg.ch_en(1 downto 0),
         FIDM       => '0',
         -- Tx interface data
         DIQ_H => inst1_diq_h,
         DIQ_L => inst1_diq_l,
         --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
         S_AXIS_ARESET_N => S_AXIS_TX_ARESET_N,
         S_AXIS_ACLK     => S_AXIS_TX_ACLK,
         S_AXIS_TVALID   => axis_tx_tvalid,
         S_AXIS_TDATA    => axis_tx_tdata,
         S_AXIS_TREADY   => axis_tx_tready,
         S_AXIS_TLAST    => axis_tx_tlast
      );

   -- Vendor specific double data rate IO instance
   inst2_lms7002_ddout : entity work.lms7002_ddout
      generic map (
         DEV_FAMILY => G_DEV_FAMILY,
         IQ_WIDTH   => G_IQ_WIDTH
      )
      port map (
         -- input ports
         CLK       => MCLK1,
         RESET_N   => from_fpgacfg.tx_en,
         DATA_IN_H => inst1_diq_h,
         DATA_IN_L => inst1_diq_l,
         -- output ports
         TXIQ    => DIQ1,
         TXIQSEL => ENABLE_IQSEL1
      );

   -- ----------------------------------------------------------------------------
   -- RX interface
   -- ----------------------------------------------------------------------------
   -- Vendor specific double data rate IO instance
   inst3_lms7002_ddin : entity work.lms7002_ddin
      generic map (
         G_VENDOR              => G_VENDOR,
         G_DEV_FAMILY          => G_DEV_FAMILY,
         G_IQ_WIDTH            => G_IQ_WIDTH,
         G_INVERT_INPUT_CLOCKS => "ON"
      )
      port map (
         -- input ports
         CLK     => MCLK2,
         RESET_N => from_fpgacfg.tx_en,
         RXIQ    => DIQ2,
         RXIQSEL => ENABLE_IQSEL2,
         -- output ports
         DATA_OUT_H => inst3_diq_h,
         DATA_OUT_L => inst3_diq_l
      );

   -- LMS7002 RX interface
   inst4_lms7002_rx : entity work.lms7002_rx
      generic map (
         G_IQ_WIDTH          => G_IQ_WIDTH,
         G_M_AXIS_FIFO_WORDS => G_M_AXIS_RX_FIFO_WORDS
      )
      port map (
         CLK          => MCLK2,
         RESET_N      => from_fpgacfg.tx_en,
         FROM_FPGACFG => FROM_FPGACFG,
         -- Mode settings
         MODE       => from_fpgacfg.mode,
         TRXIQPULSE => from_fpgacfg.trxiq_pulse,
         DDR_EN     => from_fpgacfg.ddr_en,
         MIMO_EN    => from_fpgacfg.mimo_int_en,
         CH_EN      => from_fpgacfg.ch_en(1 downto 0),
         FIDM       => '0',
         -- Tx interface data
         DIQ_H => inst3_diq_h,
         DIQ_L => inst3_diq_l,
         -- Transmit AXIS bus
         M_AXIS_ARESET_N => '1',
         M_AXIS_ACLK     => MCLK2,
         M_AXIS_TVALID   => axis_rx_tvalid,
         M_AXIS_TDATA    => axis_rx_tdata,
         M_AXIS_TREADY   => axis_rx_tready,
         M_AXIS_TLAST    => axis_rx_tlast
      );

   -- Async FIFO for clock domain crossing between MCLK2 and m_axis_rx_aclk
   inst5_cdc_rx_fifo : entity work.fifo_axis_wrap
      generic map (
         G_CLOCKING_MODE => "independent_clock",
         G_FIFO_DEPTH    => G_M_AXIS_RX_FIFO_WORDS,
         G_TDATA_WIDTH   => M_AXIS_RX_TDATA'LENGTH
      )
      port map (
         S_AXIS_ARESETN => from_fpgacfg.tx_en,
         S_AXIS_ACLK    => MCLK2,
         S_AXIS_TVALID  => axis_rx_tvalid,
         S_AXIS_TREADY  => axis_rx_tready,
         S_AXIS_TDATA   => axis_rx_tdata,
         S_AXIS_TLAST   => axis_rx_tlast,
         M_AXIS_ACLK    => M_AXIS_RX_ACLK,
         M_AXIS_TVALID  => M_AXIS_RX_TVALID,
         M_AXIS_TREADY  => M_AXIS_RX_TREADY,
         M_AXIS_TDATA   => M_AXIS_RX_TDATA,
         M_AXIS_TLAST   => M_AXIS_RX_TLAST
      );

   -- ----------------------------------------------------------------------------
   -- Output ports
   -- ----------------------------------------------------------------------------
   lms_txen_int <= from_fpgacfg.LMS1_TXEN when from_fpgacfg.LMS_TXRXEN_MUX_SEL = '0' else
                   inst1_txant_en;
   lms_rxen_int <= from_fpgacfg.LMS1_RXEN when from_fpgacfg.LMS_TXRXEN_MUX_SEL = '0' else
                   not inst1_txant_en;

   RESET       <= from_fpgacfg.LMS1_RESET;
   TXEN        <= lms_txen_int when from_fpgacfg.LMS_TXRXEN_INV='0' else
                  not lms_txen_int;
   RXEN        <= lms_rxen_int when from_fpgacfg.LMS_TXRXEN_INV='0' else
                  not lms_rxen_int;
   CORE_LDO_EN <= from_fpgacfg.LMS1_CORE_LDO_EN;
   TXNRX1      <= from_fpgacfg.LMS1_TXNRX1;
   TXNRX2      <= from_fpgacfg.LMS1_TXNRX2;

   TX_ACTIVE <= inst1_txant_en;

end architecture ARCH;
