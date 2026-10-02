library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;

  -- gain_ch is in [-4 do 4]
  -- gain_ch 001.000...00 (13 zeroes after)

entity iqim_gain_corr is
  port (
    clk                 : in  STD_LOGIC;
    reset_n, en, bypass : in  STD_LOGIC;

    ypi                 : in  STD_LOGIC_VECTOR(15 downto 0);
    ypq                 : in  STD_LOGIC_VECTOR(15 downto 0);
    gain_ch             : in  STD_LOGIC_VECTOR(15 downto 0);
    ypi_o               : out STD_LOGIC_VECTOR(15 downto 0);
    ypq_o               : out STD_LOGIC_VECTOR(15 downto 0)

  );
end entity;

architecture iqim_gain_corr_rtl of iqim_gain_corr is

  constant N : NATURAL := 18; -- Multiplier word length
  signal ypi_prim   : STD_LOGIC_VECTOR(N - 1 downto 0);
  signal ypq_prim   : STD_LOGIC_VECTOR(N - 1 downto 0);
  signal gain_prim  : STD_LOGIC_VECTOR(N - 1 downto 0);
  signal ypi_sec    : STD_LOGIC_VECTOR(15 downto 0);
  signal ypq_sec    : STD_LOGIC_VECTOR(15 downto 0);
  signal sig1, sig2 : SIGNED(2 * N - 1 downto 0);

begin

  -- gain_ch is in [-4 do 4]
  -- gain_ch 001.000...00 (13 zeroes after)
  -- ypq_prim is 0100..000 (16 zeroes after)
  process (clk)
  begin
    if rising_edge(clk) then
      if en = '1' then
        ypi_prim <= ypi(15) & ypi & '0'; -- 18 bits
        ypq_prim <= ypq(15) & ypq & '0';
        
        gain_prim <= gain_ch & "00"; -- 18 bits

        sig1 <= signed(ypi_prim) * signed(gain_prim);
        sig2 <= signed(ypq_prim) * signed(gain_prim);
        ypi_sec <= STD_LOGIC_VECTOR(sig1(31 downto 16));
        ypq_sec <= STD_LOGIC_VECTOR(sig2(31 downto 16));
      
      end if;
    end if;
  end process;
  

  WRITE_OUTPUT: process (clk) is
  begin
    if (clk'event and clk = '1') then
      if en = '1' then
        if bypass = '0' then
          ypi_o <= ypi_sec;
          ypq_o <= ypq_sec;
        else
          ypi_o <= ypi;
          ypq_o <= ypq;
        end if;

      end if;
    end if;
  end process;
end architecture;
