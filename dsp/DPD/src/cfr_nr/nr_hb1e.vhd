-- ----------------------------------------------------------------------------	
-- FILE: 	hb1e.vhd
-- DESCRIPTION:	Even part of HB1 filter.
-- DATE:	July 26, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- REVISIONS:	July 27:	Datapath width changed to 26.
-- ----------------------------------------------------------------------------	

-- ****************** Filter Design Results ******************* 
--Filter type:            HALF BAND
--Number of taps:         39
--Bands:                  0-0.198, and 0.302-0.5
--Desired amplitude:      1 for band 1 and 0 for band 2.
--Coefficients precision: 18
--CSD precision:          6
-------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
ENTITY nr_hb1e IS
    PORT (
        x : IN STD_LOGIC_VECTOR(24 DOWNTO 0); -- Input signal
        clk : IN STD_LOGIC; -- Clock and reset
        en : IN STD_LOGIC;
        reset : IN STD_LOGIC;
        y : OUT STD_LOGIC_VECTOR(24 DOWNTO 0) -- Output signal
    );
END nr_hb1e;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE hb1e_arch OF nr_hb1e IS

    -- Common sub-expression signals
    SIGNAL xp : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xo : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xm : STD_LOGIC_VECTOR(25 DOWNTO 0);

    -- Outputs from CSD multipliers
    SIGNAL xh0 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh2 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh4 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh6 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh8 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh10 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh12 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh14 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh16 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL xh18 : STD_LOGIC_VECTOR(25 DOWNTO 0);

    -- Outputs from the tap adders
    SIGNAL s0 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s2 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s4 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s6 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s8 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s10 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s12 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s14 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s16 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s18 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s20 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s22 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s24 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s26 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s28 : STD_LOGIC_VECTOR(25 DOWNTO 0); --
    SIGNAL s30 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s32 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s34 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL s36 : STD_LOGIC_VECTOR(25 DOWNTO 0);

    -- Outputs from the delay elements	
    SIGNAL b0 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b1 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b2 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b3 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b4 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b5 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b6 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b7 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b8 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b9 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b10 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b11 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b12 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b13 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b14 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b15 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b16 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b17 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b18 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b19 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b20 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b21 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b22 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b23 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b24 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b25 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b26 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b27 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b28 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b29 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b30 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b31 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b32 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b33 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b34 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b35 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b36 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL b37 : STD_LOGIC_VECTOR(25 DOWNTO 0);
    -- Logic signals
    SIGNAL zeroes : STD_LOGIC_VECTOR(25 DOWNTO 0);
    SIGNAL zero : STD_LOGIC;
    SIGNAL one : STD_LOGIC;
    COMPONENT csec IS
        PORT (
            x : IN STD_LOGIC_VECTOR(24 DOWNTO 0);
            clk : IN STD_LOGIC; -- Clock and reset
            en : IN STD_LOGIC; -- Enable
            reset : IN STD_LOGIC;
            xp : OUT STD_LOGIC_VECTOR(25 DOWNTO 0); -- x*(1+1/4)
            xo : OUT STD_LOGIC_VECTOR(25 DOWNTO 0); -- just delayed x
            xm : OUT STD_LOGIC_VECTOR(25 DOWNTO 0) -- x*(1-1/4)
        );
    END COMPONENT csec;
    COMPONENT tt IS
        PORT (
            x : IN STD_LOGIC_VECTOR(25 DOWNTO 0); -- Input signal
            clk : IN STD_LOGIC; -- Clock and reset
            en : IN STD_LOGIC; -- Enable
            reset : IN STD_LOGIC;
            y : OUT STD_LOGIC_VECTOR(24 DOWNTO 0) -- Output signal
        );
    END COMPONENT tt;
    COMPONENT ta26 IS
        PORT (
            a : IN STD_LOGIC_VECTOR(25 DOWNTO 0); -- Inputs
            b : IN STD_LOGIC_VECTOR(25 DOWNTO 0);
            sign : IN STD_LOGIC; -- Sign bit for 'a'
            clk : IN STD_LOGIC; -- Clock and reset
            en : IN STD_LOGIC; -- Enable
            reset : IN STD_LOGIC;
            s : BUFFER STD_LOGIC_VECTOR(25 DOWNTO 0) -- Output signal
        );
    END COMPONENT ta26;
    COMPONENT csdm26x4 IS
        PORT (
            x0 : IN STD_LOGIC_VECTOR(25 DOWNTO 0); -- Inputs
            x1 : IN STD_LOGIC_VECTOR(25 DOWNTO 0);
            x2 : IN STD_LOGIC_VECTOR(25 DOWNTO 0);
            x3 : IN STD_LOGIC_VECTOR(25 DOWNTO 0);
            d1 : IN STD_LOGIC; -- Sign bits for x1, ... x3
            d2 : IN STD_LOGIC;
            d3 : IN STD_LOGIC;
            clk : IN STD_LOGIC; -- Clock signal
            en : IN STD_LOGIC; -- Enable
            reset : IN STD_LOGIC; -- Reset signal
            sout : OUT STD_LOGIC_VECTOR(25 DOWNTO 0)
        );
    END COMPONENT csdm26x4;
BEGIN
    -- Set logic signals
    zeroes <= "00000000000000000000000000";
    zero <= '0';
    one <= '1';

    -- Common sub-expressions calculation
    csecb : csec PORT MAP(
        x => x, clk => clk, en => en, reset => reset,
        xp => xp, xo => xo, xm => xm);

    -- Delay line
    delay : PROCESS (clk)  --, reset
    BEGIN
--        IF reset = '0' THEN
--            b0 <= (OTHERS => '0');
--            b1 <= (OTHERS => '0');
--            b2 <= (OTHERS => '0');
--            b3 <= (OTHERS => '0');
--            b4 <= (OTHERS => '0');
--            b5 <= (OTHERS => '0');
--            b6 <= (OTHERS => '0');
--            b7 <= (OTHERS => '0');
--            b8 <= (OTHERS => '0');
--            b9 <= (OTHERS => '0');
--            b10 <= (OTHERS => '0');
--            b11 <= (OTHERS => '0');
--            b12 <= (OTHERS => '0');
--            b13 <= (OTHERS => '0');
--            b14 <= (OTHERS => '0');
--            b15 <= (OTHERS => '0');
--            b16 <= (OTHERS => '0');
--            b17 <= (OTHERS => '0');
--            b18 <= (OTHERS => '0');
--            b19 <= (OTHERS => '0');
--            b20 <= (OTHERS => '0');
--            b21 <= (OTHERS => '0');
--            b22 <= (OTHERS => '0');
--            b23 <= (OTHERS => '0');
--            b24 <= (OTHERS => '0');
--            b25 <= (OTHERS => '0');
--            b26 <= (OTHERS => '0');
--            b27 <= (OTHERS => '0');
--            b28 <= (OTHERS => '0');
--            b29 <= (OTHERS => '0');
--            b30 <= (OTHERS => '0');
--            b31 <= (OTHERS => '0');
--            b32 <= (OTHERS => '0');
--            b33 <= (OTHERS => '0');
--            b34 <= (OTHERS => '0');
--            b35 <= (OTHERS => '0');
--            b36 <= (OTHERS => '0');
--            b37 <= (OTHERS => '0');
--        ELS
        IF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                b0 <= b1;
                b1 <= s2;
                b2 <= b3;
                b3 <= s4;
                b4 <= b5;
                b5 <= s6;
                b6 <= b7;
                b7 <= s8;
                b8 <= b9;
                b9 <= s10;
                b10 <= b11;
                b11 <= s12;
                b12 <= b13;
                b13 <= s14;
                b14 <= b15;
                b15 <= s16;
                b16 <= b17;
                b17 <= s18;
                b18 <= b19;
                b19 <= s20;
                b20 <= b21;
                b21 <= s22;
                b22 <= b23;
                b23 <= s24;
                b24 <= b25;
                b25 <= s26;
                b26 <= b27;
                b27 <= s28;
                b28 <= b29;--
                b29 <= s30;
                b30 <= b31;
                b31 <= s32;
                b32 <= b33;
                b33 <= s34;
                b34 <= b35;
                b35 <= s36;
                b36 <= b37;
                b37 <= xh0;
                --b29 <= xh0;
            END IF;
        END IF;
    END PROCESS delay;

    -- CSD multiplier h(0)=-0.000335693 = xm( -1/2^11 ) + xo( +1/2^15 )
    h0 : csdm26x4
    PORT MAP(
        x0 => zeroes,

        x1(25) => xm(25), -- - xm >> 10 ----------------------------
        x1(24) => xm(25),
        x1(23) => xm(25),
        x1(22) => xm(25),
        x1(21) => xm(25),
        x1(20) => xm(25),
        x1(19) => xm(25),
        x1(18) => xm(25),
        x1(17) => xm(25),
        x1(16) => xm(25),
        x1(15 DOWNTO 0) => xm(25 DOWNTO 10),

        x2(25) => xo(25), -- + xo >> 14 ----------------------------
        x2(24) => xo(25),
        x2(23) => xo(25),
        x2(22) => xo(25),
        x2(21) => xo(25),
        x2(20) => xo(25),
        x2(19) => xo(25),
        x2(18) => xo(25),
        x2(17) => xo(25),
        x2(16) => xo(25),
        x2(15) => xo(25),
        x2(14) => xo(25),
        x2(13) => xo(25),
        x2(12) => xo(25),
        x2(11 DOWNTO 0) => xo(25 DOWNTO 14),

        x3 => zeroes,

        d1 => one,
        d2 => zero,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh0);

    -- CSD multiplier h(2)= 0.00113678 = xp( +1/2^13 ) + xo( +1/2^10) + xo( +1/2^17)
    h2 : csdm26x4
    PORT MAP(
        x0(25) => xp(25), -- + xp >> 12 ----------------------------
        x0(24) => xp(25),
        x0(23) => xp(25),
        x0(22) => xp(25),
        x0(21) => xp(25),
        x0(20) => xp(25),
        x0(19) => xp(25),
        x0(18) => xp(25),
        x0(17) => xp(25),
        x0(16) => xp(25),
        x0(15) => xp(25),
        x0(14) => xp(25),
        x0(13 DOWNTO 0) => xp(25 DOWNTO 12),

        x1(25) => xo(25), -- + xo >> 9 ----------------------------
        x1(24) => xo(25),
        x1(23) => xo(25),
        x1(22) => xo(25),
        x1(21) => xo(25),
        x1(20) => xo(25),
        x1(19) => xo(25),
        x1(18) => xo(25),
        x1(17) => xo(25),
        x1(16 DOWNTO 0) => xo(25 DOWNTO 9),

        x2(25) => xo(25), -- + xo >> 16 ----------------------------
        x2(24) => xo(25),
        x2(23) => xo(25),
        x2(22) => xo(25),
        x2(21) => xo(25),
        x2(20) => xo(25),
        x2(19) => xo(25),
        x2(18) => xo(25),
        x2(17) => xo(25),
        x2(16) => xo(25),
        x2(15) => xo(25),
        x2(14) => xo(25),
        x2(13) => xo(25),
        x2(12) => xo(25),
        x2(11) => xo(25),
        x2(10) => xo(25),
        x2(9 DOWNTO 0) => xo(25 DOWNTO 16),

        x3 => zeroes,

        d1 => zero,
        d2 => zero,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh2);

    -- CSD multiplier h(4)= -0.00277328 = xp( +1/2^13 ) + xm( -1/2^8 ) + xo( +1/2^18 )
    h4 : csdm26x4
    PORT MAP(
        x0(25) => xp(25), -- + xp >> 12 ----------------------------
        x0(24) => xp(25),
        x0(23) => xp(25),
        x0(22) => xp(25),
        x0(21) => xp(25),
        x0(20) => xp(25),
        x0(19) => xp(25),
        x0(18) => xp(25),
        x0(17) => xp(25),
        x0(16) => xp(25),
        x0(15) => xp(25),
        x0(14) => xp(25),
        x0(13 DOWNTO 0) => xp(25 DOWNTO 12),

        x1(25) => xm(25), -- - xm >> 7 ----------------------------
        x1(24) => xm(25),
        x1(23) => xm(25),
        x1(22) => xm(25),
        x1(21) => xm(25),
        x1(20) => xm(25),
        x1(19) => xm(25),
        x1(18 DOWNTO 0) => xm(25 DOWNTO 7),

        x2(25) => xo(25), -- + xo >> 17 ----------------------------
        x2(24) => xo(25),
        x2(23) => xo(25),
        x2(22) => xo(25),
        x2(21) => xo(25),
        x2(20) => xo(25),
        x2(19) => xo(25),
        x2(18) => xo(25),
        x2(17) => xo(25),
        x2(16) => xo(25),
        x2(15) => xo(25),
        x2(14) => xo(25),
        x2(13) => xo(25),
        x2(12) => xo(25),
        x2(11) => xo(25),
        x2(10) => xo(25),
        x2(9) => xo(25),
        x2(8 DOWNTO 0) => xo(25 DOWNTO 17),

        x3 => zeroes,

        d1 => one,
        d2 => zero,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh4);

    -- CSD multiplier h(6) = 0.00571442 = xp( -1/2^13 ) + xm( +1/2^7 ) + xo( +1/2^17 )
    h6 : csdm26x4
    PORT MAP(
        x0(25) => xo(25), -- + xo >> 16 ----------------------------
        x0(24) => xo(25),
        x0(23) => xo(25),
        x0(22) => xo(25),
        x0(21) => xo(25),
        x0(20) => xo(25),
        x0(19) => xo(25),
        x0(18) => xo(25),
        x0(17) => xo(25),
        x0(16) => xo(25),
        x0(15) => xo(25),
        x0(14) => xo(25),
        x0(13) => xo(25),
        x0(12) => xo(25),
        x0(11) => xo(25),
        x0(10) => xo(25),
        x0(9 DOWNTO 0) => xo(25 DOWNTO 16),

        x1(25) => xm(25), -- + xm >> 6 ----------------------------
        x1(24) => xm(25),
        x1(23) => xm(25),
        x1(22) => xm(25),
        x1(21) => xm(25),
        x1(20) => xm(25),
        x1(19 DOWNTO 0) => xm(25 DOWNTO 6),

        x2(25) => xp(25), -- - xp >> 12 ----------------------------
        x2(24) => xp(25),
        x2(23) => xp(25),
        x2(22) => xp(25),
        x2(21) => xp(25),
        x2(20) => xp(25),
        x2(19) => xp(25),
        x2(18) => xp(25),
        x2(17) => xp(25),
        x2(16) => xp(25),
        x2(15) => xp(25),
        x2(14) => xp(25),
        x2(13 DOWNTO 0) => xp(25 DOWNTO 12),

        x3 => zeroes,

        d1 => zero,
        d2 => one,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh6);

    -- CSD multiplier h(8)=-0.0106049 = xm( -1/2^6 ) + xo( +1/2^10) + xo( +1/2^13) + xo( +1/2^16)
    h8 : csdm26x4
    PORT MAP(
        x0(25) => xo(25), -- + xo >> 9 ----------------------------
        x0(24) => xo(25),
        x0(23) => xo(25),
        x0(22) => xo(25),
        x0(21) => xo(25),
        x0(20) => xo(25),
        x0(19) => xo(25),
        x0(18) => xo(25),
        x0(17) => xo(25),
        x0(16 DOWNTO 0) => xo(25 DOWNTO 9),

        x1(25) => xo(25), -- + xo >> 12 ---------------------------
        x1(24) => xo(25),
        x1(23) => xo(25),
        x1(22) => xo(25),
        x1(21) => xo(25),
        x1(20) => xo(25),
        x1(19) => xo(25),
        x1(18) => xo(25),
        x1(17) => xo(25),
        x1(16) => xo(25),
        x1(15) => xo(25),
        x1(14) => xo(25),
        x1(13 DOWNTO 0) => xo(25 DOWNTO 12),

        x2(25) => xo(25), -- + xo >> 15 ----------------------------
        x2(24) => xo(25),
        x2(23) => xo(25),
        x2(22) => xo(25),
        x2(21) => xo(25),
        x2(20) => xo(25),
        x2(19) => xo(25),
        x2(18) => xo(25),
        x2(17) => xo(25),
        x2(16) => xo(25),
        x2(15) => xo(25),
        x2(14) => xo(25),
        x2(13) => xo(25),
        x2(12) => xo(25),
        x2(11) => xo(25),
        x2(10 DOWNTO 0) => xo(25 DOWNTO 15),

        x3(25) => xm(25), -- - xm >> 5 ----------------------------
        x3(24) => xm(25),
        x3(23) => xm(25),
        x3(22) => xm(25),
        x3(21) => xm(25),
        x3(20 DOWNTO 0) => xm(25 DOWNTO 5),

        d1 => zero,
        d2 => zero,
        d3 => one,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh8);

    -- CSD multiplier h(10) = 0.0183945 = xp( +1/2^6) + xp( -1/2^13 ) + xo( -1/2^10) +xo( -1/2^17 )
    h10 : csdm26x4
    PORT MAP(
        x0(25) => xp(25), -- + xp >> 5 ----------------------------
        x0(24) => xp(25),
        x0(23) => xp(25),
        x0(22) => xp(25),
        x0(21) => xp(25),
        x0(20 DOWNTO 0) => xp(25 DOWNTO 5),

        x1(25) => xp(25), -- - xp >> 12 ---------------------------
        x1(24) => xp(25),
        x1(23) => xp(25),
        x1(22) => xp(25),
        x1(21) => xp(25),
        x1(20) => xp(25),
        x1(19) => xp(25),
        x1(18) => xp(25),
        x1(17) => xp(25),
        x1(16) => xp(25),
        x1(15) => xp(25),
        x1(14) => xp(25),
        x1(13 DOWNTO 0) => xp(25 DOWNTO 12),

        x2(25) => xo(25), -- - xo >> 9 ----------------------------
        x2(24) => xo(25),
        x2(23) => xo(25),
        x2(22) => xo(25),
        x2(21) => xo(25),
        x2(20) => xo(25),
        x2(19) => xo(25),
        x2(18) => xo(25),
        x2(17) => xo(25),
        x2(16 DOWNTO 0) => xo(25 DOWNTO 9),

        x3(25) => xo(25), -- - xo >> 16 ----------------------------
        x3(24) => xo(25),
        x3(23) => xo(25),
        x3(22) => xo(25),
        x3(21) => xo(25),
        x3(20) => xo(25),
        x3(19) => xo(25),
        x3(18) => xo(25),
        x3(17) => xo(25),
        x3(16) => xo(25),
        x3(15) => xo(25),
        x3(14) => xo(25),
        x3(13) => xo(25),
        x3(12) => xo(25),
        x3(11) => xo(25),
        x3(10) => xo(25),
        x3(9 DOWNTO 0) => xo(25 DOWNTO 16),

        d1 => one,
        d2 => one,
        d3 => one,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh10);

    -- CSD multiplier h(12)=-0.0308647 = xp( +1/2^16 ) + xm( +1/2^11 ) + xo( -1/2^5 )
    h12 : csdm26x4
    PORT MAP(
        x0(25) => xp(25), -- + xp >> 15----------------------------
        x0(24) => xp(25),
        x0(23) => xp(25),
        x0(22) => xp(25),
        x0(21) => xp(25),
        x0(20) => xp(25),
        x0(19) => xp(25),
        x0(18) => xp(25),
        x0(17) => xp(25),
        x0(16) => xp(25),
        x0(15) => xp(25),
        x0(14) => xp(25),
        x0(13) => xp(25),
        x0(12) => xp(25),
        x0(11) => xp(25),
        x0(10 DOWNTO 0) => xp(25 DOWNTO 15),

        x1(25) => xo(25), -- - xo >> 4 ---------------------------
        x1(24) => xo(25),
        x1(23) => xo(25),
        x1(22) => xo(25),
        x1(21 DOWNTO 0) => xo(25 DOWNTO 4),

        x2(25) => xm(25), -- + xm >> 10 ----------------------------
        x2(24) => xm(25),
        x2(23) => xm(25),
        x2(22) => xm(25),
        x2(21) => xm(25),
        x2(20) => xm(25),
        x2(19) => xm(25),
        x2(18) => xm(25),
        x2(17) => xm(25),
        x2(16) => xm(25),
        x2(15 DOWNTO 0) => xm(25 DOWNTO 10),

        x3 => zeroes,

        d1 => one,
        d2 => zero,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh12);

    -- CSD multiplier h(14) =  0.0523987 = xp( -1/2^7 ) + xm( -1/2^11 ) + xo( +1/2^4) + xo(+1/2^15 )
    h14 : csdm26x4
    PORT MAP(
        x0(25) => xo(25), -- + xo >> 3 ----------------------------
        x0(24) => xo(25),
        x0(23) => xo(25),
        x0(22 DOWNTO 0) => xo(25 DOWNTO 3),

        x1(25) => xp(25), -- - xp >> 6 ---------------------------
        x1(24) => xp(25),
        x1(23) => xp(25),
        x1(22) => xp(25),
        x1(21) => xp(25),
        x1(20) => xp(25),
        x1(19 DOWNTO 0) => xp(25 DOWNTO 6),

        x2(25) => xm(25), -- - xm >> 10 ----------------------------
        x2(24) => xm(25),
        x2(23) => xm(25),
        x2(22) => xm(25),
        x2(21) => xm(25),
        x2(20) => xm(25),
        x2(19) => xm(25),
        x2(18) => xm(25),
        x2(17) => xm(25),
        x2(16) => xm(25),
        x2(15 DOWNTO 0) => xm(25 DOWNTO 10),

        x3(25) => xo(25), -- + xo >> 14 ----------------------------
        x3(24) => xo(25),
        x3(23) => xo(25),
        x3(22) => xo(25),
        x3(21) => xo(25),
        x3(20) => xo(25),
        x3(19) => xo(25),
        x3(18) => xo(25),
        x3(17) => xo(25),
        x3(16) => xo(25),
        x3(15) => xo(25),
        x3(14) => xo(25),
        x3(13) => xo(25),
        x3(12) => xo(25),
        x3(11 DOWNTO 0) => xo(25 DOWNTO 14),

        d1 => one,
        d2 => one,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh14);

    -- CSD multiplier h(16) =-0.098999 = xp( +1/2^11 ) + xm( -1/2^3) +xm( -1/2^7 )
    h16 : csdm26x4
    PORT MAP(
        x0 => zeroes, --   ----------------------------

        x1(25) => xm(25), -- - xm >> 6 ---------------------------
        x1(24) => xm(25),
        x1(23) => xm(25),
        x1(22) => xm(25),
        x1(21) => xm(25),
        x1(20) => xm(25),
        x1(19 DOWNTO 0) => xm(25 DOWNTO 6),

        x2(25) => xp(25), -- + xp >> 10 ----------------------------
        x2(24) => xp(25),
        x2(23) => xp(25),
        x2(22) => xp(25),
        x2(21) => xp(25),
        x2(20) => xp(25),
        x2(19) => xp(25),
        x2(18) => xp(25),
        x2(17) => xp(25),
        x2(16) => xp(25),
        x2(15 DOWNTO 0) => xp(25 DOWNTO 10),

        x3(25) => xm(25), -- - xm >> 2 ----------------------------
        x3(24) => xm(25),
        x3(23 DOWNTO 0) => xm(25 DOWNTO 2),

        d1 => one,
        d2 => zero,
        d3 => one,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh16);

    -- CSD multiplier h(18)= 0.315872 = xp( +1/2^2 ) + xm( -1/2^14 ) + xo( +1/2^8) + xo( -1/2^11 )
    h18 : csdm26x4
    PORT MAP(
        x0(25) => xp(25), --   + xp >> 1 -----------------------
        x0(24 DOWNTO 0) => xp(25 DOWNTO 1),

        x1(25) => xm(25), -- - xm >> 13 ---------------------------
        x1(24) => xm(25),
        x1(23) => xm(25),
        x1(22) => xm(25),
        x1(21) => xm(25),
        x1(20) => xm(25),
        x1(19) => xm(25),
        x1(18) => xm(25),
        x1(17) => xm(25),
        x1(16) => xm(25),
        x1(15) => xm(25),
        x1(14) => xm(25),
        x1(13) => xm(25),
        x1(12 DOWNTO 0) => xm(25 DOWNTO 13),

        x2(25) => xo(25), -- - xo >> 10 ----------------------------
        x2(24) => xo(25),
        x2(23) => xo(25),
        x2(22) => xo(25),
        x2(21) => xo(25),
        x2(20) => xo(25),
        x2(19) => xo(25),
        x2(18) => xo(25),
        x2(17) => xo(25),
        x2(16) => xo(25),
        x2(15 DOWNTO 0) => xo(25 DOWNTO 10),

        x3(25) => xo(25), -- + xo >> 7 ----------------------------
        x3(24) => xo(25),
        x3(23) => xo(25),
        x3(22) => xo(25),
        x3(21) => xo(25),
        x3(20) => xo(25),
        x3(19) => xo(25),
        x3(18 DOWNTO 0) => xo(25 DOWNTO 7),

        d1 => one,
        d2 => one,
        d3 => zero,
        clk => clk,
        en => en,
        reset => reset,
        sout => xh18);

    -- Tap adder 0
    tadder0 : ta26
    PORT MAP(
        a => xh0, b => b0, sign => zero, clk => clk,
        en => en, reset => reset, s => s0);

    -- Tap adder 2
    tadder2 : ta26
    PORT MAP(
        a => xh2, b => b2, sign => zero, clk => clk,
        en => en, reset => reset, s => s2);

    -- Tap adder 4
    tadder4 : ta26
    PORT MAP(
        a => xh4, b => b4, sign => zero, clk => clk,
        en => en, reset => reset, s => s4);

    -- Tap adder 6
    tadder6 : ta26
    PORT MAP(
        a => xh6, b => b6, sign => zero, clk => clk,
        en => en, reset => reset, s => s6);

    -- Tap adder 8
    tadder8 : ta26
    PORT MAP(
        a => xh8, b => b8, sign => zero, clk => clk,
        en => en, reset => reset, s => s8);

    -- Tap adder 10
    tadder10 : ta26
    PORT MAP(
        a => xh10, b => b10, sign => zero, clk => clk,
        en => en, reset => reset, s => s10);

    -- Tap adder 12
    tadder12 : ta26
    PORT MAP(
        a => xh12, b => b12, sign => zero, clk => clk,
        en => en, reset => reset, s => s12);

    -- Tap adder 14
    tadder14 : ta26
    PORT MAP(
        a => xh14, b => b14, sign => zero, clk => clk,
        en => en, reset => reset, s => s14);

    -- Tap adder 16
    tadder16 : ta26
    PORT MAP(
        a => xh16, b => b16, sign => zero, clk => clk,
        en => en, reset => reset, s => s16);

    -- Tap adder 18
    tadder18 : ta26
    PORT MAP(
        a => xh18, b => b18, sign => zero, clk => clk,
        en => en, reset => reset, s => s18);

    -- Tap adder 20
    tadder20 : ta26
    PORT MAP(
        a => xh18, b => b20, sign => zero, clk => clk,
        en => en, reset => reset, s => s20);

    -- Tap adder 22
    tadder22 : ta26
    PORT MAP(
        a => xh16, b => b22, sign => zero, clk => clk,
        en => en, reset => reset, s => s22);

    -- Tap adder 24
    tadder24 : ta26
    PORT MAP(
        a => xh14, b => b24, sign => zero, clk => clk,
        en => en, reset => reset, s => s24);

    -- Tap adder 26
    tadder26 : ta26
    PORT MAP(
        a => xh12, b => b26, sign => zero, clk => clk,
        en => en, reset => reset, s => s26);

    -- Tap adder 28
    tadder28 : ta26
    PORT MAP(
        a => xh10, b => b28, sign => zero, clk => clk,
        en => en, reset => reset, s => s28);

    -- Tap adder 30
    tadder30 : ta26
    PORT MAP(
        a => xh8, b => b30, sign => zero, clk => clk,
        en => en, reset => reset, s => s30);

    -- Tap adder 32
    tadder32 : ta26
    PORT MAP(
        a => xh6, b => b32, sign => zero, clk => clk,
        en => en, reset => reset, s => s32);

    -- Tap adder 34
    tadder34 : ta26
    PORT MAP(
        a => xh4, b => b34, sign => zero, clk => clk,
        en => en, reset => reset, s => s34);

    -- Tap adder 36
    tadder36 : ta26
    PORT MAP(
        a => xh2, b => b36, sign => zero, clk => clk,
        en => en, reset => reset, s => s36);

    -- Tap termination cell
    terminator : tt PORT MAP(x => s0, clk => clk, en => en, reset => reset, y => y);

END hb1e_arch;