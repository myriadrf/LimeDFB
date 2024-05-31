-- ----------------------------------------------------------------------------
-- FILE:          axis_nto1_converter.vhd
-- DESCRIPTION:   Converts AXIS stream bus to specified ratio
-- DATE:          10:53 2024-05-23
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- This module works in AXIS packet mode.
-- e.g. if g_N_RATIO=2, and g_DATA_WIDTH=64 this module expects four 64bit words
-- and outputs two 128bit words.
-- Same with tlast - expects two tlast and outputs one.

-- s_axis interfaface is always ready to accept data thus s_axis_tready is connected 
-- to reset_n
--
-- m_axis interface is unable to accept-backpressure. There is no need for it as 
-- this module is designed for continous data stream
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity axis_nto1_converter is
   generic(
      g_N_RATIO      : integer := 2; -- Available values - 2, 4, 8
      g_DATA_WIDTH   : integer := 64 -- AXIS Slave data width
   );
   port (
      aclk           : in  std_logic;
      areset_n       : in  std_logic;
      --AXIS Slave
      s_axis_tvalid  : in  std_logic;
      s_axis_tready  : out std_logic;
      s_axis_tdata   : in  std_logic_vector(g_DATA_WIDTH-1 downto 0);
      s_axis_tlast   : in  std_logic;
      --AXIS Master 
      m_axis_tvalid  : out std_logic;
      m_axis_tdata   : out std_logic_vector(g_DATA_WIDTH*g_N_RATIO-1 downto 0);
      m_axis_tlast   : out std_logic
   );
end axis_nto1_converter;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of axis_nto1_converter is
--declare signals,  components here
type t_DATA_REG_ARRAY_TYPE is array (0 to g_N_RATIO-1) of std_logic_vector( s_axis_tdata'LENGTH-1 downto 0);

signal data_reg_array : t_DATA_REG_ARRAY_TYPE;

signal s_axis_tready_reg : std_logic;

signal s_axis_tvalid_cnt : unsigned(3 downto 0);
signal s_axis_tlast_cnt  : unsigned(3 downto 0);

signal m_axis_tvalid_reg : std_logic;
signal m_axis_tlast_reg  : std_logic;

begin

   process(aclk, areset_n)
   begin 
      if areset_n = '0' then 
         s_axis_tvalid_cnt <= (others=>'0');
      elsif rising_edge(aclk) then
         if s_axis_tready_reg = '1' AND s_axis_tvalid = '1' then
            if s_axis_tvalid_cnt < g_N_RATIO-1 then 
               s_axis_tvalid_cnt <= s_axis_tvalid_cnt + 1;
            else 
               s_axis_tvalid_cnt <= (others=>'0');
            end if;
         else
            s_axis_tvalid_cnt <= s_axis_tvalid_cnt;
         end if;
      end if;
   end process;
   
   
   process(aclk, areset_n)
   begin 
      if areset_n = '0' then 
         s_axis_tlast_cnt <= (others=>'0');
      elsif rising_edge(aclk) then
         if s_axis_tready_reg = '1' AND s_axis_tvalid = '1' AND s_axis_tlast ='1' then
            if s_axis_tlast_cnt < g_N_RATIO-1 then 
               s_axis_tlast_cnt <= s_axis_tlast_cnt + 1;
            else 
               s_axis_tlast_cnt <= (others=>'0');
            end if;
         elsif m_axis_tvalid_reg='1' AND m_axis_tlast_reg = '1' then 
            s_axis_tlast_cnt <= (others=>'0');
         else
            s_axis_tlast_cnt <= s_axis_tlast_cnt;
         end if;
         

      end if;
   end process;

   process(aclk, areset_n)
   begin 
      if areset_n = '0' then 
         data_reg_array <= (others=>(others=>'0'));
      elsif rising_edge(aclk) then
         if s_axis_tready_reg = '1' AND s_axis_tvalid = '1' then
            data_reg_array(1) <=  data_reg_array(0);        
            data_reg_array(0) <=  s_axis_tdata;
         else
            data_reg_array <= data_reg_array;
         end if;
      end if;
   end process;
   
   
   process(aclk, areset_n)
   begin 
      if areset_n = '0' then 
         m_axis_tvalid_reg <= '0';
         m_axis_tlast_reg  <= '0';
      elsif rising_edge(aclk) then
      
         if s_axis_tready_reg = '1' AND s_axis_tvalid = '1' AND s_axis_tvalid_cnt = g_N_RATIO-1 then
            m_axis_tvalid_reg <= '1';
         else
            m_axis_tvalid_reg <= '0';
         end if;
         
         if s_axis_tready_reg = '1' AND s_axis_tvalid = '1' AND s_axis_tlast='1' AND s_axis_tlast_cnt = g_N_RATIO-1 then
            m_axis_tlast_reg <= '1';
         else
            m_axis_tlast_reg <= '0';
         end if;
         
         
      end if;
   end process;
   
   process(aclk, areset_n)
   begin
      if areset_n = '0' then 
         s_axis_tready_reg<= '0';
      elsif rising_edge(aclk) then 
         s_axis_tready_reg <= '1';
      end if;
   end process;

s_axis_tready <= s_axis_tready_reg;


m_axis_tvalid <= m_axis_tvalid_reg;
m_axis_tdata  <= data_reg_array(1) & data_reg_array(0);
m_axis_tlast  <= m_axis_tlast_reg;

  
end arch;   


