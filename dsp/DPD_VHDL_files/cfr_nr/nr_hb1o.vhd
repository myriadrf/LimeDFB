
-- ----------------------------------------------------------------------------	
-- FILE: 	hb1o.vhd
-- DESCRIPTION:	Odd part of HB1 filter. It is pure delay with the 
--		following filtering function: H(z) = z^-14. 11 extra 
--		delays are introduced in H(z) in order to compensate 
--		for the delays used to pipeline CSE calculator, CSD multipliers, 
--		tap adders and saturation logic. Therefore, final filter 
--		implements H(z) = z^-25.
-- DATE:	July 26, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- REVISIONS:
-- ----------------------------------------------------------------------------	

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
ENTITY nr_hb1o IS
	PORT (
		x : IN STD_LOGIC_VECTOR(24 DOWNTO 0); -- Input signal
		clk : IN STD_LOGIC; -- Clock and reset
		en : IN STD_LOGIC;
		reset : IN STD_LOGIC;
		y : OUT STD_LOGIC_VECTOR(24 DOWNTO 0) -- Output signal
	);
END nr_hb1o;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE hb1o_arch OF nr_hb1o IS

	-- Delayed input samples
	SIGNAL x1 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x2 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x3 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x4 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x5 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x6 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x7 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x8 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x9 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x10 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x11 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x12 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x13 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x14 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x15 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x16 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x17 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x18 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x19 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x20 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x21 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x22 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x23 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x24 : STD_LOGIC_VECTOR(24 DOWNTO 0);
	SIGNAL x25, x26, x27, x28 : STD_LOGIC_VECTOR(24 DOWNTO 0);

BEGIN
	-- Delay line
	delay : PROCESS (clk)  --, reset
	BEGIN
--		IF reset = '0' THEN
--			x1 <= (OTHERS => '0');
--			x2 <= (OTHERS => '0');
--			x3 <= (OTHERS => '0');
--			x4 <= (OTHERS => '0');
--			x5 <= (OTHERS => '0');
--			x6 <= (OTHERS => '0');
--			x7 <= (OTHERS => '0');
--			x8 <= (OTHERS => '0');
--			x9 <= (OTHERS => '0');
--			x10 <= (OTHERS => '0');
--			x11 <= (OTHERS => '0');
--			x12 <= (OTHERS => '0');
--			x13 <= (OTHERS => '0');
--			x14 <= (OTHERS => '0');
--			x15 <= (OTHERS => '0');
--			x16 <= (OTHERS => '0');
--			x17 <= (OTHERS => '0');
--			x18 <= (OTHERS => '0');
--			x19 <= (OTHERS => '0');
--			x20 <= (OTHERS => '0');
--			x21 <= (OTHERS => '0');
--			x22 <= (OTHERS => '0');
--			x23 <= (OTHERS => '0');
--			x24 <= (OTHERS => '0');
--			x21 <= (OTHERS => '0');
--			x22 <= (OTHERS => '0');
--			x23 <= (OTHERS => '0');
--			x24 <= (OTHERS => '0');
--			x25 <= (OTHERS => '0');
--			x26 <= (OTHERS => '0');
--			x27 <= (OTHERS => '0');
--			x28 <= (OTHERS => '0');
--			y <= (OTHERS => '0');
--			els
			IF clk'event AND clk = '1' THEN
				IF en = '1' THEN
					x1 <= x;
					x2 <= x1;
					x3 <= x2;
					x4 <= x3;
					x5 <= x4;
					x6 <= x5;
					x7 <= x6;
					x8 <= x7;
					x9 <= x8;
					x10 <= x9;
					x11 <= x10;
					x12 <= x11;
					x13 <= x12;
					x14 <= x13;
					x15 <= x14;
					x16 <= x15;
					x17 <= x16;
					x18 <= x17;
					x19 <= x18;
					x20 <= x19;
					x21 <= x20;
					x22 <= x21;
					x23 <= x22;
					x24 <= x23;
					x25 <= x24;
					x26 <= x25;
					x27 <= x26;
					x28 <= x27;
					--y <= x24;
					y <= x28;
				END IF;
			END IF;
		END PROCESS delay;
	END hb1o_arch;