-- ----------------------------------------------------------------------------
-- FILE:          data2packets_fsm.vhd
-- DESCRIPTION:   Forms packets with provided header
-- DATE:          10:11 2024-05-24
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
entity data2packets_fsm is
   port (
      aclk                 : in  std_logic;
      areset_n             : in  std_logic;
      
      pct_size             : in  std_logic_vector(15 downto 0); -- Packet size
      pct_hdr_0            : in  std_logic_vector(63 downto 0);
      pct_hdr_1            : in  std_logic_vector(63 downto 0);
      --AXIS Slave
      s_axis_tvalid        : in  std_logic;
      s_axis_tready        : out std_logic;
      s_axis_tdata         : in  std_logic_vector(127 downto 0);
      s_axis_tlast         : in  std_logic;
      --AXIS Master 
      m_axis_tvalid        : out std_logic;
      m_axis_tready        : in  std_logic;
      m_axis_tdata         : out std_logic_vector(127 downto 0);
      m_axis_tlast         : out std_logic;
      --Misc
      wr_data_count_axis   : in  std_logic_vector(8 downto 0)
      
   );
end data2packets_fsm;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of data2packets_fsm is
--declare signals,  components here

type state_type is (idle, drop_samples, wr_header, wr_payload, pct_end);
signal current_state, next_state : state_type;

signal space_required : unsigned(15 downto 0);

constant max_buffer_words : unsigned(15 downto 0) := x"0200";

signal s_axis_tready_reg   : std_logic;

signal m_axis_tvalid_reg   : std_logic;
signal m_axis_tdata_reg    : std_logic_vector(m_axis_tdata'LENGTH-1 downto 0);
signal m_axis_tlast_reg    : std_logic;


signal pct_wrcnt           : unsigned(15 downto 0);


begin


   process (aclk, areset_n) begin
      if(areset_n = '0')then
         space_required <= (others=>'0');
      elsif rising_edge(aclk) then 
         space_required <= unsigned(wr_data_count_axis) + unsigned(pct_size);
      end if;	
   end process;

-- ----------------------------------------------------------------------------
-- State machine
-- ----------------------------------------------------------------------------
   fsm_f : process (aclk, areset_n) begin
      if(areset_n = '0')then
         current_state <= idle;
      elsif rising_edge(aclk) then 
         current_state <= next_state;
      end if;	
   end process;

-- ----------------------------------------------------------------------------
-- state machine combo
-- ----------------------------------------------------------------------------
   fsm : process(all) begin
      next_state <= current_state;
      case current_state is
      
         when idle => -- state
         if s_axis_tvalid = '1' then
            if space_required >= max_buffer_words then 
               next_state <= drop_samples;
            else
               next_state <= wr_header;
            end if;
         else
            next_state <= idle;
         end if;
         
         -- Droping samples until there is enough space in buffer and making sure that whole frame of bit packed samples are droped.
         when drop_samples =>
            if space_required <= max_buffer_words  AND s_axis_tlast = '1' then 
               next_state <= idle;
            else 
               next_state <= drop_samples;
            end if;
            
            
         when wr_header =>
            next_state <= wr_payload;

         when wr_payload =>
            if pct_wrcnt < unsigned(pct_size) then 
               next_state <= wr_payload;
            else 
               next_state <= pct_end;
            end if;
         
         when pct_end =>
            next_state <= idle;
         
         when others => 
            next_state <= idle;
            
            
      end case;
   end process;


   process (aclk, areset_n) begin
      if(areset_n = '0')then
         m_axis_tvalid_reg <= '0';
      elsif rising_edge(aclk) then 
         if current_state = wr_header OR (current_state = wr_payload AND s_axis_tvalid='1' AND s_axis_tready_reg='1') then 
            m_axis_tvalid_reg <= '1';
         else 
            m_axis_tvalid_reg <= '0';
         end if;
      end if;	
   end process;
   
   process (aclk, areset_n) begin
      if(areset_n = '0')then
         s_axis_tready_reg <= '0';
      elsif rising_edge(aclk) then 
         if (current_state = wr_payload AND m_axis_tready = '1' AND pct_wrcnt = 1) OR current_state = drop_samples then 
            s_axis_tready_reg <= '1';
         elsif current_state = wr_payload AND s_axis_tvalid='1' AND s_axis_tready_reg='1' AND pct_wrcnt=unsigned(pct_size) -1 then
            s_axis_tready_reg <= '0';
         else 
            s_axis_tready_reg <= s_axis_tready_reg;
         end if;
      end if;	
   end process;
   
   process (aclk, areset_n) begin
      if(areset_n = '0')then
         pct_wrcnt <= (others=>'0');
      elsif rising_edge(aclk) then 
         if current_state = wr_header OR (current_state = wr_payload AND s_axis_tvalid='1' AND s_axis_tready_reg='1') then 
            pct_wrcnt <= pct_wrcnt + 1;
         elsif current_state = pct_end then 
            pct_wrcnt <= (others=>'0');
         else 
            pct_wrcnt <= pct_wrcnt;
         end if;
      end if;	
   end process;
   
   
   process (aclk, areset_n) begin
      if(areset_n = '0')then
         m_axis_tlast_reg <= '0';
      elsif rising_edge(aclk) then 
         if current_state = wr_payload AND pct_wrcnt=unsigned(pct_size) -1 then 
            m_axis_tlast_reg <= '1';
         else 
            m_axis_tlast_reg <= '0';
         end if;
      end if;	
   end process;
   
   process (aclk, areset_n) begin
      if(areset_n = '0')then
         m_axis_tdata_reg  <= (others=>'0');
      elsif rising_edge(aclk) then 
         if current_state = wr_header then 
            m_axis_tdata_reg <= pct_hdr_1 & pct_hdr_0;
         elsif current_state = wr_payload AND s_axis_tvalid = '1' AND s_axis_tready_reg = '1' then 
            m_axis_tdata_reg <= s_axis_tdata;
         else
            m_axis_tdata_reg <= m_axis_tdata_reg;
         end if;
      end if;	
   end process;
   
   
   
   
   
   
   
   
-- ----------------------------------------------------------------------------
-- Output ports
-- ---------------------------------------------------------------------------- 
s_axis_tready <= s_axis_tready_reg;

m_axis_tvalid <= m_axis_tvalid_reg;
m_axis_tdata  <= m_axis_tdata_reg;
m_axis_tlast  <= m_axis_tlast_reg;

  
end arch;   


