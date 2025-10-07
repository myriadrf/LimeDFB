-- ----------------------------------------------------------------------------
-- FILE:          ram_mem_wrapper.vhd
-- DESCRIPTION:   Wrapper for vendor specific RAM memories
-- DATE:          15:55 2024-06-12
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package ram_pkg is
    function clogb2 (depth: in natural) return integer;
end ram_pkg;

package body ram_pkg is

function clogb2( depth : in natural) return integer is
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
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ram_pkg.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity ram_mem_wrapper is
   generic(
      g_VENDOR          : string  := "GENERIC";        -- "GENERIC", "XILINX"
      g_RAM_WIDTH       : integer := 64;
      g_RAM_DEPTH       : integer := 256;
      g_RAM_PERFORMANCE : string  := "LOW_LATENCY"   -- "LOW_LATENCY" or "HIGH_PERFORMANCE"
   );
   port (
      addra : in std_logic_vector((clogb2(g_RAM_DEPTH)-1) downto 0); -- Write address bus, width determined from RAM_DEPTH
      addrb : in std_logic_vector((clogb2(g_RAM_DEPTH)-1) downto 0); -- Read address bus, width determined from RAM_DEPTH
      dina  : in std_logic_vector(g_RAM_WIDTH-1 downto 0);		      -- RAM input data
      clka  : in std_logic;                       			            -- Write Clock
      clkb  : in std_logic;                       			            -- Read Clock
      wea   : in std_logic;                       			            -- Write enable
      enb   : in std_logic;                       			            -- RAM Enable, for additional power savings, disable port when not in use
      rstb  : in std_logic;                       			            -- Output reset (does not affect memory contents)
      regceb: in std_logic;                       			            -- Output register enable
      doutb : out std_logic_vector(g_RAM_WIDTH-1 downto 0)           -- RAM output data
   );
end ram_mem_wrapper;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of ram_mem_wrapper is
--declare signals,  components here

   type fifo_ram_type is array (0 to g_RAM_DEPTH-1) of std_logic_vector(g_RAM_WIDTH-1 downto 0);
   signal fifo_ram   : fifo_ram_type;
   signal ram_data   : std_logic_vector(g_RAM_WIDTH-1 downto 0);
   signal addrb_old  : std_logic_vector((clogb2(g_RAM_DEPTH)-1) downto 0);
   signal addrb_mux  : std_logic_vector((clogb2(g_RAM_DEPTH)-1) downto 0);

   component xilinx_simple_dual_port_2_clock_ram is
   generic (
      RAM_WIDTH : integer := 64;                   -- Specify RAM data width
      RAM_DEPTH : integer := 512;                  -- Specify RAM depth (number of entries)
      RAM_PERFORMANCE : string := "LOW_LATENCY";   -- Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
      INIT_FILE : string := "RAM_INIT.dat"         -- Specify name/location of RAM initialization file if using one (leave blank if not)
      );
   
   port (
         addra : in std_logic_vector((clogb2(RAM_DEPTH)-1) downto 0);     -- Write address bus, width determined from RAM_DEPTH
         addrb : in std_logic_vector((clogb2(RAM_DEPTH)-1) downto 0);     -- Read address bus, width determined from RAM_DEPTH
         dina  : in std_logic_vector(RAM_WIDTH-1 downto 0);    -- RAM input data
         clka  : in std_logic;                       			   -- Write Clock
         clkb  : in std_logic;                       			   -- Read Clock
         wea   : in std_logic;                       			   -- Write enable
         enb   : in std_logic;                       			   -- RAM Enable, for additional power savings, disable port when not in use
         rstb  : in std_logic;                       			   -- Output reset (does not affect memory contents)
         regceb: in std_logic;                       			   -- Output register enable
         doutb : out std_logic_vector(RAM_WIDTH-1 downto 0)    -- RAM output data
      );
   
   end component;

begin


   -- ----------------------------------------------------------------------------
   -- Generic RAM memory
   -- ----------------------------------------------------------------------------
   GENERIC_RAM : if g_VENDOR = "GENERIC" generate
      -- Write Data to RAM
      process(clka)
      begin
         if rising_edge(clka) then
            if wea = '1' then
               fifo_ram(to_integer(unsigned(addra))) <= dina;
            end if;
         end if;
      end process;

      -- Read Data from RAM
          -- Quartus seems to get confused with read enable (enb) and infers lots of
          -- unnecessary logic. Doing this acts the same as read enable, but Quartus
          -- does not get confused.
      addrb_mux <= addrb when enb = '1' else addrb_old;
      process(clkb)
      begin
         if rising_edge(clkb) then
              if enb = '1' then
                addrb_old <= addrb;
              end if;
--            if enb = '1' then
               ram_data <= fifo_ram(to_integer(unsigned(addrb_mux)));
--            end if;
         end if;
      end process;
      
      -- Adding extra register stage if g_RAM_PERFORMANCE=HIGH_PERFORMANCE. 
      ADD_OUTPUT_REG : if g_RAM_PERFORMANCE = "HIGH_PERFORMANCE" generate 
         process(clkb)
         begin 
            if rising_edge(clkb) then
               if regceb = '1' then 
                  doutb <= ram_data;
               end if;
            end if;
         end process;
      end generate ADD_OUTPUT_REG;
   
      -- Data from memory directly wired to output without register stage, saving one cycle   
      NO_OUTPUT_REG : if g_RAM_PERFORMANCE = "LOW_LATENCY" generate
         doutb <= ram_data;
      end generate NO_OUTPUT_REG;
      
   end generate GENERIC_RAM;
   
   -- ----------------------------------------------------------------------------
   -- XILINX recomended Dual port RAM memory implementation
   -- ----------------------------------------------------------------------------
   XILINX_RAM : if g_VENDOR = "XILINX" generate
      ram_mem_inst : xilinx_simple_dual_port_2_clock_ram
         generic map (
            RAM_WIDTH         => g_RAM_WIDTH,
            RAM_DEPTH         => g_RAM_DEPTH,
            RAM_PERFORMANCE   => g_RAM_PERFORMANCE,
            INIT_FILE         => "" 
         )
         port map  (
            addra  => addra,
            addrb  => addrb,
            dina   => dina,
            clka   => clka,
            clkb   => clkb,
            wea    => wea,
            enb    => enb,
            rstb   => rstb,
            regceb => regceb,
            doutb  => doutb
      );
   end generate XILINX_RAM;
  
end arch;   


