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
   constant clk1_period    : time := 25 ns; 
   --signals
   signal clk0,clk1        : std_logic;
   signal reset_n          : std_logic; 
   
   constant c_VENDOR       : string := "XILINX";
   constant c_DATA_WIDTH   : integer := 32;
   constant c_FIFO_DEPTH   : integer := 256;
   constant c_PACKET_MODE  : boolean := true;
   
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

   signal max_packet_words : integer := 8;
   signal tlast_gen        : boolean := true;


   procedure generate_axis_tdata(
      signal n_words     : in     integer;
      signal gen_tlast   : in     BOOLEAN;
      signal axis_aclk   : in     std_logic;
      signal axis_tvalid : out    std_logic;
      signal axis_tdata  : inout  std_logic_vector(c_DATA_WIDTH-1 downto 0);
      signal axis_tkeep  : out    std_logic_vector(c_DATA_WIDTH/8 - 1 downto 0);
      signal axis_tready : in     std_logic;
      signal axis_tlast  : out    std_logic
   ) is 
   begin
      axis_tvalid <= '0';
      axis_tkeep  <= (others=>'1');
      axis_tlast  <= '0';
      wait until rising_edge(axis_aclk);
      axis_tvalid <= '1';
      for i in 0 to n_words-1 loop
         wait until rising_edge(axis_aclk) and axis_tready='1';
         axis_tdata<=std_logic_vector(unsigned(axis_tdata) + 1);
         
         if i = n_words - 2 then 
            if gen_tlast then 
               axis_tlast  <= '1';
            end if;
         end if;
      end loop;
      axis_tvalid <= '0';
      axis_tlast  <= '0';

   end procedure;


   signal m_axis_tid    : std_logic_vector(7 downto 0);
   signal m_axis_tdest : std_logic_vector(7 downto 0);
   signal m_axis_tuser : std_logic_vector(0 downto 0);

   signal s_status_depth         : std_logic_vector(4 downto 0); 
   signal s_status_depth_commit  : std_logic_vector(4 downto 0);
   signal m_status_depth         : std_logic_vector(4 downto 0);
   signal m_status_depth_commit  : std_logic_vector(4 downto 0);




   
  
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
   
   ---- Design under test  
      dut_axi_stream_fifo : entity work.axis_fifo
      generic map(
         g_VENDOR      => c_VENDOR, 
         g_DATA_WIDTH  => c_DATA_WIDTH,
         g_FIFO_DEPTH  => c_FIFO_DEPTH,
         g_PACKET_MODE => c_PACKET_MODE
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


--fifo_axis_wrap : entity work.fifo_axis_wrap
--   generic map(
--      g_CLOCKING_MODE      => "independent_clock", -- "common_clock" or "independent_clock"
--      g_PACKET_FIFO        => "true",            -- Packet FIFO mode
--      g_FIFO_DEPTH         => 16,
--      g_TDATA_WIDTH        => 32,
--      g_RD_DATA_COUNT_WIDTH=> 4,
--      g_WR_DATA_COUNT_WIDTH=> 4
--   )
--   port map(
--      s_axis_aresetn       => s_axis_aresetn,
--      s_axis_aclk          => clk0,
--      s_axis_tvalid        => s_axis_tvalid,
--      s_axis_tready        => s_axis_tready,
--      s_axis_tdata         => s_axis_tdata,
--      s_axis_tkeep         => s_axis_tkeep,
--      s_axis_tlast         => s_axis_tlast,
--   
--      m_axis_aclk          => clk1,
--      m_axis_tvalid        => m_axis_tvalid,
--      m_axis_tready        => m_axis_tready,
--      m_axis_tdata         => m_axis_tdata,
--      m_axis_tkeep         => m_axis_tkeep,
--      m_axis_tlast         => m_axis_tlast,
--   
--      almost_empty_axis    => open, 
--      almost_full_axis     => open, 
--      rd_data_count_axis   => open, 
--      wr_data_count_axis   => open
--   ); 


   process is 
   begin 
      tlast_gen     <= true;
      s_axis_tvalid <= '0';
      s_axis_tdata  <= (others=>'0');
      s_axis_tkeep  <= (others=>'1');
      s_axis_tlast  <= '0';
      wait until rising_edge(clk0) AND s_axis_aresetn='1';
      -- Write full packet
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      wait until rising_edge(clk0);
      for i in 0 to 512 loop
         wait until rising_edge(clk0);
      end loop;

      -- Write part of the packet, no tlast
      max_packet_words  <= 3;
      tlast_gen <= false;
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      wait until rising_edge(clk0);
      wait until rising_edge(clk0);

      for i in 0 to 512 loop
         wait until rising_edge(clk0);
      end loop;

      -- Write rest of the packet packet, with tlast
      max_packet_words  <= 4;
      tlast_gen         <= false;
      wait until rising_edge(clk0);
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      -- Fill whole fifo without tlast
      max_packet_words  <= 256;
      tlast_gen         <= FALSE;
      wait until rising_edge(clk0);
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      for i in 0 to 16384 loop
         wait until rising_edge(clk0);
      end loop;

      -- Fill whole fifo without tlast
      max_packet_words  <= 3;
      tlast_gen         <= FALSE;
      wait until rising_edge(clk0);
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      -- Fill whole fifo without tlast
      max_packet_words  <= 3;
      tlast_gen         <= TRUE;
      wait until rising_edge(clk0);
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      -- Fill whole fifo without tlast
      max_packet_words  <= 3;
      tlast_gen         <= FALSE;
      wait until rising_edge(clk0);
      generate_axis_tdata(
         n_words      => max_packet_words, 
         gen_tlast    => tlast_gen, 
         axis_aclk    => clk0, 
         axis_tvalid  => s_axis_tvalid, 
         axis_tdata   => s_axis_tdata, 
         axis_tkeep   => s_axis_tkeep, 
         axis_tready  => s_axis_tready, 
         axis_tlast   => s_axis_tlast
      );

      for i in 0 to 512 loop
         wait until rising_edge(clk0);
      end loop;

         -- Fill whole fifo without tlast
         max_packet_words  <= 3;
         tlast_gen         <= TRUE;
         wait until rising_edge(clk0);
         generate_axis_tdata(
            n_words      => max_packet_words, 
            gen_tlast    => tlast_gen, 
            axis_aclk    => clk0, 
            axis_tvalid  => s_axis_tvalid, 
            axis_tdata   => s_axis_tdata, 
            axis_tkeep   => s_axis_tkeep, 
            axis_tready  => s_axis_tready, 
            axis_tlast   => s_axis_tlast
         );
         
         
      for i in 0 to 512 loop
         wait until rising_edge(clk0);
      end loop;
      
	-- Fill whole fifo with tlast
         max_packet_words  <= 256;
         tlast_gen         <= TRUE;
         wait until rising_edge(clk0);
         generate_axis_tdata(
            n_words      => max_packet_words, 
            gen_tlast    => tlast_gen, 
            axis_aclk    => clk0, 
            axis_tvalid  => s_axis_tvalid, 
            axis_tdata   => s_axis_tdata, 
            axis_tkeep   => s_axis_tkeep, 
            axis_tready  => s_axis_tready, 
            axis_tlast   => s_axis_tlast
         );
         
      for i in 0 to 16384 loop
         wait until rising_edge(clk0);
      end loop;

	-- Fill part of fifo without tlast
         max_packet_words  <= 16;
         tlast_gen         <= FALSE;
         wait until rising_edge(clk0);
         generate_axis_tdata(
            n_words      => max_packet_words, 
            gen_tlast    => tlast_gen, 
            axis_aclk    => clk0, 
            axis_tvalid  => s_axis_tvalid, 
            axis_tdata   => s_axis_tdata, 
            axis_tkeep   => s_axis_tkeep, 
            axis_tready  => s_axis_tready, 
            axis_tlast   => s_axis_tlast
         );
         
      for i in 0 to 512 loop
         wait until rising_edge(clk0);
      end loop;
      
      	-- Fill part of fifo with tlast
         max_packet_words  <= 16;
         tlast_gen         <= TRUE;
         wait until rising_edge(clk0);
         generate_axis_tdata(
            n_words      => max_packet_words, 
            gen_tlast    => tlast_gen, 
            axis_aclk    => clk0, 
            axis_tvalid  => s_axis_tvalid, 
            axis_tdata   => s_axis_tdata, 
            axis_tkeep   => s_axis_tkeep, 
            axis_tready  => s_axis_tready, 
            axis_tlast   => s_axis_tlast
         );

      wait;
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
         tdata         <= (others=>'0');
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

