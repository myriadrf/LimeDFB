-- ----------------------------------------------------------------------------
-- FILE:          pll_ps_fsm.vhd
-- DESCRIPTION:   manual and automatic phase shift
-- DATE:          11:00 AM Monday, January 15, 2018
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
--NOTES: max phase limit is "1111111110", see step_cnt_max_constant
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity pll_ps_fsm is
   generic (
      g_TIMEOUT_LIMIT   : integer := 262143; -- ~262,143 cycles (~2.62 ms @ 100MHz)
      g_RST_PLL_TIMEOUT : integer := 1023;   -- ~1023 cycles (~10.23 us @ 100MHz)
      -- post-search bias in phase steps, applied in the search direction:
      -- final phase = window centre + g_BIAS (0 = centre, legacy behaviour)
      g_BIAS            : natural := 0
   );
   port (

      clk               : in std_logic;
      reset_n           : in std_logic;
      --module control ports
      ps_en             : in std_logic; -- 0 - disabled, 1 - enabled
      ps_reset_at_start : in std_logic; -- 0 - disabled, 1 - enabled (PLL is reseted before start)
      ps_mode           : in std_logic; -- 0 - manual, 1 - auto
      ps_cnt            : in std_logic_vector(2 downto 0); 
                                                   -- 000 - ALL, 001 -   M, 010 - C0,
                                                   -- 011 -  C1, 100 -  C2, 101 - C3,
                                                   -- 110 -  C4
      ps_updwn          : in std_logic; -- 1- UP, 0 - DOWN
      ps_phase          : in std_logic_vector(9 downto 0); -- phase to shift in manual mode, 
                                                           -- max phase limit in auto mode.
      ps_step_size      : in std_logic_vector(9 downto 0); -- step size in auto mode
      ps_done           : out std_logic; -- 0 - not done,  1 - done
      ps_status         : out std_logic; -- 0 - OK, 1 - error      
      --pll ports
      pll_locked        : in std_logic;  -- pll lock status
      pll_reconfig      : in std_logic;  -- PLL reconfiguration status
      pll_reset_req     : out std_logic; -- reset request signal
      --pll_ps_cntrl ports
      ps_ctrl_busy      : in std_logic;
      ps_ctrl_en        : out std_logic;
      ps_ctrl_phase     : out std_logic_vector(9 downto 0);
      ps_ctrl_cnt       : out std_logic_vector(2 downto 0);
      ps_ctrl_updown    : out std_logic;
      --sample compare module
      smpl_cmp_en       : out std_logic;
      smpl_cmp_done     : in std_logic;
      smpl_cmp_error    : in std_logic;
      --debug: result of the last automatic search, latched at its end (step_cnt units,
      --relative to the search start): (31) error, (30) failure seen, (29:20) window min,
      --(19:10) window max, (9:0) window centre (final phase before g_BIAS)
      ps_dbg            : out std_logic_vector(31 downto 0)
        );  
end pll_ps_fsm;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of pll_ps_fsm is

function adaptive_step(step_field : std_logic_vector(9 downto 0);
                       phase_lim  : std_logic_vector(9 downto 0)) return unsigned is
   variable v_reg  : unsigned(9 downto 0);
   variable v_auto : unsigned(9 downto 0);
begin
   v_reg  := unsigned(step_field);
   v_auto := shift_right(resize(unsigned(phase_lim), 11) + 1, 6)(9 downto 0);
   if v_auto > v_reg then
      v_reg := v_auto;
   end if;
   if v_reg = 0 then
      v_reg := to_unsigned(1, 10);
   end if;
   return v_reg;
end function;
--declare signals,  components here
signal ps_done_reg_manual_mode         : std_logic;
signal ps_ctrl_busy_reg                : std_logic;
signal ps_en_reg                       : std_logic;
signal ps_cnt_reg                      : std_logic_vector(2 downto 0);
signal ps_updwn_reg                    : std_logic;
signal ps_phase_reg                    : std_logic_vector(9 downto 0);
signal ps_step_size_reg                : std_logic_vector(9 downto 0);
signal step_sz                         : unsigned(9 downto 0); -- effective step (latched inputs)
signal step_in                         : unsigned(9 downto 0); -- effective step (live inputs, idle)
signal ps_bias                         : unsigned(9 downto 0); -- g_BIAS
signal pll_reset_req_reg               : std_logic;
signal smpl_cmp_en_reg                 : std_logic;
signal find_min                        : std_logic;
signal find_max                        : std_logic;
signal seen_fail                       : std_logic; -- a failing phase was seen while looking for the minimum
signal init_valid                      : std_logic; -- passing run seen before the first failure
signal init_min                        : unsigned(9 downto 0); -- that run (it may be truncated by the
signal init_max                        : unsigned(9 downto 0); -- start of the range)
signal step_cnt                        : unsigned(9 downto 0);
signal step_cnt_min                    : unsigned(9 downto 0);
signal step_cnt_max                    : unsigned(9 downto 0);
signal step_cnt_diff                   : unsigned(9 downto 0);
signal step_cnt_middle                 : unsigned(9 downto 0);
signal step_cnt_reverse                : unsigned(9 downto 0); 
signal ps_ctrl_en_reg                  : std_logic;
signal prep_phase_cnt                  : unsigned(3 downto 0);
signal ps_ctrl_phase_reg               : std_logic_vector(9 downto 0);
signal ps_ctrl_updwn_reg               : std_logic;
signal ps_done_reg                     : std_logic;
signal ps_status_reg                   : std_logic;
signal wait_after_ph_shift_cnt         : unsigned(7 downto 0);
signal step_cnt_max_reg                : unsigned(9 downto 0);
signal step_cnt_max_constant           : unsigned(9 downto 0);

signal fsm_timer                       : unsigned(19 downto 0);
signal timeout_err                     : std_logic;
constant FSM_TIMEOUT_LIMIT             : unsigned(19 downto 0) := to_unsigned(g_TIMEOUT_LIMIT, 20);
constant RST_PLL_TIMEOUT               : unsigned(19 downto 0) := to_unsigned(g_RST_PLL_TIMEOUT, 20);



type state_type is (idle, rst_pll, wait_pll_lock, check_cmp_status, 
cmp_smpls, min_found, max_found, check_max_steps, ph_shift, wait_after_ph_shift, end_srch, sel_window, prep_phase);
signal current_state, next_state : state_type;

signal time_count                      : unsigned(31 downto 0);
attribute noprune: boolean;
attribute noprune of time_count: signal is true;


  
begin

-- "1111111111" forces to search in whole phase step range if maximum value not found
-- Effective step size in auto mode: max(register step, steps per period / 64), at least 1.
-- LimeSuiteNG writes steps per interface period - 1 into ps_phase (CNT_PHASE) before an
-- automatic search. Keeping ~64 compares per period bounds the search time at low interface
-- frequencies (where a period is up to ~1024 steps and each compare takes longer), so the
-- search ends before the host moves on to the next PLL (fixed 10 ms waits on LimeSDR-USB);
-- at >= 112 MHz (80 steps per period) the register step (1) is used. ps_phase = 0 (host not
-- writing it) leaves the register step unchanged.
-- step_sz is registered: its inputs only change when a search starts (ps_en rising edge)
-- and it is first used several states later; the combinational adaptive_step logic in
-- front of the FSM decisions was the worst sys-clock (FX3_PCLK) path.
process(clk, reset_n)
begin
   if reset_n = '0' then
      step_sz <= to_unsigned(1, step_sz'length);
   elsif rising_edge(clk) then
      step_sz <= adaptive_step(ps_step_size_reg, ps_phase_reg);
   end if;
end process;
step_in <= adaptive_step(ps_step_size, ps_phase);
ps_bias <= to_unsigned(g_BIAS, ps_bias'length);
step_cnt_max_constant <= (others=> '1');

-- ----------------------------------------------------------------------------
-- Test counter
-- ----------------------------------------------------------------------------
   process(clk, reset_n)
   begin
      if reset_n = '0' then 
         time_count <= (others => '0');
      elsif (clk'event AND clk='1') then 
         if ps_en = '1' AND ps_done_reg = '0' then 
            time_count <= time_count + 1;
         elsif ps_en = '1' AND ps_done_reg = '1' then 
            time_count <= time_count;
         else 
            time_count <= (others => '0');
         end if;
      end if;
   end process;

-- ----------------------------------------------------------------------------
-- Input registers
-- ----------------------------------------------------------------------------
   process(clk, reset_n)
   begin
      if reset_n = '0' then 
         ps_ctrl_busy_reg     <= '0';
         ps_en_reg            <= '0';
         ps_cnt_reg           <= (others=>'0');
         ps_phase_reg         <= (others=>'0');
         ps_step_size_reg     <= (others=>'0');
         ps_updwn_reg         <= '0';
      elsif (clk'event AND clk='1') then 
         ps_ctrl_busy_reg     <= ps_ctrl_busy;
         ps_en_reg            <= ps_en;
         
         --input registers latched on ps_en rising edge
         if ps_en = '1' AND ps_en_reg = '0' then 
            ps_cnt_reg        <= ps_cnt;
            ps_updwn_reg      <= ps_updwn;
            ps_phase_reg      <= ps_phase;
            ps_step_size_reg  <= ps_step_size;
         else 
            ps_cnt_reg        <= ps_cnt_reg;
            ps_updwn_reg      <= ps_updwn_reg;
            ps_phase_reg      <= ps_phase_reg;
            ps_step_size_reg  <= ps_step_size_reg;
         end if;
         
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- Other registers
-- ----------------------------------------------------------------------------
   process(clk, reset_n)
   begin
      if reset_n = '0' then
         step_cnt_max_reg <= (others=>'1');
      elsif (clk'event AND clk='1') then 
         step_cnt_max_reg <= step_cnt_max_constant - step_sz;
      end if;
   end process;
  
   
   process(clk, reset_n)
   begin
      if reset_n = '0' then 
         ps_done_reg_manual_mode <= '0';
      elsif (clk'event AND clk='1') then 
         if ps_en = '0' then 
            ps_done_reg_manual_mode <= '0';
         elsif ps_ctrl_busy_reg = '1' AND ps_ctrl_busy = '0' then 
            ps_done_reg_manual_mode <= '1';
         else
            ps_done_reg_manual_mode <= ps_done_reg_manual_mode;
         end if;
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
--state machine
-- ----------------------------------------------------------------------------
fsm_f : process(clk, reset_n)begin
   if(reset_n = '0')then
      current_state  <= idle;
   elsif(clk'event and clk = '1')then 
      current_state <= next_state;
   end if;	
end process;

-- ----------------------------------------------------------------------------
--state machine combo
-- ----------------------------------------------------------------------------
fsm : process(current_state, ps_en, ps_mode, ps_reset_at_start, pll_locked, 
               smpl_cmp_done, smpl_cmp_error, find_min, find_max, seen_fail, 
               ps_ctrl_busy, ps_ctrl_busy_reg, ps_en_reg, step_cnt, 
               prep_phase_cnt, wait_after_ph_shift_cnt, step_cnt_max_reg, fsm_timer) begin
   next_state <= current_state;
   case current_state is
   
      when idle =>                     -- wait for start
         -- rising edge of ps_en and ps_mode = 1
         if ((ps_en = '1' AND ps_en_reg = '0') AND ps_mode = '1') then
            if ps_reset_at_start = '1' then 
               next_state <= rst_pll;
            else 
               next_state <= wait_pll_lock;
            end if;
         else 
            next_state <= idle;
         end if;
         
      when rst_pll =>                  -- reset pll
         if pll_locked = '0' or fsm_timer > RST_PLL_TIMEOUT then 
            next_state <= wait_pll_lock;
         else 
            next_state <= rst_pll;
         end if;
         
      when wait_pll_lock =>            -- wait pll lock
         if pll_locked = '1' then
            -- check if this is not end of procedure
            if find_min = '1' OR find_max = '1' then
               next_state <= check_cmp_status;
            else 
               next_state <= ph_shift;
            end if;
         elsif fsm_timer > FSM_TIMEOUT_LIMIT then 
            next_state <= end_srch;
         else 
            next_state <= wait_pll_lock;
         end if;
         
      when check_cmp_status => 
         if smpl_cmp_done = '0' then 
            next_state <= cmp_smpls;
         elsif fsm_timer > FSM_TIMEOUT_LIMIT then 
            next_state <= end_srch;
         else 
            next_state <= check_cmp_status;
         end if;
         
      when cmp_smpls =>                -- get status from compared samples
         if smpl_cmp_done = '1' then
            -- check if we are looking for minimum phase 
            if find_min = '1' then 
               -- Accept the minimum only on a fail -> pass transition. A pass seen before
               -- any failure may be in the middle of a window that straddles the start
               -- phase, which would bias the midpoint. Failures at the first two
               -- steps (step_cnt <= 2) are ignored, as before, because the compare
               -- right after the PLL reset may be invalid.
               if smpl_cmp_error = '0' AND seen_fail = '1' then
                  next_state <= min_found;
               else 
                  next_state <= check_max_steps;
               end if;
            -- check if we are looking for maximum phase
            elsif find_max = '1' then  
               if smpl_cmp_error = '1' then
                  next_state <= max_found;
               else 
                  next_state <= check_max_steps;
               end if;
            -- otherwise end searching
            else  
               next_state <= end_srch;
            end if;
         elsif fsm_timer > FSM_TIMEOUT_LIMIT then 
            next_state <= end_srch;
         else 
            next_state <= cmp_smpls;
         end if;
         
      when min_found =>       -- minimum phase is found, proceed
         next_state <= check_max_steps;
         
      when max_found =>       -- maximum phase is found, prepare final phase value
         next_state <= sel_window;
         
      when sel_window =>      -- keep the larger of [min, max] and the initial passing run
         next_state <= prep_phase;
         
      when check_max_steps =>
         if step_cnt < step_cnt_max_reg then 
            next_state <= ph_shift;
         else
            -- End of range:
            --  * minimum found, maximum not: window extends to the end of the range,
            --    centre on [min, last tested step];
            --  * no failure seen at all: every phase passes, centre on the range;
            --  * failures seen but no passing window after them: error.
            if find_min = '0' OR seen_fail = '0' then 
               next_state <= sel_window;
            else 
               next_state <= end_srch;
            end if;
         end if;
         
      when ph_shift =>
         if ps_ctrl_busy = '0' AND ps_ctrl_busy_reg = '1' then  --falling edge 
            next_state <= wait_after_ph_shift;              
         elsif fsm_timer > FSM_TIMEOUT_LIMIT then 
            next_state <= end_srch;
         else 
            next_state <= ph_shift;
         end if;
         
      when wait_after_ph_shift => 
         if wait_after_ph_shift_cnt > x"FD" then 
            next_state <= check_cmp_status;
         else 
            next_state <= wait_after_ph_shift;
         end if;
         
         
      when prep_phase =>     -- wait some cycles until final phase value is calculated
         if prep_phase_cnt > 2 then 
            next_state <= ph_shift;
         else 
            next_state <= prep_phase;
         end if;
         
      when end_srch =>       -- end searching procedure
         next_state <= idle;
         
      when others => 
         next_state <= idle;
   end case;
end process;

-- ----------------------------------------------------------------------------
-- fsm dependant registers
-- ----------------------------------------------------------------------------
process(clk, reset_n)
begin
   if reset_n = '0' then 
      find_min       <= '1';
      find_max       <= '1';
      step_cnt       <= (others=> '0');
      step_cnt_min   <= (others=> '0');
      step_cnt_max   <= (others=> '1');
      prep_phase_cnt <= (others=> '0');
      wait_after_ph_shift_cnt <= (others => '0');
   elsif (clk'event AND clk='1') then
   
      -- minimum phase search control bit for fsm
      if current_state = idle then 
         find_min <= '1';
      elsif current_state = min_found OR current_state = prep_phase then 
         find_min <= '0';
      else 
         find_min <= find_min;         
      end if;
      
      -- maximum phase search control bit for fsm
      if current_state = idle then 
         find_max <= '1';
      elsif current_state = max_found OR current_state = prep_phase then 
         find_max <= '0';
      else 
         find_max <= find_max;         
      end if;
      
      -- failing phase seen while searching for the minimum
      if current_state = idle then 
         seen_fail <= '0';
      elsif current_state = cmp_smpls AND smpl_cmp_done = '1' AND find_min = '1' AND 
            smpl_cmp_error = '1' AND step_cnt > 2 then 
         seen_fail <= '1';
      end if;
      
      -- passing run before the first failure (the window may straddle the start phase;
      -- it is only used if the window found after the failure is smaller, e.g. when
      -- that one is truncated by the end of the range at low interface frequencies)
      if current_state = idle then 
         init_valid <= '0';
         init_min   <= (others => '0');
         init_max   <= (others => '0');
      elsif current_state = cmp_smpls AND smpl_cmp_done = '1' AND find_min = '1' AND 
            seen_fail = '0' AND step_cnt > 2 then 
         if smpl_cmp_error = '0' AND init_valid = '0' then 
            init_valid <= '1';
            init_min   <= step_cnt;
         elsif smpl_cmp_error = '1' then 
            init_max   <= step_cnt - step_sz;
         end if;
      end if;
      
      -- minimum phase shift register
      if current_state = sel_window AND init_valid = '1' AND seen_fail = '1' AND 
         (init_max - init_min) > (step_cnt_max - step_cnt_min) then 
         step_cnt_min <= init_min;
      elsif current_state = min_found then 
         step_cnt_min <= step_cnt;
      elsif current_state = idle then 
         step_cnt_min   <= (others=> '0');
      else 
         step_cnt_min <= step_cnt_min;
      end if;
      
      -- maximum phase shift value register
      if current_state = sel_window AND init_valid = '1' AND seen_fail = '1' AND 
         (init_max - init_min) > (step_cnt_max - step_cnt_min) then 
         step_cnt_max <= init_max;
      elsif current_state = max_found then
         -- minus 1 step, because last phase step is always invalid 
         step_cnt_max <= step_cnt - step_sz;
      elsif current_state = check_max_steps AND step_cnt >= step_cnt_max_reg AND find_max = '1' then
         -- end of range without a maximum: last tested step is the window end
         step_cnt_max <= step_cnt;
      elsif current_state = idle then 
         step_cnt_max <= step_cnt_max_constant;
      else 
         step_cnt_max <= step_cnt_max;
      end if;
      
      -- counter for phase shift value
      -- (only when a further shift follows: when the range is exhausted the PLL stays
      -- at the last tested step, and step_cnt must match it for the final reverse shift)
      if current_state = check_max_steps AND step_cnt < step_cnt_max_reg then 
         step_cnt <= step_cnt + step_sz;
      elsif current_state = idle then 
         step_cnt <= (others=> '0');
      else 
         step_cnt <= step_cnt;
      end if;
      
      -- counter to hold fsm in prep_phase state
      if current_state = prep_phase then 
         prep_phase_cnt <= prep_phase_cnt + 1;
      else 
         prep_phase_cnt <= (others => '0');
      end if;
      
      if current_state = wait_after_ph_shift then 
         wait_after_ph_shift_cnt <=  wait_after_ph_shift_cnt + 1;
      else
         wait_after_ph_shift_cnt <= (others => '0');
      end if;
      
   end if;
end process;

-- ----------------------------------------------------------------------------
-- FSM watchdog timer
-- ----------------------------------------------------------------------------
process(clk, reset_n)
begin
   if reset_n = '0' then 
      fsm_timer   <= (others => '0');
      timeout_err <= '0';
   elsif (clk'event AND clk='1') then 
      if current_state = idle then 
         fsm_timer   <= (others => '0');
         timeout_err <= '0';
      elsif current_state /= next_state then 
         fsm_timer   <= (others => '0');
      else 
         if fsm_timer /= unsigned'(x"FFFFF") then 
            fsm_timer <= fsm_timer + 1;
         end if;
         if (current_state = wait_pll_lock or current_state = check_cmp_status or 
             current_state = cmp_smpls or current_state = ph_shift) and 
            (fsm_timer > FSM_TIMEOUT_LIMIT) then 
            timeout_err <= '1';
         end if;
      end if;
   end if;
end process;


-- ----------------------------------------------------------------------------
-- output registers
-- ----------------------------------------------------------------------------
process(clk, reset_n)
begin
   if reset_n = '0' then 
      pll_reset_req_reg <= '0';
      smpl_cmp_en_reg   <= '0';
      ps_ctrl_en_reg    <= '0';
      ps_ctrl_phase_reg <= (others => '0');
      ps_done_reg       <= '0';
      ps_status_reg     <= '0';
   elsif (clk'event AND clk='1') then
      -- pll reset request
      if current_state = rst_pll then 
         pll_reset_req_reg <= '1';
      else 
         pll_reset_req_reg <= '0';
      end if;
      
      -- sample compare enable
      if current_state = cmp_smpls then 
         smpl_cmp_en_reg <= '1';
      else 
         smpl_cmp_en_reg <= '0';
      end if;
      
      -- phase shift control module enable
      if current_state = ph_shift then 
         ps_ctrl_en_reg <= '1';
      else 
         ps_ctrl_en_reg <= '0';
      end if;
      
      -- phase shift control module phase register
      if current_state = idle then 
         ps_ctrl_phase_reg <= std_logic_vector(step_in);
      elsif current_state = prep_phase then 
         -- final move from the last tested phase to centre + bias:
         -- back by (reverse - bias), or forward by (bias - reverse) if the bias is larger
         if step_cnt_reverse >= ps_bias then 
            ps_ctrl_phase_reg <= std_logic_vector(step_cnt_reverse - ps_bias);
         else 
            ps_ctrl_phase_reg <= std_logic_vector(ps_bias - step_cnt_reverse);
         end if;
      else 
         ps_ctrl_phase_reg <= ps_ctrl_phase_reg;
      end if;
      
      -- phase shift control module phase direction register
      if current_state = idle then 
         ps_ctrl_updwn_reg <= ps_updwn;
      elsif current_state = prep_phase then 
         if step_cnt_reverse >= ps_bias then 
            ps_ctrl_updwn_reg <= not ps_updwn_reg;
         else 
            ps_ctrl_updwn_reg <= ps_updwn_reg;
         end if;
      else 
         ps_ctrl_updwn_reg <= ps_ctrl_updwn_reg;
      end if;
          
      -- phase shift done register
      if ps_en = '0' then
         ps_done_reg <= '0';
      elsif current_state = end_srch then 
         ps_done_reg <= '1';
      else 
         ps_done_reg <= ps_done_reg;
      end if;
      
      -- phase shift status register
      if ps_en = '0' then
         ps_status_reg <= '0';
      elsif current_state = end_srch then
         if timeout_err = '1' or find_min = '1' then
            ps_status_reg <= '1';
         else
            ps_status_reg <= smpl_cmp_error;
         end if;
      else 
         ps_status_reg <= ps_status_reg;
      end if;
       
   end if;
end process;

-- ----------------------------------------------------------------------------
-- debug readback: last search result
-- ----------------------------------------------------------------------------
process(clk, reset_n)
begin
   if reset_n = '0' then
      ps_dbg <= (others => '0');
   elsif rising_edge(clk) then
      if current_state = end_srch then
         if timeout_err = '1' or find_min = '1' then
            ps_dbg(31) <= '1';
         else
            ps_dbg(31) <= smpl_cmp_error;
         end if;
         ps_dbg(30)           <= seen_fail;
         ps_dbg(29 downto 20) <= std_logic_vector(step_cnt_min);
         ps_dbg(19 downto 10) <= std_logic_vector(step_cnt_max);
         ps_dbg(9 downto 0)   <= std_logic_vector(step_cnt_middle);
      end if;
   end if;
end process;

-- ----------------------------------------------------------------------------
-- calculate required phase shift
-- ----------------------------------------------------------------------------
process(clk, reset_n)
begin
   if reset_n = '0' then 
      step_cnt_diff     <= (others => '0');
      step_cnt_middle   <= (others => '0');
      step_cnt_reverse  <= (others => '0');
   elsif (clk'event AND clk='1') then 
      step_cnt_diff     <= step_cnt_max - step_cnt_min;
      step_cnt_middle   <= unsigned('0' & step_cnt_diff(9 downto 1)) + step_cnt_min;
      step_cnt_reverse  <= step_cnt - step_cnt_middle;
   end if;
end process;


-- ----------------------------------------------------------------------------
-- output ports
-- ----------------------------------------------------------------------------
ps_ctrl_en     <= ps_en                   when ps_mode = '0' else ps_ctrl_en_reg;
ps_ctrl_cnt    <= ps_cnt                  when ps_mode = '0' else ps_cnt_reg;
ps_ctrl_updown <= ps_updwn                when ps_mode = '0' else ps_ctrl_updwn_reg;
ps_ctrl_phase  <= ps_phase                when ps_mode = '0' else ps_ctrl_phase_reg;
ps_done        <= ps_done_reg_manual_mode when ps_mode = '0' else ps_done_reg;
ps_status      <= ps_ctrl_busy            when ps_mode = '0' else ps_status_reg;

pll_reset_req     <= pll_reset_req_reg;
smpl_cmp_en       <= smpl_cmp_en_reg;





  
end arch;   


