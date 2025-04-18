-- ----------------------------------------------------------------------------
-- FILE:          sample_padder_tb.vhd
-- DESCRIPTION:   Test bech for sample_padder module
-- DATE:          12:58 2024-05-27
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
entity sample_padder_tb is
end sample_padder_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of sample_padder_tb is

   constant clk0_period    : time := 10 ns;
   
   --signals
   signal clk0             : std_logic;
   signal reset_n          : std_logic; 

   type sample_array_t is array (0 to 3) of std_logic_vector(127 downto 0);
   signal test_sample_array : sample_array_t;

   signal test_sample_cnt : unsigned(1 downto 0);

   signal S_AXIS_TVALID  : std_logic;
   signal S_AXIS_TDATA   : std_logic_vector(127 downto 0);
   signal S_AXIS_TREADY  : std_logic;
   signal S_AXIS_TLAST   : std_logic;
   signal M_AXIS_TDATA   : std_logic_vector(127 downto 0);
   signal M_AXIS_TVALID  : std_logic;
   signal M_AXIS_TREADY  : std_logic;
   signal M_AXIS_TLAST   : std_logic;



begin

   S_AXIS_TLAST <= '0';

   test_sample_array(0)<=x"aa555222555aaa555aaa555aaa555111";
   test_sample_array(1)<=x"5aaa555aaa555333555aaa555aaa555a";
   test_sample_array(2)<=x"555aaa555aaa555aaa555444555aaa55";

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

   process (clk0, reset_n)
   begin
      if reset_n = '0' then
         test_sample_cnt <= (others=>'0');
      elsif rising_edge(clk0) then
         if S_AXIS_TVALID = '1' and S_AXIS_TREADY = '1' then 
            if test_sample_cnt < 2 then 
               test_sample_cnt <= test_sample_cnt +1;
            else 
               test_sample_cnt <= (others=>'0');
            end if;
         else 
            test_sample_cnt<= test_sample_cnt;
         end if;
      end if;
   end process;

   --Generate S_AXIS_TVALID
   process is
      variable seed1, seed2: positive;
      variable rand: real;
      variable range_of_rand : real := 10.0;
      variable rand_num: integer :=0;
   begin
      S_AXIS_TVALID <= '0';   
      wait until rising_edge(clk0) AND reset_n='1';
      S_AXIS_TVALID <= '1';
      
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;
      
      S_AXIS_TVALID <= '0';
      
      uniform(seed1, seed2, rand);
      rand_num := integer(rand*range_of_rand);
      for i in 0 to rand_num loop
         wait until rising_edge(clk0);
      end loop;
   end process;


      --Generate M_AXIS_TREADY
      process is
         variable seed1, seed2: positive;
         variable rand: real;
         variable range_of_rand : real := 10.0;
         variable rand_num: integer :=0;
      begin
         M_AXIS_TREADY <= '0';   
         wait until rising_edge(clk0) AND reset_n='1';
         M_AXIS_TREADY <= '1';
         
         uniform(seed1, seed2, rand);
         rand_num := integer(rand*range_of_rand);
         for i in 0 to rand_num loop
            wait until rising_edge(clk0);
         end loop;
         
         M_AXIS_TREADY <= '0';
         
         uniform(seed1, seed2, rand);
         rand_num := integer(rand*range_of_rand);
         for i in 0 to rand_num loop
            wait until rising_edge(clk0);
         end loop;
      end process;




   


   S_AXIS_TDATA <= test_sample_array(to_integer(test_sample_cnt));


   sample_padder_dut : entity work.sample_padder
      port map(
          --input ports 
          CLK       		=> clk0,
          RESET_N   		=> reset_n,
          --
          S_AXIS_TVALID    => S_AXIS_TVALID ,
          S_AXIS_TDATA     => S_AXIS_TDATA  ,
          S_AXIS_TREADY    => S_AXIS_TREADY ,
          S_AXIS_TLAST	   => S_AXIS_TLAST	,
          --
          M_AXIS_TDATA     => M_AXIS_TDATA  ,
          M_AXIS_TVALID    => M_AXIS_TVALID ,
          M_AXIS_TREADY    => M_AXIS_TREADY ,
          M_AXIS_TLAST	   => M_AXIS_TLAST	,
          --
          BYPASS			   => '0'
   );


   

end tb_behave;