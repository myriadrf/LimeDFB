-- ----------------------------------------------------------------------------	
-- FILE:	nr_fircms
-- DESCRIPTION:	Serial configuration interface FIR Coeffitient Memory.
-- DATE:
-- AUTHOR(s):	
-- REVISIONS:	
-- ----------------------------------------------------------------------------	

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.nr_mem_package.ALL;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
ENTITY nr_fircms IS
    PORT (
        -- Address and location of this module
        -- These signals will be hard wired at the top level
        maddress : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
        mimo_en : IN STD_LOGIC;

        -- Serial port A IOs
        sdin : IN STD_LOGIC; -- Data in
        sclk : IN STD_LOGIC; -- Data clock
        sen : IN STD_LOGIC; -- Enable signal (active low)
        sdout : OUT STD_LOGIC; -- Data out

        -- Signals coming from the pins or top level serial interface
        hreset : IN STD_LOGIC; -- Hard reset signal, resets everything		
        oen : OUT STD_LOGIC;
        di : OUT marray16x16
    );
END nr_fircms;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
ARCHITECTURE nr_fircms_arch OF nr_fircms IS
    SIGNAL inst_reg : STD_LOGIC_VECTOR(15 DOWNTO 0); -- Instruction register
    SIGNAL inst_reg_en : STD_LOGIC;

    SIGNAL din_reg : STD_LOGIC_VECTOR(15 DOWNTO 0); -- Data in register
    SIGNAL din_reg_en : STD_LOGIC;

    SIGNAL dout_reg : STD_LOGIC_VECTOR(15 DOWNTO 0); -- Data out register
    SIGNAL dout_reg_sen, dout_reg_len : STD_LOGIC;

    SIGNAL mem : marray32x16; -- RAM memory
    SIGNAL mem_we : STD_LOGIC;

    SIGNAL oe : STD_LOGIC; -- Tri state buffers control 

    USE work.mcfg_components.mcfg64wm_fsm;
    FOR ALL : mcfg64wm_fsm USE ENTITY work.mcfg64wm_fsm(mcfg64wm_fsm_arch);
BEGIN
    -- ---------------------------------------------------------------------------------------------
    -- Finite state machines
    -- ---------------------------------------------------------------------------------------------
    fsm : mcfg64wm_fsm PORT MAP(
        address => maddress, mimo_en => mimo_en, inst_reg => inst_reg, sclk => sclk, sen => sen, reset => hreset,
        inst_reg_en => inst_reg_en, din_reg_en => din_reg_en, dout_reg_sen => dout_reg_sen,
        dout_reg_len => dout_reg_len, mem_we => mem_we, oe => oe, stateo => OPEN);

    -- ---------------------------------------------------------------------------------------------
    -- Instruction register
    -- ---------------------------------------------------------------------------------------------
    inst_reg_proc : PROCESS (sclk, hreset)
        VARIABLE i : INTEGER;
    BEGIN
        IF hreset = '0' THEN
            inst_reg <= (OTHERS => '0');
        ELSIF sclk'event AND sclk = '1' THEN
            IF inst_reg_en = '1' THEN
                FOR i IN 15 DOWNTO 1 LOOP
                    inst_reg(i) <= inst_reg(i - 1);
                END LOOP;
                inst_reg(0) <= sdin;
            END IF;
        END IF;
    END PROCESS inst_reg_proc;

    -- ---------------------------------------------------------------------------------------------
    -- Data input register
    -- ---------------------------------------------------------------------------------------------
    din_reg_proc : PROCESS (sclk, hreset)
        VARIABLE i : INTEGER;
    BEGIN
        IF hreset = '0' THEN
            din_reg <= (OTHERS => '0');
        ELSIF sclk'event AND sclk = '1' THEN
            IF din_reg_en = '1' THEN
                FOR i IN 15 DOWNTO 1 LOOP
                    din_reg(i) <= din_reg(i - 1);
                END LOOP;
                din_reg(0) <= sdin;
            END IF;
        END IF;
    END PROCESS din_reg_proc;

    -- ---------------------------------------------------------------------------------------------
    -- Data output register
    -- ---------------------------------------------------------------------------------------------
    dout_reg_proc : PROCESS (sclk, hreset)
        VARIABLE i : INTEGER;
    BEGIN
        IF hreset = '0' THEN
            dout_reg <= (OTHERS => '0');
        ELSIF sclk'event AND sclk = '0' THEN
            -- Shift operation
            IF dout_reg_sen = '1' THEN
                FOR i IN 15 DOWNTO 1 LOOP
                    dout_reg(i) <= dout_reg(i - 1);
                END LOOP;
                dout_reg(0) <= dout_reg(15);
                -- Load operation
            ELSIF dout_reg_len = '1' THEN
                dout_reg <= mem(to_integer(unsigned(inst_reg(4 DOWNTO 0))));
            END IF;
        END IF;
    END PROCESS dout_reg_proc;

    -- Tri state buffer to connect multiple serial interfaces in parallel
    sdout <= dout_reg(15) AND oe;
    oen <= oe;

    -- ---------------------------------------------------------------------------------------------
    -- Configuration memory
    -- --------------------------------------------------------------------------------------------- 
    ram : PROCESS (sclk, hreset)
    BEGIN
        IF sclk'event AND sclk = '1' THEN
            IF mem_we = '1' THEN
                mem(to_integer(unsigned(inst_reg(4 DOWNTO 0)))) <= din_reg(14 DOWNTO 0) & sdin;
            END IF;
        END IF;
    END PROCESS ram;

    -- Construct data outputs to the filter

    l0 : FOR i IN 0 TO 15 GENERATE
        di(i) <= mem(i);
    END GENERATE;

END nr_fircms_arch;