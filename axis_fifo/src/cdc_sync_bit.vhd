-- ----------------------------------------------------------------------------
-- FILE:          cdc_sync_bit.vhd
-- DESCRIPTION:   General double Flip-Flop synchronizer for one bit
-- DATE:          09:45 2023-05-15
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
entity cdc_sync_bit is
   port (
      clk   : in  std_logic;
      rst_n : in  std_logic;
      d     : in  std_logic;
      q     : out std_logic
   );
end cdc_sync_bit;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of cdc_sync_bit is
--declare signals,  components here

   signal d_req : std_logic_vector(2 downto 0);

begin 

   process (clk, rst_n)
   begin
      if rst_n = '0' then 
         d_req <=(others=>'0');
      elsif rising_edge(clk) then 
         d_req <= d_req(1 downto 0) & d;
      end if;
      
   end process;

   q <= d_req(d_req'LEFT);


  
end arch;   


