-- ----------------------------------------------------------------------------
-- FILE:          txiq_ptrn_cmp_tb.vhd
-- DESCRIPTION:   TX phase-search pattern (txiq_tst_ptrn) looped back into the
--                sample comparator (smpl_cmp_xtrx.vhd), with an idealised
--                LMS7002M digital loopback (TX DIQ_H/I -> RX DIQ_L, TX DIQ_L/Q
--                -> RX DIQ_H, IQSEL passed through).
--   Generics select the fault model on the interface:
--     g_FAULT = 0 : clean
--     g_FAULT = 1 : pin 9 rising at the I->Q boundary is latched into I
--                   (the failure seen on LimeSDR-USB at >= 112 MHz)
--     g_FAULT = 2 : half-period slip (I <- Q of frame k, Q <- I of frame k+1)
--     g_FAULT = 3 : A/B (frame) swap, IQSEL inverted
--   g_EXPECT_ERR states whether smpl_cmp must report an error.
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity txiq_ptrn_cmp_tb is
   generic (
      g_ALT_PTRN   : integer := 1;
      g_FAULT      : integer := 0;
      g_EXPECT_ERR : integer := 0;
      g_AB_STRICT  : std_logic := '1'
   );
end entity;

architecture sim of txiq_ptrn_cmp_tb is
   constant c_W      : integer := 12;
   signal clk        : std_logic := '0';
   signal ptrn_rst_n : std_logic := '0';
   signal cmp_en     : std_logic := '0';
   signal tx_h, tx_l : std_logic_vector(c_W downto 0);
   signal tx_h_d     : std_logic_vector(c_W downto 0) := (others => '0');
   signal tx_l_d     : std_logic_vector(c_W downto 0) := (others => '0');
   signal rx_h, rx_l : std_logic_vector(c_W downto 0) := (others => '0');
   signal cmp_done   : std_logic;
   signal cmp_error  : std_logic;
   signal alt        : std_logic;
begin
   clk <= not clk after 4 ns;
   alt <= '1' when g_ALT_PTRN = 1 else '0';

   ptrn : entity work.txiq_tst_ptrn
      generic map (diq_width => c_W, g_ALT_PTRN => g_ALT_PTRN)
      port map (clk => clk, reset_n => ptrn_rst_n, diq_h => tx_h, diq_l => tx_l);

   -- loopback + fault model (one clk of latency)
   loopb : process(clk)
      variable i_w, q_w : std_logic_vector(c_W downto 0);
   begin
      if rising_edge(clk) then
         tx_h_d <= tx_h;
         tx_l_d <= tx_l;
         if g_FAULT = 2 then
            i_w := tx_l_d;            -- Q half of previous frame latched as I
            q_w := tx_h;              -- I half of current frame latched as Q
         else
            i_w := tx_h;
            q_w := tx_l;
            if g_FAULT = 1 and i_w(9) = '0' and q_w(9) = '1' then
               i_w(9) := '1';         -- D9 rises too early: Q value latched into I
            end if;
         end if;
         if g_FAULT = 3 then
            i_w(c_W) := not i_w(c_W);
            q_w(c_W) := not q_w(c_W);
         end if;
         rx_l <= i_w;
         rx_h <= q_w;
      end if;
   end process;

   dut : entity work.smpl_cmp
      generic map (smpl_width => c_W, one_chnl => 0)
      port map (
         clk => clk, reset_n => cmp_en, fidm => '0', alt_ptrn => alt, alt_ab_strict => g_AB_STRICT,
         cmp_start => cmp_en, cmp_length => x"0400",
         cmp_done => cmp_done, cmp_error => cmp_error, cmp_error_cnt => open,
         DEBUG_AI_ERR => open, DEBUG_AQ_ERR => open, DEBUG_BI_ERR => open,
         DEBUG_BQ_ERR => open, DEBUG_IQ_ERR => open, DEBUG_STATE => open,
         DEBUG_SMPL_ERR => open, DEBUG_SMPL_ERR_CNT => open, DEBUG_COMPARE_CNT => open,
         DEBUG_WAIT_CNT => open, DEBUG_COMPARE_STOP => open, DEBUG_STOP_EVENT => open,
         DEBUG_DIQ_H_REG => open, DEBUG_DIQ_L_REG => open,
         diq_h => rx_h, diq_l => rx_l);

   stim : process
   begin
      wait for 40 ns;
      wait until rising_edge(clk);
      ptrn_rst_n <= '1';
      for i in 1 to 10 loop wait until rising_edge(clk); end loop;
      cmp_en <= '1';
      wait until cmp_done = '1' for 100 us;
      assert cmp_done = '1' report "TIMEOUT" severity failure;
      report "RESULT alt=" & integer'image(g_ALT_PTRN) & " fault=" & integer'image(g_FAULT) &
             " cmp_error=" & std_logic'image(cmp_error);
      if g_EXPECT_ERR = 1 then
         assert cmp_error = '1' report "FAIL: error not detected" severity failure;
      else
         assert cmp_error = '0' report "FAIL: false error" severity failure;
      end if;
      report "PASS";
      finish;
   end process;
end architecture;
