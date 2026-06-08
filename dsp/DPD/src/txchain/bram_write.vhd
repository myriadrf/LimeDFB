library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
   use ieee.std_logic_unsigned.all;

entity bram_write is
  generic (
    DATA_WIDTH : natural := 128; -- Data bus width
    ADDR_WIDTH : natural := 15  -- Address bus width (for 1024 locations)
  );
  port (
    clk         : in  std_logic; -- 491.52 MHz
    reset_n     : in  std_logic;
    start_write : in  std_logic; -- start active high
    full        : out std_logic;

    -- data ports
    xpi, xpq    : in  std_logic_vector(15 downto 0);
    ypi, ypq    : in  std_logic_vector(15 downto 0);
    xi, xq      : in  std_logic_vector(15 downto 0);

    -- memory control ports
    web         : out std_logic; -- Write enable
    enb         : out std_logic; -- Memory enable
    addrb       : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    doutb     : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture behavioral of bram_write is

  constant addr_max : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '1');
  signal start_write_f , start_write_ff : std_logic;
  signal addrb_1 : std_logic_vector(ADDR_WIDTH - 1 downto 0);
begin

  addrb <= addrb_1;

  process (clk, reset_n) is
  begin
    if reset_n = '0' then

      addrb_1 <= (others => '0');
      start_write_f <= '0';
      web <= '0';
      enb <= '0';
      full <= '0';

    elsif clk'event and clk = '1' then
      start_write_f <= start_write;
      start_write_ff <= start_write_f;

      if ((start_write_f = '1') and (start_write_ff = '0')) then -- the rising edge
        addrb_1 <= (others => '0');
        web <= '1';
        enb <= '1';
        full <= '0';
      elsif (addrb_1 = addr_max) then -- the end
        web <= '0';
        enb <= '0';
        full <= '1';
      else
        web <= '1';
        enb <= '1';
        full <= '0';
        addrb_1 <= addrb_1 + 1;
      end if;
    end if;
  end process;

  process (clk) is
  begin
  if clk'event and clk='1' then
    doutb(15 downto 0)   <= xpi;
    doutb(31 downto 16)  <= xpq;
    doutb(47 downto 32)  <= ypi;
    doutb(63 downto 48)  <= ypq;
    doutb(79 downto 64)  <= xi;
    doutb(95 downto 80)  <= xq;
    doutb(127 downto 96) <= (others => '0');
  end if;
  end process;

end architecture;

