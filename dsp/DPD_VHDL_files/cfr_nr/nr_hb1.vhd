-- ----------------------------------------------------------------------------	
-- FILE: 	hb1.vhd
-- DESCRIPTION:	HB1 implemented as interleaved polyphase filter
--		with programmable clock rate.
-- DATE:	July 26, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- TO DO:	Change enable signal generation circuitry by clkdev module.
-- REVISIONS:	Sep 12, 2001:	Clock division circuitry substituted by
--				clkdiv module.
-- ----------------------------------------------------------------------------	

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
ENTITY nr_hb1 IS
    PORT (
        -- bilo je  (24 downto 0)
        xi1 : IN STD_LOGIC_VECTOR(17 DOWNTO 0); -- I input signal
        xq1 : IN STD_LOGIC_VECTOR(17 DOWNTO 0); -- Q input signal
        n : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- Clock division ratio is n+1
        sleep, delay : IN STD_LOGIC; -- Sleep mode control
        clk : IN STD_LOGIC; -- Clock and reset
        reset, bypass : IN STD_LOGIC;
        xen : OUT STD_LOGIC; -- HBI input enable
        yi1 : OUT STD_LOGIC_VECTOR(17 DOWNTO 0); -- I output signal
        yq1 : OUT STD_LOGIC_VECTOR(17 DOWNTO 0) -- Q output signal
    );
END nr_hb1;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE hb1_arch OF nr_hb1 IS

    SIGNAL xi : STD_LOGIC_VECTOR(24 DOWNTO 0); -- I input signal
    SIGNAL xq : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Q input signal
    SIGNAL yi : STD_LOGIC_VECTOR(24 DOWNTO 0); -- I output signal
    SIGNAL yq : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Q output signal
    SIGNAL x : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Multiplexed xi and xq
    SIGNAL xe : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Even input
    SIGNAL xo : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Odd input
    SIGNAL ye : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Even output
    SIGNAL yo : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Odd output
    SIGNAL yia : STD_LOGIC_VECTOR(24 DOWNTO 0); -- Advanced yi

    -- Enable and MUX select signal
    SIGNAL en, sel : STD_LOGIC;

    COMPONENT nr_hb1e IS
        PORT (
            x : IN STD_LOGIC_VECTOR(24 DOWNTO 0); -- Input signal
            clk : IN STD_LOGIC; -- Clock and reset
            en : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            y : OUT STD_LOGIC_VECTOR(24 DOWNTO 0) -- Output signal
        );
    END COMPONENT nr_hb1e;

    COMPONENT clkdiv IS
        PORT (
            n : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- Clock division ratio is n+1
            sleep : IN STD_LOGIC; -- Sleep signal
            clk : IN STD_LOGIC; -- Clock and reset
            reset : IN STD_LOGIC;
            en : OUT STD_LOGIC -- Output enable signal
        );
    END COMPONENT clkdiv;

    COMPONENT nr_hb1o IS
        PORT (
            x : IN STD_LOGIC_VECTOR(24 DOWNTO 0); -- Input signal
            clk : IN STD_LOGIC; -- Clock and reset
            en : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            y : OUT STD_LOGIC_VECTOR(24 DOWNTO 0) -- Output signal
        );
    END COMPONENT nr_hb1o;

    SIGNAL yqprim, yqsec, yi2, yq2 : STD_LOGIC_VECTOR(17 DOWNTO 0);
BEGIN

    xi <= xi1(17 DOWNTO 0) & "0000000";
    xq <= xq1(17 DOWNTO 0) & "0000000";

    -- Clock division
    clkd : clkdiv PORT MAP(
        n => n, clk => clk, reset => reset,
        sleep => sleep, en => en);

    -- MUX select signal
    dff : PROCESS (clk, reset)
    BEGIN
        IF reset = '0' THEN
            --sel <= '0';
            sel <= '1';
        ELSIF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                sel <= NOT sel;
            END IF;
        END IF;
    END PROCESS dff;

    xen <= sel AND en; -- dodao sam  and en

    -- Multiplex xi and xq
    x <= xi WHEN sel = '1' ELSE
        xq;

    -- Latch La
    la : PROCESS (clk, reset)  --
    BEGIN
        IF reset = '0' THEN
            xe <= (OTHERS => '0');
        ELSIF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                xe <= x;
            END IF;
        END IF;
    END PROCESS la;

    -- Latch Lb
    lb : PROCESS (clk, reset)  --, reset
    BEGIN
        IF reset = '0' THEN
            xo <= (OTHERS => '0');
        ELSIF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                xo <= xe;
            END IF;
        END IF;
    END PROCESS lb;

    -- Even HB1 filter
    even : nr_hb1e
    PORT MAP(x => xe, clk => clk, en => en, reset => reset, y => ye);

    -- Odd HB1 filter
    odd : nr_hb1o
    PORT MAP(x => xo, clk => clk, en => en, reset => reset, y => yo);

    -- Multiplex ye and yo to construct yia and yq
    yia <= ye WHEN sel = '1' ELSE
        yo;
    yq <= ye WHEN sel = '0' ELSE
        yo;

    -- Delay yia one clock cycle to align it with ya

    le : PROCESS (clk, reset)  --, reset
    BEGIN
        IF reset = '0' THEN
            yi <= (OTHERS => '0');
        ELSIF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                yi <= yia;
            END IF;
        END IF;
    END PROCESS le;

    --- Borko
    delayl : PROCESS (clk)
    BEGIN
        IF clk'event AND clk = '1' THEN
            yqprim <= yq(24 DOWNTO 7);
            yqsec <= yqprim;
        END IF;
    END PROCESS delayl;

    -- Delay  both
    latch : PROCESS (clk, reset)
    BEGIN
        IF reset = '0' THEN
            yi2 <= (OTHERS => '0');
            yq2 <= (OTHERS => '0');
        ELSIF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                yi2 <= yi(24 DOWNTO 7);
                IF delay = '0' THEN
                    yq2 <= yq(24 DOWNTO 7);
                ELSE
                    yq2 <= yqsec;
                END IF;

            END IF;
        END IF;
    END PROCESS latch;

    yi1 <= yi2 WHEN bypass = '0' ELSE
        xi1;
    yq1 <= yq2 WHEN bypass = '0' ELSE
        xq1;

END hb1_arch;
