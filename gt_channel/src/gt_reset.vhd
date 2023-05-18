-- ----------------------------------------------------------------------------
-- FILE:          gt_reset.vhd
-- DESCRIPTION:   Reset sequencer module for GT transceiver
-- DATE:          12:11 2023-04-04
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
--NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity gt_reset is
   port (
      init_clk       : in std_logic;
      user_clk       : in std_logic;
      hard_reset_n   : in std_logic;
      soft_reset_n   : in std_logic;
      -- GT reset out
      gt_reset       : out std_logic;
      reset          : out std_logic
      
   );
end gt_reset;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of gt_reset is
--declare signals,  components here
constant c_CYCLES_BEFORE_RESET_DEASSERT   : integer := 7;
constant c_CYCLES_BEFORE_GT_RESET_ASSERT  : integer := 15;

type state_type is (idle, pwr_on_st_0, pwr_on_st_1, pwr_on, soft_reset_seq_0, in_soft_reset);
signal current_state, next_state : state_type;

signal gt_reset_active_cnt : unsigned (7 downto 0);
signal reset_hold_cnt    : unsigned (7 downto 0);

signal gt_reset_reg        : std_logic;
signal reset_reg_init_clk  : std_logic;
signal reset_reg_cdc       : std_logic;
signal reset_reg_user_clk  : std_logic;

  
begin


process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      reset_hold_cnt <= (others=>'0');
   elsif(init_clk'event and init_clk = '1')then
      if current_state = pwr_on_st_1 OR current_state = soft_reset_seq_0 then 
         reset_hold_cnt <= reset_hold_cnt + 1;
      elsif current_state = idle OR current_state = pwr_on then
         reset_hold_cnt <= (others=>'0');
      else 
         reset_hold_cnt <= reset_hold_cnt;
      end if;
   end if;
end process;




-- ----------------------------------------------------------------------------
-- state machine, Synchronous to init_clk
-- ----------------------------------------------------------------------------
fsm_f : process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      current_state <= idle;
   elsif(init_clk'event and init_clk = '1')then
      current_state <= next_state;
   end if;
end process;

-- ----------------------------------------------------------------------------
--state machine combo
-- ----------------------------------------------------------------------------
fsm : process(all) begin
   next_state <= current_state;
   case current_state is
   
      when idle =>
         if soft_reset_n = '1' then 
            next_state <= pwr_on_st_0;
         else 
            next_state <= idle;
         end if;
      
      when pwr_on_st_0 => 
         next_state <= pwr_on_st_1;


      when pwr_on_st_1 =>
         if reset_hold_cnt < c_CYCLES_BEFORE_RESET_DEASSERT then 
            next_state <= pwr_on_st_1;
         else 
            next_state <= pwr_on;
         end if;
         
      when pwr_on =>
         if soft_reset_n = '0' then 
            next_state <= soft_reset_seq_0;
         else 
            next_state <= pwr_on;
         end if;
         
      when soft_reset_seq_0 => 
         if reset_hold_cnt < c_CYCLES_BEFORE_GT_RESET_ASSERT then 
            next_state <= soft_reset_seq_0;
         else 
            next_state <= in_soft_reset;
         end if;
         
      when in_soft_reset =>
         if soft_reset_n = '0' then 
            next_state <= in_soft_reset;
         else 
            next_state <= pwr_on_st_0;
         end if;
      
         
      when others => 
         next_state <= idle;
   end case;
end process;


process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      gt_reset_reg <= '1';
   elsif(init_clk'event and init_clk = '1')then
      if current_state = pwr_on_st_0 then 
         gt_reset_reg <= '0';
      elsif current_state = idle OR current_state = in_soft_reset then 
         gt_reset_reg <= '1';
      else 
         gt_reset_reg <= gt_reset_reg;
      end if;
   end if;
end process;

process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      reset_reg_init_clk <= '1';
   elsif(init_clk'event and init_clk = '1')then
      if current_state = pwr_on then 
         reset_reg_init_clk <= '0';
      elsif current_state = idle OR current_state = soft_reset_seq_0 then 
         reset_reg_init_clk <= '1';
      else 
         reset_reg_init_clk <= reset_reg_init_clk;
      end if;
   end if;
end process;



process(user_clk, reset_reg_init_clk)
begin
   if(reset_reg_init_clk = '1')then
      reset_reg_cdc        <= '1';
      reset_reg_user_clk   <= '1';
   elsif(user_clk'event and user_clk = '1')then
      reset_reg_cdc <= '0';
      reset_reg_user_clk <= reset_reg_cdc;
   end if;
end process;






gt_reset <= gt_reset_reg;
reset    <= reset_reg_user_clk;
  
end arch;   


