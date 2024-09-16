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
      diq_width   : integer := 12
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
  
begin

----Test pattern 
ptrn_h <= x"AAAA"; --I
ptrn_l <= X"5555"; --Q
 
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





