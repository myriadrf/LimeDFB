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
   use work.fpgacfg_pkg.all;
   use work.tstcfg_pkg.all;
   use work.memcfg_pkg.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------

entity LMS7002_TOP_TB is
end entity LMS7002_TOP_TB;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture TB_BEHAVE of LMS7002_TOP_TB is

   constant CLK0_PERIOD             : time := 8 ns;
   constant CLK1_PERIOD             : time := 8 ns;
   constant SYS_CLK_PERIOD          : time := 8 ns;

   constant C_MIMO_DDR_SAMPLES      : integer := 16;
   -- signals
   signal clk0, clk1                : std_logic;
   signal sys_clk                   : std_logic;
   signal reset_n                   : std_logic;

   signal dut1_diq1                 : std_logic_vector(11 downto 0);
   signal dut1_enable_iqsel1        : std_logic;

   signal dut1_from_fpgacfg         : t_FROM_FPGACFG;
   signal dut1_from_tstcfg          : t_FROM_TSTCFG;
   signal dut1_from_memcfg          : t_FROM_MEMCFG;

   signal s_axis_tx_tvalid          : std_logic;
   signal s_axis_tx_tdata           : std_logic_vector(63 downto 0);
   signal s_axis_tx_tready          : std_logic;
   signal s_axis_tx_tlast           : std_logic;

   alias s_axis_tx_tdata_ai         is s_axis_tx_tdata(63 downto 52);
   alias s_axis_tx_tdata_aq         is s_axis_tx_tdata(47 downto 36);
   alias s_axis_tx_tdata_bi         is s_axis_tx_tdata(31 downto 20);
   alias s_axis_tx_tdata_bq         is s_axis_tx_tdata(15 downto  4);

   type T_TXIQ_MODE is (MIMO_DDR, SISO_DDR, TXIQ_PULSE);

   signal txiq_mode                 : T_TXIQ_MODE;

   signal ch_en                     : std_logic_vector(1 downto 0);

   signal wait_cycles               : integer;

   procedure set_txiq_mode (
      signal clk          : in  std_logic;
      signal txiq_mode    : in  T_TXIQ_MODE;
      signal ch_en        : in  std_logic_vector(1 downto 0);
      signal from_fpgacfg : out t_FROM_FPGACFG
   ) is
   begin

      report "Entering set_txiq_mode"
         severity NOTE;
      wait until rising_edge(clk);

      case txiq_mode is

         when MIMO_DDR =>
            from_fpgacfg.mode              <= '0';
            from_fpgacfg.trxiq_pulse       <= '0';
            from_fpgacfg.ddr_en            <= '1';
            from_fpgacfg.mimo_int_en       <= '1';
            from_fpgacfg.ch_en(1 downto 0) <= ch_en;

         when SISO_DDR =>
            from_fpgacfg.mode              <= '0';
            from_fpgacfg.trxiq_pulse       <= '0';
            from_fpgacfg.ddr_en            <= '1';
            from_fpgacfg.mimo_int_en       <= '0';
            from_fpgacfg.ch_en(1 downto 0) <= ch_en;

         when TXIQ_PULSE =>
            from_fpgacfg.mode              <= '0';
            from_fpgacfg.trxiq_pulse       <= '1';
            from_fpgacfg.ddr_en            <= '0';
            from_fpgacfg.mimo_int_en       <= '0';
            from_fpgacfg.ch_en(1 downto 0) <= ch_en;

         when others =>
            from_fpgacfg.mode              <= '0';
            from_fpgacfg.trxiq_pulse       <= '0';
            from_fpgacfg.ddr_en            <= '0';
            from_fpgacfg.mimo_int_en       <= '0';
            from_fpgacfg.ch_en(1 downto 0) <= "00";

      end case;

      report "Exiting set_txiq_mode"
         severity NOTE;

   end procedure;

   procedure generate_axis_data (
      signal reset_n       : in     std_logic;
      signal clk           : in     std_logic;
      signal txiq_mode     : in     T_TXIQ_MODE;
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
      wait for CLK0_PERIOD / 2;
      clk0 <= '1';
      wait for CLK0_PERIOD / 2;

   end process CLOCK0;

   CLOCK1 : process is
   begin

      -- Simulate 90deg phase shift
      wait for CLK1_PERIOD / 4;

      loop

         clk1 <= '0';
         wait for CLK1_PERIOD / 2;
         clk1 <= '1';
         wait for CLK1_PERIOD / 2;

      end loop;

   end process CLOCK1;

   SYS_CLOCK : process is
   begin

      sys_clk <= '0';
      wait for SYS_CLK_PERIOD / 2;
      sys_clk <= '1';
      wait for SYS_CLK_PERIOD / 2;

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
         --! @virtualbus cfg @dir in Configuration bus
         FROM_FPGACFG => dut1_from_fpgacfg,
         FROM_TSTCFG  => dut1_from_tstcfg,
         FROM_MEMCFG  => dut1_from_memcfg,
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
         RX_ACTIVE => open
      );

   TB_TRANSMIT_PROC : process is
   begin

      dut1_from_fpgacfg.tx_en <= '0';
      wait until reset_n='1' and rising_edge(sys_clk);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A AND B channels
      txiq_mode <= MIMO_DDR;
      ch_en     <= "11";
      wait until rising_edge(sys_clk);
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          reset_n       => reset_n,
                          clk           => sys_clk,
                          txiq_mode     => txiq_mode,
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
      dut1_from_fpgacfg.tx_en <= '0';

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channels
      txiq_mode <= MIMO_DDR;
      ch_en     <= "01";
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          reset_n       => reset_n,
                          clk           => sys_clk,
                          txiq_mode     => txiq_mode,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable B channel
      txiq_mode <= MIMO_DDR;
      ch_en     <= "10";
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          reset_n       => reset_n,
                          clk           => sys_clk,
                          txiq_mode     => txiq_mode,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';

      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channel
      txiq_mode <= SISO_DDR;
      ch_en     <= "01";  -- Does not matter in SISO DDR
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          reset_n       => reset_n,
                          clk           => sys_clk,
                          txiq_mode     => txiq_mode,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';

      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channel
      txiq_mode <= TXIQ_PULSE;
      ch_en     <= "01";  -- Does not matter in TXIQ_PULSE
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg);

      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';

      -- Generate IQ data
      generate_axis_data (
                          reset_n       => reset_n,
                          clk           => sys_clk,
                          txiq_mode     => txiq_mode,
                          s_axis_tvalid => s_axis_tx_tvalid,
                          s_axis_tdata  => s_axis_tx_tdata,
                          s_axis_tready => s_axis_tx_tready,
                          s_axis_tlast  => s_axis_tx_tlast
                       );
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);

      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';

      wait;

   end process TB_TRANSMIT_PROC;

end architecture TB_BEHAVE;

