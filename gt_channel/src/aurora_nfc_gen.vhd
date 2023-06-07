-- ----------------------------------------------------------------------------
-- FILE:          aurora_nfc_gen.vhd
-- DESCRIPTION:   Module for generating aurora nfc flow control signals
-- DATE:          13:20 2023-06-23
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity aurora_nfc_gen is
   Generic (
      g_LO_LIMIT  : integer := 300;
      g_HI_LIMIT  : integer := 400    
   );
   Port ( 
      CLK         : in STD_LOGIC;
      FIFO_USEDW  : in STD_LOGIC_VECTOR (31 downto 0);
      NFC_READY   : in STD_LOGIC;
      NFC_VALID   : out STD_LOGIC;
      NFC_DATA    : out STD_LOGIC_VECTOR(3 downto 0);
      RESET_N     : in STD_LOGIC
   );
end aurora_nfc_gen;

architecture Behavioral of aurora_nfc_gen is

   type t_STATE is (wait_for_full, wait_for_empty);
   signal current_state, next_state : t_STATE;

begin

state_sw : process(CLK,RESET_N)
begin
   if RESET_N = '0' then  
      current_state <= wait_for_full;
   elsif rising_edge(CLK) then
      current_state <= next_state;
   end if;
end process;

fsm : process(all)
begin
   next_state <= current_state;
   NFC_DATA   <= NFC_DATA;
   NFC_VALID  <= '0';
   case current_state is
           
   when wait_for_full =>
      NFC_VALID  <= '0';
      if (unsigned(FIFO_USEDW) > g_HI_LIMIT) then
         NFC_DATA   <= "1111";
         NFC_VALID  <= '1';
         if NFC_READY = '1' then
            next_state <= wait_for_empty;
         end if;
      end if;      
               
   when wait_for_empty => 
      NFC_VALID  <= '0';
      if (unsigned(FIFO_USEDW) < g_LO_LIMIT) then
         NFC_DATA   <= "0000";
         NFC_VALID  <= '1';
         if NFC_READY = '1' then
            next_state <= wait_for_full;
         end if;
      end if;      
           
   when others => next_state <= wait_for_full;
           
   end case;

end process;

end Behavioral;
