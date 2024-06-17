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

entity axi_stream_fifo is
   generic (
      g_VENDOR      : string  := "GENERIC";
      g_DATA_WIDTH  : integer := 32;
      g_FIFO_DEPTH  : integer := 16
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
end entity axi_stream_fifo;


architecture rtl of axi_stream_fifo is

   -- Total RAM width TDATA+TKEEP+TLAST
   --type fifo_ram_type is array (0 to g_FIFO_DEPTH-1) of std_logic_vector(g_DATA_WIDTH + g_DATA_WIDTH/8 downto 0);
   --signal fifo_ram                    : fifo_ram_type;
    
   constant c_PTR_WIDTH : integer := log2ceil(g_FIFO_DEPTH);
   
   signal g_wptr_sync, g_rptr_sync : std_logic_vector(c_PTR_WIDTH downto 0);
   signal b_wptr, b_rptr           : std_logic_vector(c_PTR_WIDTH downto 0);
   signal g_wptr, g_rptr           : std_logic_vector(c_PTR_WIDTH downto 0);
   
   signal waddr, raddr  : std_logic_vector(c_PTR_WIDTH-1 downto 0);
   
   signal wr_en, rd_en  : std_logic;
   signal full, empty   : std_logic;
   
   signal fwft_valid    : std_logic;
   
   signal mem_dout       : std_logic_vector(g_DATA_WIDTH + g_DATA_WIDTH/8 downto 0);
   
   component synchronizer
      generic (
         WIDTH : integer := 3
      );
      port ( 
         clk   : in  std_logic;
         rst_n : in  std_logic;
         d_in  : in  std_logic_vector(WIDTH downto 0);
         d_out : out std_logic_vector(WIDTH downto 0)
      );
   end component;
   
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

   --write pointer to read clock domain sync
   sync_wptr : synchronizer 
   generic map( 
      WIDTH => c_PTR_WIDTH
   )
   port map (m_axis_aclk, m_axis_aresetn, g_wptr, g_wptr_sync);
   
   --read pointer to write clock domain sync
   sync_rptr : synchronizer 
   generic map( 
      WIDTH => c_PTR_WIDTH
   )
   port map (s_axis_aclk, s_axis_aresetn, g_rptr, g_rptr_sync);
   
   
   
   -- Write pointer 
   wr_en <= s_axis_tvalid;
   
   wptr_h : wptr_handler 
   generic map( 
      PTR_WIDTH => c_PTR_WIDTH
   )
   port map (s_axis_aclk, s_axis_aresetn, wr_en, g_rptr_sync, b_wptr, g_wptr, wrusedw, full);
   
   -- Read pointer
   rd_en <= '1' when empty='0' AND (fwft_valid = '0' OR m_axis_tready = '1') else '0';
   
   rptr_h : rptr_handler 
   generic map( 
      PTR_WIDTH => c_PTR_WIDTH
   )
   port map (m_axis_aclk, m_axis_aresetn, rd_en, g_wptr_sync, b_rptr, g_rptr, rdusedw, empty);
   
   
  
   waddr <= b_wptr(b_wptr'left-1 downto 0);
   raddr <= b_rptr(b_rptr'left-1 downto 0);
   
   -- Write Data to FIFO
   --process(s_axis_aclk)
   --begin
   --   if rising_edge(s_axis_aclk) then
   --      if wr_en = '1' AND full='0' then
   --         fifo_ram(to_integer(unsigned(waddr))) <= s_axis_tdata & s_axis_tkeep & s_axis_tlast;
   --      end if;
   --   end if;
   --end process;
   
   -- Read Data from FIFO
   --process(m_axis_aclk)
   --begin
   --   if rising_edge(m_axis_aclk) then
   --      if empty = '0' AND rd_en = '1' then 
   --         m_axis_tdata <= fifo_ram(to_integer(unsigned(raddr)))(g_DATA_WIDTH + g_DATA_WIDTH/8 downto g_DATA_WIDTH/8+1);
   --         m_axis_tkeep <= fifo_ram(to_integer(unsigned(raddr)))(g_DATA_WIDTH/8 downto 1);
   --         m_axis_tlast <= fifo_ram(to_integer(unsigned(raddr)))(0);
   --      end if;
   --   end if;
   --end process;
   
   -- Control for First Word Fall trough logic
   process(m_axis_aclk, m_axis_aresetn)
   begin
      if m_axis_aresetn = '0' then 
         fwft_valid <= '0';
      elsif rising_edge(m_axis_aclk) then 
         if empty = '0' AND rd_en = '1' then 
            fwft_valid <='1';
         elsif m_axis_tready = '1' then 
            fwft_valid <='0';
         else 
            fwft_valid <= fwft_valid;
         end if;
      end if;
   end process;
   
   
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
   
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------
   s_axis_tready  <= NOT full;
   
   m_axis_tvalid  <= fwft_valid;
   m_axis_tdata   <= mem_dout(g_DATA_WIDTH + g_DATA_WIDTH/8 downto g_DATA_WIDTH/8+1);
   m_axis_tkeep   <= mem_dout(g_DATA_WIDTH/8 downto 1);
   m_axis_tlast   <= mem_dout(0);
   
   
   

end architecture rtl;
