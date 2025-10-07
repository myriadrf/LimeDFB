-- ----------------------------------------------------------------------------
-- FILE:          counter64.vhd
-- DESCRIPTION:   Simple two stage counter with variable increments
-- DATE:          09:45 2025-08-14
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity counter64 is
   generic (
      g_WIDTH        : integer := 64;
      g_ADD_OUTREG   : boolean := false
   );
   port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      inc_en   : in  std_logic;
      inc_val  : in  std_logic_vector(g_WIDTH/2-1 downto 0); 
      ld       : in  std_logic;
      ld_val   : in  std_logic_vector(g_WIDTH-1 downto 0);
      count_o  : out std_logic_vector(g_WIDTH-1 downto 0)
   );
end entity counter64;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture rtl of counter64 is

  -- Stage 0 registers
  signal lo0    : unsigned(g_WIDTH/2-1 downto 0);
  signal hi0    : unsigned(g_WIDTH/2-1 downto 0);
  signal sum0   : unsigned(g_WIDTH/2-1 downto 0);
  signal carry0 : std_logic;

  -- Stage 1 registers (final)
  signal lo1    : unsigned(g_WIDTH/2-1 downto 0);
  signal hi1    : unsigned(g_WIDTH/2-1 downto 0);
    

begin

   --------------------------------------------------------------------
   -- Stage 0: add increment to low 32 bits and detect carry
   --------------------------------------------------------------------
   sum0   <= lo0 + unsigned(inc_val);
   carry0 <= '1' when sum0 < lo0 else '0';  -- Unsigned overflow detection

   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            lo0 <= (others=>'0');
            hi0 <= (others=>'0');
         elsif ld = '1' then 
            -- load low and high slices
            lo0 <= unsigned(ld_val(g_WIDTH/2-1 downto 0));
            hi0 <= unsigned(ld_val(g_WIDTH-1 downto g_WIDTH/2));
         elsif inc_en = '1' then
            lo0 <= sum0;
            if carry0 = '1' then
               hi0 <= hi0 + to_unsigned(1, hi0'length);
            else
               hi0 <= hi0;
            end if;
         end if;
      end if;
   end process;

   --------------------------------------------------------------------
   -- Stage 1: 
   --------------------------------------------------------------------
   -- Add extra tegister for full 64-bit counter output 
   WITH_OUTREG : if g_ADD_OUTREG generate
      process(clk)
      begin
         if rising_edge(clk) then
            if rst = '1' then
               lo1 <= (others=>'0');
               hi1 <= (others=>'0');
            elsif inc_en = '1' then
               lo1 <= lo0;
               hi1 <= hi0;
            end if;
         end if;
      end process;
   end generate WITH_OUTREG;

   -- No extra register here
   NO_OUTREG : if NOT g_ADD_OUTREG generate 
      lo1 <= lo0;
      hi1 <= hi0;
   end generate NO_OUTREG;

   --------------------------------------------------------------------
   -- Output ports
   --------------------------------------------------------------------
   count_o <= std_logic_vector(hi1) & std_logic_vector(lo1);
   

end architecture rtl;
