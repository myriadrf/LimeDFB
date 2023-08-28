-- ----------------------------------------------------------------------------
-- FILE:          gt_reset_tb.vhd
-- DESCRIPTION:   
-- DATE:          Feb 13, 2014
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
entity gt_reset_tb is
end gt_reset_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of gt_reset_tb is
   constant clk0_period    : time := 10  ns;
   constant clk1_period    : time := 6.4 ns; 
   --signals
   signal clk0,clk1        : std_logic;
   signal reset_n          : std_logic; 
   
   signal dut0_reset        : std_logic;
   signal dut0_soft_reset_n : std_logic;
  
begin 
  
      clock0: process is
   begin
      clk0 <= '0'; wait for clk0_period/2;
      clk0 <= '1'; wait for clk0_period/2;
   end process clock0;

      clock: process is
   begin
      clk1 <= '0'; wait for clk1_period/2;
      clk1 <= '1'; wait for clk1_period/2;
   end process clock;
   
      res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;
   
   process is 
   begin
      dut0_soft_reset_n <= '1';
      wait until dut0_reset = '0';
      wait until rising_edge(clk0);
      for i in 0 to 7 loop
         wait until rising_edge(clk0);
      end loop;
      dut0_soft_reset_n <= '0';
      wait until rising_edge(clk0);
   end process;
   
      -- design under test  

   dut0 : entity work.gt_reset 
   port map(
      init_clk       => clk0,
      user_clk       => clk1,
      hard_reset_n   => reset_n,
      soft_reset_n   => dut0_soft_reset_n,
      -- GT reset out
      gt_reset       => open,
      reset          => dut0_reset
   
   );

end tb_behave;

