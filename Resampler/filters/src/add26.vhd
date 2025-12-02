-- ----------------------------------------------------------------------------	
-- FILE: 	add26.vhd
-- DESCRIPTION:	26 bit pipelined adder.
-- DATE:	Aug 24, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- REVISIONS:
-- ----------------------------------------------------------------------------	

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity add26 is
    port (
    	a: in std_logic_vector(25 downto 0); -- Inputs
    	b: in std_logic_vector(25 downto 0);
	cin: std_logic;
	clk: in std_logic;	-- Clock and reset
	en: in std_logic;	-- Enable
	reset: in std_logic;
	s: out std_logic_vector(25 downto 0); -- Output signal
	cout: out std_logic
    );
end add26;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture add26_arch of add26 is

	-- Notes:
	-- - 26-bit pipelined adder split into 4 blocks: [7:0], [15:8], [23:16], [25:24].
	-- - Three pipeline register stages capture operands/carries; a 4th stage captures the outputs.
	-- - Active-low asynchronous reset (reset='0').
	-- - Clock enable 'en' gates pipeline advancement.

	-- Internal signals
	signal a4aa, a4a, a4, b4aa, b4a, b4, s4: std_logic_vector(1 downto 0);
	signal c4: std_logic;

	signal a3a, a3, b3a, b3, s3, s3d: std_logic_vector(7 downto 0);
	signal c3, c3l: std_logic;

	signal a2, b2, s2, s2d, s2dd: std_logic_vector(7 downto 0);
	signal c2, c2l: std_logic;

	signal s1, s1d, s1dd, s1ddd: std_logic_vector(7 downto 0);
	signal c1, c1l: std_logic;

	-- Arithmetic helpers (no BCLA):
	signal sum1_u9, sum2_u9, sum3_u9 : unsigned(8 downto 0);
	signal sum4_u3                   : unsigned(2 downto 0);

begin
	-- Latch a
	latcha: process(clk, reset)
	begin
		if reset = '0' then	       
			a4aa <= (others => '0');
			b4aa <= (others => '0');
			a3a <= (others => '0');
			b3a <= (others => '0');
			a2 <= (others => '0');
			b2 <= (others => '0');
			c1l <= '0';
			s1d <= (others => '0');
		elsif rising_edge(clk) then
			if en = '1' then
				a4aa <= a(25 downto 24);
				b4aa <= b(25 downto 24);
				a3a <= a(23 downto 16);
				b3a <= b(23 downto 16);
				a2 <= a(15 downto 8);
				b2 <= b(15 downto 8);
				c1l <= c1;
				s1d <= s1;
			end if;
		end if;
	end process latcha;

	-- Latch b
	latchb: process(clk, reset)
	begin
		if reset = '0' then
			a4a <= (others => '0');
			b4a <= (others => '0');
			a3 <= (others => '0');
			b3 <= (others => '0');
			c2l <= '0';
			s2d <= (others => '0');
			s1dd <= (others => '0');
		elsif rising_edge(clk) then
			if en = '1' then
				a4a <= a4aa;
				b4a <= b4aa;
				a3 <= a3a;
				b3 <= b3a;
				c2l <= c2;
				s2d <= s2;
				s1dd <= s1d;
			end if;
		end if;
	end process latchb;
	
	-- Latch c
	latchc: process(clk, reset)
	begin
		if reset = '0' then
			a4 <= (others => '0');
			b4 <= (others => '0');
			c3l <= '0';
			s3d <= (others => '0');
			s2dd <= (others => '0');
			s1ddd <= (others => '0');
		elsif rising_edge(clk) then
			if en = '1' then
				a4 <= a4a;
				b4 <= b4a;
				c3l <= c3;
				s3d <= s3;
				s2dd <= s2d;
				s1ddd <= s1dd;
			end if;
		end if;
	end process latchc;

	-- Latch d
	latchd: process(clk, reset)
	begin
		if reset = '0' then
			s <= (others => '0');
			cout <= '0';
		elsif rising_edge(clk) then
			if en = '1' then
				s(25 downto 24) <= s4;
				s(23 downto 16) <= s3d;
				s(15 downto 8) <= s2dd;
				s(7 downto 0) <= s1ddd;
				cout <= c4;
			end if;
		end if;
	end process latchd;
	
	-- Low significant bits adder (arithmetic)
	sum1_u9 <= resize(unsigned(a(7 downto 0)), 9)
	         + resize(unsigned(b(7 downto 0)), 9)
	         + to_unsigned((1) , 9) when cin = '1' else
	           resize(unsigned(a(7 downto 0)), 9) + resize(unsigned(b(7 downto 0)), 9);
	s1      <= std_logic_vector(sum1_u9(7 downto 0));
	c1      <= sum1_u9(8);

	-- Medium significant bits adder
	sum2_u9 <= resize(unsigned(a2), 9) + resize(unsigned(b2), 9)
	         + to_unsigned((1), 9) when c1l = '1' else
	           resize(unsigned(a2), 9) + resize(unsigned(b2), 9);
	s2      <= std_logic_vector(sum2_u9(7 downto 0));
	c2      <= sum2_u9(8);

	-- High significant bits adder
	sum3_u9 <= resize(unsigned(a3), 9) + resize(unsigned(b3), 9)
	         + to_unsigned((1), 9) when c2l = '1' else
	           resize(unsigned(a3), 9) + resize(unsigned(b3), 9);
	s3      <= std_logic_vector(sum3_u9(7 downto 0));
	c3      <= sum3_u9(8);

	-- Additional 2 bit adder
	sum4_u3 <= resize(unsigned(a4), 3) + resize(unsigned(b4), 3)
	         + to_unsigned((1), 3) when c3l = '1' else
	           resize(unsigned(a4), 3) + resize(unsigned(b4), 3);
	s4      <= std_logic_vector(sum4_u3(1 downto 0));
	c4      <= sum4_u3(2);

end add26_arch;
