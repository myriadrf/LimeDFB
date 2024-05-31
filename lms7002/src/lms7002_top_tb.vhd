-- ----------------------------------------------------------------------------
-- FILE:          lms7002_top_tb.vhd
-- DESCRIPTION:   Test bech for lms7002_top module
-- DATE:          11:09 2024-02-01
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.fpgacfg_pkg.all;
use work.tstcfg_pkg.all;
use work.memcfg_pkg.all;


-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity lms7002_top_tb is
end lms7002_top_tb;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture tb_behave of lms7002_top_tb is
   constant clk0_period    : time :=  8 ns;
   constant clk1_period    : time :=  8 ns;
   constant sys_clk_period : time :=  8 ns;
   
   constant c_MIMO_DDR_SAMPLES      : integer := 16;
   --signals
   signal clk0,clk1        : std_logic;
   signal sys_clk          : std_logic;
   signal reset_n          : std_logic; 
   
   signal dut1_DIQ1           : std_logic_vector(11 downto 0);
   signal dut1_ENABLE_IQSEL1  : std_logic;
    
   signal dut1_from_fpgacfg   : t_FROM_FPGACFG;
   signal dut1_from_tstcfg    : t_FROM_TSTCFG;
   signal dut1_from_memcfg    : t_FROM_MEMCFG;
   
   signal s_axis_tx_tvalid    : std_logic;
   signal s_axis_tx_tdata     : std_logic_vector(63 downto 0);
   signal s_axis_tx_tready    : std_logic;
   signal s_axis_tx_tlast     : std_logic;
   
   signal m_axis_rx_tvalid    : std_logic;
   signal m_axis_rx_tdata     : std_logic_vector(63 downto 0);
   signal m_axis_rx_tkeep     : std_logic_vector(7 downto 0);
   
   
   
   alias s_axis_tx_tdata_AI is s_axis_tx_tdata(63 downto 52);
   alias s_axis_tx_tdata_AQ is s_axis_tx_tdata(47 downto 36);
   alias s_axis_tx_tdata_BI is s_axis_tx_tdata(31 downto 20);
   alias s_axis_tx_tdata_BQ is s_axis_tx_tdata(15 downto  4);
   
   type t_TXIQ_MODE is (MIMO_DDR, SISO_DDR, TXIQ_PULSE);
   signal txiq_mode : t_TXIQ_MODE;
   
   signal ch_en     : std_logic_vector(1 downto 0);
   
   signal wait_cycles : integer;
   
   procedure set_txiq_mode (
      signal clk           : in  std_logic;
      signal txiq_mode     : in  t_TXIQ_MODE;
      signal ch_en         : in  std_logic_vector(1 downto 0);
      signal from_fpgacfg  : out t_FROM_FPGACFG
   ) is 
   begin
      report "Entering set_txiq_mode" severity NOTE;
      wait until rising_edge(clk);
      case txiq_mode is 
         when MIMO_DDR => 
            from_fpgacfg.mode              <= '0';   
            from_fpgacfg.trxiq_pulse       <= '0';           
            from_fpgacfg.ddr_en            <= '1';         
            from_fpgacfg.mimo_int_en       <= '1'; 
            from_fpgacfg.ch_en(1 downto 0) <= ch_en;
         
         when SISO_DDR => 
            from_fpgacfg.mode              <= '0';   
            from_fpgacfg.trxiq_pulse       <= '0';           
            from_fpgacfg.ddr_en            <= '1';         
            from_fpgacfg.mimo_int_en       <= '0'; 
            from_fpgacfg.ch_en(1 downto 0) <= ch_en;
            
         when TXIQ_PULSE => 
            from_fpgacfg.mode              <= '0';   
            from_fpgacfg.trxiq_pulse       <= '1';           
            from_fpgacfg.ddr_en            <= '0';         
            from_fpgacfg.mimo_int_en       <= '0'; 
            from_fpgacfg.ch_en(1 downto 0) <= ch_en;
            
         when others =>
            from_fpgacfg.mode              <= '0';   
            from_fpgacfg.trxiq_pulse       <= '0';           
            from_fpgacfg.ddr_en            <= '0';         
            from_fpgacfg.mimo_int_en       <= '0'; 
            from_fpgacfg.ch_en(1 downto 0) <= "00";
      end case;
      report "Exiting set_txiq_mode" severity NOTE;
   end procedure;
   
   procedure generate_axis_data(
      signal reset_n       : in     std_logic;
      signal clk           : in     std_logic;
      signal txiq_mode     : in     t_TXIQ_MODE;
      signal s_axis_tvalid : out    std_logic;
      signal s_axis_tdata  : inout  std_logic_vector(63 downto 0);
      signal s_axis_tready : in     std_logic;
      signal s_axis_tlast  : out    std_logic
      
   ) is 
   begin
      report "Entering generate_axis_data" severity NOTE;
      wait until rising_edge(clk);
      s_axis_tvalid     <= '0';
      s_axis_tdata <= (others=>'0');
      if (ch_en = "11" AND txiq_mode = MIMO_DDR) OR txiq_mode = TXIQ_PULSE  then 
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"001";
         s_axis_tdata(31 downto 20) <= x"002";
         s_axis_tdata(15 downto  4) <= x"003";
      elsif (ch_en = "01" AND txiq_mode = MIMO_DDR) OR txiq_mode = SISO_DDR then 
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"001";
         s_axis_tdata(31 downto 20) <= x"000";
         s_axis_tdata(15 downto  4) <= x"000";
      elsif (ch_en = "10" AND txiq_mode = MIMO_DDR) then 
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"000";
         s_axis_tdata(31 downto 20) <= x"000";
         s_axis_tdata(15 downto  4) <= x"001";
      else 
         s_axis_tdata(63 downto 52) <= x"000";
         s_axis_tdata(47 downto 36) <= x"000";
         s_axis_tdata(31 downto 20) <= x"000";
         s_axis_tdata(15 downto  4) <= x"000";
      end if;
      s_axis_tlast      <= '0';
      
      wait until rising_edge(sys_clk);
      s_axis_tvalid <= '1';
      
      for i in 0 to c_MIMO_DDR_SAMPLES-1 loop
         wait until rising_edge(sys_clk) AND s_axis_tready='1';
         case txiq_mode is 
            when MIMO_DDR =>
               if ch_en = "11" then 
                  s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52))+4); 
                  s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36))+4);
                  s_axis_tdata(31 downto 20) <= std_logic_vector(unsigned(s_axis_tdata(31 downto 20))+4);
                  s_axis_tdata(15 downto  4) <= std_logic_vector(unsigned(s_axis_tdata(15 downto  4))+4);
               elsif ch_en = "01" then
                  s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52))+2); 
                  s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36))+2);
                  s_axis_tdata(31 downto 20) <= (others=>'0');
                  s_axis_tdata(15 downto  4) <= (others=>'0');
               elsif ch_en = "10" then 
                  s_axis_tdata(63 downto 52) <= (others=>'0');
                  s_axis_tdata(47 downto 36) <= (others=>'0');
                  s_axis_tdata(31 downto 20) <= std_logic_vector(unsigned(s_axis_tdata(31 downto 20))+2);
                  s_axis_tdata(15 downto  4) <= std_logic_vector(unsigned(s_axis_tdata(15 downto  4))+2);
               else
                  s_axis_tdata(63 downto 52) <= (others=>'0');
                  s_axis_tdata(47 downto 36) <= (others=>'0');
                  s_axis_tdata(31 downto 20) <= (others=>'0');
                  s_axis_tdata(15 downto  4) <= (others=>'0');
               end if;
            when SISO_DDR =>
               s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52))+2); 
               s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36))+2);
               s_axis_tdata(31 downto 20) <= (others=>'0');
               s_axis_tdata(15 downto  4) <= (others=>'0');
               
            when TXIQ_PULSE => 
               s_axis_tdata(63 downto 52) <= std_logic_vector(unsigned(s_axis_tdata(63 downto 52))+4); 
               s_axis_tdata(47 downto 36) <= std_logic_vector(unsigned(s_axis_tdata(47 downto 36))+4);
               s_axis_tdata(31 downto 20) <= std_logic_vector(unsigned(s_axis_tdata(31 downto 20))+4);
               s_axis_tdata(15 downto  4) <= std_logic_vector(unsigned(s_axis_tdata(15 downto  4))+4);
               
            when others => 
               s_axis_tdata(63 downto 52) <= (others=>'0');
               s_axis_tdata(47 downto 36) <= (others=>'0');
               s_axis_tdata(31 downto 20) <= (others=>'0');
               s_axis_tdata(15 downto  4) <= (others=>'0');
         end case;      
      end loop;
      wait until rising_edge(sys_clk) AND s_axis_tready='1';
      s_axis_tvalid <= '0';
      report "Exiting generate_axis_data" severity NOTE;
      
   end procedure;
   
   procedure wait_sync_cycles (
      signal clk              : in std_logic;
      signal cycles_to_wait   : in integer
   ) is 
   begin 
      report "Entering wait_sync_cycles" severity NOTE;
      report "Cycles to wait: " & integer'image(cycles_to_wait);
      wait until rising_edge(clk);
      for i in 0 to cycles_to_wait loop
         wait until rising_edge(clk);
         report "Waiting" severity NOTE;
      end loop;
      report "Exiting wait_sync_cycles" severity NOTE;
   end procedure;
  
   
   
   
begin 
  
   clock0: process is
   begin
      clk0 <= '0'; wait for clk0_period/2;
      clk0 <= '1'; wait for clk0_period/2;
   end process clock0;

   clock1: process is
   begin
      --Simulate 90deg phase shift
      wait for clk1_period/4;
      loop 
         clk1 <= '0'; wait for clk1_period/2;
         clk1 <= '1'; wait for clk1_period/2;
      end loop;
   end process clock1;
   
   sys_clock: process is 
   begin 
      sys_clk <= '0'; wait for sys_clk_period/2;
      sys_clk <= '1'; wait for sys_clk_period/2;
   end process sys_clock;
   
   res: process is
   begin
      reset_n <= '0'; wait for 20 ns;
      reset_n <= '1'; wait;
   end process res;
   
   -- Design under test  
   dut1_lms7002_top : entity work.lms7002_top
   generic map(
      g_DEV_FAMILY               => "Cyclone IV E",   -- Device family
      g_IQ_WIDTH                 => 12                -- IQ bus width
   )
   port map(  
      --! @virtualbus cfg @dir in Configuration bus
      from_fpgacfg         => dut1_from_fpgacfg,   -- Signals from FPGACFG registers
      from_tstcfg          => dut1_from_tstcfg ,   -- Signals from TSTCFG registers
      from_memcfg          => dut1_from_memcfg ,   -- Signals from MEMCFG registers @end
      --! @virtualbus LMS_PORT1 @dir out interface
      MCLK1                => clk0,  --! TX interface clock
      FCLK1                => open,  --! TX interface feedback clock
      DIQ1                 => dut1_DIQ1,           --! DIQ1 data bus
      ENABLE_IQSEL1        => dut1_ENABLE_IQSEL1,  --! IQ select flag for DIQ1 data
      TXNRX1               => open,  --! LMS_PORT1 direction select @end
      --! @virtualbus LMS_PORT2 @dir in interface
      MCLK2                => clk1,          --! RX interface clock
      FCLK2                => open,          --! RX interface feedback clock
      DIQ2                 => dut1_DIQ1,     --! DIQ2 data bus
      ENABLE_IQSEL2        => dut1_ENABLE_IQSEL1,           --! IQ select flag for DIQ2 data
      TXNRX2               => open,          --! LMS_PORT2 direction select @end
      --! @virtualbus LMS_MISC @dir out LMS miscellaneous control ports
      RESET                => open,   --! LMS hardware reset, active low
      TXEN                 => open,   --! TX hard power off
      RXEN                 => open,   --! RX hard power off
      CORE_LDO_EN          => open,   --! LMS internal LDO enable control @end
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      s_axis_tx_areset_n   => reset_n,          -- TX interface active low reset
      s_axis_tx_aclk       => sys_clk,          -- TX FIFO write clock
      s_axis_tx_tvalid     => s_axis_tx_tvalid, -- TX FIFO write request
      s_axis_tx_tdata      => s_axis_tx_tdata,  -- TX FIFO data
      s_axis_tx_tready     => s_axis_tx_tready, -- TX FIFO write full 
      s_axis_tx_tlast      => s_axis_tx_tlast,  --!  @end
      --! @virtualbus m_axis_rx @dir out Receive AXIS bus
      m_axis_rx_areset_n   => reset_n,       -- RX interface active low reset
      m_axis_rx_aclk       => sys_clk,       -- RX FIFO read clock
      m_axis_rx_tvalid     => m_axis_rx_tvalid,          -- Received data from DIQ2 port valid signal
      m_axis_rx_tdata      => m_axis_rx_tdata, -- Received data from DIQ2 port 
      m_axis_rx_tkeep      => m_axis_rx_tkeep,
      m_axis_rx_tready     => '1',  -- @end
      -- misc
      tx_active            => open, -- TX antenna enable flag
      rx_active            => open  -- RX sample counter enable
   );
   

   tb_transmit_proc: process is
   begin
      dut1_from_fpgacfg.tx_en  <= '0'; 
      wait until reset_n='1' AND rising_edge(sys_clk);
      
      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A AND B channels
      txiq_mode <= MIMO_DDR;
      ch_en     <= "11";
      wait until rising_edge(sys_clk);
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg );
      
      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';
      
      -- Generate IQ data
      generate_axis_data (
         reset_n        => reset_n           ,      
         clk            => sys_clk           ,
         txiq_mode      => txiq_mode         ,
         s_axis_tvalid  => s_axis_tx_tvalid  ,
         s_axis_tdata   => s_axis_tx_tdata,
         s_axis_tready  => s_axis_tx_tready  ,  
         s_axis_tlast   => s_axis_tx_tlast     
      );
      
      wait_cycles <= 64;
      wait until rising_edge(sys_clk);
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- Disable TX
      wait until rising_edge(sys_clk);
      report "Disabling tx" severity NOTE;
      dut1_from_fpgacfg.tx_en <= '0';
      
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channels
      txiq_mode <= MIMO_DDR;
      ch_en     <= "01";
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg );
      
      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';
      
      -- Generate IQ data
      generate_axis_data (
         reset_n        => reset_n           ,      
         clk            => sys_clk           ,
         txiq_mode      => txiq_mode         ,
         s_axis_tvalid  => s_axis_tx_tvalid  ,
         s_axis_tdata   => s_axis_tx_tdata,
         s_axis_tready  => s_axis_tx_tready  ,  
         s_axis_tlast   => s_axis_tx_tlast     
      );
      
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';
      
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable B channel
      txiq_mode <= MIMO_DDR;
      ch_en     <= "10";
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg );
      
      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';
      
      -- Generate IQ data
      generate_axis_data (
         reset_n        => reset_n           ,      
         clk            => sys_clk           ,
         txiq_mode      => txiq_mode         ,
         s_axis_tvalid  => s_axis_tx_tvalid  ,
         s_axis_tdata   => s_axis_tx_tdata,
         s_axis_tready  => s_axis_tx_tready  ,  
         s_axis_tlast   => s_axis_tx_tlast     
      );
      
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';
      
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channel
      txiq_mode <= SISO_DDR;
      ch_en     <= "01";  -- Does not matter in SISO DDR
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg );
      
      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';
      
      -- Generate IQ data
      generate_axis_data (
         reset_n        => reset_n           ,      
         clk            => sys_clk           ,
         txiq_mode      => txiq_mode         ,
         s_axis_tvalid  => s_axis_tx_tvalid  ,
         s_axis_tdata   => s_axis_tx_tdata   ,
         s_axis_tready  => s_axis_tx_tready  ,  
         s_axis_tlast   => s_axis_tx_tlast     
      );
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';
      
            -- ----------------------------------------------------------------------------
      -- Set txiq_mode and enable A channel
      txiq_mode <= TXIQ_PULSE;
      ch_en     <= "01";  -- Does not matter in TXIQ_PULSE
      set_txiq_mode(clk=> sys_clk, txiq_mode => txiq_mode, ch_en => ch_en, from_fpgacfg => dut1_from_fpgacfg );
      
      -- Enable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '1';
      
      -- Generate IQ data
      generate_axis_data (
         reset_n        => reset_n           ,      
         clk            => sys_clk           ,
         txiq_mode      => txiq_mode         ,
         s_axis_tvalid  => s_axis_tx_tvalid  ,
         s_axis_tdata   => s_axis_tx_tdata   ,
         s_axis_tready  => s_axis_tx_tready  ,  
         s_axis_tlast   => s_axis_tx_tlast     
      );
      wait_cycles <= 64;
      wait_sync_cycles(sys_clk, wait_cycles);
      
      -- Disable TX
      wait until rising_edge(sys_clk);
      dut1_from_fpgacfg.tx_en <= '0';
      
      wait;
   end process tb_transmit_proc;
   
   
   

end tb_behave;

