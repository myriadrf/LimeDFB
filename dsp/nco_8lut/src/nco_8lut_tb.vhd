-- ----------------------------------------------------------------------------
-- FILE:          nco_8lut_tb.vhd
-- DESCRIPTION:   Test bech for nco_8lut module
-- DATE:          10:26 2025-10-23
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
entity nco_8lut_tb is
end nco_8lut_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of nco_8lut_tb is
   constant clk0_period    : time :=  8 ns;
   constant clk1_period    : time :=  8 ns;
   
   constant c_MIMO_DDR_SAMPLES      : integer := 16;
   --signals
   signal clk0             : std_logic;
   signal reset_n          : std_logic; 


   signal en         : std_logic := '1';
   signal swapiq     : std_logic := '0';
   signal mode       : std_logic := '0';
   signal newnco     : std_logic := '1';
   signal ldi        : std_logic := '0';
   signal ldq        : std_logic := '0';
   signal diq        : std_logic_vector(15 downto 0) := x"AAAA";
   signal fcw        : std_logic_vector(1 downto 0)  := "01";
   signal fullscaleo : std_logic := '1';


   signal dut1_yi, dut1_yq : std_logic_vector(15 downto 0);
   signal dut2_yi, dut2_yq : std_logic_vector(15 downto 0);
   
   
begin 
  
   clock0: process is
   begin
      clk0 <= '0'; wait for clk0_period/2;
      clk0 <= '1'; wait for clk0_period/2;
   end process clock0;

   
   res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;
   

   -- ASIC implementation
   dut1 : entity work.nco_8lut
   generic map (g_ASIC_IMPL => True
      )
	port map(
		clk         => clk0,
		nrst        => reset_n,
		en          => en        ,
		swapiq      => swapiq    ,
		mode        => mode      ,
		newnco      => newnco    ,
		ldi         => ldi       ,
      ldq         => ldq       ,
		diq         => diq       ,
		fcw         => fcw       ,
		fullscaleo  => fullscaleo,
		yi          => dut1_yi,
		yq          => dut1_yq
	);

   --FPGA implementation
   dut2 : entity work.nco_8lut
   generic map (g_ASIC_IMPL => False
      )
	port map(
		clk         => clk0,
		nrst        => reset_n,
		en          => en        ,
		swapiq      => swapiq    ,
		mode        => mode      ,
		newnco      => newnco    ,
		ldi         => ldi       ,
      ldq         => ldq       ,
		diq         => diq       ,
		fcw         => fcw       ,
		fullscaleo  => fullscaleo,
		yi          => dut2_yi,
		yq          => dut2_yq
	);


   -- Check if both implementations match in simulation
   process(all)
   begin 
      assert(dut1_yi = dut2_yi) report "yi data does not match" severity failure;
      assert(dut1_yq = dut2_yq) report "yq data does not match" severity failure;
   end process;

end tb_behave;

