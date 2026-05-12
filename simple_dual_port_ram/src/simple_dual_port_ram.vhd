-- ----------------------------------------------------------------------------
-- FILE:          simple_dual_port_ram.vhd
-- DESCRIPTION:   Simple dual-port RAM with independent read and write clocks
-- DATE:          May 5 2026
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simple_dual_port_ram is
    generic (
        DATA_WIDTH : positive := 32;
        ADDR_WIDTH : positive := 10;

        -- Synthesis hints. Unsupported tools usually ignore unknown attributes.
        AMD_RAM_STYLE    : string := "ultra";      -- Vivado: "block", "distributed", "ultra"
        INTEL_RAMSTYLE   : string := "M20K";       -- Quartus: "M20K", "MLAB", "AUTO"
        LATTICE_RAMSTYLE : string := "block_ram"   -- Lattice/Synplify/Radiant
    );
    port (
        -- Write port
        wr_clk  : in  std_logic;
        wr_en   : in  std_logic;
        wr_addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        wr_data : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Read port
        rd_clk  : in  std_logic;
        rd_en   : in  std_logic;
        rd_addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        rd_data : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity simple_dual_port_ram;

architecture rtl of simple_dual_port_ram is

    constant RAM_DEPTH : positive := 2 ** ADDR_WIDTH;

    type ram_t is array (0 to RAM_DEPTH-1)
        of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal ram : ram_t;

    signal rd_data_r : std_logic_vector(DATA_WIDTH-1 downto 0);

    --------------------------------------------------------------------
    -- RAM inference attributes
    --------------------------------------------------------------------

    -- AMD / Xilinx Vivado
    attribute ram_style : string;
    attribute ram_style of ram : signal is AMD_RAM_STYLE;

    -- Intel / Altera Quartus
    attribute ramstyle : string;
    attribute ramstyle of ram : signal is INTEL_RAMSTYLE;

    -- Lattice / Synplify / Radiant
    attribute syn_ramstyle : string;
    attribute syn_ramstyle of ram : signal is LATTICE_RAMSTYLE;

begin

    rd_data <= rd_data_r;

    --------------------------------------------------------------------
    -- Write port
    --------------------------------------------------------------------
    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_en = '1' then
                ram(to_integer(unsigned(wr_addr))) <= wr_data;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Read port
    -- Synchronous, registered read.
    -- This is the preferred style for BRAM inference.
    --------------------------------------------------------------------
    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if rd_en = '1' then
                rd_data_r <= ram(to_integer(unsigned(rd_addr)));
            end if;
        end if;
    end process;

end architecture rtl;
