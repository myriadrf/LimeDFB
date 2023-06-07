-- ----------------------------------------------------------------------------
-- FILE:          ctrl_pkt.vhd
-- DESCRIPTION:   Packs control data into ctrl packet. 
-- DATE:          09:48 2023-05-05
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
-- Packet structure:
--    HEADER[127:0] DATA[511:0]
-- Header structure:
--    HEADER[ 7: 0]  - Packet type: 0x0 - Control, 0x1 - Data
--    HEADER[15: 8]  - Reserver
--    HEADER[47:16]  - Byte count including header

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity ctrl_pkt is
   generic(
      g_PKT_HEADER_WIDTH   : integer := 128;
      g_CTRL_DWIDTH        : integer := 512;
      g_AXIS_DWIDTH        : integer := 128
   );
   port (
      clk            : in  std_logic;
      reset_n        : in  std_logic;
      ctrl_data      : in  std_logic_vector(g_CTRL_DWIDTH-1 downto 0);
      ctrl_valid     : in  std_logic;
      ctrl_ready     : out std_logic;
      m_axis_tdata   : out std_logic_vector(g_AXIS_DWIDTH-1 downto 0);
      m_axis_tlast   : out std_logic;
      m_axis_tready  : in  std_logic;
      m_axis_tvalid  : out std_logic
      
   );
end ctrl_pkt;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of ctrl_pkt is
--declare signals,  components here
signal pkt_reg       : std_logic_vector(g_CTRL_DWIDTH+g_PKT_HEADER_WIDTH-1 downto 0); 
alias pkt_type       : std_logic_vector( 7 downto 0) is pkt_reg( 7 downto  0);
alias pkt_byte_cnt   : std_logic_vector(31 downto 0) is pkt_reg(47 downto 16);
alias pkt_data       : std_logic_vector(g_CTRL_DWIDTH-1 downto 0) is pkt_reg(639 downto 128);

constant c_MAX_TVALID_CNT  : integer := (g_PKT_HEADER_WIDTH + g_CTRL_DWIDTH)/g_AXIS_DWIDTH;

signal tvalid_cnt : unsigned(3 downto 0);

signal m_axis_tvalid_reg   : std_logic;
signal m_axis_tlast_reg    : std_logic;

signal ctrl_ready_reg      : std_logic;

attribute MARK_DEBUG : string;
attribute MARK_DEBUG of reset_n       : signal is "TRUE";      
attribute MARK_DEBUG of ctrl_data     : signal is "TRUE";
attribute MARK_DEBUG of ctrl_valid    : signal is "TRUE";
attribute MARK_DEBUG of ctrl_ready    : signal is "TRUE";
attribute MARK_DEBUG of m_axis_tdata  : signal is "TRUE";
attribute MARK_DEBUG of m_axis_tlast  : signal is "TRUE";
attribute MARK_DEBUG of m_axis_tready : signal is "TRUE";
attribute MARK_DEBUG of m_axis_tvalid : signal is "TRUE";



begin

   -- capture ctrl_data and shift right in axis slave is ready
   process(reset_n, clk)
      begin
         if reset_n = '0' then
            pkt_reg <= (others=>'0');  
         elsif (clk'event and clk = '1') then
            if ctrl_valid = '1' AND ctrl_ready_reg = '1' then
               pkt_reg        <= (others=>'0');
               -- Assign to pkt_reg aliases
               pkt_type       <= x"00";         -- ctrl packet type
               pkt_byte_cnt   <= x"00000050";   -- 80 bytes
               pkt_data       <= ctrl_data;     -- 64 bytes of data
            elsif m_axis_tready = '1' then
               -- shifting right if axis is ready
               pkt_reg <= x"00000000000000000000000000000000" & pkt_reg(639 downto 128);
            end if; 
         end if;
   end process;
   
   -- tvalid counter
   process(reset_n, clk)
   begin
      if reset_n = '0' then
         tvalid_cnt <= (others=>'0');
      elsif rising_edge(clk) then 
         if ctrl_valid = '1' AND ctrl_ready_reg = '1' then 
            tvalid_cnt <= to_unsigned(c_MAX_TVALID_CNT-1, tvalid_cnt'length);
         elsif tvalid_cnt > 0 AND m_axis_tready = '1' then 
            tvalid_cnt <= tvalid_cnt - 1;
         else 
            tvalid_cnt <= tvalid_cnt;
         end if;
      end if;
   end process;
   
   --axis tvalid signal
   process(reset_n, clk)
   begin
      if reset_n = '0' then
         m_axis_tvalid_reg <= '0';
      elsif rising_edge(clk) then 
         if ctrl_valid = '1'  OR tvalid_cnt > 0 then 
            m_axis_tvalid_reg <= '1';
         elsif tvalid_cnt = 0 AND m_axis_tready = '1' then 
            m_axis_tvalid_reg <= '0';
         else 
            m_axis_tvalid_reg <= m_axis_tvalid_reg;
         end if;
      end if;
   end process;
   
   --axis tlast signal
   process(reset_n, clk)
   begin
      if reset_n = '0' then
         m_axis_tlast_reg <= '0';
      elsif rising_edge(clk) then 
         if tvalid_cnt = 1 AND m_axis_tready = '1'then 
            m_axis_tlast_reg <= '1';
         elsif tvalid_cnt = 0 AND m_axis_tready = '1' then 
            m_axis_tlast_reg <= '0';
         else 
            m_axis_tlast_reg <= m_axis_tlast_reg;
         end if;
      end if;
   end process;
   
   process(reset_n, clk)
   begin
      if reset_n = '0' then
         ctrl_ready_reg <= '1';
      elsif rising_edge(clk) then 
         if ctrl_valid = '1' AND ctrl_ready_reg ='1' then 
            ctrl_ready_reg <= '0';
         elsif m_axis_tlast_reg = '1' AND  m_axis_tready ='1' then 
            ctrl_ready_reg <= '1';
         else 
            ctrl_ready_reg <= ctrl_ready_reg;
         end if;
      end if;
   end process;
   
   
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------
   m_axis_tdata   <= pkt_reg(g_AXIS_DWIDTH-1 downto 0); 
   m_axis_tvalid  <= m_axis_tvalid_reg;
   m_axis_tlast   <= m_axis_tlast_reg;
   
   ctrl_ready     <= ctrl_ready_reg;

  
end arch;   


