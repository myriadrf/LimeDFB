-- ----------------------------------------------------------------------------	
-- FILE: 	ta26.vhd
-- DESCRIPTION:	26 bit tap adder.
-- DATE:	Jul 24, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- REVISIONS:	July 27:	Datapath width changed to 26.
-- ----------------------------------------------------------------------------	

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ------------------------------------ ---------------------------------------
entity ta26 is
    port (
    	a: in std_logic_vector(25 downto 0); -- Inputs
    	b: in std_logic_vector(25 downto 0);
	sign: in std_logic;	-- Sign bit for 'a'
	clk: in std_logic;	-- Clock and reset
	en: in std_logic;	-- Enable
	reset: in std_logic;
	s: buffer std_logic_vector(25 downto 0) -- Output signal
    );
end ta26;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture ta26_arch of ta26 is
	-- Carry signals
	signal c1, c1l, c2, c2l, c3, c3l: std_logic;
	
	-- Delayed versions of sign bit
	signal signl, signll, signlll: std_logic;
	
	-- Inverted version of 'a' input signal
	signal a1: std_logic_vector(7 downto 0);
	signal a2: std_logic_vector(7 downto 0);
	signal a3: std_logic_vector(7 downto 0);
	signal a4: std_logic_vector(1 downto 0);
	
	-- Internal adder sums for inferred arithmetic (8+8+8+2 with carry)
	signal sum1 : unsigned(8 downto 0);
	signal sum2 : unsigned(8 downto 0);
	signal sum3 : unsigned(8 downto 0);
	signal sum4 : unsigned(2 downto 0);
	-- Local carry-in vectors (LSB carries) for each segment
	signal cin1 : unsigned(8 downto 0);
	signal cin2 : unsigned(8 downto 0);
	signal cin3 : unsigned(8 downto 0);
	signal cin4 : unsigned(2 downto 0);
	
begin

	-- LATCHES
	latches: process(clk, reset)
	begin
		if reset = '0' then
			c1l <= '0';
			c2l <= '0';
			c3l <= '0';
			signl <= '0';
			signll <= '0';
			signlll <= '0';
		elsif clk'event and clk = '1' then
			if en = '1' then
				c1l <= c1;
				c2l <= c2;
				c3l <= c3;
				signl <= sign;
				signll <= signl;
				signlll <= signll;
			end if;
		end if;
	end process latches;
	
	-- Invert 'a' input if sign = 1
	a1 <= a(7 downto 0) when sign = '0' else not a(7 downto 0);
	a2 <= a(15 downto 8) when signl = '0' else not a(15 downto 8);
	a3 <= a(23 downto 16) when signll = '0' else not a(23 downto 16);
	a4 <= a(25 downto 24) when signlll = '0' else not a(25 downto 24);
	
	-- Inferred segmented adders (8 + 8 + 8 + 2) with registered carry hand-off
	-- Form carry-in vectors with only LSB set when carry-in is '1'
	cin1 <= (8 downto 1 => '0', 0 => sign);
	cin2 <= (8 downto 1 => '0', 0 => c1l);
	cin3 <= (8 downto 1 => '0', 0 => c2l);
	cin4 <= (2 downto 1 => '0', 0 => c3l);

	-- Low significant 8 bits
	sum1 <= unsigned('0' & a1) + unsigned('0' & b(7 downto 0)) + cin1;
	c1   <= sum1(8);
	s(7 downto 0) <= std_logic_vector(sum1(7 downto 0));

	-- Medium significant 8 bits
	sum2 <= unsigned('0' & a2) + unsigned('0' & b(15 downto 8)) + cin2;
	c2   <= sum2(8);
	s(15 downto 8) <= std_logic_vector(sum2(7 downto 0));

	-- High significant 8 bits
	sum3 <= unsigned('0' & a3) + unsigned('0' & b(23 downto 16)) + cin3;
	c3   <= sum3(8);
	s(23 downto 16) <= std_logic_vector(sum3(7 downto 0));

	-- Top 2 bits
	sum4 <= unsigned('0' & a4) + unsigned('0' & b(25 downto 24)) + cin4;
	s(25 downto 24) <= std_logic_vector(sum4(1 downto 0));

end ta26_arch;
