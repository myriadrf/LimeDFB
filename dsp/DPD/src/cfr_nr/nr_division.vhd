LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY nr_division IS
	GENERIC (mul_n : NATURAL := 18);
	PORT (
		clk, reset_n, data_valid : IN STD_LOGIC;
		A_in : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
		B_in : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
		Z_out : OUT STD_LOGIC_VECTOR(17 DOWNTO 0));
END nr_division;

ARCHITECTURE struct OF nr_division IS

	COMPONENT adder IS
		GENERIC (
			res_n : NATURAL := 18; 
			op_n : NATURAL := 18; 
			addi : NATURAL := 1);
		PORT (
			dataa : IN STD_LOGIC_VECTOR (op_n - 1 DOWNTO 0);
			datab : IN STD_LOGIC_VECTOR (op_n - 1 DOWNTO 0);
			res : OUT STD_LOGIC_VECTOR (res_n - 1 DOWNTO 0));
	END COMPONENT adder;

	TYPE marray19x20 IS ARRAY (18 DOWNTO 0) OF STD_LOGIC_VECTOR(19 DOWNTO 0);
	SIGNAL ax, bx, cx : marray19x20;

	TYPE marray19x18 IS ARRAY (18 DOWNTO 0) OF STD_LOGIC_VECTOR(17 DOWNTO 0);
	SIGNAL B, C : marray19x18;

	TYPE marray19x40 IS ARRAY (18 DOWNTO 0) OF STD_LOGIC_VECTOR(39 DOWNTO 0);
	SIGNAL A : marray19x40;

BEGIN
	PROCESS (clk, reset_n) IS
	BEGIN
		IF reset_n = '0' THEN
			Z_out <= (OTHERS => '0');
		ELSIF clk'event AND clk = '1' THEN
			IF data_valid = '1' THEN
				Z_out <= C(18);
			END IF;
		END IF;
	END PROCESS;

	A(0) <= A_in(17) & A_in(17) & A_in(17) & A_in & x"0000" & "000";
	B(0) <= B_in;
	C(0) <= (OTHERS => '0');

	lab : FOR i IN 1 TO 18 GENERATE

		ax(i) <= A(i - 1)(39 DOWNTO 20);
		bx(i) <= B(i - 1)(17) & B(i - 1)(17) & B(i - 1);

		Adder1 : adder GENERIC MAP(res_n => mul_n + 2, op_n => mul_n + 2, addi => 0)
		PORT MAP(dataa => ax(i), datab => bx(i), res => cx(i));

		PROCESS (clk) IS
		BEGIN
			IF clk'event AND clk = '1' THEN
				IF data_valid = '1' THEN
					B(i) <= B(i - 1);
					IF cx(i)(19) = '0' THEN
						A(i) <= cx(i)(18 DOWNTO 0) & A(i - 1)(19 DOWNTO 0) & '0';
						C(i) <= C(i - 1)(16 DOWNTO 0) & '1';
					ELSE
						A(i) <= A(i - 1)(38 DOWNTO 0) & '0';
						C(i) <= C(i - 1)(16 DOWNTO 0) & '0';
					END IF;
				END IF;
			END IF;
		END PROCESS;
	END GENERATE;
END struct;
