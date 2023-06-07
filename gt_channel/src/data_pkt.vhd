-- ----------------------------------------------------------------------------
-- FILE:          my_module.vhd
-- DESCRIPTION:   describe file
-- DATE:          Jan 27, 2016
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
entity data_pkt is
   generic(
      g_PKT_HEADER_WIDTH      : integer := 128;
      g_GEN_INTERNAL_TLAST    : string  := "True";
      g_INTERNAL_TLAST_PERIOD : integer := 256;
      g_AXIS_DWIDTH           : integer := 128
   );
   port (
      clk                  : in  std_logic;
      reset_n              : in  std_logic;
      s_axis_tdata         : in  std_logic_vector(g_AXIS_DWIDTH-1 downto 0);
      s_axis_tlast         : in  std_logic;
      s_axis_tready        : out std_logic;
      s_axis_tvalid        : in  std_logic;
      m_axis_tdata         : out std_logic_vector(g_AXIS_DWIDTH-1 downto 0);
      m_axis_tlast         : out std_logic;
      m_axis_tready        : in  std_logic;
      m_axis_tvalid        : out std_logic
      
   );
end data_pkt;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of data_pkt is
--declare signals,  components here
type t_TDATA_ARRAY is array (0 to 1) of std_logic_vector (g_AXIS_DWIDTH-1 downto 0);
signal tdata_reg : t_TDATA_ARRAY;

type state_type is (idle, wr_header, wr_data);
signal current_state, next_state : state_type;


signal m_axis_tlast_reg    : std_logic;
signal s_axis_tready_reg   : std_logic;
signal s_axis_valid_write  : std_logic;

signal m_axis_tvalid_reg   : std_logic;
signal m_axis_valid_write  : std_logic;

signal s_axi_wr_cnt        : unsigned(7 downto 0);

signal pending_slave_write_cnt : unsigned(3 downto 0);

signal pending_write       : std_logic;

signal last_word     : std_logic;




begin


   s_axis_valid_write <= s_axis_tvalid       AND s_axis_tready_reg;
   m_axis_valid_write <= m_axis_tvalid_reg   AND m_axis_tready;

   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         s_axi_wr_cnt <= (others=>'0');
      elsif rising_edge(clk) then
         if s_axis_valid_write = '1' then
            if s_axi_wr_cnt < g_INTERNAL_TLAST_PERIOD AND s_axis_tlast = '0' then 
               s_axi_wr_cnt <= s_axi_wr_cnt + 1;
            else 
               s_axi_wr_cnt <= (others=>'0');
            end if;   
         else 
            s_axi_wr_cnt <= s_axi_wr_cnt;
         end if;
      end if;
   end process;
   

   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         tdata_reg(0) <= x"AA550000000000000000000000000001";
         tdata_reg(1) <= (others=>'0');
      elsif rising_edge(clk) then
         if s_axis_valid_write = '1' then 
            tdata_reg(0) <= s_axis_tdata;
            tdata_reg(1) <= tdata_reg(0);
         elsif m_axis_valid_write = '1' AND last_word = '1' then 
            tdata_reg(0) <= x"AA550000000000000000000000000001";
            tdata_reg(1) <= tdata_reg(0);
         else 
            tdata_reg <= tdata_reg;
         end if;
      end if;
   end process;

   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         pending_write <= '0';
      elsif rising_edge(clk) then
         if s_axis_valid_write = '1' then 
            pending_write <= '1';
         elsif s_axis_valid_write = '0' AND m_axis_valid_write = '1' then 
            pending_write <= '0';
         else 
            pending_write <= pending_write;
         end if;
      end if;
   end process;
   
   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         pending_slave_write_cnt <= (others=>'0');
      elsif rising_edge(clk) then
         if s_axis_valid_write = '1' AND m_axis_valid_write = '0' then 
            pending_slave_write_cnt <= pending_slave_write_cnt + 1;
         elsif s_axis_valid_write = '0' AND m_axis_valid_write = '1' then 
            pending_slave_write_cnt <= pending_slave_write_cnt - 1;
         else 
            pending_slave_write_cnt <= pending_slave_write_cnt;
         end if;
      end if;
   end process;
   
   INTERNAL_TLAST : if g_GEN_INTERNAL_TLAST = "True" generate 
      process(clk, reset_n)
      begin
         if(reset_n = '0')then
            last_word <= '0';
         elsif rising_edge(clk) then
            if s_axis_valid_write = '1' AND (s_axis_tlast = '1' OR s_axi_wr_cnt = g_INTERNAL_TLAST_PERIOD-1) then 
               last_word <= '1';
            elsif m_axis_valid_write = '1' AND last_word = '1' then 
               last_word <= '0';
            else 
               last_word <= last_word;
            end if;
         end if;
      end process;
   end generate INTERNAL_TLAST;
   
   EXTERNAL_TLAST : if g_GEN_INTERNAL_TLAST = "False" generate 
      process(clk, reset_n)
      begin
         if(reset_n = '0')then
            last_word <= '0';
         elsif rising_edge(clk) then
            if s_axis_valid_write = '1' AND s_axis_tlast = '1' then 
               last_word <= '1';
            elsif m_axis_valid_write = '1' AND last_word = '1' then 
               last_word <= '0';
            else 
               last_word <= last_word;
            end if;
         end if;
      end process;
   end generate EXTERNAL_TLAST;
   
   
   
   
   
   s_axis_tready_reg <= m_axis_tready AND NOT last_word;
   m_axis_tvalid_reg <= s_axis_tvalid OR last_word;
   
   
   
   
   
   
   
     
   
   
   
   
   m_axis_tlast_reg  <= last_word;




   s_axis_tready <= s_axis_tready_reg;

   m_axis_tlast    <= m_axis_tlast_reg;
   m_axis_tvalid   <= m_axis_tvalid_reg;
   m_axis_tdata    <= tdata_reg(0);

  
end arch;   


