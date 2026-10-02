library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.std_logic_unsigned.all;
  -- ----------------------------------------------------------------------------
  -- Entity declaration
  -- ----------------------------------------------------------------------------

entity adapter_txchain is
  port (
    clk1          : in  std_logic;                      -- 245.76 MHz 
    clk2          : in  std_logic;                      -- 491.52 MHz 
    reset_n       : in  std_logic;                      -- active 0
    --tx_sync_reset : in  std_logic;                      -- active 1
    sel_ch_tx     : in  std_logic_vector(1 downto 0);
    data_in       : in  std_logic_vector(255 downto 0); -- 245.76 MS/s
    data_out      : out std_logic_vector(255 downto 0); -- 491.52 MS/s

    -- control interface to BRAM
    mem_web       : out std_logic;                      -- Write enable
    mem_enb       : out std_logic;                      -- Memory enable
    mem_addrb     : out std_logic_vector(14 downto 0);
    mem_doutb     : out std_logic_vector(127 downto 0);

    -- monitoring path capture
    moni          : in  std_logic_vector(15 downto 0);
    monq          : in  std_logic_vector(15 downto 0);

    -- SPI interface
    sdin          : in  STD_LOGIC;                      -- Data in
    sclk          : in  STD_LOGIC;                      -- Data clock
    sen           : in  STD_LOGIC;                      -- Enable signal (active low)
    sdout         : out STD_LOGIC                       -- Data out
  );
end entity;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture adapter_txchain_arch of adapter_txchain is
 
  component txchain is
    generic (
      TXCHAINCFG_START_ADDR : INTEGER := 0;
      CFR0CFG_START_ADDR    : INTEGER := 64;
      CFR1CFG_START_ADDR    : INTEGER := 128;
      FIR0CFG_START_ADDR    : INTEGER := 192;
      FIR1CFG_START_ADDR    : INTEGER := 256
    );
    
    port (
      clk1       : in  std_logic; -- 245.76 MHz
      clk2       : in  std_logic; -- 491.52 MHz 

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
      mem_web    : out std_logic; -- Write enable
      mem_enb    : out std_logic; -- Memory enable
      mem_addrb  : out std_logic_vector(14 downto 0);
      mem_doutb  : out std_logic_vector(127 downto 0);

      -- monitoring path capture
      moni, monq : in  std_logic_vector(15 downto 0)
    );
  end component;

  signal cnt  : std_logic;
  signal cnt2 : std_logic;

  signal chD_Q1, chD_Q0, chD_I1, chD_I0 : std_logic_vector(15 downto 0);
  signal chC_Q1, chC_Q0, chC_I1, chC_I0 : std_logic_vector(15 downto 0);
  signal chB_Q1, chB_Q0, chB_I1, chB_I0 : std_logic_vector(15 downto 0);
  signal chA_Q1, chA_Q0, chA_I1, chA_I0 : std_logic_vector(15 downto 0);

  signal xi1, xq1, xi1prim, xq1prim : std_logic_vector(15 downto 0);
  signal yi1, yq1                   : std_logic_vector(15 downto 0);

  signal xi1_a, xq1_a, xi1_b, xq1_b, xi1_c, xq1_c, xi1_d, xq1_d : std_logic_vector(15 downto 0);

  signal xen : std_logic;

  signal chD_Q1_2, chD_Q0_2, chD_I1_2, chD_I0_2 : std_logic_vector(15 downto 0);
  signal chC_Q1_2, chC_Q0_2, chC_I1_2, chC_I0_2 : std_logic_vector(15 downto 0);
  signal chB_Q1_2, chB_Q0_2, chB_I1_2, chB_I0_2 : std_logic_vector(15 downto 0);
  signal chA_Q1_2, chA_Q0_2, chA_I1_2, chA_I0_2 : std_logic_vector(15 downto 0);

  signal data_out_prim, data_out_sec : std_logic_vector(255 downto 0); -- 491.52 MS/s
  signal I0_2, Q0_2, I1_2, Q1_2      : std_logic_vector(15 downto 0);
  signal data_out1                   : std_logic_vector(63 downto 0);

  attribute MARK_DEBUG : STRING;

  --ATTRIBUTE MARK_DEBUG OF xi1 : SIGNAL IS "TRUE";
  --ATTRIBUTE MARK_DEBUG OF xq1 : SIGNAL IS "TRUE";
  --ATTRIBUTE MARK_DEBUG OF yi1 : SIGNAL IS "TRUE";
  --ATTRIBUTE MARK_DEBUG OF yq1 : SIGNAL IS "TRUE";
  --  attribute MARK_DEBUG of chD_Q1_2 : signal is "TRUE";
  --  attribute MARK_DEBUG of chD_Q0_2 : signal is "TRUE";
  --  attribute MARK_DEBUG of chD_I1_2 : signal is "TRUE";
  --  attribute MARK_DEBUG of chD_I0_2 : signal is "TRUE";

  --signal data_out1 : std_logic_vector(255 downto 0);  
  --ATTRIBUTE MARK_DEBUG OF data_out1 : SIGNAL IS "TRUE"; 

begin

  -- at a rate of 122.88MHz, 256-bit data is made available at data_in
  process (clk1) is -- 245.76 MHz
  begin
    if clk1'event and clk1 = '1' then --- 245.76 MHz 
      if cnt = '1' then
        chD_Q1 <= data_in(255 downto 240);
        chD_Q0 <= data_in(239 downto 224);
        chD_I1 <= data_in(223 downto 208);
        chD_I0 <= data_in(207 downto 192);
        chC_Q1 <= data_in(191 downto 176);
        chC_Q0 <= data_in(175 downto 160);
        chC_I1 <= data_in(159 downto 144);
        chC_I0 <= data_in(143 downto 128);
        chB_Q1 <= data_in(127 downto 112);
        chB_Q0 <= data_in(111 downto 96);
        chB_I1 <= data_in(95 downto 80);
        chB_I0 <= data_in(79 downto 64);
        chA_Q1 <= data_in(63 downto 48);
        chA_Q0 <= data_in(47 downto 32);
        chA_I1 <= data_in(31 downto 16);
        chA_I0 <= data_in(15 downto 0);
      end if;
    end if;
  end process;

  process (clk1, reset_n) is -- 245.76 MHz
  begin
    if reset_n = '0' then
      cnt <= '0';
    elsif clk1'event and clk1 = '1' then --- 245.76 MHz 
      cnt <= not cnt;
      --end if;   
      if cnt = '1' then 
        xi1_a <= chA_I1(15 downto 0); 
        xq1_a <= chA_Q1(15 downto 0);
        xi1_b <= chB_I1(15 downto 0);
        xq1_b <= chB_Q1(15 downto 0);
        xi1_c <= chC_I1(15 downto 0);
        xq1_c <= chC_Q1(15 downto 0);
        xi1_d <= chD_I1(15 downto 0);
        xq1_d <= chD_Q1(15 downto 0);
      else
        xi1_a <= chA_I0(15 downto 0); 
        xq1_a <= chA_Q0(15 downto 0);
        xi1_b <= chB_I0(15 downto 0);
        xq1_b <= chB_Q0(15 downto 0);
        xi1_c <= chC_I0(15 downto 0);
        xq1_c <= chC_Q0(15 downto 0);
        xi1_d <= chD_I0(15 downto 0);
        xq1_d <= chD_Q0(15 downto 0);
      end if;
    end if;
  end process;

  process (clk1) is -- 245.76 MHz
  begin
    if clk1'event and clk1 = '1' then
      case sel_ch_tx is
        when "00" =>
          xi1prim <= xi1_a;
          xq1prim <= xq1_a;
        when "01" =>
          xi1prim <= xi1_b;
          xq1prim <= xq1_b;
        when "10" =>
          xi1prim <= xi1_c;
          xq1prim <= xq1_c;
        when others =>
          xi1prim <= xi1_d;
          xq1prim <= xq1_d;
      end case;
    end if;
  end process;

  xi1 <= xi1prim;
  xq1 <= xq1prim;

  inst_0: txchain
    port map (
      clk1      => clk1,    -- 245.76 MHz
      clk2      => clk2,    -- 491.52 MHz 
      reset_n   => reset_n, -- active 0
      xi        => xi1,     -- input
      xq        => xq1,
      yi        => yi1,
      yq        => yq1,     -- output
      -- SPI interface
      sdin      => sdin,    -- Data in
      sclk      => sclk,    -- Data clock
      sen       => sen,     -- Enable signal (active low)
      sdout     => sdout,   -- Data out

      -- control interface to BRAM
      mem_web   => mem_web,
      mem_enb   => mem_enb,
      mem_addrb => mem_addrb,
      mem_doutb => mem_doutb,

      -- monitoring path capture
      moni      => moni,
      monq      => monq);

  -- yi1, yq1, 491.52 MHz
     
  process (clk2, reset_n) is --  491.52 MHz 
  begin
    if reset_n = '0' then
      cnt2 <= '0';
    elsif clk2'event and clk2 = '1' then       
      cnt2 <= not cnt2;
      if cnt2 = '1' then 
        I1_2(15 downto 0) <= yi1(15 downto 0); --  I1
        Q1_2(15 downto 0) <= yq1(15 downto 0);        
      else
        I0_2(15 downto 0) <= yi1(15 downto 0); --  I0
        Q0_2(15 downto 0) <= yq1(15 downto 0);
        
        data_out1(63 downto 48) <= Q1_2;
        data_out1(47 downto 32) <= Q0_2;
        data_out1(31 downto 16) <= I1_2;
        data_out1(15 downto 0) <= I0_2;        
      end if;
    end if;
  end process;

  process (clk2) is
  begin
    if clk2'event and clk2 = '1' then
       if cnt2 = '1' then
        data_out_prim <= (others => '0');
        case sel_ch_tx is
            when "00" => data_out_prim(63 downto 0) <= data_out1;
            when "01" => data_out_prim(127 downto 64) <= data_out1;
            when "10" => data_out_prim(191 downto 128) <= data_out1;
            when others => data_out_prim(255 downto 192) <= data_out1;
        end case;
      end if;
    end if;
  end process;

  
  data_out <= data_out_prim;  
 -- at a rate of 245.76MHz, 256-bit data is made available at data_out
end architecture;

