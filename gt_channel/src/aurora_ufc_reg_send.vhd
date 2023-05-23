-- ----------------------------------------------------------------------------
-- FILE:          aurora_ufc_reg_sen.vhd
-- DESCRIPTION:   Module for sending ufc messages
-- DATE:          13:20 2023-06-23
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity aurora_ufc_reg_send is
    Port ( clk             : in STD_LOGIC;
           reset_n         : in STD_LOGIC;
           ufc_tx_valid    : out STD_LOGIC;
           ufc_tx_data     : out STD_LOGIC_VECTOR (2 downto 0);
           ufc_tx_ready    : in STD_LOGIC;
           axis_tx_data    : out STD_LOGIC_VECTOR (31 downto 0);
           reg_input       : in STD_LOGIC_VECTOR (31 downto 0) := (others => '0')
           );
end aurora_ufc_reg_send;

architecture Behavioral of aurora_ufc_reg_send is

    signal reg_input_reg : std_logic_vector(31 downto 0);
    type t_state is (idle,send);
    
    signal current_state, next_state : t_state;
    
    signal axis_tx_data_int : std_logic_vector(31 downto 0);
    

begin
    
    --Fixed size : 4 bytes to align with aurora bus width
    ufc_tx_data <= "001";

    state_sw : process(clk,reset_n)
    begin
        if reset_n = '0' then  
            current_state <= idle;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;
    
    fsm : process(clk, current_state, reg_input_reg, ufc_tx_ready,reg_input)
    begin
        next_state       <= current_state;
        axis_tx_data_int <= axis_tx_data_int;
        ufc_tx_valid     <= '0';
        
        case current_state is 
        
            when idle =>
                if reg_input_reg /= reg_input then
                   axis_tx_data_int <= reg_input;
                   next_state       <= send;
                end if;
                
            when send =>
                ufc_tx_valid <= '1';
                if ufc_tx_ready = '1' then
                    ufc_tx_valid <= '0';
                    next_state   <= idle;
                end if;
                
            when others => next_state <= idle;
        end case;
    end process;
    
    input_reg : process(clk,current_state)
    begin
        if rising_edge(clk) then
            if current_state = idle then
                reg_input_reg <= reg_input;
            else
                reg_input_reg <= reg_input_reg;        
            end if;
        end if;
    end process;
    
    axis_tx_data <= axis_tx_data_int;

end Behavioral;
