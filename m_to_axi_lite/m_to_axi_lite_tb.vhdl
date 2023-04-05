-- ----------------------------------------------------------------------------
-- FILE:          m_to_axi_lite_tb.vhd
-- DESCRIPTION:   
-- DATE:          Feb 13, 2014
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity m_to_axi_lite_tb is
end m_to_axi_lite_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of m_to_axi_lite_tb is
   constant clk0_period    : time := 10 ns;
   constant clk1_period    : time := 10 ns; 
   
   constant c_DATA_WIDTH            : integer := 512;
   constant c_AXI_LITE_DATA_WIDTH   : integer := 32;
   constant c_AXI_LITE_ADDR_WIDTH   : integer := 32;
   constant c_AXI_LITE_PROT_WIDTH   : integer := 2;
   constant c_AXI_LITE_STB_WIDTH    : integer := 4;
   constant c_AXI_LITE_RESP_WIDTH   : integer := 2;
   
   signal dut0_reader_data_valid    : std_logic;
   signal dut0_reader_data          : std_logic_vector(c_DATA_WIDTH-1 downto 0);
   signal dut0_writer_data_valid    : std_logic;
   signal dut0_writer_data          : std_logic_vector(c_DATA_WIDTH-1 downto 0);
   signal dut0_writer_data_reg      : std_logic_vector(c_DATA_WIDTH-1 downto 0);
   
   signal dut0_m_axi_lite_awaddr    : std_logic_vector(c_AXI_LITE_ADDR_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_awprot    : std_logic_vector(c_AXI_LITE_PROT_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_awvalid   : std_logic;
   signal dut0_m_axi_lite_awready   : std_logic;
   signal dut0_m_axi_lite_wdata     : std_logic_vector(c_AXI_LITE_DATA_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_wstrb     : std_logic_vector(c_AXI_LITE_STB_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_wvalid    : std_logic;
   signal dut0_m_axi_lite_wready    : std_logic;
   signal dut0_m_axi_lite_bresp     : std_logic_vector(c_AXI_LITE_RESP_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_bvalid    : std_logic;
   signal dut0_m_axi_lite_bready    : std_logic;
   signal dut0_m_axi_lite_araddr    : std_logic_vector(c_AXI_LITE_ADDR_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_arprot    : std_logic_vector(c_AXI_LITE_PROT_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_arvalid   : std_logic;
   signal dut0_m_axi_lite_arready   : std_logic;
   signal dut0_m_axi_lite_rdata     : std_logic_vector(c_AXI_LITE_DATA_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_rresp     : std_logic_vector(c_AXI_LITE_RESP_WIDTH-1 downto 0);
   signal dut0_m_axi_lite_rvalid    : std_logic;
   signal dut0_m_axi_lite_rready    : std_logic;
   
   type t_ram is array (0 to c_DATA_WIDTH/c_AXI_LITE_DATA_WIDTH-1) of std_logic_vector(c_AXI_LITE_DATA_WIDTH-1 downto 0);
   signal ram : t_ram;
   
   signal ram_wr_address   : std_logic_vector(c_AXI_LITE_ADDR_WIDTH-1 downto 0);
   signal ram_wr           : std_logic;
   signal ram_rd_address   : std_logic_vector(c_AXI_LITE_ADDR_WIDTH-1 downto 0);
   
   --signals
   signal clk0,clk1        : std_logic;
   signal reset_n          : std_logic; 
  
begin 

-- ----------------------------------------------------------------------------
-- Clocks and resets
-- ----------------------------------------------------------------------------
      clock0: process is
   begin
      clk0 <= '0'; wait for clk0_period/2;
      clk0 <= '1'; wait for clk0_period/2;
   end process clock0;
   
      res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;
   

-- ----------------------------------------------------------------------------
-- writer_data generation and reader_data check 
-- ----------------------------------------------------------------------------
   process is 
   begin 
      dut0_writer_data_valid <= '0';
      dut0_writer_data <= (others=>'0');
      wait until rising_edge(clk0) AND reset_n = '1';
      dut0_writer_data_valid <= '1';
      dut0_writer_data <=  x"AA55AA55" &
                           x"11111111" &
                           x"22222222" &
                           x"33333333" &
                           x"44444444" &
                           x"55555555" &
                           x"66666666" &
                           x"77777777" &
                           x"88888888" &
                           x"99999999" &
                           x"AAAAAAAA" &
                           x"BBBBBBBB" &
                           x"CCCCCCCC" &
                           x"DDDDDDDD" &
                           x"EEEEEEEE" &
                           x"FFFFFFFF";
      wait until rising_edge(clk0);
      dut0_writer_data_valid <= '0';
      dut0_writer_data <= (others=>'0');
      wait until dut0_reader_data_valid = '1' AND rising_edge(clk0);
      report "Writer data: 0x" & to_hstring(unsigned(dut0_writer_data_reg)) severity NOTE;
      report "Reader data: 0x" & to_hstring(unsigned(dut0_reader_data)) severity NOTE;
      if dut0_writer_data_reg = dut0_reader_data then
         report "--------------------------------------------------------------------------------" severity NOTE;
         report "Test pass" severity NOTE;
         report "--------------------------------------------------------------------------------" severity NOTE;
      else 
         report "--------------------------------------------------------------------------------" severity NOTE;
         report "Test FAIL - reader_data does not match with writer_data" severity ERROR;
         report "--------------------------------------------------------------------------------" severity NOTE;
      end if;
      wait;
   end process;
   
   process(clk0)
   begin
      if(dut0_writer_data_valid = '1') then
         dut0_writer_data_reg <= dut0_writer_data;
      end if;
   end process;


-- ----------------------------------------------------------------------------
-- axi_lite write channel 
-- ----------------------------------------------------------------------------   
   process is 
      variable seed1, seed2   : positive; -- seed values for random generator
      variable rand           : real;     -- random real-number value in range 0 to 1.0  
      variable range_of_rand  : real      := 5.0;    -- the range of random values created will be 0 to +10.
      variable rand_i         : integer   := 0;
   begin
      uniform(seed1, seed2, rand);           -- generate random number
      rand_i := integer(rand*range_of_rand); -- rescale to 0..5, convert integer part 
      
      dut0_m_axi_lite_awready <= '0';
      wait until rising_edge(dut0_m_axi_lite_awvalid);
      for i in 0 to rand_i loop
         wait until rising_edge(clk0);
      end loop;
      dut0_m_axi_lite_awready <= '1';
      wait until rising_edge(clk0);
      wait until dut0_m_axi_lite_awvalid = '0';
   end process;
   
   process is 
   begin
      dut0_m_axi_lite_wready <= '0';
      wait until rising_edge(dut0_m_axi_lite_wvalid);
      for i in 0 to 0 loop
         wait until rising_edge(clk0);
      end loop;
      dut0_m_axi_lite_wready <= '1';
      wait until rising_edge(clk0);
      wait until dut0_m_axi_lite_wvalid = '0';
   end process;
   
   process is 
   begin 
      dut0_m_axi_lite_bvalid <= '0';
      --Wait for handshake 
      wait until  (dut0_m_axi_lite_awvalid='1' AND  dut0_m_axi_lite_awready = '1' AND rising_edge(clk0)) OR
                  (dut0_m_axi_lite_wvalid = '1' AND  dut0_m_axi_lite_wready = '1' AND rising_edge(clk0));
      wait until  (dut0_m_axi_lite_awvalid='1' AND  dut0_m_axi_lite_awready = '1' AND rising_edge(clk0)) OR
                  (dut0_m_axi_lite_wvalid = '1' AND  dut0_m_axi_lite_wready = '1' AND rising_edge(clk0));
      report "handshake done, wait for master to be ready to accept response";
      wait until dut0_m_axi_lite_bready = '1';
      wait until rising_edge(clk0);
      dut0_m_axi_lite_bvalid <= '1';
      wait until rising_edge(clk0);
      dut0_m_axi_lite_bvalid <= '0';
   end process;
   
   dut0_m_axi_lite_bresp <= (others=>'0'); -- "00" - OKAY, "01" - EXOKAY, "10" - SLVERR, "11" - DECERR
   
-- ----------------------------------------------------------------------------
-- axi_lite read channel 
-- ----------------------------------------------------------------------------   
   process is 
   begin
      dut0_m_axi_lite_arready <= '0';
      wait until rising_edge(dut0_m_axi_lite_arvalid);
      for i in 0 to 2 loop
         wait until rising_edge(clk0);
      end loop;
      dut0_m_axi_lite_arready <= '1';
      wait until rising_edge(clk0);
      wait until dut0_m_axi_lite_arvalid = '0';
   end process;
   
   process is 
   begin
      dut0_m_axi_lite_rvalid <= '0';
      wait until rising_edge(dut0_m_axi_lite_rready);
      for i in 0 to 1 loop
         wait until rising_edge(clk0);
      end loop;
      dut0_m_axi_lite_rvalid <= '1';
      wait until rising_edge(clk0);
   end process;
   
      
-- ----------------------------------------------------------------------------
-- Design under test 
-- ----------------------------------------------------------------------------
dut0 : entity work.m_to_axi_lite 
   generic map(
      g_DATA_WIDTH            => c_DATA_WIDTH,
      g_AXI_LITE_DATA_WIDTH   => c_AXI_LITE_DATA_WIDTH,
      g_AXI_LITE_ADDR_WIDTH   => c_AXI_LITE_ADDR_WIDTH,
      g_AXI_LITE_PROT_WIDTH   => c_AXI_LITE_PROT_WIDTH,
      g_AXI_LITE_STB_WIDTH    => c_AXI_LITE_STB_WIDTH,
      g_AXI_LITE_RESP_WIDTH   => c_AXI_LITE_RESP_WIDTH
   )
   port map(
      clk      => clk0,
      reset_n  => reset_n,
      
      --General data interface
      reader_data_valid    => dut0_reader_data_valid,
      reader_data          => dut0_reader_data,
      writer_data_valid    => dut0_writer_data_valid,
      writer_data          => dut0_writer_data,
      -- AXI4 lite master interface
      m_axi_lite_awaddr    => dut0_m_axi_lite_awaddr ,
      m_axi_lite_awprot    => dut0_m_axi_lite_awprot ,
      m_axi_lite_awvalid   => dut0_m_axi_lite_awvalid,
      m_axi_lite_awready   => dut0_m_axi_lite_awready,
      m_axi_lite_wdata     => dut0_m_axi_lite_wdata  ,
      m_axi_lite_wstrb     => dut0_m_axi_lite_wstrb  ,
      m_axi_lite_wvalid    => dut0_m_axi_lite_wvalid ,
      m_axi_lite_wready    => dut0_m_axi_lite_wready ,
      m_axi_lite_bresp     => dut0_m_axi_lite_bresp  ,
      m_axi_lite_bvalid    => dut0_m_axi_lite_bvalid ,
      m_axi_lite_bready    => dut0_m_axi_lite_bready ,
      m_axi_lite_araddr    => dut0_m_axi_lite_araddr ,
      m_axi_lite_arprot    => dut0_m_axi_lite_arprot ,
      m_axi_lite_arvalid   => dut0_m_axi_lite_arvalid,
      m_axi_lite_arready   => dut0_m_axi_lite_arready,
      m_axi_lite_rdata     => dut0_m_axi_lite_rdata  ,
      m_axi_lite_rresp     => dut0_m_axi_lite_rresp  ,
      m_axi_lite_rvalid    => dut0_m_axi_lite_rvalid ,
      m_axi_lite_rready    => dut0_m_axi_lite_rready 
   );
   
-- ----------------------------------------------------------------------------
-- Test bech internals 
-- ----------------------------------------------------------------------------   
   -- Basic memory model. 
   -- AXI4-Lite master writes and reads this memory
   process(clk0, reset_n)
   begin
      if(reset_n = '0')then
         ram_wr_address <= (others=>'0');
      elsif(clk0'event and clk0 = '1')then
         -- Capture write address
         if dut0_m_axi_lite_awvalid = '1' AND dut0_m_axi_lite_awready = '1' then 
            ram_wr_address <= dut0_m_axi_lite_awaddr;
         end if;
         
         --Capture read address
         if dut0_m_axi_lite_arvalid = '1' AND dut0_m_axi_lite_arready = '1' then 
            ram_rd_address <= dut0_m_axi_lite_araddr;
         end if;
         
         --Write to memory
         if dut0_m_axi_lite_wvalid = '1' AND dut0_m_axi_lite_wready = '1' then   
            ram(to_integer(unsigned(ram_wr_address))/(c_AXI_LITE_DATA_WIDTH/8)) <= dut0_m_axi_lite_wdata;
         end if;
         
         -- Read from memory
         if dut0_m_axi_lite_rready = '1' then   
            dut0_m_axi_lite_rdata <= ram(to_integer(unsigned(ram_rd_address))/(c_AXI_LITE_DATA_WIDTH/8));
         end if;
         
      end if;
   end process;
   
end tb_behave;

