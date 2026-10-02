-----------------------------------------------------------------------------	
-- FILE: 	QADPD.vhd
-- DESCRIPTION:	Quadrature predistorter model
-- DATE:          10:55 AM Friday, December 19, 2018
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_unsigned.all;
  use ieee.math_real.all;
  --USE ieee.std_logic_arith.ALL;
  use ieee.numeric_std.all;

entity QADPD is
  generic (
    n     : NATURAL := 4; -- memory depth
    m     : NATURAL := 3; -- nonlinearity
    mul_n : NATURAL := 18); -- precision
  port (
    clk, sclk   : in  STD_LOGIC;
    reset_n     : in  STD_LOGIC;
    reset_mem_n : in  STD_LOGIC; -- reset coefficients
    xpi         : in  STD_LOGIC_VECTOR(13 downto 0);
    xpq         : in  STD_LOGIC_VECTOR(13 downto 0);
    ypi         : out STD_LOGIC_VECTOR(17 downto 0);
    ypq         : out STD_LOGIC_VECTOR(17 downto 0);
    spi_ctrl    : in  STD_LOGIC_VECTOR(15 downto 0);
    spi_data    : in  STD_LOGIC_VECTOR(15 downto 0)
  );
end entity;

architecture structure of QADPD is
   
  component adder is
    generic (
      res_n : NATURAL := 18;
      op_n  : NATURAL := 18;
      addi  : NATURAL := 1); -- addition addi==1
    port (
      dataa : in  STD_LOGIC_VECTOR(op_n - 1 downto 0);
      datab : in  STD_LOGIC_VECTOR(op_n - 1 downto 0);
      res   : out STD_LOGIC_VECTOR(res_n - 1 downto 0));
  end component;

  ---------------------------------------------------------------------------
  constant extens : STD_LOGIC_VECTOR(mul_n - 18 downto 0) := (others => '0');
  signal XIp, XQp, XIp1, XQp1, XIp2, XQp2, XIp3, XQp3 : STD_LOGIC_VECTOR(mul_n - 1 downto 0);
  signal sig1, sig2                                   : SIGNED(2 * mul_n - 1 downto 0);
  signal sig3, sig4, ep, ep2                          : STD_LOGIC_VECTOR(mul_n - 1 downto 0);

  type cols_M_18b is array (M downto 0) of STD_LOGIC_VECTOR(mul_n - 1 downto 0);
  type cols_M_18b_signed is array (M downto 0) of signed(mul_n - 1 downto 0);
  signal epprim, epsec : cols_M_18b_signed;
  type matr_MM_18b_signed is array (M downto 0) of cols_M_18b_signed;
  signal xIep_z, xQep_z   : matr_MM_18b_signed;
  signal xIep_z2, xQep_z2 : matr_MM_18b_signed;

  type cols_M_36b is array (M downto 0) of STD_LOGIC_VECTOR(2 * mul_n - 1 downto 0);
  type cols_M_36b_signed is array (M downto 0) of SIGNED(2 * mul_n - 1 downto 0);
  type matr_NM_36b is array (N downto 0) of cols_M_36b;
  type matr_NM_36b_signed is array (N downto 0) of cols_M_36b_signed;
  signal xIep_s, xQep_s : cols_M_36b_signed;

  type matr_NM_18b is array (N downto 0) of cols_M_18b;
  signal a, ap, b, bp           : matr_NM_18b;
  signal xIep, xQep             : matr_NM_18b;
  signal res1, res2, res3, res4 : matr_NM_36b_signed;

  type cols_M_31b is array (M downto 0) of STD_LOGIC_VECTOR(mul_n + 12 downto 0);
  type matr_NM_31b is array (N downto 0) of cols_M_31b;
  signal res1_s, res2_s, res3_s, res4_s : matr_NM_31b;
  signal ijYpI, ijYpQ                   : matr_NM_36b;

  type cols_0_36b is array (0 downto 0) of STD_LOGIC_VECTOR(2 * mul_n - 1 downto 0);
  type cols_0_36b_signed is array (0 downto 0) of SIGNED(2 * mul_n - 1 downto 0);
  type cols_0_18b is array (0 downto 0) of std_logic_vector(mul_n - 1 downto 0);
  type matr_N0_18b is array (N downto 0) of cols_0_18b;
  signal c, d, cp, dp : matr_N0_18b;

  type matr_N0_36b is array (N downto 0) of cols_0_36b;
  type matr_N0_36b_signed is array (N downto 0) of cols_0_36b_signed;
  signal res5, res6, res7, res8 : matr_N0_36b_signed;

  type cols_0_31b is array (0 downto 0) of STD_LOGIC_VECTOR(mul_n + 12 downto 0);
  type matr_N0_31b is array (N downto 0) of cols_0_31b;
  signal res5_s, res6_s, res7_s, res8_s : matr_N0_31b;

  signal iIQpI, iIQpQ : matr_N0_36b;

  constant zer       : STD_LOGIC_VECTOR(mul_n - 17 downto 0) := (others => '0');
  constant all_zeros : STD_LOGIC_VECTOR(mul_n - 5 downto 0)  := (others => '0'); --[-16, 16]
  constant all_ones  : STD_LOGIC_VECTOR(mul_n - 5 downto 0)  := (others => '1'); --[-16, 16]

  type matr_MM_36b is array (M downto 0) of cols_M_36b;
  type matr_NMM_36b is array (N downto 0) of matr_MM_36b;
  signal ijYpI_s, ijYpQ_s : matr_NMM_36b;

  type cols_M1_36b is array (M + 1 downto 0) of std_logic_vector(2 * mul_n - 1 downto 0);
  type matr_NM1_36b is array (N downto 0) of cols_M1_36b;
  signal iYpI_s, iYpQ_s : matr_NM1_36b;

  type matr_0M1_36b is array (0 downto 0) of cols_M1_36b;
  type matr_N0M1_36b is array (N downto 0) of matr_0M1_36b;
  signal iIQpI_s, iIQpQ_s : matr_N0M1_36b;

  type cols_N_36b is array (N downto 0) of std_logic_vector(2 * mul_n - 1 downto 0);
  type matr_NN_36b is array (N downto 0) of cols_N_36b;
  signal YpI_s, YpQ_s   : matr_NN_36b;
  signal YpI_s2, YpQ_s2 : cols_N_36b;

  signal sigI, sigQ           : STD_LOGIC_VECTOR(mul_n - 5 downto 0); --[-16, 16]
  signal address_i, address_j : STD_LOGIC_VECTOR(4 downto 0);

begin

  address_i <= '0' & spi_ctrl(7 downto 4);
  address_j <= '0' & spi_ctrl(3 downto 0);

  process (reset_mem_n, sclk) is -- was  reset_n
  begin
    if reset_mem_n = '0' then
      for i in 0 to N loop
        for j in 0 to M loop
          a(i)(j) <= (others => '0');
          ap(i)(j) <= (others => '0');
          b(i)(j) <= (others => '0');
          bp(i)(j) <= (others => '0');
        end loop;
        for j in 0 to 0 loop
          c(i)(j) <= (others => '0');
          d(i)(j) <= (others => '0');
          cp(i)(j) <= (others => '0');
          dp(i)(j) <= (others => '0');
        end loop;
      end loop;
   
      a(0)(0) <= x"2000" & zer; -- [-4, 4]
      ap(0)(0) <= x"2000" & zer;
      
      -- 2^^15

    elsif (sclk'event and sclk = '1') then
      if (spi_ctrl(15 downto 12) = "0001") then -- a coeff
        ap(CONV_INTEGER(address_i))(CONV_INTEGER(address_j)) <= spi_data & spi_ctrl(9 downto 8);
      elsif (spi_ctrl(15 downto 12) = "0010") then -- b coeff
        bp(CONV_INTEGER(address_i))(CONV_INTEGER(address_j)) <= spi_data & spi_ctrl(9 downto 8);
      elsif (spi_ctrl(15 downto 12) = "0011") then -- c coeff				
        cp(CONV_INTEGER(address_i))(0) <= spi_data & spi_ctrl(9 downto 8);
      elsif (spi_ctrl(15 downto 12) = "0100") then -- d coeff					
        dp(CONV_INTEGER(address_i))(0) <= spi_data & spi_ctrl(9 downto 8);
      elsif (spi_ctrl(15 downto 12) = "1111") then -- update all coeffs
        for i in 0 to n loop
          for j in 0 to m loop
            a(i)(j) <= ap(i)(j);
            b(i)(j) <= bp(i)(j);
          end loop;
          for j in 0 to 0 loop
            c(i)(j) <= cp(i)(j);
            d(i)(j) <= dp(i)(j);
          end loop;
        end loop;
      end if;
    end if;
  end process;

  process (clk) is
  begin
    if (clk'event and clk = '1') then
      XIp <= xpi(13) & xpi(13) & xpi(13) & xpi & extens; --xpi,xpq 14-bits [-8191,8192]
      XQp <= xpq(13) & xpq(13) & xpq(13) & xpq & extens;
    end if;
  end process;

  process (clk) is
  begin
    if (clk'event and clk = '1') then
      sig1 <= signed(XIp) * signed(XIp); -- 2^^14 x 2^^14 = 2^^28
      sig2 <= signed(XQp) * signed(XQp);
      sig3(mul_n - 1 downto 0) <= STD_LOGIC_VECTOR(sig1(2 * mul_n - 5 downto mul_n - 4)); -- FS  (31:14)  0001.00 ... 00 
      sig4(mul_n - 1 downto 0) <= STD_LOGIC_VECTOR(sig2(2 * mul_n - 5 downto mul_n - 4)); -- FS  -- 2^^14

      XIp1 <= XIp;
      XQp1 <= XQp;
      xIp2 <= xIp1; -- 2^^14
      xQp2 <= xQp1;
    end if;
  end process;

  Add1: adder
    generic map (res_n => mul_n, op_n => mul_n, addi => 1)
    port map (dataa => sig3, datab => sig4, res => ep);

  process (clk) is
  begin
    if (clk'event and clk = '1') then
      xIp3 <= xIp2; -- 2^^14
      xQp3 <= xQp2;
      ep2 <= ep; --2^^14
    end if;
  end process;

  xIep_z(0)(0) <= signed(XIp3);
  xQep_z(0)(0) <= signed(XQp3);
  epprim(0)    <= signed(ep2);

  l1: for j in 1 to M generate -- nonlinearity
    -- ovo su vrste
    process (clk) is
    begin
      if (clk'event and clk = '1') then
        xIep_s(j - 1) <= xIep_z(j - 1)(j - 1) * epprim(j - 1); -- 2^^28
        xQep_s(j - 1) <= xQep_z(j - 1)(j - 1) * epprim(j - 1);
        xIep_z(j)(j) <= xIep_s(j - 1)(2 * mul_n - 5 downto mul_n - 4); --[31 30 29 28 .. 15 14]
        xQep_z(j)(j) <= xQep_s(j - 1)(2 * mul_n - 5 downto mul_n - 4); --[0  0  0  1  .. 0  0]
        epsec(j) <= epprim(j - 1);
        epprim(j) <= epsec(j);
      end if;
    end process;

    -- FS  -- 2^^14
    l2: for k in 0 to j - 1 generate
      process (clk) is
      begin
        if (clk'event and clk = '1') then
          xIep_z2(j)(k) <= xIep_z(j - 1)(k);
          xQep_z2(j)(k) <= xQep_z(j - 1)(k);

          xIep_z(j)(k) <= xIep_z2(j)(k);
          xQep_z(j)(k) <= xQep_z2(j)(k);
        end if;
      end process;
    end generate;
  end generate;

  l3: for j in 0 to M generate -- nonlinearity
    xIep(0)(j) <= std_logic_vector(xIep_z(M)(j));
    xQep(0)(j) <= std_logic_vector(xQep_z(M)(j));
  end generate;

  l4: for i in N downto 1 generate
    l5: for j in 0 to M generate
      process (clk) is --, reset_n
      begin
        if (clk'event and clk = '1') then
          xIep(i)(j) <= xIep(i - 1)(j);
          xQep(i)(j) <= xQep(i - 1)(j);
        end if;
      end process;
    end generate;
  end generate;

  -------------------------------------------
  l6: for i in 0 to N generate
    l7: for j in 0 to M generate
      process (clk) is
      begin
        if (clk'event and clk = '1') then
          res1(i)(j) <= signed(a(i)(j)) * signed(xIep(i)(j));
          res2(i)(j) <= signed(b(i)(j)) * signed(xQep(i)(j));
          res3(i)(j) <= signed(a(i)(j)) * signed(xQep(i)(j));
          res4(i)(j) <= signed(b(i)(j)) * signed(xIep(i)(j));
          --res1_s(i)(j) <= STD_LOGIC_VECTOR(res1(i)(j)(2 * mul_n - 6 downto 0 ));
          --res2_s(i)(j) <= STD_LOGIC_VECTOR(res2(i)(j)(2 * mul_n - 6 downto 0 ));
          --res3_s(i)(j) <= STD_LOGIC_VECTOR(res3(i)(j)(2 * mul_n - 6 downto 0 ));
          --res4_s(i)(j) <= STD_LOGIC_VECTOR(res4(i)(j)(2 * mul_n - 6 downto 0 )); 
          res1_s(i)(j) <= STD_LOGIC_VECTOR(res1(i)(j)(2 * mul_n - 1 downto mul_n - 13 ));
          res2_s(i)(j) <= STD_LOGIC_VECTOR(res2(i)(j)(2 * mul_n - 1 downto mul_n - 13 ));
          res3_s(i)(j) <= STD_LOGIC_VECTOR(res3(i)(j)(2 * mul_n - 1 downto mul_n - 13 ));
          res4_s(i)(j) <= STD_LOGIC_VECTOR(res4(i)(j)(2 * mul_n - 1 downto mul_n - 13 ));
        end if;
      end process;

      Add2: adder
        generic map (res_n => 2 * mul_n, op_n => mul_n + 13, addi => 0) -- subtraction
        port map (dataa => res1_s(i)(j), datab => res2_s(i)(j), res => ijYpI(i)(j));

      Add3: adder
        generic map (res_n => 2 * mul_n, op_n => mul_n + 13, addi => 1) -- addition
        port map (dataa => res3_s(i)(j), datab => res4_s(i)(j), res => ijYpQ(i)(j));

      process (clk) is -- 1. ppl
      begin
        if (clk'event and clk = '1') then -- pipeline
          ijYpI_s(i)(j)(0) <= ijYpI(i)(j);
          ijYpQ_s(i)(j)(0) <= ijYpQ(i)(j);
        end if;
      end process;

      l8: for k in 1 to M generate -- from 2. to M+1 ppl
        process (clk) is
        begin
          if (clk'event and clk = '1') then -- pipeline
            ijYpI_s(i)(j)(k) <= ijYpI_s(i)(j)(k - 1);
            ijYpQ_s(i)(j)(k) <= ijYpQ_s(i)(j)(k - 1);
          end if;
        end process;
      end generate;
    end generate;

    -- ovde fali proces sa taktom
    process (clk) is
    begin
      if (clk'event and clk = '1') then -- 2 ppl.       
        iYpI_s(i)(0) <= ijYpI_s(i)(0)(0); -- init.
        iYpQ_s(i)(0) <= ijYpQ_s(i)(0)(0);
      end if;
    end process;

    l9: for k in 1 to M generate
      process (clk) is
      begin
        if (clk'event and clk = '1') then -- pipeline  3. to M+2 ppl
          iYpI_s(i)(k) <= iYpI_s(i)(k - 1) + ijYpI_s(i)(k)(k); 
          iYpQ_s(i)(k) <= iYpQ_s(i)(k - 1) + ijYpQ_s(i)(k)(k);
        end if;
      end process;
    end generate;

    ----------------------------------
    ---- complex part		
    l10: for j in 0 to 0 generate -- nonlinearity	
    
      process (clk) is
      begin
        if (clk'event and clk = '1') then
          res5(i)(j) <= signed(c(i)(j)) * signed(xIep(i)(j));
          res6(i)(j) <= signed(d(i)(j)) * signed(xQep(i)(j));
          res7(i)(j) <= signed(d(i)(j)) * signed(xIep(i)(j));
          res8(i)(j) <= signed(c(i)(j)) * signed(xQep(i)(j));          
          --res5_s(i)(j) <= STD_LOGIC_VECTOR(res5(i)(j)(2 * mul_n - 6 downto 0)); 
          --res6_s(i)(j) <= STD_LOGIC_VECTOR(res6(i)(j)(2 * mul_n - 6 downto 0));
          --res7_s(i)(j) <= STD_LOGIC_VECTOR(res7(i)(j)(2 * mul_n - 6 downto 0));
          --res8_s(i)(j) <= STD_LOGIC_VECTOR(res8(i)(j)(2 * mul_n - 6 downto 0));
          res5_s(i)(j) <= STD_LOGIC_VECTOR(res5(i)(j)(2 * mul_n - 1 downto mul_n - 13)); 
          res6_s(i)(j) <= STD_LOGIC_VECTOR(res6(i)(j)(2 * mul_n - 1 downto mul_n - 13));
          res7_s(i)(j) <= STD_LOGIC_VECTOR(res7(i)(j)(2 * mul_n - 1 downto mul_n - 13));
          res8_s(i)(j) <= STD_LOGIC_VECTOR(res8(i)(j)(2 * mul_n - 1 downto mul_n - 13));
       
        end if;
      end process;

      Add4: adder
        generic map (res_n => 2 * mul_n, op_n => mul_n + 13, addi => 1) -- addition 
        port map (dataa => res5_s(i)(j), datab => res6_s(i)(j), res => iIQpI(i)(j));

      Add5: adder
        generic map (res_n => 2 * mul_n, op_n => mul_n + 13, addi => 0) -- subtraction 
        port map (dataa => res7_s(i)(j), datab => res8_s(i)(j), res => iIQpQ(i)(j));

      process (clk) is -- 1. ppl
      begin
        if (clk'event and clk = '1') then
          iIQpI_s(i)(0)(0) <= iIQpI(i)(0);
          iIQpQ_s(i)(0)(0) <= iIQpQ(i)(0);
        end if;
      end process;

      l11: for k in 1 to M + 1 generate -- from 2. to M+2 ppl
        process (clk) is
        begin
          if (clk'event and clk = '1') then -- pipeline
            iIQpI_s(i)(0)(k) <= iIQpI_s(i)(0)(k - 1);
            iIQpQ_s(i)(0)(k) <= iIQpQ_s(i)(0)(k - 1);
          end if;
        end process;
      end generate;

      process (clk) is
      begin
        if (clk'event and clk = '1') then -- pipeline
          iYpI_s(i)(M + 1) <= iYpI_s(i)(M) + iIQpI_s(i)(0)(M + 1);
          iYpQ_s(i)(M + 1) <= iYpQ_s(i)(M) + iIQpQ_s(i)(0)(M + 1);
        end if;
      end process;
    end generate;
  end generate;

  YpI_s(0)(0) <= iYpI_s(0)(M + 1);
  YpQ_s(0)(0) <= iYpQ_s(0)(M + 1); -- memory	

  process (clk) is
  begin
    if (clk'event and clk = '1') then -- pipeline 

      YpI_s2(0) <= iYpI_s(0)(M + 1);
      YpQ_s2(0) <= iYpQ_s(0)(M + 1); -- memory	
    end if;
  end process;

  l12: for i in 1 to N generate

    YpI_s(i)(0) <= iYpI_s(i)(M + 1);
    YpQ_s(i)(0) <= iYpQ_s(i)(M + 1); -- memory

    l13: for k in 1 to N generate
      process (clk) is
      begin
        if (clk'event and clk = '1') then -- pipeline
          YpI_s(i)(k) <= YpI_s(i)(k - 1);
          Ypq_s(i)(k) <= Ypq_s(i)(k - 1);
        end if;
      end process;
    end generate;

    process (clk) is
    begin
      if (clk'event and clk = '1') then -- pipeline
        YpI_s2(i) <= YpI_s2(i - 1) + YpI_s(i)(i);
        YpQ_s2(i) <= YpQ_s2(i - 1) + Ypq_s(i)(i); -- memory	
      end if;
    end process;

  end generate;
 
  sigI <= YpI_s2(N)(2 * mul_n - 1) & YpI_s2(N)(2 * mul_n - 1) & YpI_s2(N)(2 * mul_n - 1 downto mul_n + 6);
  sigQ <= YpQ_s2(N)(2 * mul_n - 1) & YpQ_s2(N)(2 * mul_n - 1) & YpQ_s2(N)(2 * mul_n - 1 downto mul_n + 6);

  process (clk) is
  begin
    if (clk'event and clk = '1') then -- pipeline
      if (sigI = all_zeros) then      
         ypi <= YpI_s2(N)(mul_n + 6 downto mul_n - 11); --[-4, 4]       
      elsif (sigI = all_ones) then
         ypi <= YpI_s2(N)(mul_n + 6 downto mul_n - 11);  --[-4, 4]
      elsif sigI(mul_n - 5) = '0' then
        ypi <= (17 => '0', others => '1');
      else
        ypi <= (17 => '1', others => '0');
      end if;
    end if;
  end process;  

  process (clk) is
  begin
    if (clk'event and clk = '1') then -- pipeline
      if (sigQ = all_zeros) then
         ypq <= YpQ_s2(N)(mul_n + 6 downto mul_n - 11);
      elsif (sigQ = all_ones) then
         ypq <= YpQ_s2(N)(mul_n + 6 downto mul_n - 11);
      elsif sigQ(mul_n - 5) = '0' then
        ypq <= (17 => '0', others => '1');
      else
        ypq <= (17 => '1', others => '0');
      end if;
    end if;
  end process;

end architecture;
