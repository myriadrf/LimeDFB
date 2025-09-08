-- ----------------------------------------------------------------------------
-- FILE:          counter64_tb.vhd
-- DESCRIPTION:   Test bech for counter64 module
-- DATE:          12:13 2025-08-14
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use ieee.math_real.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity counter64_tb is
end counter64_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of counter64_tb is
   constant clk0_period    : time := 10 ns;
   constant clk1_period    : time := 10 ns;
   constant clk2_period    : time := 10 ns;  

   constant C_DATA_WIDTH   : integer := 8;
   
   --signals
   signal clk0,clk1,clk2   : std_logic;
   signal reset_n          : std_logic; 

   signal inc_val          : std_logic_vector(C_DATA_WIDTH/2-1 downto 0);



begin 
  
   clock0: process is
   begin
      clk0 <= '0'; wait for clk0_period/2;
      clk0 <= '1'; wait for clk0_period/2;
   end process clock0;

   clock1: process is
   begin
      clk1 <= '0'; wait for clk1_period/2;
      clk1 <= '1'; wait for clk1_period/2;
   end process clock1;
   
   clock2: process is
   begin
      clk2 <= '0'; wait for clk2_period/2;
      clk2 <= '1'; wait for clk2_period/2;
   end process clock2;
   
   res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;


   inc_val <= std_logic_vector(to_unsigned(1, inc_val'LENGTH));



   counter64_inst : entity work.counter64
   generic map (
      g_WIDTH       => C_DATA_WIDTH,
      g_ADD_OUTREG  => false
   )
   port map(
      clk      => clk0,
      rst      => NOT reset_n,
      -- AXI Stream Write Interface
      inc_en   => '1' ,
      inc_val  =>  inc_val,
      ld       => '0',
      ld_val   => (others=>'0'),
      count_o  => open
   );
   
end tb_behave;

