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
      -- GT 
      gt_reset       : out std_logic;
      reset          : out std_logic
      
   );
end gt_reset;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of gt_reset is
--declare signals,  components here
constant c_MAX_CNT_PWRON_ST0              : integer := 8;
constant c_MAX_CNT_PWRON_ST1              : integer := 100000000;
-- c_MAX_CNT_SOFTRST_ST0 should be atleast 128 user_clk cycles.  
-- user_clk period 6.4ns  x 128 = 819.2ns.
-- state machine is clocked from init_clk (10 ns period)
-- 819.2/10 = ~82 cycles atleast 
constant c_MAX_CNT_SOFTRST_ST0            : integer := 100;   
constant c_MAX_CNT_SOFTRST_ST1            : integer := 120000000;

type state_type is (idle, pwr_on_st_0, pwr_on_st_1, pwr_on, soft_rst_st_0, soft_rst_st_1, in_soft_reset);
signal current_state, next_state : state_type;

signal pwron_st0_cnt     : unsigned(28 downto 0);
signal pwron_st1_cnt     : unsigned(28 downto 0);
signal softrst_st0_cnt   : unsigned(15 downto 0);
signal softrst_st1_cnt   : unsigned(28 downto 0);

signal gt_reset_reg        : std_logic;
signal reset_reg_init_clk  : std_logic;
signal reset_reg_cdc       : std_logic;
signal reset_reg0_user_clk : std_logic;
signal reset_reg1_user_clk : std_logic;
signal soft_reset_n_cdc_reg: std_logic_vector(2 downto 0);

attribute MARK_DEBUG : string;
attribute MARK_DEBUG of current_state          : signal is "TRUE";
attribute MARK_DEBUG of pwron_st0_cnt          : signal is "TRUE";
attribute MARK_DEBUG of pwron_st1_cnt          : signal is "TRUE";
attribute MARK_DEBUG of hard_reset_n           : signal is "TRUE";
attribute MARK_DEBUG of soft_reset_n           : signal is "TRUE";


attribute KEEP : string;
attribute KEEP of current_state         : signal is "TRUE";
attribute KEEP of pwron_st0_cnt         : signal is "TRUE";
attribute KEEP of pwron_st1_cnt         : signal is "TRUE";
attribute KEEP of hard_reset_n          : signal is "TRUE";
attribute KEEP of soft_reset_n          : signal is "TRUE";

  
begin

process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      soft_reset_n_cdc_reg <= (others=>'0');
   elsif(init_clk'event and init_clk = '1')then
        soft_reset_n_cdc_reg <= soft_reset_n_cdc_reg(1 downto 0) & soft_reset_n;
   end if;
end process;

--pwron_st0_cnt
process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      pwron_st0_cnt <= (others=>'0');
   elsif(init_clk'event and init_clk = '1')then
      if current_state = pwr_on_st_0 then 
         pwron_st0_cnt <= pwron_st0_cnt + 1;
      else
         pwron_st0_cnt <= (others=>'0');
      end if;
   end if;
end process;


--pwron_st1_cnt
process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      pwron_st1_cnt <= (others=>'0');
   elsif(init_clk'event and init_clk = '1')then
      if current_state = pwr_on_st_1 then 
         pwron_st1_cnt <= pwron_st1_cnt + 1;
      else
         pwron_st1_cnt <= (others=>'0');
      end if;
   end if;
end process;


--softrst_st0_cnt
process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      softrst_st0_cnt <= (others=>'0');
   elsif(init_clk'event and init_clk = '1')then
      if current_state = soft_rst_st_0 then 
         softrst_st0_cnt <= softrst_st0_cnt + 1;
      else
         softrst_st0_cnt <= (others=>'0');
      end if;
   end if;
end process;


--softrst_st1_cnt
process(init_clk, hard_reset_n)
begin
   if(hard_reset_n = '0')then
      softrst_st1_cnt <= (others=>'0');
   elsif(init_clk'event and init_clk = '1')then
      if current_state = soft_rst_st_1 then 
         softrst_st1_cnt <= softrst_st1_cnt + 1;
      else
         softrst_st1_cnt <= (others=>'0');
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
         if soft_reset_n_cdc_reg(2) = '1' then 
            next_state <= pwr_on_st_0;
         else 
            next_state <= idle;
         end if;
         
      when pwr_on_st_0 =>
         if pwron_st0_cnt < c_MAX_CNT_PWRON_ST0 then 
            next_state <= pwr_on_st_0;
         else 
            next_state <= pwr_on_st_1;
         end if;

      -- deasert gt_reset
      when pwr_on_st_1 =>
         if pwron_st1_cnt < c_MAX_CNT_PWRON_ST1 then 
            next_state <= pwr_on_st_1;
         else 
            next_state <= pwr_on;
         end if;
      
      -- deasert reset
      when pwr_on =>
         if soft_reset_n_cdc_reg(2) = '0' then 
            next_state <= soft_rst_st_0;
         else 
            next_state <= pwr_on;
         end if;
      
      -- assert reset
      when soft_rst_st_0 => 
         if softrst_st0_cnt < c_MAX_CNT_SOFTRST_ST0 then 
            next_state <= soft_rst_st_0;
         else 
            next_state <= soft_rst_st_1;
         end if;
         
      -- assert and hold gt_reset    
      when soft_rst_st_1 =>
         if softrst_st1_cnt < c_MAX_CNT_SOFTRST_ST1 then 
            next_state <= soft_rst_st_1;
         else 
            next_state <= in_soft_reset;
         end if;
         
      --gt_reset and reset asserted wait for signal to exit reset state
      when in_soft_reset =>
         if soft_reset_n_cdc_reg(2) = '0' then 
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
      if current_state = pwr_on_st_1 then 
         gt_reset_reg <= '0';
      elsif current_state = idle OR current_state = soft_rst_st_1 then 
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
      elsif current_state = idle OR current_state = soft_rst_st_0 then 
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
      reset_reg0_user_clk  <= '1';
      reset_reg1_user_clk  <= '1';
   elsif(user_clk'event and user_clk = '1')then
      reset_reg_cdc <= '0';
      reset_reg0_user_clk <= reset_reg_cdc;
      reset_reg1_user_clk <= reset_reg0_user_clk;
   end if;
end process;


gt_reset <= gt_reset_reg;
reset    <= reset_reg1_user_clk;
  
end arch;   


