-- ----------------------------------------------------------------------------
-- FILE:          axi4_tlast_gen.vhd
-- DESCRIPTION:   Basic module for generatic tlast signal for axi4stream data
-- DATE:          June 05, 2023
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
entity axi4_tlast_gen is
   generic(
      g_DATA_WIDTH    : integer := 32;
      g_LAST_PERIOD   : integer := 100
   );
   port(
      CLK             : in  std_logic;
      RESET_N         : in  std_logic;
      --AXI_S = axi peripheral providing data to this module
      AXI_S_DATA      : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
      AXI_S_READY     : out std_logic;
      AXI_S_VALID     : in  std_logic;
      --AXI_M = axi peripheral receiving data from this module
      AXI_M_DATA      : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
      AXI_M_READY     : in  std_logic;
      AXI_M_VALID     : out std_logic;
      AXI_M_LAST      : out std_logic
    );
end axi4_tlast_gen;

architecture Behavioral of axi4_tlast_gen is

   signal word_counter : integer range 0 to g_LAST_PERIOD + 1;

begin

   --Assign data passthrough
   AXI_M_DATA  <= AXI_S_DATA;
   
   --Counter increment and reset logic
   counter_proc: process(CLK,RESET_N)
   begin
      if RESET_N = '0' then
         word_counter <= 0;
      elsif rising_edge(CLK) then
         if word_counter = g_LAST_PERIOD + 1 then
            word_counter <= 0;
         elsif AXI_S_VALID = '1' and AXI_M_READY = '1' then
            word_counter <= word_counter + 1;
         end if;
      end if;
    end process;
       
   --Output assignments
   AXI_M_LAST  <= AXI_S_VALID when word_counter = g_LAST_PERIOD else '0';
   AXI_S_READY <= '0' when word_counter = g_LAST_PERIOD + 1 else AXI_M_READY;
   AXI_M_VALID <= '0' when word_counter = g_LAST_PERIOD + 1 else AXI_S_VALID;
    
    
    
end Behavioral;
