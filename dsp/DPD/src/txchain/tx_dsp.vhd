
library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.std_logic_unsigned.all;
  use IEEE.std_logic_arith.all;
  -- ----------------------------------------------------------------------------
  -- Entity declaration
  -- ----------------------------------------------------------------------------

entity tx_dsp is

  generic (
    TXCHAINCFG_START_ADDR : INTEGER := 0;
    CFR0CFG_START_ADDR    : INTEGER := 64;
    CFR1CFG_START_ADDR    : INTEGER := 128;
    FIR0CFG_START_ADDR    : INTEGER := 192;
    FIR1CFG_START_ADDR    : INTEGER := 256
  );
  port (
    clk1       : in  std_logic; -- 245.76 MHz
    --clk2       : in  std_logic; -- 491.52 MHz 

    reset_n    : in  std_logic; -- active 0

    -- block inputs, outputs
    xi, xq     : in  std_logic_vector(15 downto 0);
    yi, yq     : out std_logic_vector(15 downto 0);

    -- SPI interface
    sdin       : in  STD_LOGIC; -- Data in
    sclk       : in  STD_LOGIC; -- Data clock
    sen        : in  STD_LOGIC; -- Enable signal (active low)
    sdout      : out STD_LOGIC; -- Data out

    -- control interface to BRAM
    --mem_web    : out std_logic; -- Write enable
    --mem_enb    : out std_logic; -- Memory enable
    --mem_addrb  : out std_logic_vector(14 downto 0);
    --mem_doutb  : out std_logic_vector(127 downto 0)--;

    -- monitoring path capture
    --moni, monq : in  std_logic_vector(15 downto 0);

    adpd_ctrl_reg     : out STD_LOGIC_VECTOR(15 downto 0);
    adpd_data_reg     : out STD_LOGIC_VECTOR(15 downto 0);
    mem_start_write   : out std_logic;
    mem_full          : in  std_logic

  );
end entity;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tx_dsparch of tx_dsp is

  component bram_write is
    generic (
      DATA_WIDTH : natural := 128; -- Data bus width
      ADDR_WIDTH : natural := 15   -- Address bus width (for 1024 locations)
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
      doutb       : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
  end component;

  component nr_cfr is
    generic (nd : NATURAL := 40);
    port (
      sleep       : in  STD_LOGIC; -- Sleep signal
      clk         : in  STD_LOGIC; -- Clock
      reset       : in  STD_LOGIC; -- Reset
      reset_mem_n : in  STD_LOGIC;
      bypass      : in  STD_LOGIC; --  Bypass
      odd         : in  STD_LOGIC;
      xi          : in  STD_LOGIC_VECTOR(15 downto 0);
      xq          : in  STD_LOGIC_VECTOR(15 downto 0);
      threshold   : in  STD_LOGIC_VECTOR(15 downto 0);
      maddressf0  : in  STD_LOGIC_VECTOR(8 downto 0);
      maddressf1  : in  STD_LOGIC_VECTOR(8 downto 0);
      mimo_en     : in  STD_LOGIC;
      sdin        : in  STD_LOGIC; -- Data in
      sclk        : in  STD_LOGIC; -- Data clock
      sen         : in  STD_LOGIC; -- Enable signal (active low)
      sdout       : out STD_LOGIC; -- Data out
      oen         : out STD_LOGIC;
      yi          : out STD_LOGIC_VECTOR(15 downto 0);
      yq          : out STD_LOGIC_VECTOR(15 downto 0);
      xen         : out STD_LOGIC);
  end component;

  component iqim_gain_corr is
    port (
      clk, reset_n, en, bypass : in  STD_LOGIC;
      ypi                      : in  STD_LOGIC_VECTOR(15 downto 0);
      ypq                      : in  STD_LOGIC_VECTOR(15 downto 0);
      gain_ch                  : in  STD_LOGIC_VECTOR(15 downto 0);
      ypi_o                    : out STD_LOGIC_VECTOR(15 downto 0);
      ypq_o                    : out STD_LOGIC_VECTOR(15 downto 0)
    );
  end component;

  component nr_gfirhf is
    port (
      sleep       : in  STD_LOGIC; -- Sleep signal
      clk         : in  STD_LOGIC; -- Clock
      reset       : in  STD_LOGIC; -- Reset
      reset_mem_n : in  STD_LOGIC;
      bypass      : in  STD_LOGIC;
      odd, half   : in  STD_LOGIC;
      xi          : in  STD_LOGIC_VECTOR(15 downto 0);
      xq          : in  STD_LOGIC_VECTOR(15 downto 0);
      maddressf0  : in  STD_LOGIC_VECTOR(8 downto 0);
      maddressf1  : in  STD_LOGIC_VECTOR(8 downto 0);
      mimo_en     : in  STD_LOGIC;
      sdin        : in  STD_LOGIC; -- Data in
      sclk        : in  STD_LOGIC; -- Data clock
      sen         : in  STD_LOGIC; -- Enable signal (active low)
      sdout       : out STD_LOGIC; -- Data out
      oen         : out STD_LOGIC;
      yi          : out STD_LOGIC_VECTOR(17 downto 0);
      yq          : out STD_LOGIC_VECTOR(17 downto 0);
      xen         : out STD_LOGIC
    );
  end component;

  component hb1 is -- OBICAN
    port (
      xi1   : in  std_logic_vector(17 downto 0); -- I input signal
      xq1   : in  std_logic_vector(17 downto 0); -- Q input signal
      n     : in  std_logic_vector(7 downto 0);  -- Clock division ratio is n+1
      sleep, delay : in  std_logic;                     -- Sleep mode control
      clk   : in  std_logic;                     -- Clock and reset
      reset : in  std_logic;
      xen   : out std_logic;                     -- HBI input enable
      yi1   : out std_logic_vector(17 downto 0); -- I output signal
      yq1   : out std_logic_vector(17 downto 0)  -- Q output signal
    );
  end component;

  component QADPD is -- OVO PREPRAVITI
    generic (
      n     : NATURAL := 4; -- memory depth
      m     : NATURAL := 3; -- nonlinearity
      mul_n : NATURAL := 18); -- multiplier precision
    port (
      clk, sclk   : in  STD_LOGIC;
      reset_n     : in  STD_LOGIC;
      reset_mem_n : in  STD_LOGIC;
      xpi         : in  STD_LOGIC_VECTOR(13 downto 0);
      xpq         : in  STD_LOGIC_VECTOR(13 downto 0);
      ypi         : out STD_LOGIC_VECTOR(17 downto 0);
      ypq         : out STD_LOGIC_VECTOR(17 downto 0);
      spi_ctrl    : in  STD_LOGIC_VECTOR(15 downto 0);
      spi_data    : in  STD_LOGIC_VECTOR(15 downto 0)
    );
  end component;

  component txchaincfg is
    port (
      maddress          : in  std_logic_vector(9 downto 0); -- 10 bit
      mimo_en           : in  std_logic;                    -- ???
      sdin              : in  std_logic;
      sclk              : in  std_logic;
      sen               : in  std_logic;
      sdout             : out std_logic;
      lreset            : in  std_logic;
      mreset            : in  std_logic;
      oen               : out std_logic;
      stateo            : out std_logic_vector(5 downto 0); -- ???
      mem_reset_n       : out std_logic;
      cfr_sleep         : out std_logic;
      cfr_bypass        : out std_logic;
      cfr_odd           : out std_logic;
      cfr_threshold     : out std_logic_vector(15 downto 0);
      gain_corr_bypass  : out std_logic;
      gain_corr_gain    : out std_logic_vector(15 downto 0);
      fir_sleep         : out std_logic;
      fir_bypass        : out std_logic;
      fir_odd           : out std_logic;
      adpd_ctrl_reg     : out STD_LOGIC_VECTOR(15 downto 0);
      adpd_data_reg     : out STD_LOGIC_VECTOR(15 downto 0);
      mem_start_write   : out std_logic;                    -- start active high
      mem_full          : in  std_logic;
      sel_buffer_source : out std_logic_vector(1 downto 0);
      hb1_delay : out std_logic
    );
  end component;

  signal mem_reset_n : std_logic;
  -- nr_cfr
  signal xi1, xq1 : std_logic_vector(15 downto 0);
  signal yi1, yq1 : std_logic_vector(15 downto 0);

  -- define this
  signal cfr_sleep     : std_logic;
  signal cfr_bypass    : std_logic;
  signal cfr_odd       : std_logic;
  signal cfr_threshold : std_logic_vector(15 downto 0);

  signal cfr_sdout : std_logic; -- sdout
  signal cfr_xen   : std_logic;

  -- gain_corr
  signal xi2, xq2 : std_logic_vector(15 downto 0);
  signal yi2, yq2 : std_logic_vector(15 downto 0);
  -- define this
  signal gain_corr_bypass : std_logic;
  signal gain_corr_gain   : std_logic_vector(15 downto 0);

  -- fir
  signal xi3, xq3   : std_logic_vector(15 downto 0);
  signal yi3, yq3   : std_logic_vector(17 downto 0); -- 18 bits
  -- define this
  signal fir_sleep  : std_logic;
  signal fir_bypass : std_logic;
  signal fir_odd    : std_logic;

  signal fir_sdout : std_logic; -- sdout

  -- hb
  signal xi4, xq4 : std_logic_vector(17 downto 0);
  signal yi4, yq4 : std_logic_vector(17 downto 0); -- 18 bits
  signal hb1_xen  : std_logic;

  -- dpd
  signal xi5, xq5 : std_logic_vector(13 downto 0);
  signal yi5, yq5 : std_logic_vector(17 downto 0); -- 18 bits

  -- dpd data capture
  signal xpi, xpq : std_logic_vector(15 downto 0);
  signal ypi, ypq : std_logic_vector(15 downto 0);

  --signal adpd_ctrl_reg : STD_LOGIC_VECTOR(15 downto 0);
  --signal adpd_data_reg : STD_LOGIC_VECTOR(15 downto 0);

  signal cfg_sdout       : std_logic;
  --signal mem_start_write : std_logic;
  --signal mem_full        : std_logic;

  signal sel_buffer_source : std_logic_vector(1 downto 0);
  signal hb1_delay : std_logic;

begin


  sdout       <= cfg_sdout or cfr_sdout or fir_sdout;
  mem_reset_n <= reset_n;

  txchaincfg_i: txchaincfg
    port map (
      maddress          => conv_std_logic_vector(TXCHAINCFG_START_ADDR / 32, 10),
      mimo_en           => '1',
      sdin              => sdin,
      sclk              => sclk,
      sen               => sen,
      sdout             => cfg_sdout, --SDOUT
      lreset            => reset_n,
      mreset            => reset_n,
      oen               => open,
      stateo            => open,
      mem_reset_n       => open,      --mem_reset_n,
      cfr_sleep         => cfr_sleep,
      cfr_bypass        => cfr_bypass,
      cfr_odd           => cfr_odd,
      cfr_threshold     => cfr_threshold,
      gain_corr_bypass  => gain_corr_bypass,
      gain_corr_gain    => gain_corr_gain,
      fir_sleep         => fir_sleep,
      fir_bypass        => fir_bypass,
      fir_odd           => fir_odd,
      adpd_ctrl_reg     => adpd_ctrl_reg,
      adpd_data_reg     => adpd_data_reg,
      mem_start_write   => mem_start_write,
      mem_full          => mem_full,
      sel_buffer_source => sel_buffer_source,
      hb1_delay => hb1_delay 
    );

  xi1 <= xi;
  xq1 <= xq;

  nr_cfr_i: nr_cfr -- 245.76 MSPS
    generic map (nd => 40)
    port map (
      -- Clock related inputs
      sleep       => cfr_sleep,
      clk         => clk1,      -- 245.76MHz
      reset       => reset_n,
      reset_mem_n => mem_reset_n,
      bypass      => cfr_bypass,
      odd         => cfr_odd,
      xi          => xi1,       -- 16 bits
      xq          => xq1,       -- 16 bits
      threshold   => cfr_threshold,
      maddressf0  => conv_std_logic_vector(CFR0CFG_START_ADDR / 64, 9),
      maddressf1  => conv_std_logic_vector(CFR1CFG_START_ADDR / 64, 9),
      mimo_en     => '1',
      sdin        => sdin,
      sclk        => sclk,
      sen         => sen,
      sdout       => cfr_sdout, -- Data out
      oen         => open,
      yi          => yi1,       -- 16 bits
      yq          => yq1,       -- 16 bits
      xen         => cfr_xen);

  xi2 <= yi1;
  xq2 <= yq1;

  gain_corr_i: iqim_gain_corr
    port map (
      clk     => clk1, -- 245.76 MHz
      reset_n => reset_n,
      en      => '1',
      bypass  => gain_corr_bypass,
      ypi     => xi2,
      ypq     => xq2,
      gain_ch => gain_corr_gain,
      ypi_o   => yi2,  -- 16 bits
      ypq_o   => yq2 -- 16 bits
    );

  xi3 <= yi2;
  xq3 <= yq2;

  nr_gfirhf_i: nr_gfirhf
    port map (
      sleep       => fir_sleep,
      clk         => clk1, -- 245.76 MHz
      reset       => reset_n,
      reset_mem_n => mem_reset_n,
      bypass      => fir_bypass,
      odd         => fir_odd,
      half        => '0',
      xi          => xi3,  -- 16 bits
      xq          => xq3,  -- 16 bits
      maddressf0  => conv_std_logic_vector(FIR0CFG_START_ADDR / 64, 9),
      maddressf1  => conv_std_logic_vector(FIR1CFG_START_ADDR / 64, 9),
      mimo_en     => '1',
      sdin        => sdin,
      sclk        => sclk,
      sen         => sen,
      sdout       => fir_sdout,
      oen         => open,
      yi          => yi3,  -- 18 bits
      yq          => yq3,  -- 18 bits
      xen         => open
    );

  --xi4 <= yi3;
  --xq4 <= yq3;
  -- xi4, xq4, 245.76MHz

  -- interpolation
  --hb1_i: hb1
  --  port map (
  --    xi1   => xi4,  -- 18 bits
  --    xq1   => xq4,  -- 18 bits
  --    n     => x"00",
  --    sleep => '0',
  --    delay =>  hb1_delay,  
  --    clk   => clk2, -- 491.52 MHz
  --    reset => reset_n,
  --    xen   => hb1_xen,
  --    yi1   => yi4,  -- 18 bits
  --    yq1   => yq4); -- 18 bits
--
  -- yi4, yq4, 491.52 MHz
  --xi5 <= yi4(17 downto 4);
  --xq5 <= yq4(17 downto 4);

 --process (clk2) is
 --begin
 --  if clk2'event and clk2 = '1' then
 --    case sel_buffer_source is
 --      when "00" => -- 0: CFR       
 --        xpi <= xi1;
 --        xpq <= xq1;
 --        ypi <= yi1;
 --        ypq <= yq1;
 --      when "01" => -- 1: FIR       
 --        xpi <= xi3;
 --        xpq <= xq3;
 --        ypi <= yi3(17 downto 2);
 --        ypq <= yq3(17 downto 2);
 --      when "10" => -- 2: interpolator       
 --        xpi <= xi4(17 downto 2);
 --        xpq <= xq4(17 downto 2);
 --        ypi <= yi4(17 downto 2);
 --        ypq <= yq4(17 downto 2);
 --      when others => -- 3: DPD
 --        xpi <= yi4(17 downto 2);
 --        xpq <= yq4(17 downto 2);
 --        ypi <= yi5(17 downto 2);
 --        ypq <= yq5(17 downto 2);
 --    end case;
 --    
 --    
 --  end if;
 --end process;

  --qadpd_i: QADPD
  --  generic map (
  --    n     => 4, -- memory depth      
  --    m     => 2, -- nonlinearity
  --    
  --    mul_n => 18) -- precision
  --  port map (
  --    clk         => clk2, -- 491.52 MHz
  --    sclk        => sclk,
  --    reset_n     => reset_n,
  --    reset_mem_n => mem_reset_n,
  --    xpi         => xi5,  -- 14 bits
  --    xpq         => xq5,  -- 14 bits
  --    ypi         => yi5,  -- 18 bits
  --    ypq         => yq5,  -- 18 bits	
  --    spi_ctrl    => adpd_ctrl_reg,
  --    spi_data    => adpd_data_reg
  --  );

  --yi <= yi5(17 downto 2);
  --yq <= yq5(17 downto 2);

  yi <= yi3(17 downto 2);
  yq <= yq3(17 downto 2);

  --bram_ctrl: bram_write
  --  generic map (
  --    DATA_WIDTH => 128, -- Data bus width
  --    ADDR_WIDTH => 15 -- Address bus width (for 1024 locations)
  --  )
  --  port map (
  --    clk         => clk2,            -- 491.52 MHz
  --    reset_n     => reset_n,
  --    start_write => mem_start_write, -- start active high
  --    full        => mem_full,        --active high
  --    -- data ports
  --    xpi         => xpi,
  --    xpq         => xpq,
  --    ypi         => ypi,
  --    ypq         => ypq,
  --    xi          => moni,
  --    xq          => monq,
  --    -- memory control ports
  --    web         => mem_web,
  --    enb         => mem_enb,
  --    addrb       => mem_addrb,
  --    doutb       => mem_doutb
  --  );

end architecture;


