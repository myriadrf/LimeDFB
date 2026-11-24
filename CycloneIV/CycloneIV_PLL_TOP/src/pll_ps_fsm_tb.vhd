-- Testbench: pll_ps_top (pll_ps_fsm + pll_ps) automatic phase search against a
-- behavioural PLL phase-step model and a sample-compare model whose pass/fail
-- result is a function of the current PLL phase.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity pll_ps_fsm_tb is
   generic (
      g_PERIOD     : integer := 80;   -- phase steps per interface clock period
      g_WIN_START  : integer := 30;   -- passing window [start, start+len) modulo period
      g_WIN_LEN    : integer := 12;
      g_START_PH   : integer := 0;    -- PLL phase after reset
      g_STEP       : integer := 2;    -- auto phase step size
      g_BIAS       : integer := 0;    -- post-search bias (steps)
      g_PHASE_LIM  : integer := 0;    -- ps_phase in auto mode (host: steps per period - 1)
      g_EXPECT_OK  : integer := 1;    -- expected status: 1 = success
      g_TOL        : integer := 2     -- allowed distance of final phase from window centre
   );
end entity;

architecture sim of pll_ps_fsm_tb is
   signal clk            : std_logic := '0';
   signal reset_n        : std_logic := '0';
   signal ps_en          : std_logic := '0';
   signal ps_done        : std_logic;
   signal ps_status      : std_logic;
   signal pll_cntsel     : std_logic_vector(2 downto 0);
   signal pll_updown     : std_logic;
   signal pll_phasestep  : std_logic;
   signal pll_phasedone  : std_logic := '1';
   signal pll_locked     : std_logic := '1';
   signal pll_reset_req  : std_logic;
   signal cmp_en         : std_logic;
   signal cmp_done       : std_logic := '0';
   signal cmp_error      : std_logic := '0';
   signal phase          : integer := g_START_PH;
   signal n_cmp          : integer := 0;

   function passes(ph : integer) return boolean is
      variable rel : integer;
   begin
      rel := (ph - g_WIN_START) mod g_PERIOD;
      return rel < g_WIN_LEN;
   end function;
begin
   clk <= not clk after 5 ns;

   dut : entity work.pll_ps_top
      port map (
         clk => clk, reset_n => reset_n,
         ps_en => ps_en, ps_mode => '1', ps_tst => '0', ps_cnt => "011",
         ps_updwn => '1', ps_phase => std_logic_vector(to_unsigned(g_PHASE_LIM, 10)),
         ps_step_size => std_logic_vector(to_unsigned(g_BIAS, 3)) & std_logic_vector(to_unsigned(g_STEP, 7)),
         ps_busy => open, ps_done => ps_done, ps_status => ps_status,
         pll_phasecounterselect => pll_cntsel, pll_phaseupdown => pll_updown,
         pll_phasestep => pll_phasestep, pll_phasedone => pll_phasedone,
         pll_locked => pll_locked, pll_reconfig => '0', pll_reset_req => pll_reset_req,
         smpl_cmp_en => cmp_en, smpl_cmp_done => cmp_done, smpl_cmp_error => cmp_error);

   -- PLL model: reset returns phase to g_START_PH; each phasestep pulse moves one step
   pll : process
   begin
      wait until rising_edge(clk);
      if pll_reset_req = '1' then
         pll_locked <= '0';
         phase      <= g_START_PH;
         wait until pll_reset_req = '0';
         for i in 1 to 20 loop wait until rising_edge(clk); end loop;
         pll_locked <= '1';
      elsif pll_phasestep = '1' then
         for i in 1 to 2 loop wait until rising_edge(clk); end loop;
         pll_phasedone <= '0';
         if pll_updown = '1' then phase <= phase + 1; else phase <= phase - 1; end if;
         for i in 1 to 2 loop wait until rising_edge(clk); end loop;
         pll_phasedone <= '1';
         if pll_phasestep = '1' then wait until pll_phasestep = '0'; end if;
      end if;
   end process;

   -- smpl_cmp model (held in reset while cmp_en = '0', like the real module)
   cmp : process
   begin
      wait until rising_edge(clk);
      if cmp_en = '0' then
         cmp_done  <= '0';
         cmp_error <= '0';
      elsif cmp_done = '0' then
         for i in 1 to 10 loop wait until rising_edge(clk); end loop;
         if passes(phase) then cmp_error <= '0'; else cmp_error <= '1'; end if;
         cmp_done <= '1';
         n_cmp    <= n_cmp + 1;
      end if;
   end process;

   stim : process
      variable centre, dist : integer;
   begin
      wait for 50 ns;
      reset_n <= '1';
      wait for 50 ns;
      wait until rising_edge(clk);
      ps_en <= '1';
      wait until ps_done = '1' for 50 ms;
      assert ps_done = '1' report "TIMEOUT: search never finished" severity failure;
      wait for 1 us;
      centre := (g_WIN_START + (g_WIN_LEN - 1) / 2 + g_BIAS) mod g_PERIOD;
      dist   := abs((phase - centre + g_PERIOD/2) mod g_PERIOD - g_PERIOD/2);
      report "RESULT status=" & std_logic'image(ps_status) &
             " final_phase=" & integer'image(phase) &
             " (mod " & integer'image(g_PERIOD) & " = " & integer'image(phase mod g_PERIOD) & ")" &
             " window=[" & integer'image(g_WIN_START) & "," & integer'image((g_WIN_START + g_WIN_LEN - 1) mod g_PERIOD) & "]" &
             " centre=" & integer'image(centre) & " dist=" & integer'image(dist) &
             " passes=" & boolean'image(passes(phase)) & " compares=" & integer'image(n_cmp);
      if g_EXPECT_OK = 1 then
         assert ps_status = '0' report "FAIL: expected success status" severity failure;
         assert dist <= g_TOL report "FAIL: final phase too far from window centre" severity failure;
      else
         assert ps_status = '1' report "FAIL: expected error status" severity failure;
      end if;
      report "PASS";
      finish;
   end process;
end architecture;
