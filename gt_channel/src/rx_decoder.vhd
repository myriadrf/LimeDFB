-- ----------------------------------------------------------------------------
-- FILE:          rx_decoder.vhd
-- DESCRIPTION:   AXIS slave accepts control and data packets and unpacks them
-- DATE:          10:03 2023-05-12
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- There is no flow control in this module. Accept all incomming data or loose it 
-- Cannot introduce any back-pressure.
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity rx_decoder is
   generic(
      g_PKT_HEADER_WIDTH   : integer := 128;
      g_S_AXIS_DWIDTH      : integer := 128;
      g_M_AXIS_DWIDTH      : integer := 128
   );
   port (
      clk               : in  std_logic;
      reset_n           : in  std_logic;
      --general data bus
      m_axis_0_tvalid   : out std_logic;
      m_axis_0_tready   : in  std_logic;
      m_axis_0_tdata    : out std_logic_vector(g_M_AXIS_DWIDTH-1 downto 0);
      m_axis_0_tlast    : out std_logic;
      --AXI stream slave
      m_axis_1_tvalid   : out std_logic;
      m_axis_1_tready   : in  std_logic;
      m_axis_1_tdata    : out std_logic_vector(g_M_AXIS_DWIDTH-1 downto 0);
      m_axis_1_tlast    : out std_logic;
      --AXI stream master
      s_axis_tvalid     : in  std_logic; 
      s_axis_tready     : out std_logic;
      s_axis_tdata      : in  std_logic_vector(g_S_AXIS_DWIDTH-1 downto 0);
      s_axis_tlast      : in  std_logic
   );
end rx_decoder;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of rx_decoder is
--declare signals,  components here

signal rec_hdr             : std_logic;
signal rec_ctrl_packet     : std_logic;
signal rec_data_packet     : std_logic;

signal m_axis_0_tvalid_reg : std_logic;
signal m_axis_0_tdata_reg  : std_logic_vector(g_M_AXIS_DWIDTH-1 downto 0);
signal m_axis_0_tlast_reg  : std_logic;

signal m_axis_1_tvalid_reg : std_logic;
signal m_axis_1_tdata_reg  : std_logic_vector(g_M_AXIS_DWIDTH-1 downto 0);
signal m_axis_1_tlast_reg  : std_logic;


signal s_axis_tready_reg   : std_logic;
signal s_axis_valid_write  : std_logic;


begin
   
   s_axis_valid_write   <= s_axis_tvalid AND s_axis_tready_reg;


   process (clk, reset_n)
   begin 
      if reset_n = '0' then 
         s_axis_tready_reg <= '0';
      elsif rising_edge(clk) then 
         s_axis_tready_reg <= '1';
      end if;
   end process;

   process (clk, reset_n)
   begin 
      if reset_n = '0' then 
         rec_hdr <= '0';
      elsif rising_edge(clk) then 
         if s_axis_valid_write = '1' AND s_axis_tlast ='0' then 
            rec_hdr <= '1';
         elsif s_axis_valid_write = '1' AND s_axis_tlast ='1' then 
            rec_hdr <= '0';
         else 
            rec_hdr <= rec_hdr;
         end if;
      end if;
   end process;
   
   
   process (clk, reset_n)
   begin 
   if reset_n = '0' then 
      rec_ctrl_packet <= '0';
      rec_data_packet <= '0';
   elsif rising_edge(clk) then 
      if s_axis_valid_write = '1' AND rec_hdr ='0' then 
         if s_axis_tdata = x"55AA0000000000000000000000500002" then
            rec_ctrl_packet <= '1';
            rec_data_packet <= '0';
         elsif s_axis_tdata = x"AA550000000000000000000000000001" then
            rec_ctrl_packet <= '0';
            rec_data_packet <= '1';
         else 
            rec_ctrl_packet <= rec_ctrl_packet;
            rec_data_packet <= rec_data_packet;
         end if;
      elsif s_axis_valid_write = '1' AND s_axis_tlast ='1' then 
         rec_ctrl_packet <= '0';
         rec_data_packet <= '0';
      else 
         rec_ctrl_packet <= rec_ctrl_packet;
         rec_data_packet <= rec_data_packet;
      end if;
   end if;
   end process;
   
   
   --axis tdata
   process (clk, reset_n)
   begin 
      if reset_n = '0' then
         m_axis_0_tdata_reg <= (others=>'0');
         m_axis_1_tdata_reg <= (others=>'0');
      elsif rising_edge(clk) then
         -- axis 0
         if rec_ctrl_packet ='1' AND s_axis_valid_write = '1' then 
            m_axis_0_tdata_reg <= s_axis_tdata; 
         else 
            m_axis_0_tdata_reg <=(others=>'0');
         end if;
         
         --axis 1
         if rec_data_packet ='1' AND s_axis_valid_write = '1' then 
            m_axis_1_tdata_reg <= s_axis_tdata;
         else
            m_axis_1_tdata_reg <= (others=>'0');
         end if;
         
      end if;
   end process;
   
   --axis tvalid
   process (clk, reset_n)
   begin 
      if reset_n = '0' then 
         m_axis_0_tvalid_reg <= '0';
         m_axis_1_tvalid_reg <= '0';
      elsif rising_edge(clk) then 
      
         if rec_ctrl_packet ='1' AND s_axis_valid_write = '1' then 
            m_axis_0_tvalid_reg <= '1';
         else 
            m_axis_0_tvalid_reg <= '0';
         end if;
         
         if rec_data_packet ='1' AND s_axis_valid_write = '1' then 
            m_axis_1_tvalid_reg <= '1';
         else 
            m_axis_1_tvalid_reg <= '0';
         end if;

      end if;
   end process;
   
   --axis tlast
   process (clk, reset_n)
   begin 
      if reset_n = '0' then 
         m_axis_0_tlast_reg <= '0';
         m_axis_1_tlast_reg <= '0';
      elsif rising_edge(clk) then 
      
         if rec_ctrl_packet ='1' AND s_axis_valid_write = '1' AND s_axis_tlast = '1' then 
            m_axis_0_tlast_reg <= '1';
         else 
            m_axis_0_tlast_reg <= '0';
         end if;
         
         if rec_data_packet ='1' AND s_axis_valid_write = '1' AND s_axis_tlast = '1' then 
            m_axis_1_tlast_reg <= '1';
         else 
            m_axis_1_tlast_reg <= '0';
         end if;

      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------   
   m_axis_0_tvalid   <= m_axis_0_tvalid_reg;
   m_axis_0_tdata    <= m_axis_0_tdata_reg;
   m_axis_0_tlast    <= m_axis_0_tlast_reg;
   
   
   m_axis_1_tvalid   <= m_axis_1_tvalid_reg;
   m_axis_1_tdata    <= m_axis_1_tdata_reg;
   m_axis_1_tlast    <= m_axis_1_tlast_reg;
   
   s_axis_tready     <= s_axis_tready_reg;
   


  
end arch;   


