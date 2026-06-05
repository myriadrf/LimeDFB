-- ----------------------------------------------------------------------------	
-- FILE: 	nr_fehf.vhd
-- DESCRIPTION:	Filtering engine of the phase equaliser.
-- DATE:	
-- AUTHOR(s):	
-- REVISIONS:
-- ----------------------------------------------------------------------------	
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.ALL;
USE ieee.numeric_std.ALL;
USE work.nr_mem_package.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ------------------------------------ ---------------------------------------
ENTITY nr_fehf IS
    PORT (
        x : IN STD_LOGIC_VECTOR(17 DOWNTO 0); -- Input signal
        -- Filter configuration
        h : marray16x16;
        -- Clock related inputs
        clk, reset, sleep : IN STD_LOGIC;
        odd, half : IN STD_LOGIC;
        y : OUT STD_LOGIC_VECTOR(17 DOWNTO 0) -- Filter output    
    );
END nr_fehf;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE nr_fehf_arch OF nr_fehf IS

    COMPONENT adder IS
        GENERIC (
            res_n : NATURAL := 18; 
            op_n : NATURAL := 18; 
            addi : NATURAL := 1);
        PORT (
            dataa : IN STD_LOGIC_VECTOR (op_n - 1 DOWNTO 0);
            datab : IN STD_LOGIC_VECTOR (op_n - 1 DOWNTO 0);
            res : OUT STD_LOGIC_VECTOR (res_n - 1 DOWNTO 0)
        );
    END COMPONENT adder;

    TYPE marray16x18 IS ARRAY (15 DOWNTO 0) OF STD_LOGIC_VECTOR(17 DOWNTO 0);
    SIGNAL hprim, xprim : marray16x18;
    TYPE marray32x18 IS ARRAY (31 DOWNTO 0) OF STD_LOGIC_VECTOR(17 DOWNTO 0);
    SIGNAL mem : marray32x18;
    TYPE marray16x19 IS ARRAY (15 DOWNTO 0) OF STD_LOGIC_VECTOR(18 DOWNTO 0);
    SIGNAL mem1 : marray16x19;
    TYPE marray IS ARRAY (15 DOWNTO 0) OF SIGNED(35 DOWNTO 0);
    SIGNAL res : marray;
    TYPE marray16x20 IS ARRAY (15 DOWNTO 0) OF STD_LOGIC_VECTOR(19 DOWNTO 0);
    SIGNAL res1 : marray16x20;
    TYPE marray8x20 IS ARRAY (7 DOWNTO 0) OF STD_LOGIC_VECTOR(19 DOWNTO 0);
    SIGNAL res2 : marray8x20;
    TYPE marray4x20 IS ARRAY (3 DOWNTO 0) OF STD_LOGIC_VECTOR(19 DOWNTO 0);
    SIGNAL res3 : marray4x20;
    TYPE marray2x20 IS ARRAY (3 DOWNTO 0) OF STD_LOGIC_VECTOR(19 DOWNTO 0);
    SIGNAL res4 : marray2x20;
    SIGNAL res5 : STD_LOGIC_VECTOR(19 DOWNTO 0);
    SIGNAL en : STD_LOGIC;

BEGIN

    en <= NOT sleep;
    -- Reset and shift
    shift : PROCESS (clk)
    BEGIN
        IF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                FOR i IN 31 DOWNTO 1 LOOP
                    mem(i) <= mem(i - 1);
                END LOOP;
                IF (odd = '1') THEN
                    mem(16) <= mem(14); -- skip no.15
                    mem(15) <= (OTHERS => '0');
                END IF;
                mem(0) <= x;
            END IF;
        END IF;
    END PROCESS shift;

    l0 : FOR i IN 0 TO 15 GENERATE

        l1 : adder GENERIC MAP(res_n => 19, op_n => 18, addi => 1)
        PORT MAP(dataa => mem(i), datab => mem(31 - i), res => mem1(i));

        hprim(i) <= h(i) & "00"; -- 18 bit

        l_new : PROCESS (clk)
        BEGIN
            IF clk'event AND clk = '1' THEN
                IF en = '1' THEN
                    IF half = '0' THEN
                        xprim(i) <= mem1(i)(18 DOWNTO 1);  -- 18 bit
                    ELSE
                        xprim(i) <= mem(i)(17) & mem(i)(17 DOWNTO 1); -- half='1'
                    END IF;
                END IF;
            END IF;
        END PROCESS;

        PROCESS (clk)
        BEGIN
            IF rising_edge(clk) THEN
                IF en = '1' THEN
                    res(i) <= signed(xprim(i)) * signed(hprim(i));
                    res1(i) <= STD_LOGIC_VECTOR(res(i)(34 DOWNTO 15)); -- 20 bit
                END IF;
            END IF;
        END PROCESS;
    END GENERATE;

    l4 : FOR i IN 0 TO 7 GENERATE
        l5 : PROCESS (clk)
        BEGIN
            IF clk'event AND clk = '1' THEN
                IF en = '1' THEN
                    res2(i) <= res1(i) + res1(15 - i);
                END IF;
            END IF;
        END PROCESS;
    END GENERATE;

    l6 : FOR i IN 0 TO 3 GENERATE
        l7 : PROCESS (clk)
        BEGIN
            IF clk'event AND clk = '1' THEN
                IF en = '1' THEN
                    res3(i) <= res2(i) + res2(7 - i);
                END IF;
            END IF;
        END PROCESS;
    END GENERATE;
    
    

    l8 : FOR i IN 0 TO 1 GENERATE
        l9 : PROCESS (clk)
        BEGIN
            IF clk'event AND clk = '1' THEN
                IF en = '1' THEN
                    res4(i) <= res3(i) + res3(3 - i);
                END IF;
            END IF;
        END PROCESS;
    END GENERATE;

    l10 : PROCESS (clk)
    BEGIN
        IF clk'event AND clk = '1' THEN
            IF en = '1' THEN
                res5 <= res4(0) + res4(1);
            END IF;
        END IF;
    END PROCESS;
       
    y <= res5(18 DOWNTO 1); -- to 18 bit

END ARCHITECTURE nr_fehf_arch;