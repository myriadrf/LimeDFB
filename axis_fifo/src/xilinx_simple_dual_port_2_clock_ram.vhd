
--  Xilinx Simple Dual Port 2 Clock RAM
--  This code implements a parameterizable SDP dual clock memory.
--  If a reset or enable is not necessary, it may be tied off or removed from the code.

library ieee;
use ieee.std_logic_1164.all;

package ram_pkg is
    function clogb2 (depth: in natural) return integer;
end ram_pkg;

package body ram_pkg is

function clogb2( depth : natural) return integer is
variable temp    : integer := depth;
variable ret_val : integer := 0;
begin
    while temp > 1 loop
        ret_val := ret_val + 1;
        temp    := temp / 2;
    end loop;

    return ret_val;
end function;

end package body ram_pkg;


library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ram_pkg.all;
USE std.textio.all;

entity xilinx_simple_dual_port_2_clock_ram is
generic (
    RAM_WIDTH : integer := 64;                      -- Specify RAM data width
    RAM_DEPTH : integer := 512;                    -- Specify RAM depth (number of entries)
    RAM_PERFORMANCE : string := "LOW_LATENCY";      -- Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    INIT_FILE : string := "RAM_INIT.dat"                        -- Specify name/location of RAM initialization file if using one (leave blank if not)
    );

port (
        addra : in std_logic_vector((clogb2(RAM_DEPTH)-1) downto 0);     -- Write address bus, width determined from RAM_DEPTH
        addrb : in std_logic_vector((clogb2(RAM_DEPTH)-1) downto 0);     -- Read address bus, width determined from RAM_DEPTH
        dina  : in std_logic_vector(RAM_WIDTH-1 downto 0);		  -- RAM input data
        clka  : in std_logic;                       			  -- Write Clock
        clkb  : in std_logic;                       			  -- Read Clock
        wea   : in std_logic;                       			  -- Write enable
        enb   : in std_logic;                       			  -- RAM Enable, for additional power savings, disable port when not in use
        rstb  : in std_logic;                       			  -- Output reset (does not affect memory contents)
        regceb: in std_logic;                       			  -- Output register enable
        doutb : out std_logic_vector(RAM_WIDTH-1 downto 0)   			  -- RAM output data
     );

end xilinx_simple_dual_port_2_clock_ram;

architecture rtl of xilinx_simple_dual_port_2_clock_ram is

constant C_RAM_WIDTH : integer := RAM_WIDTH;
constant C_RAM_DEPTH : integer := RAM_DEPTH;
constant C_RAM_PERFORMANCE : string := RAM_PERFORMANCE;
constant C_INIT_FILE : string := INIT_FILE;


signal doutb_reg : std_logic_vector(C_RAM_WIDTH-1 downto 0) := (others => '0');

type ram_type is array (C_RAM_DEPTH-1 downto 0) of std_logic_vector (C_RAM_WIDTH-1 downto 0);          -- 2D Array Declaration for RAM signal

signal ram_data : std_logic_vector(C_RAM_WIDTH-1 downto 0) ;

-- The folowing code either initializes the memory values to a specified file or to all zeros to match hardware

function initramfromfile (ramfilename : in string) return ram_type is
file ramfile	: text is in ramfilename;
variable ramfileline : line;
variable ram_name	: ram_type;
variable bitvec : bit_vector(C_RAM_WIDTH-1 downto 0);
begin
    for i in ram_type'range loop
        readline (ramfile, ramfileline);
        read (ramfileline, bitvec);
        ram_name(i) := to_stdlogicvector(bitvec);
    end loop;
    return ram_name;
end function;

function init_from_file_or_zeroes(ramfile : string) return ram_type is
begin
    if ramfile = "RAM_INIT.dat" then
        return InitRamFromFile("RAM_INIT.dat") ;
    else
        return (others => (others => '0'));
    end if;
end;
-- Following code defines RAM

signal ram_name : ram_type := init_from_file_or_zeroes(C_INIT_FILE);

begin

process(clka)
begin
    if(clka'event and clka = '1') then
        if(wea = '1') then
            ram_name(to_integer(unsigned(addra))) <= dina;
        end if;
    end if;
end process;

process(clkb)
begin
    if(clkb'event and clkb = '1') then
        if(enb = '1') then
            ram_data <= ram_name(to_integer(unsigned(addrb)));
        end if;
    end if;
end process;

--  Following code generates LOW_LATENCY (no output register)
--  Following is a 1 clock cycle read latency at the cost of a longer clock-to-out timing

no_output_register : if C_RAM_PERFORMANCE = "LOW_LATENCY" generate
    doutb <= ram_data;
end generate;

--  Following code generates HIGH_PERFORMANCE (use output register)
--  Following is a 2 clock cycle read latency with improved clock-to-out timing

output_register : if C_RAM_PERFORMANCE = "HIGH_PERFORMANCE"  generate
process(clkb)
begin
    if(clkb'event and clkb = '1') then
        if(rstb = '1') then
            doutb_reg <= (others => '0');
        elsif(regceb = '1') then
            doutb_reg <= ram_data;
        end if;
    end if;
end process;
doutb <= doutb_reg;

end generate;
end rtl;

-- The following is an instantiation template for xilinx_simple_dual_port_2_clock_ram
-- Component Declaration
-- Uncomment the below component declaration when using
--component xilinx_simple_dual_port_2_clock_ram is
-- generic (
-- RAM_WIDTH : integer,
-- RAM_DEPTH : integer,
-- RAM_PERFORMANCE : string,
-- INIT_FILE : string
--);
--port
--(
-- addra : in std_logic_vector(clogb2(RAM_DEPTH)-1) downto 0);
-- addrb : in std_logic_vector(clogb2(RAM_DEPTH)-1) downto 0);
-- dina  : in std_logic_vector(RAM_WIDTH-1 downto 0);
-- clka  : in std_logic;
-- clkb  : in std_logic;
-- wea   : in std_logic;
-- enb   : in std_logic;
-- rstb  : in std_logic;
-- regceb: in std_logic;
-- doutb : out std_logic_vector(RAM_WIDTH-1 downto 0)
--);
--end component;
-- Instantiation
-- Uncomment the instantiation below when using
--<your_instance_name> : xilinx_simple_dual_port_2_clock_ram
-- generic map (
-- RAM_WIDTH => 18,
-- RAM_DEPTH => 1024,
-- RAM_PERFORMANCE => "HIGH_PERFORMANCE",
-- INIT_FILE => "" 
--)
--  port map  (
-- addra  => addra,
-- addrb  => addrb,
-- dina   => dina,
-- clka   => clka,
-- clkb   => clkb,
-- wea    => wea,
-- enb    => enb,
-- rsta   => rsta,
-- regceb => regceb,
-- doutb  => doutb
--);

						
						