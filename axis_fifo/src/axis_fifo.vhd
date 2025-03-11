-- ----------------------------------------------------------------------------
-- FILE:          axis_fifo.vhd
-- DESCRIPTION:   Vendor specific axis_fifo implementation 
-- DATE:          09:45 2023-05-15
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;

package axi_stream_fifo_pkg is 
   function log2ceil(x: integer) return integer;
end axi_stream_fifo_pkg;

package body axi_stream_fifo_pkg is
    function log2ceil(x: integer) return integer is
        variable res : integer := 0;
    begin
        while (2**res < x) loop
            res := res + 1;
        end loop;
        return res;
    end function;
end package body axi_stream_fifo_pkg;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.axi_stream_fifo_pkg.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity axis_fifo is
   generic (
      g_VENDOR      : string  := "GENERIC";  -- "GENERIC" or "XILINX"
      g_DATA_WIDTH  : integer := 128;
      g_FIFO_DEPTH  : integer := 256;
      g_PACKET_MODE : boolean := true
   );
   port (
      -- AXI Stream Write Interface
      s_axis_aclk    : in  std_logic;
      s_axis_aresetn : in  std_logic;
      s_axis_tdata   : in  std_logic_vector(g_DATA_WIDTH-1 downto 0);
      s_axis_tkeep   : in  std_logic_vector(g_DATA_WIDTH/8-1 downto 0);
      s_axis_tlast   : in  std_logic;
      s_axis_tvalid  : in  std_logic;
      s_axis_tready  : out std_logic;
      wrusedw        : out std_logic_vector(log2ceil(g_FIFO_DEPTH) downto 0);
      
      -- AXI Stream Read Interface
      m_axis_aclk    : in  std_logic;
      m_axis_aresetn : in  std_logic;
      m_axis_tdata   : out std_logic_vector(g_DATA_WIDTH-1 downto 0);
      m_axis_tkeep   : out std_logic_vector(g_DATA_WIDTH/8-1 downto 0);
      m_axis_tlast   : out std_logic;
      m_axis_tvalid  : out std_logic;
      m_axis_tready  : in  std_logic;
      rdusedw        : out std_logic_vector(log2ceil(g_FIFO_DEPTH) downto 0)
   );
end entity axis_fifo;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture rtl of axis_fifo is
    
   constant c_PTR_WIDTH : integer := log2ceil(g_FIFO_DEPTH);
   
   signal g_wptr_sync, g_rptr_sync : std_logic_vector(c_PTR_WIDTH downto 0);
   signal b_wptr, b_rptr           : std_logic_vector(c_PTR_WIDTH downto 0);
   signal g_wptr, g_rptr           : std_logic_vector(c_PTR_WIDTH downto 0);
   
   signal waddr, raddr  : std_logic_vector(c_PTR_WIDTH-1 downto 0);
   
   signal wr_en, rd_en  : std_logic;
   signal full, empty   : std_logic;

   signal wrusedw_sig   : std_logic_vector(log2ceil(g_FIFO_DEPTH) downto 0); 

   -- Packet write pointers
   signal pctwr_en       : std_logic;
   signal g_pctrptr_sync : std_logic_vector(c_PTR_WIDTH downto 0):=(others=>'0');
   signal b_pctwptr      : std_logic_vector(c_PTR_WIDTH downto 0);
   signal g_pctwptr      : std_logic_vector(c_PTR_WIDTH downto 0);
   
   signal pctwrusedw     : std_logic_vector(log2ceil(g_FIFO_DEPTH) downto 0);
   signal pctfull        : std_logic;

   -- Pct read pointers
   signal pctrd_en       : std_logic;
   signal g_pctwptr_sync : std_logic_vector(c_PTR_WIDTH downto 0):=(others=>'0');
   signal b_pctrptr      : std_logic_vector(c_PTR_WIDTH downto 0);
   signal g_pctrptr      : std_logic_vector(c_PTR_WIDTH downto 0);
   
   signal pctrdusedw     : std_logic_vector(log2ceil(g_FIFO_DEPTH) downto 0);
   signal pctempty       : std_logic;

   signal pct_overflow           : std_logic;
   signal pct_overflow_latch     : std_logic;
   signal pct_overflow_latch_d1  : std_logic;
   signal pct_overflow_rdsync: std_logic;
   
   signal fwft_valid    : std_logic;
   
   signal mem_dout       : std_logic_vector(g_DATA_WIDTH + g_DATA_WIDTH/8 downto 0);

   signal m_axis_tvalid_reg : std_logic;
   signal m_axis_tvalid_ack : std_logic;
   

   component wptr_handler
   generic (
      PTR_WIDTH : integer := 3
   );
   port ( 
      wclk        : in  std_logic;
      wrst_n      : in  std_logic;
      w_en        : in  std_logic;
      g_rptr_sync : in  std_logic_vector(PTR_WIDTH downto 0);
      b_wptr      : out std_logic_vector(PTR_WIDTH downto 0);
      g_wptr      : out std_logic_vector(PTR_WIDTH downto 0);
      usedw       : out std_logic_vector(PTR_WIDTH downto 0);
      full        : out std_logic
   );
   end component;
   
   component rptr_handler
   generic (
      PTR_WIDTH : integer := 3
   );
   port ( 
      rclk        : in  std_logic;
      rrst_n      : in  std_logic;
      r_en        : in  std_logic;
      g_wptr_sync : in  std_logic_vector(PTR_WIDTH downto 0);
      b_rptr      : out std_logic_vector(PTR_WIDTH downto 0);
      g_rptr      : out std_logic_vector(PTR_WIDTH downto 0);
      usedw       : out std_logic_vector(PTR_WIDTH downto 0);
      empty       : out std_logic
   );
   end component;
   
   component ram_mem_wrapper
   generic(
      g_VENDOR          : string  := "XILINX";
      g_RAM_WIDTH       : integer := 64;
      g_RAM_DEPTH       : integer := 256;
      g_RAM_PERFORMANCE : string  := "LOW_LATENCY"
   );
   port (
      addra : in std_logic_vector((log2ceil(g_RAM_DEPTH)-1) downto 0); -- Write address bus, width determined from RAM_DEPTH
      addrb : in std_logic_vector((log2ceil(g_RAM_DEPTH)-1) downto 0); -- Read address bus, width determined from RAM_DEPTH
      dina  : in std_logic_vector(g_RAM_WIDTH-1 downto 0);		      -- RAM input data
      clka  : in std_logic;                       			            -- Write Clock
      clkb  : in std_logic;                       			            -- Read Clock
      wea   : in std_logic;                       			            -- Write enable
      enb   : in std_logic;                       			            -- RAM Enable, for additional power savings, disable port when not in use
      rstb  : in std_logic;                       			            -- Output reset (does not affect memory contents)
      regceb: in std_logic;                       			            -- Output register enable
      doutb : out std_logic_vector(g_RAM_WIDTH-1 downto 0)           -- RAM output data
   );
   end component;

begin

-- ----------------------------------------------------------------------------
-- WR/RD pointers 
-- ---------------------------------------------------------------------------- 
   --write pointer to read clock domain sync
   sync_wptr : entity work.cdc_sync_bus
      generic map ( g_WIDTH => c_PTR_WIDTH + 1 
      )
      port map(m_axis_aclk, m_axis_aresetn, g_wptr, g_wptr_sync);
   

   --read pointer to write clock domain sync
   sync_rptr : entity work.cdc_sync_bus
   generic map ( g_WIDTH => c_PTR_WIDTH + 1 
   )
   port map (s_axis_aclk, s_axis_aresetn, g_rptr, g_rptr_sync);
   
   
   -- Write pointer 
   wr_en <= s_axis_tvalid;
   
   wptr_h : wptr_handler 
   generic map( 
      PTR_WIDTH => c_PTR_WIDTH
   )
   port map (s_axis_aclk, s_axis_aresetn, wr_en, g_rptr_sync, b_wptr, g_wptr, wrusedw_sig, full);
   
   -- Read pointer
   PACKET_MODE_RD_EN : if g_PACKET_MODE generate
      rd_en <= '1' when (empty='0' AND (pctempty='0' OR pct_overflow_rdsync='1')) AND (fwft_valid = '0' OR m_axis_tready = '1') else '0';
   end generate PACKET_MODE_RD_EN;

   NORMAL_MODE_RD_EN : if NOT g_PACKET_MODE generate
      rd_en <= '1' when empty='0' AND (fwft_valid = '0' OR m_axis_tready = '1') else '0';
   end generate NORMAL_MODE_RD_EN;


   rptr_h : rptr_handler 
   generic map( 
      PTR_WIDTH => c_PTR_WIDTH
   )
   port map (m_axis_aclk, m_axis_aresetn, rd_en, g_wptr_sync, b_rptr, g_rptr, rdusedw, empty);
   
   
   waddr <= b_wptr(b_wptr'left-1 downto 0);
   raddr <= b_rptr(b_rptr'left-1 downto 0);


-- ----------------------------------------------------------------------------
-- WR/RD packet pointers for packet mode
-- ---------------------------------------------------------------------------- 
PACKET_MODE_LOGIC : if g_PACKET_MODE generate

      -- Catch pct_overflow when FIFO is full but tlast not received
      process(s_axis_aclk, s_axis_aresetn)
      begin
         if s_axis_aresetn = '0' then 
            pct_overflow_latch <= '0';
         elsif rising_edge(s_axis_aclk) then
            if s_axis_tvalid = '1' AND s_axis_tlast = '0' AND unsigned(wrusedw_sig) >=  g_FIFO_DEPTH - 1 then
               pct_overflow_latch <= '1';
            elsif s_axis_tvalid = '1' AND s_axis_tlast = '1' AND full = '0' then
               pct_overflow_latch <= '0';
            else 
               pct_overflow_latch <= pct_overflow_latch;
            end if;

         end if;

      end process;

      -- Synck to m_axis_aclk
      cdc_sync_inst : entity work.cdc_sync_bit
         port map(
            clk   => m_axis_aclk, 
            rst_n => m_axis_aresetn, 
            d     => pct_overflow_latch, 
            q     => pct_overflow_rdsync
         );
      

      -- Write Packet counter pointer hadler
      pctwr_en <= (s_axis_tvalid AND s_axis_tlast AND NOT full);
      
      pct_wptr_h : wptr_handler 
      generic map( 
         PTR_WIDTH => c_PTR_WIDTH
      )
      port map (s_axis_aclk, s_axis_aresetn, pctwr_en, g_pctrptr_sync, b_pctwptr, g_pctwptr, pctwrusedw, pctfull);


      --Read Packet counter pointer handler
      pctrd_en <= fwft_valid AND mem_dout(0) AND m_axis_tready;
      
      pct_rptr_h : rptr_handler 
      generic map( 
         PTR_WIDTH => c_PTR_WIDTH
      )
      port map (m_axis_aclk, m_axis_aresetn, pctrd_en, g_pctwptr_sync, b_pctrptr, g_pctrptr, pctrdusedw, pctempty);


      --Packet write pointer to read clock domain sync
      sync_pctwptr : entity work.cdc_sync_bus
      generic map ( g_WIDTH => c_PTR_WIDTH + 1 
      )
      port map (m_axis_aclk, m_axis_aresetn, g_pctwptr, g_pctwptr_sync);

      
      --Packet read pointer to write clock domain sync
      sync_pctrptr : entity work.cdc_sync_bus
      generic map ( g_WIDTH => c_PTR_WIDTH + 1 
      )
      port map (s_axis_aclk, s_axis_aresetn, g_pctrptr, g_pctrptr_sync);

   end generate PACKET_MODE_LOGIC;


-- ----------------------------------------------------------------------------
-- Control for First Word Fall trough logic (must have for AXIS FIFO logic)
-- ---------------------------------------------------------------------------- 
   process(m_axis_aclk, m_axis_aresetn)
   begin
      if m_axis_aresetn = '0' then 
         fwft_valid <= '0';
      elsif rising_edge(m_axis_aclk) then 
         if empty = '0' AND rd_en = '1' then 
            fwft_valid <='1';
         elsif m_axis_tvalid_ack = '1' then 
            fwft_valid <='0';
         else 
            fwft_valid <= fwft_valid;
         end if;
      end if;
   end process;
   

-- ----------------------------------------------------------------------------
-- RAM memory implementation
-- ----------------------------------------------------------------------------   
   ram_inst : ram_mem_wrapper
   generic map(
      g_VENDOR          => g_VENDOR,
      g_RAM_WIDTH       => g_DATA_WIDTH + g_DATA_WIDTH/8 + 1,
      g_RAM_DEPTH       => g_FIFO_DEPTH,
      g_RAM_PERFORMANCE => "LOW_LATENCY"
   )
   port map(
      addra  => waddr,              -- Write address bus, width determined from RAM_DEPTH
      addrb  => raddr,              -- Read address bus, width determined from RAM_DEPTH
      dina   => s_axis_tdata & s_axis_tkeep & s_axis_tlast, -- RAM input data
      clka   => s_axis_aclk,        -- Write Clock
      clkb   => m_axis_aclk,        -- Read Clock
      wea    => wr_en AND NOT full, -- Write enable
      enb    => rd_en,              -- RAM Enable, for additional power savings, disable port when not in use
      rstb   => '0',                -- Output reset (does not affect memory contents)
      regceb => '1',                -- Output register enable
      doutb  => mem_dout            -- RAM output data
   );
   

   m_axis_tvalid_ack <= m_axis_tvalid_reg AND m_axis_tready;

-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------
   s_axis_tready  <= NOT full AND s_axis_aresetn AND m_axis_aresetn;
   
   PACKET_MODE_M_AXISTVALID : if g_PACKET_MODE generate
      m_axis_tvalid_reg  <= fwft_valid AND (NOT pctempty OR pct_overflow_rdsync);
   end generate PACKET_MODE_M_AXISTVALID;

   NORMAL_MODE_M_AXISTVALID : if NOT g_PACKET_MODE generate
      m_axis_tvalid_reg  <= fwft_valid;
   end generate NORMAL_MODE_M_AXISTVALID;


   m_axis_tvalid  <= m_axis_tvalid_reg;
   m_axis_tdata   <= mem_dout(g_DATA_WIDTH + g_DATA_WIDTH/8 downto g_DATA_WIDTH/8+1);
   m_axis_tkeep   <= mem_dout(g_DATA_WIDTH/8 downto 1);
   m_axis_tlast   <= mem_dout(0);

   wrusedw <= wrusedw_sig;
   
   
   

end architecture rtl;
