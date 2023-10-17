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
   Port (
      CLK             : in STD_LOGIC;
      RESET_N         : in STD_LOGIC;
      UFC_TX_VALID    : out STD_LOGIC;
      UFC_TX_DATA     : out STD_LOGIC_VECTOR (2 downto 0);
      UFC_TX_READY    : in STD_LOGIC;
      AXIS_TX_DATA    : out STD_LOGIC_VECTOR (31 downto 0);
      REG_INPUT       : in STD_LOGIC_VECTOR (31 downto 0) := (others => '0')
   );
end aurora_ufc_reg_send;

architecture Behavioral of aurora_ufc_reg_send is

    signal reg_input_reg : std_logic_vector(31 downto 0);
    type t_STATE is (idle,send);
    
    signal current_state : t_STATE;
    
    signal axis_tx_data_int : std_logic_vector(31 downto 0);
    
--   attribute MARK_DEBUG : string;
--   attribute MARK_DEBUG of current_state  : signal is "TRUE";
--   attribute MARK_DEBUG of UFC_TX_VALID   : signal is "TRUE";
--   attribute MARK_DEBUG of UFC_TX_DATA    : signal is "TRUE";
--   attribute MARK_DEBUG of UFC_TX_READY   : signal is "TRUE";
--   attribute MARK_DEBUG of AXIS_TX_DATA   : signal is "TRUE";
--   attribute MARK_DEBUG of REG_INPUT      : signal is "TRUE";
   
begin
    
    --Fixed size : 4 bytes to align with aurora bus width
    UFC_TX_DATA <= "001";
    
    fsm : process(clk, reset_n)
    begin
        if reset_n = '0' then
            current_state <= idle;
        elsif rising_edge(clk) then
         current_state       <= current_state;
         axis_tx_data_int <= axis_tx_data_int;
         UFC_TX_VALID     <= '0';
        
         case current_state is 
        
            when idle =>
                if reg_input_reg /= REG_INPUT then
                  axis_tx_data_int    <= REG_INPUT;
                  current_state       <= send;
                end if;
                
            when send =>
                UFC_TX_VALID <= '1';
                if UFC_TX_READY = '1' then
                    UFC_TX_VALID    <= '0';
                    current_state   <= idle;
                end if;
                
            when others => current_state <= idle;
         end case;
      end if;
    end process;
    
    input_reg : process(CLK)
    begin
        if rising_edge(CLK) then
            if current_state = idle then
                reg_input_reg <= REG_INPUT;
            else
                reg_input_reg <= reg_input_reg;        
            end if;
        end if;
    end process;
    
    AXIS_TX_DATA <= axis_tx_data_int;

end Behavioral;
