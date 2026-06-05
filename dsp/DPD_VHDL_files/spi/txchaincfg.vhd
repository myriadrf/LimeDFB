-- ----------------------------------------------------------------------------	
-- FILE:	fpgacfg.vhd
-- DESCRIPTION:	Serial configuration interface to control TX modules
-- DATE:	June 07, 2007
-- AUTHOR(s):	Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------	

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.nr_mem_package.all;

  -- ----------------------------------------------------------------------------
  -- Entity declaration
  -- ----------------------------------------------------------------------------

entity txchaincfg is
  port (
    maddress         : in  std_logic_vector(9 downto 0);
    mimo_en          : in  std_logic;                    -- ???
    sdin             : in  std_logic;
    sclk             : in  std_logic;
    sen              : in  std_logic;
    sdout            : out std_logic;
    lreset           : in  std_logic;
    mreset           : in  std_logic;
    oen              : out std_logic;
    stateo           : out std_logic_vector(5 downto 0); -- ???	

    mem_reset_n      : out std_logic;

    cfr_sleep        : out std_logic;
    cfr_bypass       : out std_logic;
    cfr_odd          : out std_logic;
    cfr_threshold    : out std_logic_vector(15 downto 0);

    gain_corr_bypass : out std_logic;
    gain_corr_gain   : out std_logic_vector(15 downto 0);

    fir_sleep        : out std_logic;
    fir_bypass       : out std_logic;
    fir_odd          : out std_logic;

    adpd_ctrl_reg    : out STD_LOGIC_VECTOR(15 downto 0);
    adpd_data_reg    : out STD_LOGIC_VECTOR(15 downto 0);
    mem_start_write  : out std_logic;                    -- mem(0)(1);                -- start active high
    mem_full         : in  std_logic;                     -- mem(1)(0);
    sel_buffer_source : out std_logic_vector(1 downto 0);
    hb1_delay : out std_logic
  );
end entity;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture txchaincfg_arch of txchaincfg is

  signal inst_reg    : std_logic_vector(15 downto 0); -- Instruction register
  signal inst_reg_en : std_logic;

  signal din_reg    : std_logic_vector(15 downto 0); -- Data in register
  signal din_reg_en : std_logic;

  signal dout_reg                   : std_logic_vector(15 downto 0); -- Data out register
  signal dout_reg_sen, dout_reg_len : std_logic;

  signal mem    : marray32x16; -- Config memory
  signal mem_we : std_logic;

  signal oe : std_logic; -- Tri state buffers control

  -- Components
  use work.mcfg_components.mcfg32wm_fsm;
  for all: mcfg32wm_fsm use entity work.mcfg32wm_fsm(mcfg32wm_fsm_arch);

    signal cfr_order : std_logic_vector(7 downto 0);
  begin

    -- ---------------------------------------------------------------------------------------------
    -- Finite state machines
    -- ---------------------------------------------------------------------------------------------
    fsm: mcfg32wm_fsm
    port map (
        address => maddress, mimo_en => mimo_en, inst_reg => inst_reg, sclk => sclk, sen => sen, reset => lreset,
        inst_reg_en => inst_reg_en, din_reg_en => din_reg_en, dout_reg_sen => dout_reg_sen,
        dout_reg_len => dout_reg_len, mem_we => mem_we, oe => oe, stateo => stateo);

    -- ---------------------------------------------------------------------------------------------
    -- Instruction register
    -- ---------------------------------------------------------------------------------------------
    inst_reg_proc: process (sclk, lreset)
      variable i : integer;
    begin
      if lreset = '0' then
        inst_reg <= (others => '0');
      elsif sclk'event and sclk = '1' then
        if inst_reg_en = '1' then
          for i in 15 downto 1 loop
            inst_reg(i) <= inst_reg(i - 1);
          end loop;
          inst_reg(0) <= sdin;
        end if;
      end if;
    end process;

    -- ---------------------------------------------------------------------------------------------
    -- Data input register
    -- ---------------------------------------------------------------------------------------------
    din_reg_proc: process (sclk, lreset)
      variable i : integer;
    begin
      if lreset = '0' then
        din_reg <= (others => '0');
      elsif sclk'event and sclk = '1' then
        if din_reg_en = '1' then
          for i in 15 downto 1 loop
            din_reg(i) <= din_reg(i - 1);
          end loop;
          din_reg(0) <= sdin;
        end if;
      end if;
    end process;

    -- ---------------------------------------------------------------------------------------------
    -- Data output register
    -- ---------------------------------------------------------------------------------------------
    dout_reg_proc: process (sclk, lreset)
      variable i : integer;
    begin
      if lreset = '0' then
        dout_reg <= (others => '0');
      elsif sclk'event and sclk = '0' then
        -- Shift operation
        if dout_reg_sen = '1' then
          for i in 15 downto 1 loop
            dout_reg(i) <= dout_reg(i - 1);
          end loop;
          dout_reg(0) <= dout_reg(15);
          -- Load operation
        elsif dout_reg_len = '1' then
          case inst_reg(4 downto 0) is -- mux read-only outputs
            when "00001" => dout_reg <= "000000000000000" & mem_full;
            when others => dout_reg <= mem(to_integer(unsigned(inst_reg(4 downto 0))));
          end case;
        end if;
      end if;
    end process;

    -- Tri state buffer to connect multiple serial interfaces in parallel
    sdout <= dout_reg(15) and oe;
    oen <= oe;
    -- ---------------------------------------------------------------------------------------------
    -- Configuration memory
    -- --------------------------------------------------------------------------------------------- 
    ram: process (sclk, mreset) --(remap)
    begin
      -- Defaults
      if mreset = '0' then
        --Read only registers
        mem(0) <= "0000000000011101"; -- hb1_delay, sel_buffer_source, mem_start_write, mem_reset_n,
        mem(1) <= "0000000000000000"; -- 15 free, mem_full
        mem(2) <= "0000000000000010"; -- cfr_odd, cfr_bypass, cfr_sleep, 
        mem(3) <= "1111111111111111"; -- cfr_threshold,
        mem(4) <= "0000000000000001"; -- gain_corr_bypass,
        mem(5) <= "0010000000000000"; -- gain_corr_gain,
        mem(6) <= "0000000000000010"; -- fir_odd, fir_bypass, fir_sleep, 
        mem(7) <= "0000000000000000"; -- adpd_ctrl_reg,
        mem(8) <= "0000000000000000"; -- adpd_data_reg,
        mem(9) <= "0000000000000000"; -- 16 free,
        mem(10) <= "0000000000000000"; -- 16 free, 
        mem(11) <= "0000000000000000"; -- 16 free, 
        mem(12) <= "0000000000000000"; -- 16 free, 
        mem(13) <= "0000000000000000"; -- 16 free, 
        mem(14) <= "0000000000000000"; -- 16 free, 
        mem(15) <= "0000000000000000"; -- 16 free, 
        mem(16) <= "0000000000000000"; -- 16 free, 
        mem(17) <= "0000000000000000"; -- 16 free,
        mem(18) <= "0000000000000000"; -- 16 free, 
        mem(19) <= "0000000000000000"; -- 16 free, 
        mem(20) <= "0000000000000000"; -- 16 free, 
        mem(21) <= "0000000000000000"; -- 16 free, 
        mem(22) <= "0000000000000000"; -- 16 free, 
        mem(23) <= "0000000000000000"; -- 16 free, 		

      elsif sclk'event and sclk = '1' then
        if mem_we = '1' then
          mem(to_integer(unsigned(inst_reg(4 downto 0)))) <= din_reg(14 downto 0) & sdin;
        end if;

        if dout_reg_len = '0' then
        end if;

      end if;
    end process;

    -- ---------------------------------------------------------------------------------------------
    -- Decoding logic
    -- ---------------------------------------------------------------------------------------------
    mem_reset_n <= mem(0)(0); -- default 1
    mem_start_write <= mem(0)(1); -- default 0
    sel_buffer_source <= mem(0)(3 downto 2);  -- default 3

    hb1_delay <= mem(0)(4); -- default 1 (workarround)

    cfr_sleep <= mem(2)(0); -- default 0
    cfr_bypass <= mem(2)(1); -- default 1
    cfr_odd <= mem(2)(2); -- default 1

    cfr_order <= mem(2)(10 downto 3); -- ???, mozda ne treba

    cfr_threshold <= mem(3)(15 downto 0); --"1111111111111111"	

    gain_corr_bypass <= mem(4)(0); -- default 1
    gain_corr_gain <= mem(5)(15 downto 0); --"0010000000000000"

    fir_sleep <= mem(6)(0); -- default 0
    fir_bypass <= mem(6)(1); -- default 1
    fir_odd <= mem(6)(2); -- default 1

    adpd_ctrl_reg <= mem(7)(15 downto 0);
    adpd_data_reg <= mem(8)(15 downto 0);

  end architecture;
