-- ----------------------------------------------------------------------------
-- FILE:    csdm26x4.vhd
-- DESCRIPTION: 26-bit, 4-term conditional-signed adder (refactored)
--   Functionally equivalent to legacy csdm26x4; improved readability and
--   encourages arithmetic inference. Slices of sout update over 4 pipeline
--   stages to preserve original timing: [7:0] at stage B, [15:8] at C,
--   [23:16] at D, [25:24] at E. Active-low reset; en is clock enable.
-- ----------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity csdm26x4 is
    port (
        x0   : in  std_logic_vector(25 downto 0);
        x1   : in  std_logic_vector(25 downto 0);
        x2   : in  std_logic_vector(25 downto 0);
        x3   : in  std_logic_vector(25 downto 0);
        d1   : in  std_logic; -- if '1' then x1 is negated (two's complement)
        d2   : in  std_logic; -- if '1' then x2 is negated
        d3   : in  std_logic; -- if '1' then x3 is negated
        clk  : in  std_logic;
        en   : in  std_logic;
        reset: in  std_logic; -- active-low
        sout : out std_logic_vector(25 downto 0)
    );
end csdm26x4;

architecture csdm26x4_arch of csdm26x4 is
    -- Extend to 28 bits during accumulation to avoid overflow; final result is modulo 2^26
    subtype U26 is unsigned(25 downto 0);
    subtype U28 is unsigned(27 downto 0);

    signal x0u, x1u, x2u, x3u : U26;
    signal x1eff, x2eff, x3eff: U26; -- two's complement if corresponding dN='1'

    signal sum_abcd: U28;
    signal sum_01 : U28;
    signal sum_23 : U28;

    -- Pipeline registers carrying the complete 26-bit result to preserve per-slice timing
    signal rA, rB, rC, rD : std_logic_vector(25 downto 0);
    -- Prevent the synthesiser from optimising these registers away
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of rA: signal is "TRUE";
    attribute DONT_TOUCH of rB: signal is "TRUE";
    attribute DONT_TOUCH of rC: signal is "TRUE";
    attribute DONT_TOUCH of rD: signal is "TRUE";
begin
    -- Cast inputs
    x0u <= unsigned(x0);
    x1u <= unsigned(x1);
    x2u <= unsigned(x2);
    x3u <= unsigned(x3);

    -- Conditional two's complement (negation) per original sign bits behavior
    x1eff <= x1u when d1 = '0' else (not x1u) + 1; -- (~x1)+1
    x2eff <= x2u when d2 = '0' else (not x2u) + 1;
    x3eff <= x3u when d3 = '0' else (not x3u) + 1;

    -- These two additions happen IN PARALLEL
    sum_01 <= U28("00" & x0u)   + U28("00" & x1eff); 
    sum_23 <= U28("00" & x2eff) + U28("00" & x3eff);
    -- This is the final add.
    sum_abcd <= sum_01 + sum_23;

    -- LATCH A: capture full result for staged byte updates (preserves original pipeline depth)
    latcha: process(clk, reset)
    begin
        if reset = '0' then
            rA <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                rA <= std_logic_vector(sum_abcd(25 downto 0));
            end if;
        end if;
    end process latcha;

    -- LATCH B: write lower byte, advance pipeline
    latchb: process(clk, reset)
    begin
        if reset = '0' then
            rB <= (others => '0');
            sout(7 downto 0) <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                rB <= rA;
                sout(7 downto 0) <= rA(7 downto 0);
            end if;
        end if;
    end process latchb;

    -- LATCH C: write next byte, advance pipeline
    latchc: process(clk, reset)
    begin
        if reset = '0' then
            rC <= (others => '0');
            sout(15 downto 8) <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                rC <= rB;
                sout(15 downto 8) <= rB(15 downto 8);
            end if;
        end if;
    end process latchc;

    -- LATCH D: write next byte, advance pipeline
    latchd: process(clk, reset)
    begin
        if reset = '0' then
            rD <= (others => '0');
            sout(23 downto 16) <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                rD <= rC;
                sout(23 downto 16) <= rC(23 downto 16);
            end if;
        end if;
    end process latchd;

    -- LATCH E: write final two bits
    latche: process(clk, reset)
    begin
        if reset = '0' then
            sout(25 downto 24) <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                sout(25 downto 24) <= rD(25 downto 24);
            end if;
        end if;
    end process latche;

end csdm26x4_arch;
