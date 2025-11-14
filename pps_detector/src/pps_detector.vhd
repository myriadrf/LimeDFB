-- ----------------------------------------------------------------------------	
-- FILE        :	pps_detector.vhd
-- DESCRIPTION :	Detects if pps is active during specified timeout period
-- DATE        :	Aug 20, 2001
-- AUTHOR(s)   :	Lime Microsystems
-- REVISIONS   :
-- ----------------------------------------------------------------------------	
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pps_detector is
    Generic (
        CLK_FREQ_HZ : integer := 6_000_000; -- Nominal system clock frequency
        TOLERANCE   : integer := 3_000_000   -- Allow ±50% tolerance (adjust as needed)
    );
    Port (
        clk        : in  std_logic; -- System clock
        reset      : in  std_logic; -- Reset signal
        pps        : in  std_logic; -- 1PPS input signal
        pps_active : out std_logic  -- Indicates if PPS is active
    );
end pps_detector;

architecture Behavioral of pps_detector is
    constant c_TIMEOUT_MAX : integer := CLK_FREQ_HZ + TOLERANCE; -- Upper bound


    signal pps_detected : std_logic := '0';
    signal pps_reg      : std_logic;
    signal timeout_cnt  : unsigned(23 downto 0);

begin


    -- Register incoming pps signal
    process(clk) 
    begin 
        if rising_edge(clk) then 
            pps_reg <= pps;
        end if;
    end process;


    -- Reset timeout counter on every risign edge of pps or when it reaches timeout
    process(clk) 
    begin 
        if rising_edge(clk) then 
            if (pps = '1' AND pps_reg = '0') OR timeout_cnt = c_TIMEOUT_MAX then 
                timeout_cnt <=(others=>'0');
            else 
                timeout_cnt <= timeout_cnt + 1;
            end if;
        end if;
    end process;


    -- pps is detected on rising edge of pps and gets reset only if counter reaches timeout
    process(clk, reset) 
    begin 
        if reset='1' then 
            pps_detected <= '0';
        elsif rising_edge(clk) then 
            if pps = '1' AND pps_reg = '0' then 
                pps_detected <= '1';
            elsif timeout_cnt = c_TIMEOUT_MAX then 
                pps_detected <= '0';
            else 
                pps_detected <= pps_detected;
            end if;
        end if;
    end process;


    pps_active <= pps_detected;
    
end Behavioral;