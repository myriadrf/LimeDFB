-- ----------------------------------------------------------------------------
-- FILE:          lms7002_top_tb.vhd
-- DESCRIPTION:   Test bech for lms7002_top module
-- DATE:          11:09 2024-02-01
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

entity LMS7002_TOP_TB is
end entity LMS7002_TOP_TB;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture TB_BEHAVE of LMS7002_TOP_TB is

   constant C_CLK0_PERIOD                       : time := 8 ns;
   constant C_CLK1_PERIOD                       : time := 8 ns;
   constant C_SYS_CLK_PERIOD                    : time := 8 ns;

   constant C_MIMO_DDR_SAMPLES                  : integer := 16;
   -- signals
   signal clk0, clk1                            : std_logic;
   signal sys_clk                               : std_logic;
   signal reset_n                               : std_logic;

   signal dut1_diq1                             : std_logic_vector(11 downto 0);
   signal dut1_enable_iqsel1                    : std_logic;

   signal dut1_trxiq_pulse                      : std_logic;
   signal dut1_ddr_en                           : std_logic;
   signal dut1_mimo_int_en                      : std_logic;
   signal dut1_tx_en                            : std_logic;

   signal s_axis_tx_tvalid                      : std_logic;
   signal s_axis_tx_tdata                       : std_logic_vector(63 downto 0);
   signal s_axis_tx_tready                      : std_logic;
   signal s_axis_tx_tlast                       : std_logic;

   alias s_axis_tx_tdata_ai                     is s_axis_tx_tdata(63 downto 52);
   alias s_axis_tx_tdata_aq                     is s_axis_tx_tdata(47 downto 36);
   alias s_axis_tx_tdata_bi                     is s_axis_tx_tdata(31 downto 20);
   alias s_axis_tx_tdata_bq                     is s_axis_tx_tdata(15 downto  4);

   type T_TXIQ_MODE is (MIMO_DDR, SISO_DDR, TXIQ_PULSE);

   signal dut1_txiq_mode                        : T_TXIQ_MODE;

   signal dut1_ch_en                            : std_logic_vector(1 downto 0);

   signal wait_cycles                           : integer;

   procedure set_txiq_mode (
      signal clk         : in  std_logic;
      signal txiq_mode   : in  T_TXIQ_MODE;
      signal trxiq_pulse : out std_logic;
      signal ddr_en      : out std_logic;
      signal mimo_int_en : out std_logic

   ) is
   begin

      report "Entering set_txiq_mode"
         severity NOTE;
      wait until rising_edge(clk);

      case txiq_mode is

         when MIMO_DDR =>
            trxiq_pulse <= '0';
            ddr_en      <= '1';
            mimo_int_en <= '1';

         when SISO_DDR =>
            trxiq_pulse <= '0';
            ddr_en      <= '1';
            mimo_int_en <= '0';

         when TXIQ_PULSE =>
            trxiq_pulse <= '1';
            ddr_en      <= '0';
            mimo_int_en <= '0';

         when others =>
            trxiq_pulse <= '0';
            ddr_en      <= '0';
            mimo_int_en <= '0';

      end case;

      report "Exiting set_txiq_mode"
         severity NOTE;

   end procedure;

   procedure generate_axis_data (
      signal clk           : in     std_logic;
      signal txiq_mode     : in     T_TXIQ_MODE;
      signal ch_en         : in     std_logic_vector(1 downto 0);
      signal s_axis_tvalid : out    std_logic;
      signal s_axis_tdata  : inout  std_logic_vector(63 downto 0);
      signal s_axis_tready : in     std_logic;
      signal s_axis_tlast  : out    std_logic

   ) is
   begin

      report "Entering generate_axis_data"
         severity NOTE;
      wait until rising_edge(clk);
      s_axis_tvalid <= '0';
      s_axis_tdata  <= (others => '0');

      if ((ch_en = "11" and txiq_mode = MIMO_DDR) or txiq_mode = TXIQ_PULSE) then
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"001";
         s_axis_tdata(31 downto 20) <= x"002";
         s_axis_tdata(15 downto  4) <= x"003";
      elsif ((ch_en = "01" and txiq_mode = MIMO_DDR) or txiq_mode = SISO_DDR) then
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"001";
         s_axis_tdata(31 downto 20) <= x"000";
         s_axis_tdata(15 downto  4) <= x"000";
      elsif (ch_en = "10" and txiq_mode = MIMO_DDR) then
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"000";
         s_axis_tdata(31 downto 20) <= x"000";
         s_axis_tdata(15 downto  4) <= x"001";
      else
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"000";
         s_axis_tdata(31 downto 20) <= x"000";
         s_axis_tdata(15 downto  4) <= x"000";
      end if;

      s_axis_tlast <= '0';

      wait until rising_edge(sys_clk);
      s_axis_tvalid <= '1';

      for i in 0 to C_MIMO_DDR_SAMPLES - 1 loop

         wait until rising_edge(sys_clk) and s_axis_tready='1';

         case txiq_mode is

            when MIMO_DDR =>

               if (ch_en = "11") then
                  s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52)) + 4);
                  s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36)) + 4);
                  s_axis_tdata(31 downto 20) <= std_logic_vector(unsigned(s_axis_tdata(31 downto 20)) + 4);
                  s_axis_tdata(15 downto  4) <= std_logic_vector(unsigned(s_axis_tdata(15 downto  4)) + 4);
               elsif (ch_en = "01") then
                  s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52)) + 2);
                  s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36)) + 2);
                  s_axis_tdata(31 downto 20) <= (others => '0');
                  s_axis_tdata(15 downto  4) <= (others => '0');
               elsif (ch_en = "10") then
                  s_axis_tdata(63 downto 52) <= (others => '0');
                  s_axis_tdata(47 downto 36) <= (others => '0');
                  s_axis_tdata(31 downto 20) <= std_logic_vector(unsigned(s_axis_tdata(31 downto 20)) + 2);
                  s_axis_tdata(15 downto  4) <= std_logic_vector(unsigned(s_axis_tdata(15 downto  4)) + 2);
               else
                  s_axis_tdata(63 downto 52) <= (others => '0');
                  s_axis_tdata(47 downto 36) <= (others => '0');
                  s_axis_tdata(31 downto 20) <= (others => '0');
                  s_axis_tdata(15 downto  4) <= (others => '0');
               end if;

            when SISO_DDR =>
               s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52)) + 2);
               s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36)) + 2);
               s_axis_tdata(31 downto 20) <= (others => '0');
               s_axis_tdata(15 downto  4) <= (others => '0');

            when TXIQ_PULSE =>
               s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52)) + 4);
               s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36)) + 4);
               s_axis_tdata(31 downto 20) <= std_logic_vector(unsigned(s_axis_tdata(31 downto 20)) + 4);
               s_axis_tdata(15 downto  4) <= std_logic_vector(unsigned(s_axis_tdata(15 downto  4)) + 4);

            when others =>
               s_axis_tdata(63 downto 52) <= (others => '0');
               s_axis_tdata(47 downto 36) <= (others => '0');
               s_axis_tdata(31 downto 20) <= (others => '0');
               s_axis_tdata(15 downto  4) <= (others => '0');

         end case;

      end loop;

      wait until rising_edge(sys_clk) and s_axis_tready='1';
      s_axis_tvalid <= '0';
      report "Exiting generate_axis_data"
         severity NOTE;

   end procedure;

   procedure wait_sync_cycles (
      signal clk            : in std_logic;
      signal cycles_to_wait : in integer
   ) is
   begin

      report "Entering wait_sync_cycles"
         severity NOTE;
      report "Cycles to wait: " & integer'image(cycles_to_wait);
      wait until rising_edge(clk);

      for i in 0 to cycles_to_wait loop

         wait until rising_edge(clk);
         report "Waiting"
            severity NOTE;

      end loop;

      report "Exiting wait_sync_cycles"
         severity NOTE;

   end procedure;

begin

   CLOCK0 : process is
   begin

      clk0 <= '0';
      wait for C_CLK0_PERIOD / 2;
      clk0 <= '1';
      wait for C_CLK0_PERIOD / 2;

   end process CLOCK0;

   CLOCK1 : process is
   begin

      -- Simulate 90deg phase shift
      wait for C_CLK1_PERIOD / 4;

      loop

         clk1 <= '0';
         wait for C_CLK1_PERIOD / 2;
         clk1 <= '1';
         wait for C_CLK1_PERIOD / 2;

      end loop;

   end process CLOCK1;

   SYS_CLOCK : process is
   begin

      sys_clk <= '0';
      wait for C_SYS_CLK_PERIOD / 2;
      sys_clk <= '1';
      wait for C_SYS_CLK_PERIOD / 2;

   end process SYS_CLOCK;

   RES : process is
   begin

      reset_n <= '0';
      wait for 20 ns;
      reset_n <= '1';
      wait;

   end process RES;

   -- Design under test
   dut1_lms7002_top : entity work.lms7002_top
      generic map (
         G_DEV_FAMILY => "Cyclone IV E",
         G_IQ_WIDTH   => 12
      )
      port map (
         --! @virtualbus LMS_PORT1 @dir out interface
         MCLK1         => clk0,
         FCLK1         => open,
         DIQ1          => dut1_diq1,
         ENABLE_IQSEL1 => dut1_enable_iqsel1,
         TXNRX1        => open,
         --! @virtualbus LMS_PORT2 @dir in interface
         MCLK2         => clk1,
         FCLK2         => open,
         DIQ2          => dut1_diq1,
         ENABLE_IQSEL2 => dut1_enable_iqsel1,
         TXNRX2        => open,
         --! @virtualbus LMS_MISC @dir out LMS miscellaneous control ports
         RESET       => open,
         TXEN        => open,
         RXEN        => open,
         CORE_LDO_EN => open,
         --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
         S_AXIS_TX_ARESET_N => reset_n,
         S_AXIS_TX_ACLK     => sys_clk,
         S_AXIS_TX_TVALID   => s_axis_tx_tvalid,
         S_AXIS_TX_TDATA    => s_axis_tx_tdata,
         S_AXIS_TX_TREADY   => s_axis_tx_tready,
         S_AXIS_TX_TLAST    => s_axis_tx_tlast,
         --! @virtualbus m_axis_rx @dir out Receive AXIS bus
         M_AXIS_RX_ARESET_N => reset_n,
         M_AXIS_RX_ACLK     => sys_clk,
         M_AXIS_RX_TVALID   => open,
         M_AXIS_RX_TDATA    => open,
         M_AXIS_RX_TREADY   => '1',
         -- misc
         TX_ACTIVE => open,
         RX_ACTIVE => open,
         --! @virtualbus interface_cfg @dir in Interface configuration pins
         TX_EN              => dut1_tx_en,
         TRXIQ_PULSE        => dut1_trxiq_pulse,
         DDR_EN             => dut1_ddr_en,
         MIMO_INT_EN        => dut1_mimo_int_en,
         CH_EN              => dut1_ch_en,
         LMS1_TXEN          => '0',
         LMS_TXRXEN_MUX_SEL => '0',
         LMS1_RXEN          => '0',
         LMS1_RESET         => '0',
         LMS_TXRXEN_INV     => '0',
         LMS1_CORE_LDO_EN   => '0',
         LMS1_TXNRX1        => '0',
         LMS1_TXNRX2        => '0'
      );

   TB_TRANSMIT_PROC : process is
   begin

      dut1_tx_en <= '0';
      wait until reset_n='1' and rising_edge(sys_clk);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A AND B channels
      dut1_txiq_mode <= MIMO_DDR;
      dut1_ch_en     <= "11";
      wait until rising_edge(sys_clk);
      set_txiq_mode(clk=> sys_clk, txiq_mode => dut1_txiq_mode, trxiq_pulse => dut1_trxiq_pulse, ddr_en => dut1_ddr_en, mimo_int_en => dut1_mimo_int_en);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          clk           => sys_clk,
                          txiq_mode     => dut1_txiq_mode,
                          ch_en         => dut1_ch_en,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );

      wait_cycles <= 64;
      wait until rising_edge(sys_clk);
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      report "Disabling tx"
         severity NOTE;
      dut1_tx_en <= '0';

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channels
      dut1_txiq_mode <= MIMO_DDR;
      dut1_ch_en     <= "01";
      set_txiq_mode(clk=> sys_clk, txiq_mode => dut1_txiq_mode, trxiq_pulse => dut1_trxiq_pulse, ddr_en => dut1_ddr_en, mimo_int_en => dut1_mimo_int_en);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          clk           => sys_clk,
                          txiq_mode     => dut1_txiq_mode,
                          ch_en         => dut1_ch_en,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '0';

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable B channel
      dut1_txiq_mode <= MIMO_DDR;
      dut1_ch_en     <= "10";
      set_txiq_mode(clk=> sys_clk, txiq_mode => dut1_txiq_mode, trxiq_pulse => dut1_trxiq_pulse, ddr_en => dut1_ddr_en, mimo_int_en => dut1_mimo_int_en);
      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          clk           => sys_clk,
                          txiq_mode     => dut1_txiq_mode,
                          ch_en         => dut1_ch_en,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '0';

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channel
      dut1_txiq_mode <= SISO_DDR;
      dut1_ch_en     <= "01";  -- Does not matter in SISO DDR
      set_txiq_mode(clk=> sys_clk, txiq_mode => dut1_txiq_mode, trxiq_pulse => dut1_trxiq_pulse, ddr_en => dut1_ddr_en, mimo_int_en => dut1_mimo_int_en);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          clk           => sys_clk,
                          txiq_mode     => dut1_txiq_mode,
                          ch_en         => dut1_ch_en,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '0';

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channel
      dut1_txiq_mode <= TXIQ_PULSE;
      dut1_ch_en     <= "01";  -- Does not matter in TXIQ_PULSE
      set_txiq_mode(clk=> sys_clk, txiq_mode => dut1_txiq_mode, trxiq_pulse => dut1_trxiq_pulse, ddr_en => dut1_ddr_en, mimo_int_en => dut1_mimo_int_en);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          clk           => sys_clk,
                          txiq_mode     => dut1_txiq_mode,
                          ch_en         => dut1_ch_en,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_tx_en <= '0';

      wait;

   end process TB_TRANSMIT_PROC;

end architecture TB_BEHAVE;

