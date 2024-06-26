-- ----------------------------------------------------------------------------
-- FILE:          tx_top_tb.vhd
-- DESCRIPTION:   Test bench for tx_path_top module
-- DATE:          June 25 2024
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use work.tx_top_pkg.all;
   use std.env.finish;

entity TX_TOP_TB is
end entity TX_TOP_TB;

architecture BENCH of TX_TOP_TB is

   -- Constant
   constant C_S_AXIS_CLK_PERIOD           : time := 3 ns;
   constant C_M_AXIS_CLK_PERIOD           : time := 4 ns;
   constant C_RX_CLK_PERIOD               : time := 5 ns;
   -- Ports
   signal s_axis_areset_n                 : std_logic;
   signal s_axis_aclk                     : std_logic;
   signal s_axis_tvalid                   : std_logic;
   signal s_axis_tdata                    : std_logic_vector(127 downto 0);
   signal s_axis_tready                   : std_logic;
   signal s_axis_tlast                    : std_logic;

   signal m_axis_areset_n                 : std_logic;
   signal m_axis_aclk                     : std_logic;
   signal m_axis_tvalid                   : std_logic;
   signal m_axis_tdata                    : std_logic_vector(63 downto 0);
   signal m_axis_tready                   : std_logic;
   signal m_axis_tlast                    : std_logic;

   signal s_axis_in                       : T_S_AXIS_IN;
   signal s_axis_out                      : T_S_AXIS_OUT;

   signal ch_en                           : std_logic_vector(1 downto 0);
   signal sample_width                    : std_logic_vector(1 downto 0);

   -- arbitrary large number 32kB of data

   signal m_axis_clk_count                : integer;
   signal s_axis_clk_count                : integer;

   -- tb signals
   signal ai_data                         : std_logic_vector(15 downto 0); -- T_DATAARRAY;
   signal aq_data                         : std_logic_vector(15 downto 0); -- T_DATAARRAY;
   signal bi_data                         : std_logic_vector(15 downto 0); -- T_DATAARRAY;
   signal bq_data                         : std_logic_vector(15 downto 0); -- T_DATAARRAY;
   signal data_counter                    : integer;
   signal pct_loss_cnt                    : integer;
   signal data_counter_rst                : std_logic := '0';
   signal ai_data_arr                     : T_DATAARRAY;
   signal aq_data_arr                     : T_DATAARRAY;
   signal bi_data_arr                     : T_DATAARRAY;
   signal bq_data_arr                     : T_DATAARRAY;
   -- rx related signals
   signal rx_clk                          : std_logic;
   signal rx_sample_nr                    : std_logic_vector(63 downto 0);
   signal pct_sync_dis                    : std_logic;
   signal pct_loss_flg                    : std_logic;
   signal pct_loss_flg_clr                : std_logic;

   component TX_PATH_TOP is
      generic (
         G_BUFF_COUNT : integer := 4
      );
      port (
         S_AXIS_IQPACKET_ARESET_N      : in    std_logic;
         S_AXIS_IQPACKET_ACLK          : in    std_logic;
         S_AXIS_IQPACKET_TVALID        : in    std_logic;
         S_AXIS_IQPACKET_TDATA         : in    std_logic_vector(127 downto 0);
         S_AXIS_IQPACKET_TREADY        : out   std_logic;
         S_AXIS_IQPACKET_TLAST         : in    std_logic;
         --
         M_AXIS_IQSAMPLE_ARESET_N      : in    std_logic;
         M_AXIS_IQSAMPLE_ACLK          : in    std_logic;
         M_AXIS_IQSAMPLE_TVALID        : out   std_logic;
         M_AXIS_IQSAMPLE_TDATA         : out   std_logic_vector(63 downto 0);
         M_AXIS_IQSAMPLE_TREADY        : in    std_logic;
         M_AXIS_IQSAMPLE_TLAST         : out   std_logic;
         --
         RX_SAMPLE_NR                  : in    std_logic_vector(63 downto 0);
         RX_CLK                        : in    std_logic;
         PCT_SYNC_DIS                  : in    std_logic;
         PCT_LOSS_FLG                  : out   std_logic;
         PCT_LOSS_FLG_CLR              : in    std_logic;
         CFG_CH_EN                     : in    std_logic_vector(1 downto 0);
         CFG_SAMPLE_WIDTH              : in    std_logic_vector(1 downto 0);
         RESET_N                       : in    std_logic
      );
   end component;

begin

   s_axis_in.ARESET_N <= s_axis_areset_n;
   s_axis_in.ACLK     <= s_axis_aclk;
   s_axis_in.TREADY   <= s_axis_tready;
   s_axis_tvalid      <= s_axis_out.TVALID;
   s_axis_tdata       <= s_axis_out.TDATA;
   s_axis_tlast       <= s_axis_out.TLAST;

   inst0_tx_top : TX_PATH_TOP
      generic map (
         G_BUFF_COUNT => 4
      )
      port map (
         S_AXIS_IQPACKET_ARESET_N => s_axis_areset_n,
         S_AXIS_IQPACKET_ACLK     => s_axis_aclk,
         S_AXIS_IQPACKET_TVALID   => s_axis_tvalid,
         S_AXIS_IQPACKET_TDATA    => s_axis_tdata,
         S_AXIS_IQPACKET_TREADY   => s_axis_tready,
         S_AXIS_IQPACKET_TLAST    => s_axis_tlast,
         --
         M_AXIS_IQSAMPLE_ARESET_N => m_axis_areset_n,
         M_AXIS_IQSAMPLE_ACLK     => m_axis_aclk,
         M_AXIS_IQSAMPLE_TVALID   => m_axis_tvalid,
         M_AXIS_IQSAMPLE_TDATA    => m_axis_tdata,
         M_AXIS_IQSAMPLE_TREADY   => m_axis_tready,
         M_AXIS_IQSAMPLE_TLAST    => m_axis_tlast,
         --
         RX_SAMPLE_NR     => rx_sample_nr,
         RX_CLK           => rx_clk,
         PCT_SYNC_DIS     => pct_sync_dis,
         PCT_LOSS_FLG     => pct_loss_flg,
         PCT_LOSS_FLG_CLR => pct_loss_flg_clr,
         CFG_CH_EN        => ch_en,
         CFG_SAMPLE_WIDTH => sample_width,
         RESET_N          => s_axis_areset_n
      );

   ------------------------------------------
   RESET_GEN : process is
   begin

      s_axis_areset_n <= '0';
      m_axis_areset_n <= '0';
      wait for 1000 ns;
      s_axis_areset_n <= '1';
      m_axis_areset_n <= '1';
      wait;

   end process RESET_GEN;

   ------------------------------------------
   S_AXIS_CLK_GEN : process is
   begin

      if (s_axis_aclk = '0') then
         s_axis_aclk <= '1';
      else
         s_axis_aclk <= '0';
      end if;

      wait for C_S_AXIS_CLK_PERIOD / 2;

   end process S_AXIS_CLK_GEN;

   ------------------------------------------
   RX_CLK_GEN : process is
   begin

      if (rx_clk = '0') then
         rx_clk <= '1';
      else
         rx_clk <= '0';
      end if;

      wait for C_RX_CLK_PERIOD / 2;

   end process RX_CLK_GEN;

   ------------------------------------------
   M_AXIS_CLK_GEN : process is
   begin

      if (m_axis_aclk = '0') then
         m_axis_aclk <= '1';
      else
         m_axis_aclk <= '0';
      end if;

      wait for C_M_AXIS_CLK_PERIOD / 2;

   end process M_AXIS_CLK_GEN;

   ------------------------------------------
   -- s_axis clock counter
   S_AXIS_CLK_CNT : process (s_axis_aclk, s_axis_areset_n) is
   begin

      if (s_axis_areset_n = '0') then
         s_axis_clk_count <= 0;
      elsif rising_edge(s_axis_aclk) then
         s_axis_clk_count <= s_axis_clk_count + 1;
      end if;

   end process S_AXIS_CLK_CNT;

   -- m_axis clock counter
   M_AXIS_CLK_CNT : process (m_axis_aclk, m_axis_areset_n) is
   begin

      if (m_axis_areset_n = '0') then
         m_axis_clk_count <= 0;
      elsif rising_edge(m_axis_aclk) then
         m_axis_clk_count <= m_axis_clk_count + 1;
      end if;

   end process M_AXIS_CLK_CNT;

   -- pct loss counter
   PCT_LOSS_CNT_PROC : process (rx_clk, m_axis_areset_n) is
   begin

      if (m_axis_areset_n = '0') then
         pct_loss_cnt     <= 0;
         pct_loss_flg_clr <= '1';
      elsif rising_edge(rx_clk) then
         if (pct_loss_flg = '1' and pct_loss_flg_clr = '0') then
            pct_loss_cnt     <= pct_loss_cnt + 1;
            pct_loss_flg_clr <= '1';
         elsif (pct_loss_flg = '0') then
            pct_loss_flg_clr <= '0';
         end if;
      end if;

   end process PCT_LOSS_CNT_PROC;

   -- rx_sample_nr generator
   RX_SAMPLE_NR_PROC : process (rx_clk, m_axis_areset_n) is
   begin

      if (m_axis_areset_n = '0') then
         rx_sample_nr <= (others => '0');
      elsif rising_edge(rx_clk) then
         rx_sample_nr <= std_logic_vector(unsigned(rx_sample_nr) + 1);
      end if;

   end process RX_SAMPLE_NR_PROC;

   ------------------------------------------
   DATA_GEN : process is
   begin

      -- TODO add timeout logic to avoid stalling forever

      s_axis_out.TVALID <= '0';
      s_axis_out.TDATA  <= (others => '0');
      s_axis_out.TLAST  <= '0';
      -- wait for 1000 * (C_S_AXIS_CLK_PERIOD / 2);
      skip_clocks(s_axis_in.ACLK, 1000);
      sample_width <= "00";

      pct_sync_dis <= '1';

      sample_width <= "00";
      ch_en        <= "01";
      skip_clocks(s_axis_in.ACLK, 100);
      -- p_send_data_packet(s_axis_in, s_axis_out, 21, 1000, rx_sample_nr, '0');

      -- make sure we are not in reset

      if (m_axis_areset_n = '0') then
         wait until m_axis_areset_n = '1';
      end if;

      if (s_axis_areset_n = '0') then
         wait until s_axis_areset_n = '1';
      end if;

      p_test_16bit_data(
                        interface_in     => s_axis_in,
                        interface_out    => s_axis_out,
                        ai_data_arr      => ai_data_arr,
                        aq_data_arr      => aq_data_arr,
                        bi_data_arr      => bi_data_arr,
                        bq_data_arr      => bq_data_arr,
                        data_counter     => data_counter,
                        data_counter_rst => data_counter_rst,
                        ch_en            => ch_en,
                        sample_width     => sample_width,
                        num_packets      => 11,
                        packetlen        => 201
                     );

      p_test_12bit_data(
                        interface_in     => s_axis_in,
                        interface_out    => s_axis_out,
                        ai_data_arr      => ai_data_arr,
                        aq_data_arr      => aq_data_arr,
                        bi_data_arr      => bi_data_arr,
                        bq_data_arr      => bq_data_arr,
                        data_counter     => data_counter,
                        data_counter_rst => data_counter_rst,
                        ch_en            => ch_en,
                        sample_width     => sample_width,
                        num_packets      => 11,
                        packetlen        => 201
                     );

      p_test_sync(
                  interface_in     => s_axis_in,
                  interface_out    => s_axis_out,
                  data_counter     => data_counter,
                  data_counter_rst => data_counter_rst,
                  ch_en            => ch_en,
                  sample_width     => sample_width,
                  rx_sample_nr     => rx_sample_nr,
                  pct_loss_cnt     => pct_loss_cnt,
                  pct_sync_dis     => pct_sync_dis,
                  num_packets      => 11,
                  packetlen        => 201
               );

      -- if we get here, it means all tests passed

      report "Simulation finished, no errors found"
         severity NOTE;
      finish;

      wait;

   end process DATA_GEN;

   DATA_RECV : process (m_axis_aclk, m_axis_areset_n) is
   begin

      if (m_axis_areset_n = '0') then
         m_axis_tready <= '0';
         data_counter  <= 0;
      elsif rising_edge(m_axis_aclk) then
         if (data_counter_rst = '0') then
            m_axis_tready <= '1';
            if (m_axis_tvalid = '1') then
               ai_data_arr(data_counter) <= m_axis_tdata(63   downto   48);
               aq_data_arr(data_counter) <= m_axis_tdata(47   downto   32);
               bi_data_arr(data_counter) <= m_axis_tdata(31   downto   16);
               bq_data_arr(data_counter) <= m_axis_tdata(15   downto   0);
               ai_data                   <= m_axis_tdata(63   downto   48);
               aq_data                   <= m_axis_tdata(47   downto   32);
               bi_data                   <= m_axis_tdata(31   downto   16);
               bq_data                   <= m_axis_tdata(15   downto   0);
               data_counter              <= data_counter + 1;
            end if;
         else
            data_counter <= 0;
         end if;
      end if;

   end process DATA_RECV;

end architecture BENCH;
