-- ----------------------------------------------------------------------------
-- FILE:          my_module.vhd
-- DESCRIPTION:   describe file
-- DATE:          Jan 27, 2016
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
entity my_module is
   generic(
      g_DATA_WIDTH   : integer := 12
   );
   port (
      clk      : in  std_logic;
      reset_n  : in  std_logic;
      d        : in  std_logic_vector(g_DATA_WIDTH-1 downto 0);
      q        : out std_logic_vector(g_DATA_WIDTH-1 downto 0)
   );
end my_module;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of my_module is
--declare signals,  components here
signal d_reg : std_logic_vector (g_DATA_WIDTH-1 downto 0); 

begin

   process(reset_n, clk)
      begin
         if reset_n = '0' then
            d_reg <= (others=>'0');  
         elsif (clk'event and clk = '1') then
            d_reg <= d;
         end if;
   end process;
   
   q <= d_reg;
  
end arch;   


