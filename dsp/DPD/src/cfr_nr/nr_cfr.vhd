LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.ALL;
USE IEEE.math_real.ALL;
USE ieee.std_logic_arith.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ------------------------------------ ---------------------------------------
ENTITY nr_cfr IS
	GENERIC (nd : NATURAL := 40);
	PORT (
		-- Clock related inputs
		sleep : IN STD_LOGIC; -- Sleep signal
		clk : IN STD_LOGIC; -- Clock
		reset : IN STD_LOGIC; -- Reset
		reset_mem_n : IN STD_LOGIC;
		bypass : IN STD_LOGIC; --  Bypass
		odd : IN STD_LOGIC;

		-- Data input signals
		xi : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		xq : IN STD_LOGIC_VECTOR(15 DOWNTO 0);

		-- Filter configuration
		threshold : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		-- Coefficient memory interface
		maddressf0 : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
		maddressf1 : IN STD_LOGIC_VECTOR(8 DOWNTO 0);

		mimo_en : IN STD_LOGIC;
		sdin : IN STD_LOGIC; -- Data in
		sclk : IN STD_LOGIC; -- Data clock
		sen : IN STD_LOGIC; -- Enable signal (active low)
		sdout : OUT STD_LOGIC; -- Data out
		oen : OUT STD_LOGIC;

		-- Filter output signals
		yi : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		yq : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		xen : OUT STD_LOGIC
	);
END nr_cfr;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE struct OF nr_cfr IS

	COMPONENT nr_gfirhf IS
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

			-- Filter output signals
			--yi : OUT STD_LOGIC_VECTOR(24 DOWNTO 0);
			--yq : OUT STD_LOGIC_VECTOR(24 DOWNTO 0);
			yi : OUT STD_LOGIC_VECTOR(17 DOWNTO 0);
			yq : OUT STD_LOGIC_VECTOR(17 DOWNTO 0);
			xen : OUT STD_LOGIC
		);
	END COMPONENT nr_gfirhf;

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

	COMPONENT nr_sqroot IS
		GENERIC (
			mul_n : NATURAL := 18;
			root : BOOLEAN);
		PORT (
			clk, reset_n, data_valid : IN STD_LOGIC;
			A_in : IN STD_LOGIC_VECTOR(2 * mul_n - 1 DOWNTO 0);
			B_out : OUT STD_LOGIC_VECTOR(mul_n - 1 DOWNTO 0)
		);
	END COMPONENT nr_sqroot;

	COMPONENT nr_division IS
		GENERIC (mul_n : NATURAL := 18);
		PORT (
			clk, reset_n, data_valid : IN STD_LOGIC;
			A_in : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
			B_in : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
			Z_out : OUT STD_LOGIC_VECTOR(17 DOWNTO 0));
	END COMPONENT nr_division;

	SIGNAL xi1, xq1, threshold1, sig7, sig8, e, c, sig9, sig10, f, y, o, b, xq2, xi2, b1 : STD_LOGIC_VECTOR (17 DOWNTO 0);
	--SIGNAL sig3, sig4, sig5, sig6 : STD_LOGIC_VECTOR (35 DOWNTO 0);
	SIGNAL sig1, sig2, sig11, sig12 : SIGNED(35 DOWNTO 0);

	TYPE array1 IS ARRAY (0 TO 20) OF STD_LOGIC;
	SIGNAL sign, sleep1 : array1;

	CONSTANT DELAY: integer := 66;  -- delay of CFR
	
	TYPE array2 IS ARRAY (0 TO DELAY) OF STD_LOGIC_VECTOR(17 DOWNTO 0);
	SIGNAL xi_reg, xq_reg : array2;

	SIGNAL xen1, data_valid : STD_LOGIC;
	--SIGNAL o1, f1 : STD_LOGIC_VECTOR (24 DOWNTO 0);
	SIGNAL o1, f1 : STD_LOGIC_VECTOR (17 DOWNTO 0);

	SIGNAL selsig : STD_LOGIC_VECTOR(7 DOWNTO 0);
	CONSTANT LE : INTEGER := 1;
	TYPE array3 IS ARRAY (0 TO LE) OF STD_LOGIC_VECTOR(17 DOWNTO 0);
	SIGNAL cpom, cpom2 : array3;
	SIGNAL max, min, cprim, cprim2 : STD_LOGIC_VECTOR(17 DOWNTO 0);

	SIGNAL sig13, sig14 : STD_LOGIC_VECTOR(15 DOWNTO 0);
	CONSTANT one : STD_LOGIC_VECTOR(17 DOWNTO 0) := "01" & x"0000";
	CONSTANT zero : STD_LOGIC_VECTOR(17 DOWNTO 0) := (OTHERS => '0');

	SIGNAL sig3a, sig4a, sig5a, sig6a : STD_LOGIC_VECTOR(23 DOWNTO 0); --temp
	SIGNAL ea : STD_LOGIC_VECTOR(11 DOWNTO 0); --temp
	SIGNAL eb : STD_LOGIC_VECTOR(17 DOWNTO 0); --temp
	SIGNAL ovr : STD_LOGIC;
	
	

BEGIN

	threshold1 <= "00" & threshold;
	data_valid <= xen1;
	xen <= xen1;
	PROCESS (clk) IS
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN
				xi1 <= xi(15) & xi & '0';
				xq1 <= xq(15) & xq & '0';
			END IF;
		END IF;
	END PROCESS;

	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF (data_valid = '1') THEN
				sig1 <= signed(xi1) * signed(xi1);
				sig2 <= signed(xq1) * signed(xq1);
				sig3a <= STD_LOGIC_VECTOR(sig1(33 DOWNTO 10));--temp
	            sig4a <= STD_LOGIC_VECTOR(sig2(33 DOWNTO 10));--temp
			END IF;
		END IF;
	END PROCESS;
	--sig3 <= STD_LOGIC_VECTOR(sig1(33 DOWNTO 0)) & "00";
	--sig4 <= STD_LOGIC_VECTOR(sig2(33 DOWNTO 0)) & "00";

	

	--Adder1 : adder GENERIC MAP(res_n => 36, op_n => 36, addi => 1) PORT MAP(dataa => sig3, datab => sig4, res => sig5);
	Adder1a : adder GENERIC MAP(res_n => 24, op_n => 24, addi => 1) PORT MAP(dataa => sig3a, datab => sig4a, res => sig5a);  --temp

	PROCESS (clk) IS
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN
				--sig6 <= sig5;
				sig6a <= sig5a; --temp
			END IF;
		END IF;
	END PROCESS;
	--Sqroot1 : nr_sqroot GENERIC MAP(mul_n => 18, root => true) PORT MAP(clk => clk, reset_n => reset, data_valid => data_valid, A_in => sig6, B_out => e);
	Sqroot1a : nr_sqroot GENERIC MAP(mul_n => 12, root => true) PORT MAP(clk => clk, reset_n => reset, data_valid => data_valid, A_in => sig6a, B_out => ea);--temp
	eb <= ea &"000000";
	--Adder2 : adder GENERIC MAP(res_n => 18, op_n => 18, addi => 0) PORT MAP(dataa => e, datab => threshold1, res => sig7);
	Adder2 : adder GENERIC MAP(res_n => 18, op_n => 18, addi => 0) PORT MAP(dataa => eb, datab => threshold1, res => sig7); --temp
	sign(0) <= sig7(17);

	--Div1 : nr_division GENERIC MAP(mul_n => 18) PORT MAP(clk => clk, reset_n => reset, data_valid => data_valid, A_in => threshold1, B_in => e, Z_out => sig8);
	Div1 : nr_division GENERIC MAP(mul_n => 18) PORT MAP(clk => clk, reset_n => reset, data_valid => data_valid, A_in => threshold1, B_in => eb, Z_out => sig8);  -- temp

	sleep1(0) <= sleep;
	lab0 : FOR i IN 1 TO 19 GENERATE
		PROCESS (clk) IS
		BEGIN
			IF clk'event AND clk = '1' THEN
				IF (data_valid = '1') THEN
					sign(i) <= sign(i - 1);
					sleep1(i) <= sleep1(i - 1);
				END IF;
			END IF;
		END PROCESS;
	END GENERATE;

	c <= sig8 WHEN (sign(19) = '0' AND sleep1(19) = '0') ELSE
		one;

	PROCESS (clk) IS
		VARIABLE pommin : STD_LOGIC_VECTOR(17 DOWNTO 0);
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN

				IF (min = cpom(LE)) THEN
					cprim <= cpom(LE);
				ELSE
					cprim <= one;
				END IF;

				cpom(0) <= c;
				pommin := c;
				FOR i IN 0 TO LE - 1 LOOP
					cpom(i + 1) <= cpom(i);
					IF (pommin > cpom(i)) THEN
						pommin := cpom(i);
					END IF;
				END LOOP;
			END IF;
		END IF;
		min <= pommin;
	END PROCESS;

	PROCESS (clk) IS
		VARIABLE pommax : STD_LOGIC_VECTOR(17 DOWNTO 0);
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN

				IF (max = cpom2(0)) THEN
					cprim2 <= cpom2(0);
				ELSE
					cprim2 <= one;
				END IF;

				cpom2(0) <= cprim;
				pommax := cprim;
				FOR i IN 0 TO LE - 1 LOOP
					cpom2(i + 1) <= cpom2(i);
					IF (pommax > cpom2(i)) THEN
						pommax := cpom2(i);
					END IF;
				END LOOP;
			END IF;
		END IF;
		max <= pommax;
	END PROCESS;

	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF (data_valid = '1') THEN
				sig10 <= one - cprim2 - f;
				IF (sig10(17) = '0') THEN
					y <= sig10;
				ELSE
					y <= zero;
				END IF;
			END IF;
		END IF;
	END PROCESS;
	gfir : nr_gfirhf PORT MAP(
		sleep => sleep,
		clk => clk,
		reset => reset,
		reset_mem_n => reset_mem_n,
		bypass => '0',
		xi => y(17 DOWNTO 2),
		xq => y(17 DOWNTO 2),
		maddressf0 => maddressf0,
		maddressf1 => maddressf1,
		mimo_en => mimo_en,
		sdin => sdin,
		sclk => sclk,
		sen => sen,
		sdout => sdout,
		oen => oen,
		yi => o1,
		yq => f1,
		xen => xen1,
		odd => odd,
		half => '1');

	--o <= o1(23 DOWNTO 6);
	--f <= f1(24 DOWNTO 7);
	o <= o1(16 DOWNTO 0)&'0';
	f <= f1(17 DOWNTO 0);

	Adder5 : adder GENERIC MAP(res_n => 18, op_n => 18, addi => 0) PORT MAP(dataa => one, datab => o, res => b1);

	PROCESS (clk) IS
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN
				b <= b1;
			END IF;
		END IF;
	END PROCESS;

	xi_reg(0) <= xi1;
	xq_reg(0) <= xq1;

	--lab1 : FOR i IN 1 TO 66 GENERATE
	lab1 : FOR i IN 1 TO DELAY GENERATE
		PROCESS (clk) IS
		BEGIN
			IF clk'event AND clk = '1' THEN
				IF (data_valid = '1') THEN
					xi_reg(i) <= xi_reg(i - 1);
					xq_reg(i) <= xq_reg(i - 1);
				END IF;
			END IF;
		END PROCESS;
	END GENERATE;

	--selsig <= "01000010"; --66
	PROCESS (clk) IS
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN
				xi2 <= xi_reg(DELAY);
				xq2 <= xq_reg(DELAY);
			END IF;
		END IF;
	END PROCESS;

	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF (data_valid = '1') THEN
				sig11 <= signed(xi2) * signed(b);
				sig12 <= signed(xq2) * signed(b);
			END IF;
		END IF;
	END PROCESS;
	sig13 <= STD_LOGIC_VECTOR(sig11(32 DOWNTO 17));
	sig14 <= STD_LOGIC_VECTOR(sig12(32 DOWNTO 17));

	PROCESS (clk) IS
	BEGIN
		IF clk'event AND clk = '1' THEN
			IF (data_valid = '1') THEN
				IF bypass = '0' THEN
					yi <= sig13;
					yq <= sig14;
				ELSE
					yi <= xi2(16 DOWNTO 1);
					yq <= xq2(16 DOWNTO 1);
				END IF;
			END IF;
		END IF;
	END PROCESS;

END ARCHITECTURE struct;