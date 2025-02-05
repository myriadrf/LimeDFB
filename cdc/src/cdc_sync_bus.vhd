-- ----------------------------------------------------------------------------
-- FILE:          cdc_sync_bus.vhd
-- DESCRIPTION:   General double Flip-Flop synchronizer for multiple bit data bus
-- DATE:          09:45 2025-02-05
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
entity cdc_sync_bus is
   generic( g_WIDTH : integer := 1
   );
   port (
      clk   : in  std_logic;
      rst_n : in  std_logic;
      d     : in  std_logic_vector(g_WIDTH-1 downto 0);
      q     : out std_logic_vector(g_WIDTH-1 downto 0)
   );
end cdc_sync_bus;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of cdc_sync_bus is
--declare signals,  components here
   signal d_reg0 : std_logic_vector(g_WIDTH-1 downto 0);
   signal d_reg1 : std_logic_vector(g_WIDTH-1 downto 0);

begin 

   process (clk, rst_n)
   begin
      if rst_n = '0' then 
         d_reg0 <=(others=>'0');
         d_reg1 <=(others=>'0');
      elsif rising_edge(clk) then 
         d_reg0 <= d;
         d_reg1 <= d_reg0;
      end if;
      
   end process;

   q <= d_reg1;


  
end arch;   


