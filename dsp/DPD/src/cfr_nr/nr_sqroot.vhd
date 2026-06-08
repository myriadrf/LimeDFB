LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY nr_sqroot IS
	GENERIC (
		mul_n : NATURAL := 18;
		root : BOOLEAN);
	PORT (
		clk, reset_n, data_valid : IN STD_LOGIC;
		A_in : IN STD_LOGIC_VECTOR(2 * mul_n - 1 DOWNTO 0);
		B_out : OUT STD_LOGIC_VECTOR(mul_n - 1 DOWNTO 0));
END nr_sqroot;

ARCHITECTURE nr_sqroot1 OF nr_sqroot IS

	COMPONENT adder IS
		GENERIC (
			res_n : NATURAL := mul_n;
			op_n : NATURAL := mul_n;
			addi : NATURAL := 1);
		PORT (
			dataa : IN STD_LOGIC_VECTOR (op_n - 1 DOWNTO 0);
			datab : IN STD_LOGIC_VECTOR (op_n - 1 DOWNTO 0);
			res : OUT STD_LOGIC_VECTOR (res_n - 1 DOWNTO 0));
	END COMPONENT adder;

	TYPE marray19x20 IS ARRAY (mul_n DOWNTO 0) OF STD_LOGIC_VECTOR(mul_n + 1 DOWNTO 0);
	SIGNAL ax, bx, cx : marray19x20;

	TYPE marray19x18 IS ARRAY (mul_n DOWNTO 0) OF STD_LOGIC_VECTOR(mul_n - 1 DOWNTO 0);
	SIGNAL B, C : marray19x18;

	TYPE marray19x56 IS ARRAY (mul_n DOWNTO 0) OF STD_LOGIC_VECTOR(3 * mul_n + 1 DOWNTO 0); --39 
	SIGNAL A : marray19x56;
	CONSTANT zero : STD_LOGIC_VECTOR(mul_n + 1 DOWNTO 0) := (OTHERS => '0');

BEGIN

	PROCESS (clk, reset_n) IS
	BEGIN
		IF reset_n = '0' THEN
			B_out <= (OTHERS => '0');
		ELSIF clk'event AND clk = '1' THEN
			IF data_valid = '1' THEN
				IF (root = true) THEN
					B_out <= B(mul_n);
				ELSE
					B_out <= C(mul_n);
				END IF;
			END IF;
		END IF;
	END PROCESS;

	A(0) <= zero & A_in;
	B(0) <= (OTHERS => '0');
	C(0) <= A_in(2 * mul_n - 1 DOWNTO mul_n);

	lab : FOR i IN 1 TO mul_n GENERATE

		ax(i) <= A(i - 1)(3 * mul_n + 1 DOWNTO 2 * mul_n);
		bx(i) <= B(i - 1) & "01";

		Adder1 : adder GENERIC MAP(res_n => mul_n + 2, op_n => mul_n + 2, addi => 0)
		PORT MAP(dataa => ax(i), datab => bx(i), res => cx(i));

		PROCESS (clk) IS
		BEGIN
			IF clk'event AND clk = '1' THEN
				IF data_valid = '1' THEN
					C(i) <= C(i - 1);
					IF cx(i)(mul_n + 1) = '0' THEN
						A(i) <= cx(i)(mul_n - 1 DOWNTO 0) & A(i - 1)(2 * mul_n - 1 DOWNTO 0) & "00";
						B(i) <= B(i - 1)(mul_n - 2 DOWNTO 0) & '1';
					ELSE
						A(i) <= A(i - 1)(3 * mul_n - 1 DOWNTO 0) & "00";
						B(i) <= B(i - 1)(mul_n - 2 DOWNTO 0) & '0';
					END IF;
				END IF;
			END IF;
		END PROCESS;
	END GENERATE;

END nr_sqroot1;