-- ----------------------------------------------------------------------------	
-- FILE: 	nr_gfirhf.vhd
-- DESCRIPTION:	Filtering engine of the phase equaliser.
-- DATE:
-- AUTHOR(s):
-- REVISIONS:
-- ----------------------------------------------------------------------------	

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.nr_mem_package.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
ENTITY nr_gfirhf IS
	PORT (
		-- Clock related inputs
		sleep : IN STD_LOGIC; -- Sleep signal
		clk : IN STD_LOGIC; -- Clock
		reset : IN STD_LOGIC; -- Reset
		reset_mem_n : IN STD_LOGIC;

		bypass : IN STD_LOGIC;
		odd, half : IN STD_LOGIC;

		-- Data input signals
		xi : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		xq : IN STD_LOGIC_VECTOR(15 DOWNTO 0);

		-- Coefficient memory interface
		maddressf0 : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
		maddressf1 : IN STD_LOGIC_VECTOR(8 DOWNTO 0);

		mimo_en : IN STD_LOGIC;
		sdin : IN STD_LOGIC; -- Data in
		sclk : IN STD_LOGIC; -- Data clock
		sen : IN STD_LOGIC; -- Enable signal (active low)
		sdout : OUT STD_LOGIC; -- Data out
		oen : OUT STD_LOGIC;

		yi : OUT STD_LOGIC_VECTOR(17 DOWNTO 0);
		yq : OUT STD_LOGIC_VECTOR(17 DOWNTO 0);
		xen : OUT STD_LOGIC
	);
END nr_gfirhf;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE nr_gfirhf_arch OF nr_gfirhf IS

	COMPONENT nr_fehf IS
		PORT (
			--x : IN STD_LOGIC_VECTOR(24 DOWNTO 0); -- Input signal
			x : IN STD_LOGIC_VECTOR(17 DOWNTO 0); -- Input signal
			h : IN marray16x16;
			clk, reset, sleep : IN STD_LOGIC;
			odd, half : IN STD_LOGIC;
			--y : OUT STD_LOGIC_VECTOR(24 DOWNTO 0) -- Filter output 
			y : OUT STD_LOGIC_VECTOR(17 DOWNTO 0) -- Filter output       
		);
	END COMPONENT nr_fehf;

	COMPONENT nr_fircms IS
		PORT (
			maddress : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
			mimo_en : IN STD_LOGIC;
			sdin : IN STD_LOGIC; -- Data in
			sclk : IN STD_LOGIC; -- Data clock
			sen : IN STD_LOGIC; -- Enable signal (active low)
			sdout : OUT STD_LOGIC; -- Data out
			hreset : IN STD_LOGIC; -- Hard reset signal, resets everything		
			oen : OUT STD_LOGIC;
			di : OUT marray16x16
		);
	END COMPONENT nr_fircms;

	SIGNAL ce0h, ce1h : marray16x16;-- Coefficients
	SIGNAL xii, xqi, yii, yim, yqi, yqm : STD_LOGIC_VECTOR(17 DOWNTO 0);
	SIGNAL sdout0, oen0, sdout1, oen1 : STD_LOGIC;

BEGIN

	xen <= '1';
	xii <= xi & "00"; --18 bit
	xqi <= xq & "00";

	-- Configuration engines
	ce0 : nr_fircms PORT MAP(
		maddress => maddressf0,
		mimo_en => mimo_en,
		sdin => sdin,
		sclk => sclk,
		sen => sen,
		sdout => sdout0,
		hreset => reset_mem_n,
		oen => oen0,
		di => ce0h
	);

	ce1 : nr_fircms PORT MAP(
		maddress => maddressf1,
		mimo_en => mimo_en,
		sdin => sdin,
		sclk => sclk,
		sen => sen,
		sdout => sdout1,
		hreset => reset_mem_n,
		oen => oen1,
		di => ce1h
	);

	sdout <= (sdout0 AND oen0) OR (sdout1 AND oen1);
	oen <= oen0 OR oen1;

	fei0 : nr_fehf PORT MAP(
		x => xii, h => ce0h,
		clk => clk, reset => reset, sleep => sleep,
		odd => odd, half => '0',
		y => yii
	);

	feq0 : nr_fehf PORT MAP(
		x => xqi, h => ce1h,
		clk => clk, reset => reset, sleep => sleep,
		odd => odd, half => half,
		y => yqi
	);

	-- Bypass MUX'es and registers
	yim <= xii WHEN bypass = '1' ELSE
		yii;
	yqm <= xqi WHEN bypass = '1' ELSE
		yqi;

	dl : PROCESS (clk, reset)
	BEGIN
		IF reset = '0' THEN
			yi <= (OTHERS => '0');
			yq <= (OTHERS => '0');
		ELSIF clk'event AND clk = '1' THEN
			--IF sleep = '0' THEN
			yi <= yim;
			yq <= yqm;
			--END IF;
		END IF;
	END PROCESS dl;
END nr_gfirhf_arch;