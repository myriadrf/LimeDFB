-- ----------------------------------------------------------------------------
-- FILE:          axis_fifo_tb.vhd
-- DESCRIPTION:   Test bech for pure VHDL AXIS FIFO
-- DATE:          14:25 2024-06-04
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
entity axis_fifo_tb is
end axis_fifo_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of axis_fifo_tb is
   constant clk0_period    : time := 1 ns;
   constant clk1_period    : time := 1 ns; 
   --signals
   signal clk0,clk1        : std_logic;
   signal reset_n          : std_logic; 
   
   constant c_DATA_WIDTH   : integer := 32;
   constant c_FIFO_DEPTH   : integer := 16;
   
   signal s_axis_aresetn   : std_logic;
   signal s_axis_tdata     : std_logic_vector(c_DATA_WIDTH-1 downto 0);
   signal s_axis_tkeep     : std_logic_vector(c_DATA_WIDTH/8-1 downto 0);
   signal s_axis_tlast     : std_logic;
   signal s_axis_tvalid    : std_logic;
   signal s_axis_tready    : std_logic;
   
   signal m_axis_aresetn   : std_logic;
   signal m_axis_tdata     : std_logic_vector(c_DATA_WIDTH-1 downto 0);
   signal m_axis_tkeep     : std_logic_vector(c_DATA_WIDTH/8-1 downto 0);
   signal m_axis_tlast     : std_logic;
   signal m_axis_tvalid    : std_logic;
   signal m_axis_tready    : std_logic;
   
   signal tdata            : std_logic_vector(c_DATA_WIDTH-1 downto 0);
   
  
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
   
   s_axis_aresetn <= reset_n;
   m_axis_aresetn <= reset_n;
   
   -- Design under test  
   dut_axi_stream_fifo : entity work.axi_stream_fifo
   generic map(
      g_DATA_WIDTH  => c_DATA_WIDTH,
      g_FIFO_DEPTH  => c_FIFO_DEPTH
   )
   port map(
      -- AXI Stream Write Interface
      s_axis_aclk    => clk0  ,
      s_axis_aresetn => s_axis_aresetn,
      s_axis_tdata   => s_axis_tdata ,
      s_axis_tkeep   => s_axis_tkeep ,
      s_axis_tlast   => s_axis_tlast ,
      s_axis_tvalid  => s_axis_tvalid,
      s_axis_tready  => s_axis_tready,
      
      -- AXI Stream Read Interface
      m_axis_aclk    => clk1  ,
      m_axis_aresetn => m_axis_aresetn,
      m_axis_tdata   => m_axis_tdata ,
      m_axis_tkeep   => m_axis_tkeep ,
      m_axis_tlast   => m_axis_tlast ,
      m_axis_tvalid  => m_axis_tvalid,
      m_axis_tready  => m_axis_tready
   );
   
   
   s_axis_tkeep <= (others=>'1');
   s_axis_tlast <= '0';
   
   process(clk0, s_axis_aresetn)
   begin 
      if s_axis_aresetn = '0' then 
         s_axis_tdata  <= (others=>'1');
         s_axis_tvalid <= '0';
      elsif rising_edge(clk0) then 
         s_axis_tvalid <= '1';
         if s_axis_tvalid ='1' and s_axis_tready = '1' then 
            s_axis_tdata <= std_logic_vector(unsigned(s_axis_tdata) + 1);
         else
            s_axis_tdata <= s_axis_tdata;
         end if;
      end if;
   end process;
   
   
   process is
      variable seed1, seed2: positive;
      variable rand: real;
      variable range_of_rand : real := 10.0;
      variable rand_num: integer :=0;
   begin
      m_axis_tready <= '0';   
      wait until rising_edge(clk1) AND m_axis_aresetn='1' AND m_axis_tvalid = '1';
      m_axis_tready <= '1';
      
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk1);
      end loop;
      
      m_axis_tready <= '0';
      
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk1);
      end loop;
   end process;
      
         
   
   
   process(clk1, m_axis_aresetn)
   begin 
      if s_axis_aresetn = '0' then 
         tdata         <= (others=>'1');
      elsif rising_edge(clk1) then 
         if m_axis_tvalid ='1' and m_axis_tready = '1' then 
            tdata <= std_logic_vector(unsigned(tdata) + 1);
         else
            tdata <= tdata;
         end if;
      end if;
   end process;
   
   process(clk1)
   begin 
   if rising_edge(clk1) then 
      if m_axis_tvalid ='1' and m_axis_tready = '1' then 
         assert(tdata = m_axis_tdata) report "m_axis_tdata is not equal to written s_axis_tdata" severity failure;
      end if;
   end if;
   end process;
   
   
   
   
   

   
   

end tb_behave;

