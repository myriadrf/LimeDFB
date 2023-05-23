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
        Lo_limit : integer := 300;
        Hi_limit  : integer := 400    
    );
    Port ( clk : in STD_LOGIC;
           fifo_usedw : in STD_LOGIC_VECTOR (31 downto 0);
           nfc_ready : in STD_LOGIC;
           nfc_valid : out STD_LOGIC;
           nfc_data : out STD_LOGIC_VECTOR(3 downto 0);
           reset_n : in STD_LOGIC);
end aurora_nfc_gen;

architecture Behavioral of aurora_nfc_gen is

type T_state is (wait_for_full, wait_for_empty);
signal current_state, next_state : T_state;

begin

state_sw : process(clk,reset_n)
begin
    if reset_n = '0' then  
        current_state <= wait_for_full;
    elsif rising_edge(clk) then
        current_state <= next_state;
    end if;
end process;

fsm : process(all)
begin
    next_state <= current_state;
    nfc_data   <= nfc_data;
    nfc_valid  <= '0';
    case current_state is
        
        when wait_for_full =>
            nfc_valid  <= '0';
            if (unsigned(fifo_usedw) > Hi_limit) then
                nfc_data   <= "1111";
                nfc_valid  <= '1';
                if nfc_ready = '1' then
                    next_state <= wait_for_empty;
                end if;
            end if;      
            
        when wait_for_empty => 
            nfc_valid  <= '0';
            if (unsigned(fifo_usedw) < Lo_limit) then
                nfc_data   <= "0000";
                nfc_valid  <= '1';
                if nfc_ready = '1' then
                    next_state <= wait_for_full;
                end if;
            end if;      
        
        when others => next_state <= wait_for_full;
        
    end case;

end process;




end Behavioral;
