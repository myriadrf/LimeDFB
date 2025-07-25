-- ----------------------------------------------------------------------------
-- FILE:          axis_byte_combiner_tb.vhd
-- DESCRIPTION:   Test bech for axis_byte_combiner module
-- DATE:          12:58 2025-07-14
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use ieee.math_real.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity axis_chnl_combiner_tb is
end axis_chnl_combiner_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of axis_chnl_combiner_tb is
   constant clk0_period    : time := 10 ns;
   constant clk1_period    : time := 10 ns;
   constant clk2_period    : time := 10 ns;  

   constant C_DATA_WIDTH   : integer := 128;
   
   --signals
   signal clk0,clk1,clk2   : std_logic;
   signal reset_n          : std_logic; 


   signal s_axis_tdata     : std_logic_vector(C_DATA_WIDTH-1 downto 0);
   signal s_axis_tkeep     : std_logic_vector(C_DATA_WIDTH/8-1 downto 0);
   signal s_axis_tuser     : std_logic_vector(C_DATA_WIDTH/8/4-1 downto 0);
   signal s_axis_tlast     : std_logic;
   signal s_axis_tvalid    : std_logic;
   signal s_axis_tready    : std_logic;

   signal m_axis_tdata     : std_logic_vector(C_DATA_WIDTH-1 downto 0);
   signal m_axis_tkeep     : std_logic_vector(C_DATA_WIDTH/8-1 downto 0);
   signal m_axis_tlast     : std_logic;
   signal m_axis_tvalid    : std_logic;
   signal m_axis_tready    : std_logic;


   type sample_array_t is array (0 to 19) of std_logic_vector(31 downto 0);
   signal test_sample_array   : sample_array_t;
   signal tdata_reg_array     : sample_array_t;


   signal trnsfer_index : unsigned(3 downto 0);

   signal ch0_index : unsigned(4 downto 0);
   signal ch1_index : unsigned(4 downto 0);
   signal ch2_index : unsigned(4 downto 0);
   signal ch3_index : unsigned(4 downto 0);


   COMPONENT axis_combiner_0
  PORT (
    aclk : IN STD_LOGIC;
    aresetn : IN STD_LOGIC;
    s_axis_tvalid : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    s_axis_tready : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    s_axis_tdata : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
    s_axis_tkeep : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    m_axis_tvalid : OUT STD_LOGIC;
    m_axis_tready : IN STD_LOGIC;
    m_axis_tdata : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
    m_axis_tkeep : OUT STD_LOGIC_VECTOR(15 DOWNTO 0) 
  );
END COMPONENT;



   

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
   
   clock2: process is
   begin
      clk2 <= '0'; wait for clk2_period/2;
      clk2 <= '1'; wait for clk2_period/2;
   end process clock2;
   
   res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;


   test_sample_array(0)<=x"33221100";
   test_sample_array(1)<=x"77665544";
   test_sample_array(2)<=x"BBAA9988";
   test_sample_array(3)<=x"FFEEDDCC";

   test_sample_array(4)<=x"77665544";
   test_sample_array(5)<=x"BBAA9988";
   test_sample_array(6)<=x"BBAA9988";
   test_sample_array(7)<=x"FFEEDDCC";

   test_sample_array(8)<=x"BBAA9988";
   test_sample_array(9)<=x"77665544";
   test_sample_array(10)<=x"BBAA9988";
   test_sample_array(11)<=x"FFEEDDCC";

   test_sample_array(12)<=x"FFEEDDCC";
   test_sample_array(13)<=x"77665544";
   test_sample_array(14)<=x"BBAA9988";
   test_sample_array(15)<=x"FFEEDDCC";

   test_sample_array(16)<=x"33221100";
   test_sample_array(17)<=x"77665544";
   test_sample_array(18)<=x"BBAA9988";
   test_sample_array(19)<=x"FFEEDDCC";



   axis_byte_combiner_inst : entity work.axis_chnl_combiner
   generic map (
      g_DATA_WIDTH  => 128
   )
   port map(
      aclk           => clk0,
      aresetn        => reset_n,
      -- AXI Stream Write Interface
      s_axis_tdata   => s_axis_tdata ,
      s_axis_tkeep   => s_axis_tkeep ,
      s_axis_tuser   => s_axis_tuser,
      s_axis_tlast   => s_axis_tlast ,
      s_axis_tvalid  => s_axis_tvalid,
      s_axis_tready  => s_axis_tready,
      -- AXI Stream Read Interface
      m_axis_tdata   => m_axis_tdata ,
      m_axis_tkeep   => m_axis_tkeep ,
      m_axis_tlast   => m_axis_tlast ,
      m_axis_tvalid  => m_axis_tvalid,
      m_axis_tready  => m_axis_tready
   );

   ----Generate s_axis_tvalid
   --process is
   --   variable seed1, seed2: positive;
   --   variable rand: real;
   --   variable range_of_rand : real := 10.0;
   --   variable rand_num: integer :=0;
   --begin
   --   s_axis_tvalid  <= '0';
   --   wait until rising_edge(clk0) AND reset_n='1';
   --   s_axis_tvalid  <= '1';
   --   uniform(seed1, seed2, rand);
   --   rand_num := integer(rand*range_of_rand);
   --   for i in 0 to rand_num loop
   --      wait until rising_edge(clk0);
   --   end loop;
--
   --   s_axis_tvalid  <= '0';
   --   uniform(seed1, seed2, rand);
   --   rand_num := integer(rand*range_of_rand);
   --   for i in 0 to rand_num loop
   --      wait until rising_edge(clk0);
   --   end loop;
   --end process;

   --Generate s_axis_tuser

   process is 
      variable seed1, seed2: positive;
      variable rand: real;
      variable range_of_rand : real := 10.0;
      variable rand_num: integer :=0;
   begin
      s_axis_tdata   <= (others=>'0');
      s_axis_tuser   <= "0000";
      s_axis_tkeep   <= x"0000";
      s_axis_tvalid  <= '0';
      wait until rising_edge(clk0) AND reset_n='1';
      s_axis_tkeep   <= x"000F";
     
      -------------------------------------------------------------
      s_axis_tvalid  <= '1';
      s_axis_tuser   <= "0101";
      s_axis_tdata   <= x"00000000_77665544_00000000_33221100";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_ffeeddcc_00000000_bbaa9988";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_ffeeddcc_00000000_bbaa9988";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_77665544_00000000_33221100";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tvalid  <= '0';
      s_axis_tuser   <= "0000";
      s_axis_tdata   <= (others=>'0');


      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;

      -------------------------------------------------------------
      s_axis_tvalid  <= '1';
      s_axis_tuser   <= "1010";
      s_axis_tdata   <= x"77665544_00000000_33221100_00000000";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"ffeeddcc_00000000_bbaa9988_00000000";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"77665544_00000000_33221100_00000000";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"ffeeddcc_00000000_bbaa9988_00000000";
      wait until rising_edge(clk0) AND s_axis_tready='1';

      s_axis_tvalid  <= '0';
      s_axis_tuser   <= "0000";
      s_axis_tdata   <= (others=>'0');

      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;

      -------------------------------------------------------------
      s_axis_tvalid  <= '1';
      s_axis_tuser   <= "0001";
      s_axis_tdata   <= x"00000000_00000000_00000000_33221100";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_00000000_00000000_77665544";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_00000000_00000000_bbaa9988";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_00000000_00000000_ffeeddcc";
      wait until rising_edge(clk0) AND s_axis_tready='1';

      s_axis_tvalid  <= '0';
      s_axis_tuser   <= "0000";
      s_axis_tdata   <= (others=>'0');

      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;

      -------------------------------------------------------------
      s_axis_tvalid  <= '1';
      s_axis_tuser   <= "1111";
      s_axis_tdata   <= x"ffeeddcc_bbaa9988_77665544_33221100";
      wait until rising_edge(clk0) AND s_axis_tvalid = '1' AND s_axis_tready='1';
      s_axis_tdata   <= x"ffeeddcc_bbaa9988_77665544_33221100";
      wait until rising_edge(clk0) AND s_axis_tvalid = '1' AND s_axis_tready='1';
      s_axis_tdata   <= x"ffeeddcc_bbaa9988_77665544_33221100";
      wait until rising_edge(clk0) AND s_axis_tvalid = '1' AND s_axis_tready='1';
      s_axis_tdata   <= x"ffeeddcc_bbaa9988_77665544_33221100";
      wait until rising_edge(clk0) AND s_axis_tvalid = '1' AND s_axis_tready='1';


      s_axis_tvalid  <= '0';
      s_axis_tuser   <= "0000";
      s_axis_tdata   <= (others=>'0');

      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;


      -------------------------------------------------------------
      s_axis_tvalid  <= '1';
      s_axis_tuser   <= "0111";
      s_axis_tdata   <= x"00000000_bbaa9988_77665544_33221100";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_77665544_33221100_ffeeddcc";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_33221100_ffeeddcc_bbaa9988";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"00000000_ffeeddcc_bbaa9988_77665544";
      wait until rising_edge(clk0) AND s_axis_tready='1';

      s_axis_tvalid  <= '0';
      s_axis_tuser   <= "0000";
      s_axis_tdata   <= (others=>'0');

      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;

      -------------------------------------------------------------
     s_axis_tvalid  <= '1';
      s_axis_tuser   <= "1011";
      s_axis_tdata   <= x"bbaa9988_00000000_77665544_33221100";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"77665544_00000000_33221100_ffeeddcc";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"33221100_00000000_ffeeddcc_bbaa9988";
      wait until rising_edge(clk0) AND s_axis_tready='1';
      s_axis_tdata   <= x"ffeeddcc_00000000_bbaa9988_77665544";
      wait until rising_edge(clk0) AND s_axis_tready='1';

      s_axis_tvalid  <= '0';
      s_axis_tuser   <= "0000";
      s_axis_tdata   <= (others=>'0');

      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;

      wait;


   end process;








   --Generate M_AXIS_TREADY
   process is
      variable seed1, seed2: positive;
      variable rand: real;
      variable range_of_rand : real := 10.0;
      variable rand_num: integer :=0;
   begin
      m_axis_tready <= '0';   
      wait until rising_edge(clk0) AND reset_n='1' AND m_axis_tvalid='1';
      m_axis_tready <= '0';
      
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;
      
      m_axis_tready <= '1';
      
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;
   end process;


  your_instance_name : axis_combiner_0
  PORT MAP (
    aclk          => clk0,
    aresetn       => reset_n,
    s_axis_tvalid => "00000011",
    s_axis_tready => open,
    s_axis_tdata  => s_axis_tdata,
    s_axis_tkeep  => (others=>'1'),
    m_axis_tvalid => open,
    m_axis_tready => '1',
    m_axis_tdata  => open,
    m_axis_tkeep  => open
  );



   

end tb_behave;

