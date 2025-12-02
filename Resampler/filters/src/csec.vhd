-- ----------------------------------------------------------------------------	
-- FILE:	csec.vhd
-- DESCRIPTION:	Common sub-expressions calculation block.
-- DATE:	July 24, 2001
-- AUTHOR(s):	Microelectronic Centre Design Team
--		MUMEC
--		Bounds Green Road
--		N11 2NQ London
-- REVISIONS:	July 27:	Datapath width changed to 26.
--				Input inverted and latched not to produce
--				short gleches at the filter start up.
-- ----------------------------------------------------------------------------	

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ------------------------------------ ---------------------------------------
entity csec is
    port (
	x: in std_logic_vector(24 downto 0);
	clk: in std_logic;			-- Clock and reset
	en: in std_logic;			-- Enable
	reset: in std_logic;
	xp: out std_logic_vector(25 downto 0); 	-- x*(1+1/4)
	xo: out std_logic_vector(25 downto 0);	-- just delayed x
	xm: out std_logic_vector(25 downto 0)	-- x*(1-1/4)
    );
end csec;

-- ----------------------------------------------------------------------------
-- Architecture of csec
-- ----------------------------------------------------------------------------
architecture csec_arch of csec is
    -- Use signed arithmetic for clarity and inference
    -- Internal 26-bit signed pipeline of the input (sign-extended)
    signal x_s1, x_s2, x_s3 : signed(25 downto 0);
    -- Combinational helpers
    signal x_shift2  : signed(25 downto 0);
    signal xp_next   : signed(25 downto 0);
    signal xm_next   : signed(25 downto 0);

begin
    -- Arithmetic: shift_right on signed performs arithmetic shift (sign-preserving)
    x_shift2 <= shift_right(x_s3, 2);
    xp_next  <= x_s3 + x_shift2; -- x*(1 + 1/4)
    xm_next  <= x_s3 - x_shift2; -- x*(1 - 1/4)

    -- Single process for pipelining and registered outputs
    process(clk, reset)
        variable x_ext : signed(25 downto 0);
    begin
        if reset = '0' then
            x_s1 <= (others => '0');
            x_s2 <= (others => '0');
            x_s3 <= (others => '0');
            xo   <= (others => '0');
            xp   <= (others => '0');
            xm   <= (others => '0');
        elsif clk'event and clk = '1' then
            if en = '1' then
                -- Stage 0: capture sign-extended input (26 bits)
                x_ext := signed(x(24) & x);
                -- Advance pipeline (3 stages total to match original latency)
                x_s1 <= x_ext;
                x_s2 <= x_s1;
                x_s3 <= x_s2;

                -- Registered outputs (same cycle as stage 3)
                xo <= std_logic_vector(x_s3);
                xp <= std_logic_vector(xp_next);
                xm <= std_logic_vector(xm_next);
            end if;
        end if;
    end process;


end csec_arch;
