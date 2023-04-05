-- ----------------------------------------------------------------------------
-- FILE:          m_to_axi_lite.vhd
-- DESCRIPTION:   Converts general data stream to AXI lite master
-- DATE:          10:43 2023-03-30
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- AXI4-Lite interface uses byte addresing
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity m_to_axi_lite is
   generic(
      g_DATA_WIDTH            : integer := 512; -- Has to be multiple of g_AXI_LITE_DATA_WIDTH
      g_AXI_LITE_DATA_WIDTH   : integer := 32;  -- 32 or 64
      g_AXI_LITE_ADDR_WIDTH   : integer := 32;
      g_AXI_LITE_PROT_WIDTH   : integer := 2;
      g_AXI_LITE_STB_WIDTH    : integer := 4;
      g_AXI_LITE_RESP_WIDTH   : integer := 2
   );
   port (
      clk      : in std_logic;
      reset_n  : in std_logic;
      
      --General data interface
      reader_data_valid    : out std_logic;
      reader_data          : out std_logic_vector(g_DATA_WIDTH-1 downto 0);
      writer_data_valid    : in  std_logic;
      writer_data          : in  std_logic_vector(g_DATA_WIDTH-1 downto 0);
      -- AXI4 lite master interface
      m_axi_lite_awaddr    : out std_logic_vector(g_AXI_LITE_ADDR_WIDTH-1 downto 0);
      m_axi_lite_awprot    : out std_logic_vector(g_AXI_LITE_PROT_WIDTH-1 downto 0);
      m_axi_lite_awvalid   : out std_logic;
      m_axi_lite_awready   : in  std_logic;
      m_axi_lite_wdata     : out std_logic_vector(g_AXI_LITE_DATA_WIDTH-1 downto 0);
      m_axi_lite_wstrb     : out std_logic_vector(g_AXI_LITE_STB_WIDTH-1 downto 0);
      m_axi_lite_wvalid    : out std_logic;
      m_axi_lite_wready    : in  std_logic;
      m_axi_lite_bresp     : in  std_logic_vector(g_AXI_LITE_RESP_WIDTH-1 downto 0);
      m_axi_lite_bvalid    : in  std_logic;
      m_axi_lite_bready    : out std_logic;
      m_axi_lite_araddr    : out std_logic_vector(g_AXI_LITE_ADDR_WIDTH-1 downto 0);
      m_axi_lite_arprot    : out std_logic_vector(g_AXI_LITE_PROT_WIDTH-1 downto 0);
      m_axi_lite_arvalid   : out std_logic;
      m_axi_lite_arready   : in  std_logic;
      m_axi_lite_rdata     : in  std_logic_vector(g_AXI_LITE_DATA_WIDTH-1 downto 0);
      m_axi_lite_rresp     : in  std_logic_vector(g_AXI_LITE_RESP_WIDTH-1 downto 0);
      m_axi_lite_rvalid    : in  std_logic;
      m_axi_lite_rready    : out std_logic
   );
end m_to_axi_lite;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of m_to_axi_lite is
--declare signals,  components here

constant c_AXI_TRANSACTIONS : integer := g_DATA_WIDTH/g_AXI_LITE_DATA_WIDTH;
constant c_BYTES_IN_AXI_DATA: integer := g_AXI_LITE_DATA_WIDTH/8;

signal writer_data_valid_reg : std_logic; 

signal axi_write_cnt : unsigned(7 downto 0);
signal axi_read_cnt  : unsigned(7 downto 0);

type state_type is (idle, axi_write_addr, axi_write, axi_write_resp, axi_read_addr, axi_read, axi_read_resp, axi_read_done);
signal current_state, next_state : state_type;

signal writer_data_reg  : std_logic_vector(g_DATA_WIDTH-1 downto 0);
signal reader_data_reg  : std_logic_vector(g_DATA_WIDTH-1 downto 0);
signal zeros            : std_logic_vector(g_AXI_LITE_DATA_WIDTH-1 downto 0) := (others=>'0');


signal m_axi_lite_awaddr_reg : unsigned(g_AXI_LITE_ADDR_WIDTH-1 downto 0);
signal m_axi_lite_araddr_reg : unsigned(g_AXI_LITE_ADDR_WIDTH-1 downto 0);

  
begin


   process(reset_n, clk)
   begin
      if reset_n='0' then
         writer_data_valid_reg <= '0';  
      elsif (clk'event and clk = '1') then
         writer_data_valid_reg <= writer_data_valid;
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- state machine
-- ----------------------------------------------------------------------------
   fsm_f : process(clk, reset_n)
   begin
      if(reset_n = '0')then
         current_state <= idle;
      elsif(clk'event and clk = '1')then
         current_state <= next_state;
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- state machine combo
-- ----------------------------------------------------------------------------
fsm : process(all) begin
   next_state <= current_state;
   case current_state is
      -- Wait for risign edge of writer data valid signal
      when idle => 
         if writer_data_valid = '1' AND writer_data_valid_reg = '0' then 
            next_state <= axi_write_addr;
         else 
            next_state <= idle;
         end if;
      
      -- Set address
      when axi_write_addr => 
         if m_axi_lite_awready = '1' then 
            next_state <= axi_write;
         else 
            next_state <= axi_write_addr;
         end if;
         
      -- Write value
      when axi_write => 
         if m_axi_lite_wready = '1' then
            next_state <= axi_write_resp;
         else 
            next_state <= axi_write;
         end if;
         
      -- Handshake done, wait for write response
      when axi_write_resp => 
         if m_axi_lite_bvalid = '1' then 
            -- Repeat write proccess untill we write all 
            if axi_write_cnt < c_AXI_TRANSACTIONS then 
               next_state <= axi_write_addr;
            else 
               next_state <= axi_read_addr;
            end if;
         else 
            next_state <= axi_write_resp;
         end if;
         
      when axi_read_addr => 
         if m_axi_lite_arready = '1' then 
            next_state <= axi_read;
         else 
            next_state <= axi_read_addr;
         end if;
         
      -- Read word
      when axi_read => 
         if m_axi_lite_rvalid = '1' then
            if axi_read_cnt < c_AXI_TRANSACTIONS-1 then 
               next_state <= axi_read_addr;
            else 
               next_state <= axi_read_done;
            end if;
         else 
            next_state <= axi_read;
         end if;
         
      when axi_read_done => 
         next_state <= idle;
         
      when others => 
   end case;
end process;


-- ----------------------------------------------------------------------------
-- Write logic
-- ----------------------------------------------------------------------------
   process (current_state)
   begin 
      if current_state = axi_write_addr then 
         m_axi_lite_awvalid <= '1';
      else 
         m_axi_lite_awvalid <= '0';
      end if;
      
      if current_state = axi_write then 
         m_axi_lite_wvalid <= '1';
      else 
         m_axi_lite_wvalid <= '0';
      end if;
      
      if current_state = axi_write_resp OR current_state = axi_read_resp then 
         m_axi_lite_bready <= '1'; 
      else 
         m_axi_lite_bready <= '0';
      end if; 
   end process;

   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         axi_write_cnt           <= (others=>'0');
         m_axi_lite_awaddr_reg   <= (others=>'0');
      elsif(clk'event and clk = '1')then
         if m_axi_lite_wready='1' AND current_state = axi_write then 
            axi_write_cnt           <= axi_write_cnt + 1;
            m_axi_lite_awaddr_reg   <= m_axi_lite_awaddr_reg + c_BYTES_IN_AXI_DATA;
         elsif current_state = idle then 
            axi_write_cnt           <= (others=>'0');
            m_axi_lite_awaddr_reg   <= (others=>'0');
         else 
            axi_write_cnt           <= axi_write_cnt;
            m_axi_lite_awaddr_reg   <= m_axi_lite_awaddr_reg;
         end if;
      end if;
   end process;
   
   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         writer_data_reg <= (others=>'0');
      elsif(clk'event and clk = '1')then
         
         if writer_data_valid = '1' AND writer_data_valid_reg = '0' then
            writer_data_reg <= writer_data;
         elsif m_axi_lite_wready='1' AND current_state = axi_write then 
            writer_data_reg <= writer_data_reg(g_DATA_WIDTH-g_AXI_LITE_DATA_WIDTH-1 downto 0) & zeros;
         else 
            writer_data_reg <= writer_data_reg;
         end if;
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- Read logic
-- ----------------------------------------------------------------------------   
   process (current_state)
   begin 
      if current_state = axi_read_addr then 
         m_axi_lite_arvalid <= '1';
      else 
         m_axi_lite_arvalid <= '0';
      end if;
      
      if current_state = axi_read then 
         m_axi_lite_rready <= '1';
      else
         m_axi_lite_rready <= '0';
      end if;
      
      if current_state = axi_read_done then 
         reader_data_valid <= '1'; 
      else 
         reader_data_valid <= '0'; 
      end if;
   end process;
   
   
   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         axi_read_cnt            <= (others=>'0');
         m_axi_lite_araddr_reg   <= (others=>'0');
      elsif(clk'event and clk = '1')then
         if m_axi_lite_rvalid='1' AND current_state = axi_read then 
            axi_read_cnt            <= axi_read_cnt + 1;
            m_axi_lite_araddr_reg   <= m_axi_lite_araddr_reg + c_BYTES_IN_AXI_DATA;
         elsif current_state = idle then 
            axi_read_cnt            <= (others=>'0');
            m_axi_lite_araddr_reg   <= (others=>'0');
         else 
            axi_read_cnt            <= axi_read_cnt;
            m_axi_lite_araddr_reg   <= m_axi_lite_araddr_reg;
         end if;
      end if;
   end process;
   
   
   process(clk, reset_n)
   begin
      if(reset_n = '0')then
         reader_data_reg <= (others=>'0');
      elsif(clk'event and clk = '1')then
         if m_axi_lite_rvalid='1' AND current_state = axi_read then 
            reader_data_reg <= reader_data_reg(g_DATA_WIDTH-g_AXI_LITE_DATA_WIDTH-1 downto 0) & m_axi_lite_rdata;
         else 
            reader_data_reg <= reader_data_reg;
         end if;
      end if;
   end process;
   
   m_axi_lite_wdata  <= writer_data_reg(g_DATA_WIDTH-1 downto g_DATA_WIDTH-g_AXI_LITE_DATA_WIDTH);
   m_axi_lite_awaddr <= std_logic_vector(m_axi_lite_awaddr_reg);
   
   m_axi_lite_araddr <= std_logic_vector(m_axi_lite_araddr_reg);
   
   reader_data <= reader_data_reg;
   
   m_axi_lite_wstrb  <= (others=>'1');
   m_axi_lite_awprot <= (others=>'0');
   
   
   
   


   
   
   
   
  
end arch;   


