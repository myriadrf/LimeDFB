-- ----------------------------------------------------------------------------
-- FILE:          gt_txrx_encoder_tb.vhd
-- DESCRIPTION:   Test bech description
-- DATE:          15:40 2023-04-25
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
entity gt_txrx_encoder_tb is
end gt_txrx_encoder_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of gt_txrx_encoder_tb is
   constant clk0_period    : time := 10 ns;
   constant clk1_period    : time := 10 ns; 
   --signals
   signal clk0,clk1        : std_logic;
   signal reset_n          : std_logic;
   
   constant c_CTRL_DATA_WIDTH       : integer := 512;
   
   constant c_DMA_CH_DATA_WIDTH     : integer := 128;
   constant c_DMA_CH_WORDS_TO_WRITE : integer := 256;
   
   signal ctrl_writer_data  : std_logic_vector(c_CTRL_DATA_WIDTH-1 downto 0);
   signal ctrl_writer_valid : std_logic;
   signal ctrl_writer_ready : std_logic;
   
   signal data_trnsfr_cnt   : unsigned(16 downto 0);
   
   
   signal inst1_s_axis_tvalid : std_logic;
   signal inst1_s_axis_tready : std_logic;
   signal inst1_s_axis_tdata  : std_logic_vector(c_DMA_CH_DATA_WIDTH-1 downto 0);
   signal inst1_s_axis_tlast  : std_logic;
   signal inst1_m_axis_tvalid : std_logic;
   signal inst1_m_axis_tready : std_logic;
   signal inst1_m_axis_tdata  : std_logic_vector(c_DMA_CH_DATA_WIDTH-1 downto 0);
   signal inst1_m_axis_tlast  : std_logic;
   
   
   signal dut1_m_axis_tdata   : std_logic_vector(127 downto 0);
   signal dut1_m_axis_tlast   : std_logic;
   signal dut1_m_axis_tvalid  : std_logic;
   signal dut1_m_axis_tready  : std_logic;
   
   signal data_axis_tdata    : std_logic_vector(127 downto 0);
   signal data_axis_tlast    : std_logic;
   signal data_axis_tready   : std_logic;
   signal data_axis_tvalid   : std_logic;
   
   signal data_pkt_axis_tdata    : std_logic_vector(127 downto 0);
   signal data_pkt_axis_tlast    : std_logic;
   signal data_pkt_axis_tready   : std_logic;
   signal data_pkt_axis_tvalid   : std_logic;
   
   signal pkt_axis_tdata    : std_logic_vector(31 downto 0);
   signal pkt_axis_tlast    : std_logic;
   signal pkt_axis_tready   : std_logic;
   signal pkt_axis_tvalid   : std_logic;
   
   
   
   signal rec_ctrl_packet        : std_logic;
   signal rec_data_packet        : std_logic;
   signal rec_hdr                : std_logic;
   
   signal rec_ctrl               : std_logic_vector(127 downto 0);
   signal rec_data               : std_logic_vector(127 downto 0);
   signal rec_cmp_data           : std_logic_vector(127 downto 0);
   signal rec_data_error         : std_logic;
   
   
   signal rx_axis_0_tvalid       : std_logic;
   signal rx_axis_0_tready       : std_logic;
   signal rx_axis_0_tdata        : std_logic_vector(511 downto 0);
   signal rx_axis_0_tlast        : std_logic;
   
   signal rx_axis_1_tvalid       : std_logic;
   signal rx_axis_1_tready       : std_logic;
   signal rx_axis_1_tdata        : std_logic_vector(127 downto 0);
   signal rx_axis_1_tlast        : std_logic;
   
   constant c_CTRL_TEST_PACKET   : std_logic_vector(511 downto 0):=  x"44444444444444444444444444444444" &
                                                                     x"33333333333333333333333333333333" &
                                                                     x"22222222222222222222222222222222" &
                                                                     x"11111111111111111111111111111111";
                                                                    
begin
   clock0: process is
   begin
      clk0 <= '0'; wait for clk0_period/2;
      clk0 <= '1'; wait for clk0_period/2;
   end process clock0;

   clock1: process is
   begin
      clk1 <= '0'; wait for clk1_period/2;
      clk1 <= '1'; wait for clk1_period/2;
   end process clock1;
   
   res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;
   
-- ----------------------------------------------------------------------------
-- Simulate Control channel
-- ----------------------------------------------------------------------------
   process is
      variable seed1, seed2: positive;
      variable rand: real;
      variable range_of_rand : real := 64000.0;
      variable rand_num: integer :=0;
   begin
      ctrl_writer_valid <= '0'; 
      ctrl_writer_data <= (others=>'0'); 
      wait until rising_edge(clk0) AND reset_n = '1' AND ctrl_writer_ready = '1';
      ctrl_writer_valid <= '1';
      ctrl_writer_data  <= c_CTRL_TEST_PACKET;
      wait until rising_edge(clk0);
      ctrl_writer_valid <= '0';
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;
   end process;

-- ----------------------------------------------------------------------------
-- Simulate DMA channel
-- ----------------------------------------------------------------------------   
   process is
      variable seed1, seed2: positive;
      variable rand: real;
      variable range_of_rand : real := 320.0;
      variable rand_num: integer :=0;
   begin
      inst1_s_axis_tvalid <= '0'; wait until rising_edge(clk0) AND reset_n = '1';
      inst1_s_axis_tvalid <= '1';
      for i in 0 to c_DMA_CH_WORDS_TO_WRITE-1 loop
         wait until rising_edge(clk0) AND inst1_s_axis_tready = '1';
      end loop;
      inst1_s_axis_tvalid <= '0';
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;
   end process;
   
   process (clk0, reset_n)
   begin 
      if reset_n = '0' then 
         inst1_s_axis_tdata <= (others=>'0');
      elsif rising_edge(clk0) then 
         if inst1_s_axis_tvalid = '1' AND inst1_s_axis_tready = '1' then 
            inst1_s_axis_tdata <= std_logic_vector(unsigned(inst1_s_axis_tdata) + 1 );
         end if;
      end if;
   end process;
   
   process (clk0, reset_n)
   begin 
      if reset_n = '0' then 
         data_trnsfr_cnt <= (others=>'0');
      elsif rising_edge(clk0) then 
         if inst1_s_axis_tvalid = '1' AND inst1_s_axis_tready = '1' AND data_trnsfr_cnt = c_DMA_CH_WORDS_TO_WRITE-1 then 
            data_trnsfr_cnt <= (others=>'0');
         elsif inst1_s_axis_tvalid = '1' AND inst1_s_axis_tready = '1' then 
            data_trnsfr_cnt <= data_trnsfr_cnt + 1;
         end if;
      end if;
   end process;
   
   process (clk0, reset_n)
   begin 
      if reset_n = '0' then 
         inst1_s_axis_tlast <= '0';
      elsif rising_edge(clk0) then 
         if inst1_s_axis_tvalid = '1' AND data_trnsfr_cnt = c_DMA_CH_WORDS_TO_WRITE-1 AND inst1_s_axis_tready = '1' then 
            inst1_s_axis_tlast <= '0';
         elsif inst1_s_axis_tvalid = '1' AND data_trnsfr_cnt = c_DMA_CH_WORDS_TO_WRITE-2 AND inst1_s_axis_tready = '1' then 
            inst1_s_axis_tlast <= '1';
         end if;
      end if;
   end process;
  
  inst1_data_fifo : entity work.fifo_axis_wrap
   generic map(
      g_CLOCKING_MODE       => "independent_clock", -- "common_clock" or "independent_clock"
      g_FIFO_DEPTH          =>  256,
      g_TDATA_WIDTH         =>  c_DMA_CH_DATA_WIDTH,
      g_RD_DATA_COUNT_WIDTH =>  9,
      g_WR_DATA_COUNT_WIDTH =>  9
   )
   port map(
      s_axis_aresetn       => reset_n,
      s_axis_aclk          => clk0,
      s_axis_tvalid        => inst1_s_axis_tvalid,
      s_axis_tready        => inst1_s_axis_tready,
      s_axis_tdata         => inst1_s_axis_tdata,
      --Not using tlast here
      s_axis_tlast         => '0', --inst1_s_axis_tlast,
      m_axis_aclk          => clk0,
      m_axis_tvalid        => data_axis_tvalid,
      m_axis_tready        => data_axis_tready,
      m_axis_tdata         => data_axis_tdata,
      m_axis_tlast         => data_axis_tlast,
      almost_empty_axis    => open,
      rd_data_count_axis   => open,
      wr_data_count_axis   => open
   );
     

   --process is
   --begin
   --   dut1_m_axis_tready <= '0';
   --   wait until dut1_m_axis_tvalid = '1' and rising_edge(clk0);
   --   wait until rising_edge(clk0);
   --   dut1_m_axis_tready <= '1';
   --   wait until rising_edge(clk0);
   --   wait until rising_edge(clk0);
   --   wait until rising_edge(clk0);
   --   dut1_m_axis_tready <= '0';
   --   wait until rising_edge(clk0);
   --   wait until rising_edge(clk0);
   --   dut1_m_axis_tready <= '0';
   --   wait until rising_edge(clk0);
   --   dut1_m_axis_tready <= '1';
   --end process;
  
  
--   dut1: entity work.ctrl_pkt 
--   generic map(
--      g_CTRL_DWIDTH  => 512,
--      g_AXIS_DWIDTH  => 128
--   )
--   port map(
--      clk            => clk0,
--      reset_n        => reset_n,
--      ctrl_data      => ctrl_writer_data,
--      ctrl_valid     => ctrl_writer_valid,
--      ctrl_ready     => ctrl_writer_ready,
--      m_axis_tdata   => dut1_m_axis_tdata,
--      m_axis_tlast   => dut1_m_axis_tlast,
--      m_axis_tready  => dut1_m_axis_tready,
--      m_axis_tvalid  => dut1_m_axis_tvalid
--   );
--   
--   dut2 : entity work.data_pkt
--   generic map (
--      g_PKT_HEADER_WIDTH   => 128,
--      g_DATA_DWIDTH        => 128,
--      g_AXIS_DWIDTH        => 128
--   )
--   port map(
--      clk            => clk0,
--      reset_n        => reset_n,
--      s_axis_tdata   => data_axis_tdata,
--      s_axis_tlast   => data_axis_tlast,
--      s_axis_tready  => data_axis_tready,
--      s_axis_tvalid  => data_axis_tvalid, 
--      m_axis_tdata   => data_pkt_axis_tdata,
--      m_axis_tlast   => data_pkt_axis_tlast,
--      m_axis_tready  => data_pkt_axis_tready,
--      m_axis_tvalid  => data_pkt_axis_tvalid 
--   );
--   
--   
--   dut3 : entity work.axis_interconnect_0
--   PORT MAP (
--      ACLK                 => clk0,
--      ARESETN              => reset_n,
--      
--      S00_AXIS_ACLK        => clk0,
--      S00_AXIS_ARESETN     => reset_n,
--      S00_AXIS_TVALID      => dut1_m_axis_tvalid,
--      S00_AXIS_TREADY      => dut1_m_axis_tready,
--      S00_AXIS_TDATA       => dut1_m_axis_tdata,
--      S00_AXIS_TLAST       => dut1_m_axis_tlast,
--      
--      S01_AXIS_ACLK        => clk0,
--      S01_AXIS_ARESETN     => reset_n,
--      S01_AXIS_TVALID      => data_pkt_axis_tvalid,
--      S01_AXIS_TREADY      => data_pkt_axis_tready,
--      S01_AXIS_TDATA       => data_pkt_axis_tdata,
--      S01_AXIS_TLAST       => data_pkt_axis_tlast,
--      
--      M00_AXIS_ACLK        => clk0,
--      M00_AXIS_ARESETN     => reset_n,
--      M00_AXIS_TVALID      => pkt_axis_tvalid,
--      M00_AXIS_TREADY      => pkt_axis_tready,
--      M00_AXIS_TDATA       => pkt_axis_tdata,
--      M00_AXIS_TLAST       => pkt_axis_tlast,
--      
--      S00_ARB_REQ_SUPPRESS => '0',
--      S01_ARB_REQ_SUPPRESS => '0'
--  );
  
  
  dut1 : entity work.gt_tx_encoder
   generic map(
      g_PKT_HEADER_WIDTH      => 128,
      g_I_AXIS_DWIDTH         => 128,
      g_S_AXIS_0_DWIDTH       => 512,
      g_S_AXIS_0_BUFFER_WORDS => 16,
      g_S_AXIS_1_DWIDTH       => 128,
      g_S_AXIS_1_BUFFER_WORDS => 512,
      g_M_AXIS_DWIDTH         => 32,
      g_M_AXIS_BUFFER_WORDS   => 1024
   )
   port map(
      --AXI stream slave
      s_axis_0_aclk     => clk0,
      s_axis_0_aresetn  => reset_n,
      s_axis_0_tvalid   => ctrl_writer_valid,
      s_axis_0_tready   => ctrl_writer_ready,
      s_axis_0_tdata    => ctrl_writer_data, 
      s_axis_0_tlast    => '0',              --not used
      --AXI stream slave
      s_axis_1_aclk     => clk0,
      s_axis_1_aresetn  => reset_n,
      s_axis_1_tvalid   => data_axis_tvalid,
      s_axis_1_tready   => data_axis_tready,
      s_axis_1_tdata    => data_axis_tdata,
      s_axis_1_tlast    => data_axis_tlast,
      --Control
      s_axis_0_arb_req_supress => '0',
      s_axis_1_arb_req_supress => '0',
      --AXI stream master
      m_axis_aclk       => clk0,
      m_axis_aresetn    => reset_n,
      m_axis_tvalid     => pkt_axis_tvalid,
      m_axis_tready     => pkt_axis_tready,
      m_axis_tdata      => pkt_axis_tdata,
      m_axis_tlast      => pkt_axis_tlast
   );
   
   dut2 : entity work.gt_rx_decoder
   generic map(
      g_PKT_HEADER_WIDTH      => 128,
      g_I_AXIS_DWIDTH         => 128,
      g_S_AXIS_DWIDTH         => 32,
      g_S_AXIS_BUFFER_WORDS   => 2048,
      g_M_AXIS_0_DWIDTH       => 512,
      g_M_AXIS_0_BUFFER_WORDS => 16,
      g_M_AXIS_1_DWIDTH       => 128,
      g_M_AXIS_1_BUFFER_WORDS => 512
   )
   port map(
      --AXI stream master 0
      m_axis_0_aclk     => clk0,
      m_axis_0_tvalid   => rx_axis_0_tvalid,
      m_axis_0_tready   => rx_axis_0_tready,
      m_axis_0_tdata    => rx_axis_0_tdata,
      m_axis_0_tlast    => rx_axis_0_tlast,
      m_axis_0_wrusedw  => open, 
      --AXI stream master 1
      m_axis_1_aclk     => clk0,
      m_axis_1_aresetn  => reset_n,
      m_axis_1_tvalid   => rx_axis_1_tvalid,
      m_axis_1_tready   => rx_axis_1_tready,
      m_axis_1_tdata    => rx_axis_1_tdata,
      m_axis_1_tlast    => rx_axis_1_tlast,
      m_axis_1_wrusedw  => open, 
      --AXI stream master
      s_axis_aclk       => clk0,
      s_axis_aresetn    => reset_n,
      s_axis_tvalid     => pkt_axis_tvalid,
      s_axis_tready     => pkt_axis_tready,
      s_axis_tdata      => pkt_axis_tdata,
      s_axis_tlast      => pkt_axis_tlast
   );
   
   
   
   
   process (clk0, reset_n)
   begin 
      if reset_n = '0' then 
         rx_axis_0_tready <= '0';
      elsif rising_edge(clk0) then
         rx_axis_0_tready <= '1';
         
         if rx_axis_0_tvalid = '1' AND rx_axis_0_tready = '1' then 
            if rx_axis_0_tdata /= c_CTRL_TEST_PACKET then 
               report "--------------------------------------------------------------------------------" severity NOTE;
               report "Test FAIL - control packet does not match" severity ERROR;
               report "--------------------------------------------------------------------------------" severity NOTE;
               assert false report "Test: ERROR control packed does not match" severity failure;
            end if;
         end if;
      end if;
   end process;
   
   process (clk0, reset_n)
   begin 
      if reset_n = '0' then 
         rec_cmp_data      <= (others => '0');
         rx_axis_1_tready  <= '0';
      elsif rising_edge(clk0) then
         rx_axis_1_tready <= '1';
         
         if rx_axis_1_tvalid ='1' AND rx_axis_1_tready = '1'  then 
            rec_cmp_data <= std_logic_vector(unsigned(rec_cmp_data) + 1 );
            
            if rec_cmp_data /= rx_axis_1_tdata then
               report "--------------------------------------------------------------------------------" severity NOTE;
               report "Test FAIL - rx data packed does not match with tx" severity ERROR;
               report "--------------------------------------------------------------------------------" severity NOTE;
               assert false report "Test: ERROR rx data packed does not match with tx" severity failure;
            end if;
         end if;
         
         
      end if;
   end process;
   


end tb_behave;

