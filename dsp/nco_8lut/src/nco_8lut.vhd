-- ----------------------------------------------------------------------------	
-- FILE:	nco_8lut.vhd
-- DESCRIPTION:	NCO, implemented using 8 values LUT
-- DATE:	24 Jan 2014
-- AUTHOR(s):	Lime Microsystems
-- REVISIONS:	
-- ----------------------------------------------------------------------------	

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity nco_8lut is
	generic(
		g_ASIC_IMPL : boolean := False
	);
	port (
		clk: in std_logic; -- Clock
		nrst: in std_logic; -- Reset
		en: in std_logic; -- enable signal
		swapiq: in std_logic; -- Swap I and Q channels
		mode: in std_logic; -- NCO mode: 0 when NCO, 1 when DC
		newnco: in std_logic; -- Produce new NCO value
		ldi, ldq: in std_logic; -- Load output registers when rising edge with di and dq
		diq: in std_logic_vector(15 downto 0); -- Data to be loaded to output registers
		fcw: in std_logic_vector(1 downto 0); -- Frequency control word
		fullscaleo: in std_logic;							-- Set to 1 if want full scale output. Set to 0 for -6dB (default).
		yi: out std_logic_vector(15 downto 0); -- Cosine ouput
		yq: out std_logic_vector(15 downto 0) -- Sine ouput
	);
end nco_8lut;

-- ----------------------------------------------------------------------------
-- Architecture of nco
-- ----------------------------------------------------------------------------
architecture nco_8lut_arch of nco_8lut is

	signal phs, phr: std_logic_vector(2 downto 0);	-- Phase accumulator related
	signal lutS, lutC: std_logic_vector(15 downto 0);	-- sine & cosine LUTs
	signal lutSi, lutCi, lutSfc, lutCfc: std_logic_vector(15 downto 0);	-- Internal sine & cosine from LUTs
	signal syncLdI, syncLdQ: std_logic_vector(2 downto 0);	-- Load synchronizers
	signal sum: std_logic_vector(3 downto 0);	-- Adder's output
	

begin
	
	-- sine 8 point LUT
	lutS <= x"0000" when phr = "000" else
					x"5A82" when phr = "001" else
					x"7FFF" when phr = "010" else
					x"5A82" when phr = "011" else
					x"0000" when phr = "100" else
					x"A57E" when phr = "101" else
					x"8001" when phr = "110" else
					x"A57E";
	
	--cosine 8 point LUT
	lutC <= x"7FFF" when phr = "000" else
					x"5A82" when phr = "001" else
					x"0000" when phr = "010" else
					x"A57E" when phr = "011" else
					x"8001" when phr = "100" else
					x"A57E" when phr = "101" else
					x"0000" when phr = "110" else
					x"5A82";
	
	-- I and Q swap implementation
	lutSi <= lutS when swapiq = '0' else lutC;
	lutCi <= lutC when swapiq = '0' else lutS;
	
	-- Full scale/-6dB implementation
	lutSfc <= lutSi when fullscaleo = '1' else lutSi(15) & lutSi(15 downto 1);
	lutCfc <= lutCi when fullscaleo = '1' else lutCi(15) & lutCi(15 downto 1);
					
	-- Load synchronizers
	ildsync: process(clk, nrst)
	begin
		if(nrst = '0') then
			syncLdI <= (others => '0');
			syncLdQ <= (others => '0');
		elsif rising_edge(clk) then
			if en = '1' then
				syncLdI <= syncLdI(1 downto 0) & ldi;
				syncLdQ <= syncLdQ(1 downto 0) & ldq;
			end if;
		end if;
	end process ildsync;


	-- Use 4 bit Binary Carry Look Ahead (BCLA) adder implementation (ASIC implementation)
	ASIC_IMPLEMENTATION : if g_ASIC_IMPL generate		
		-- Phase accumulator
		iphadd: entity work.bcla4b port map(a(3) => '0', a(2 downto 0) => phr, b(3 downto 2) => "00", b(1 downto 0) => fcw, cin => '0', cout => open, s => sum);
	end generate ASIC_IMPLEMENTATION;

	-- Use general sum operator from FPGA synthesis tools (FPGA implementation)
	FPGA_IMPLEMENTATION : if NOT g_ASIC_IMPL generate
		process(all)
		begin 
			sum <= std_logic_vector(resize(unsigned(phr), 4) + resize(unsigned(fcw), 4));
		end process;
	end generate FPGA_IMPLEMENTATION;


	phs <= sum(2 downto 0);


	phreg: process(clk, nrst)
	begin
		if(nrst = '0') then
			phr <= (others => '0');
		elsif rising_edge(clk) then
			if en = '1' and mode = '0' and newnco = '1' then
				phr <= phs;
			end if;
		end if;
	end process phreg;

	-- Registered outputs
	oreg: process(clk, nrst)
	begin
		if(nrst = '0') then
			yq <= x"0000";
			yi <= x"7FFF";
		elsif rising_edge(clk) then
			if en = '1' then
				if mode = '0' then 
					yq <= lutSfc;
					yi <= lutCfc;
				else
					if syncLdI(2) = '0' and syncLdI(1) = '1' then
						yi <= diq;
					end if;
					if syncLdQ(2) = '0' and syncLdQ(1) = '1' then
						yq <= diq;
					end if;
				end if;
			end if;
		end if;
	end process oreg;

end nco_8lut_arch;
