-- ----------------------------------------------------------------------------	
-- FILE:	clkdiv.vhd
-- DESCRIPTION:	Programmable clock divider. Division can be in the range 1-256.
-- DATE:	Sep 05, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- REVISIONS:	March 01, 2001:	Clich in 'en' signal eliminated.
-- ----------------------------------------------------------------------------	

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity clkdiv is
    port (
	n: in std_logic_vector(7 downto 0);	-- Clock division ratio is n+1
	sleep: in std_logic;			-- Sleep signal
	clk: in std_logic;			-- Clock and reset
	reset: in std_logic;
	en: out std_logic			-- Output enable signal
    );
end clkdiv;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture clkdiv_arch of clkdiv is
    -- 8-bit counter; counts 0..n and generates a one-cycle strobe on match
    signal cnt : unsigned(7 downto 0) := (others => '0');
begin
    -- Single clocked process with active-low asynchronous reset.
    process(clk, reset)
    begin
        if reset = '0' then
            cnt <= (others => '0');
            en  <= '0';
        elsif rising_edge(clk) then
            if sleep = '0' then
                if cnt = unsigned(n) then
                    -- Reached division ratio (n); pulse en and wrap to 0
                    cnt <= (others => '0');
                    en  <= '1';
                else
                    -- Increment towards match
                    cnt <= cnt + 1;
                    en  <= '0';
                end if;
            else
                -- Sleep: hold counter and keep enable low
                en <= '0';
            end if;
        end if;
    end process;
end clkdiv_arch;
