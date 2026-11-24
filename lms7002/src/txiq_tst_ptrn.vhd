-- ----------------------------------------------------------------------------	
-- FILE: 	txiq_tst_ptrn.vhd
-- DESCRIPTION:	Creates test samples for tx IQ in DDR mode
-- DATE:	Jan 27, 2016
-- AUTHOR(s):	Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------	
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity txiq_tst_ptrn is
   generic(
      diq_width   : integer := 12;
      -- 0: legacy constant pattern, I = 0xAAA, Q = 0x555 in every frame.
      -- 1: 4-frame sequence (see below) that drives every data pin both rising and
      --    falling at both the I->Q (mid-frame) and the Q->I (frame) boundary.
      g_ALT_PTRN  : integer range 0 to 1 := 0
   );
   port (

      clk      : in std_logic;
      reset_n  : in std_logic;

      diq_h    : out std_logic_vector(diq_width downto 0);
      diq_l    : out std_logic_vector(diq_width downto 0)

        );
end txiq_tst_ptrn;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of txiq_tst_ptrn is
--declare signals,  components here
signal fsync_int  : std_logic;
signal fsync_ext  : std_logic;
signal ptrn_h     : std_logic_vector(15 downto 0);
signal ptrn_l     : std_logic_vector(15 downto 0);
signal frame_cnt  : unsigned(1 downto 0);
  
begin

----Test pattern 
-- With the legacy constant pattern every odd pin only ever falls at the I->Q
-- boundary and rises at the Q->I boundary (even pins the opposite), so half of
-- the edge/direction combinations are never exercised by the phase search.
-- The alternative sequence (one frame per clk, I/Q):
--    0: AAA/000   1: AAA/FFF   2: 555/000   3: 555/FFF
-- gives on an odd pin  1,0 | 1,1 | 0,0 | 0,1  -> I->Q: fall, rise; Q->I: rise, fall
-- and on an even pin   0,0 | 0,1 | 1,0 | 1,1  -> I->Q: rise, fall; Q->I: fall, rise
-- I words are always 0xAAA/0x555 and Q words 0x000/0xFFF: within each set the words
-- differ in all 12 bits (any bit error is detected), and the sets are disjoint, so a
-- half-period (I<->Q) slip is detected as well (smpl_cmp alt_ptrn mode).
-- Exactly 6 of 12 pins toggle at every half-cycle boundary (legacy: all 12).
ptrn_gen_const : if g_ALT_PTRN = 0 generate
   ptrn_h <= x"AAAA"; --I
   ptrn_l <= X"5555"; --Q
end generate;

ptrn_gen_alt : if g_ALT_PTRN = 1 generate
   frame_cnt_proc : process(reset_n, clk)
   begin
      if reset_n = '0' then
         frame_cnt <= (others => '0');
      elsif rising_edge(clk) then
         frame_cnt <= frame_cnt + 1;
      end if;
   end process;

   ptrn_h <= x"AAAA" when frame_cnt(1) = '0' else x"5555"; --I
   ptrn_l <= x"0000" when frame_cnt(0) = '0' else x"FFFF"; --Q
end generate;
 
fsync_gen : process(reset_n, clk)
    begin
      if reset_n='0' then
         fsync_int <= '1';  
      elsif (clk'event and clk = '1') then
 	      fsync_int <= not fsync_int;
 	    end if;
    end process;
    
fsync_ext <=  NOT fsync_int;

diq_h(diq_width) <= fsync_ext;
diq_l(diq_width) <= fsync_ext;

diq_h(diq_width-1 downto 0) <= ptrn_h(diq_width-1 downto 0);
diq_l(diq_width-1 downto 0) <= ptrn_l(diq_width-1 downto 0);
  
end arch;   





