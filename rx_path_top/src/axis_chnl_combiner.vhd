-- ----------------------------------------------------------------------------
-- FILE:          axis_chnl_combiner.vhd
-- DESCRIPTION:   Combines separate channels into full word axi stream
-- DATE:          09:45 2025-07-14
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
entity axis_chnl_combiner is
   generic (
      g_DATA_WIDTH      : integer := 128;
      g_N_CHANNELS      : integer := 4;
      g_CHANNEL_WIDTH   : integer := 32
   );
   port (
      aclk           : in  std_logic;
      aresetn        : in  std_logic;
      -- AXI Stream Write Interface
      s_axis_tdata   : in  std_logic_vector(g_DATA_WIDTH-1 downto 0);
      s_axis_tkeep   : in  std_logic_vector(g_DATA_WIDTH/8-1 downto 0);
      s_axis_tuser   : in  std_logic_vector(g_N_CHANNELS-1 downto 0);
      s_axis_tlast   : in  std_logic;
      s_axis_tvalid  : in  std_logic;
      s_axis_tready  : out std_logic;
      -- AXI Stream Read Interface
      m_axis_tdata   : out std_logic_vector(g_DATA_WIDTH-1 downto 0);
      m_axis_tkeep   : out std_logic_vector(g_DATA_WIDTH/8-1 downto 0);
      m_axis_tlast   : out std_logic;
      m_axis_tvalid  : out std_logic;
      m_axis_tready  : in  std_logic;

      debug_write_pointer : out std_logic_vector(4 downto 0);
      debug_read_pointer  : out std_logic_vector(4 downto 0);
      debug_wrusedw       : out std_logic_vector(4 downto 0);
      debug_pipeline_en   : out std_logic_vector(2 downto 0)
   );
end entity axis_chnl_combiner;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture rtl of axis_chnl_combiner is

   signal s_axis_tready_reg : std_logic;
   signal s_axis_tdata_reg  : std_logic_vector(s_axis_tdata'LENGTH-1 downto 0);
   signal s_axis_tkeep_reg  : std_logic_vector(s_axis_tkeep'LENGTH-1 downto 0);
   signal s_axis_tuser_reg  : std_logic_vector(s_axis_tuser'LENGTH-1 downto 0);

   signal m_axis_tdata_reg  : std_logic_vector(m_axis_tdata'LENGTH-1 downto 0);

   type t_RAM_ARRAY is array (0 to g_DATA_WIDTH*2/8-1) of std_logic_vector (7 downto 0);
   signal ram_buffer    : t_RAM_ARRAY;
   --signal byte_index    : unsigned(4 downto 0);
   signal ram_buffer_byte_occupied  : std_logic_vector(g_DATA_WIDTH*2/8-1 downto 0);

   signal m_axis_tvalid_reg : std_logic;

   signal ram_buffer_overflow : std_logic;


   signal pipeline_en : std_logic;

   type t_valid_bytes_index_array is array (0 to 15) of unsigned(4 downto 0);
   signal valid_bytes_index_array : t_valid_bytes_index_array;
   signal valid_bytes : std_logic_vector(15 downto 0);

   type t_BYTE_ARRAY is array (0 to 3) of std_logic_vector(31 downto 0);
   signal byte_array       : t_BYTE_ARRAY;
   signal byte_array_tkeep : std_logic_vector(g_DATA_WIDTH/8/4-1 downto 0);

   signal pipeline_en_stage1 : std_logic;
   signal valid_byte_count   : unsigned(3 downto 0);

   type t_BYTE_ACCUM is array (0 to 15) of std_logic_vector(31 downto 0); 
   signal byte_accum       : t_BYTE_ACCUM;
   signal byte_accum_tkeep : std_logic_vector(15 downto 0);
   signal pipeline_en_stage2 : std_logic;

   signal write_pointer      : unsigned(4 downto 0);
   signal wrptr              : unsigned(3 downto 0);


   signal read_pointer       : unsigned(4 downto 0);
   signal rdptr              : unsigned(3 downto 0);

   signal wrusedw            : unsigned(4 downto 0);
    

begin


   debug_write_pointer  <= std_logic_vector(write_pointer);
   debug_read_pointer   <= std_logic_vector(read_pointer) ;
   debug_wrusedw        <= std_logic_vector(wrusedw)      ;

   debug_pipeline_en    <= pipeline_en_stage2 & pipeline_en_stage1 & pipeline_en;


-- ----------------------------------------------------------------------------
-- Read pointer
-- ---------------------------------------------------------------------------- 
   process (aclk, aresetn)
   begin
      if aresetn = '0' then
         read_pointer <=(others=>'0');
      elsif rising_edge(aclk) then
         if m_axis_tready = '1' AND m_axis_tvalid_reg = '1' then 
            read_pointer <= read_pointer + 4;
         end if;
      end if;
   end process;

   rdptr <= read_pointer(read_pointer'LEFT-1 downto 0);


-- ----------------------------------------------------------------------------
-- Stage0: Iput registers
-- ---------------------------------------------------------------------------- 
   process (aclk, aresetn)
   begin
      if aresetn = '0' then
         s_axis_tdata_reg  <= (others=>'0');
         s_axis_tkeep_reg  <= (others=>'0');
         s_axis_tuser_reg  <= (others=>'0');
         pipeline_en       <= '0';
      elsif rising_edge(aclk) then
         if s_axis_tvalid='1' AND s_axis_tready_reg='1' then
            s_axis_tdata_reg <= s_axis_tdata;
            s_axis_tkeep_reg <= s_axis_tkeep;
            s_axis_tuser_reg <= s_axis_tuser;
         end if;    

         if s_axis_tvalid='1' AND s_axis_tready_reg='1' then
            pipeline_en <= '1';
         else 
            pipeline_en <= '0';
         end if;
      end if;
   end process;


-- ----------------------------------------------------------------------------
-- Stage1: Capture only valid bytes
-- ----------------------------------------------------------------------------
   process (aclk, aresetn)
      variable count : integer range 0 to g_DATA_WIDTH/8/4-1 :=0;
   begin
      if aresetn = '0' then
         pipeline_en_stage1   <= '0';
         valid_byte_count     <= (others=>'0');
         byte_array           <= (others=>(others=>'0'));
         byte_array_tkeep     <= (others=>'0');
      elsif rising_edge(aclk) then
         count :=0;
         if pipeline_en = '1' then 
            for i in 0 to s_axis_tuser_reg'LENGTH-1 loop
               if s_axis_tuser_reg(i)='1' then
                  byte_array(count) <= s_axis_tdata_reg(32*i+31 downto 32*i);
                  byte_array_tkeep(count) <= '1'; 
                  count := count + 1; 
               else 
                  byte_array_tkeep(count) <= '0'; 
               end if;
            end loop;
            valid_byte_count <= to_unsigned(count, valid_byte_count'LENGTH);
            pipeline_en_stage1 <= '1';
         else 
            pipeline_en_stage1 <= '0';
         end if;
      end if;
   end process;


-- ----------------------------------------------------------------------------
-- Stage2: Accumulate valid bytes
-- ----------------------------------------------------------------------------
   process (aclk, aresetn)
      variable pointer  : integer range 0 to 15 :=0;
   begin
      if aresetn = '0' then
         pipeline_en_stage2   <= '0';
         write_pointer        <= (others=>'0');
         wrptr                <= (others=>'0');
         byte_accum           <= (others=>(others=>'0'));
         byte_accum_tkeep     <= (others=>'0');
      elsif rising_edge(aclk) then
         pointer:= to_integer(write_pointer);
         if pipeline_en_stage1 = '1' then 
            for i in 0 to byte_array_tkeep'LENGTH-1 loop
               if byte_array_tkeep(i)='1' then
                  byte_accum(pointer mod 16) <= byte_array(i);
                  byte_accum_tkeep(pointer mod 16) <= '1'; 
                  pointer:= (pointer + 1); 
               else 
                  byte_accum_tkeep(pointer mod 16) <= '0'; 
               end if;
            end loop;
            write_pointer <= to_unsigned(pointer, write_pointer'LENGTH);
            wrptr         <= to_unsigned((pointer mod 16), wrptr'LENGTH);
            pipeline_en_stage2 <= '1';
         else 
            pipeline_en_stage2 <= '0';
         end if;
      end if;
   end process;

-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------




--process (aclk, aresetn) 
--begin 
--   if aresetn = '0' then
--      m_axis_tdata_reg  <= (others=>'0');
--      m_axis_tvalid_reg <= '0';
--   elsif rising_edge(aclk) then
--      if byte_accum_tkeep(3)='1' AND byte_accum_pointer < 4 then 
--         for i in 0 to 3 loop
--            m_axis_tdata_reg(i*32 + 31 downto i*32) <= byte_accum(i);
--         end loop;
--      elsif byte_accum_tkeep(7)='1' AND byte_accum_pointer > 4 then 
--         for i in 0 to 3 loop
--            m_axis_tdata_reg(i*32 + 31 downto i*32) <= byte_accum(i+3);
--         end loop;
--      else 
--         m_axis_tdata_reg <= m_axis_tdata_reg;
--      end if;
--
--      if (pipeline_en_stage2 = '1' AND (byte_accum_tkeep(3)='1' OR  byte_accum_tkeep(7)='1')) then 
--         m_axis_tvalid_reg <= '1';
--      elsif m_axis_tvalid_reg = '1' AND m_axis_tready = '0' then 
--         m_axis_tvalid_reg <= '1';
--      else
--         m_axis_tvalid_reg <= '0';
--      end if;
--
--   end if;
--end process;


process(all)
begin 
   wrusedw <= write_pointer - read_pointer;
end process;


process(all)
begin
   m_axis_tvalid_reg <= '1' when wrusedw > 3 else '0';
end process;


process(all)
begin 
   m_axis_tdata_reg <=byte_accum(to_integer(rdptr+3)) & byte_accum(to_integer(rdptr+2)) & byte_accum(to_integer(rdptr+1)) & byte_accum(to_integer(rdptr));
end process;








ram_buffer_overflow <= ram_buffer_byte_occupied(16);


s_axis_tready_reg <= '0' when (aresetn='0' OR (
                              write_pointer(write_pointer'LEFT) /= read_pointer(read_pointer'LEFT) AND 
                              write_pointer(write_pointer'LEFT-1 downto 0) = read_pointer(read_pointer'LEFT-1 downto 0) ) OR
                              wrusedw >= 8) else '1';

s_axis_tready <= s_axis_tready_reg;

m_axis_tvalid <= m_axis_tvalid_reg;

m_axis_tdata <= m_axis_tdata_reg;

m_axis_tkeep <= (others=>'1');

m_axis_tlast <= '1';




   
   
   

end architecture rtl;
