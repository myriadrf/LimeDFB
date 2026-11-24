-- ----------------------------------------------------------------------------
-- FILE:          slaveFIFO5b_sched_tb.vhd
-- DESCRIPTION:   Thread scheduling testbench for slaveFIFO5b (ctrl_poll_skip, data_out_idle_skip).
--                Behavioural FX3 model: 1024-word DMA buffers per socket, flags derived
--                from the buffer state of the addressed socket (no 3-cycle flag latency,
--                the DUT waits for it anyway). FPGA side: TX FIFO drained and RX FIFO filled
--                at a constant sample rate, control packets injected periodically.
--                Reports TX underrun / RX overflow cycles, transferred words and the
--                worst control-packet latency. Not cycle-exact to the FX3; for A/B only.
-- Run (GHDL):    ghdl -a --std=08 slaveFIFO5b.vhd slaveFIFO5b_sched_tb.vhd
--                ghdl -r --std=08 slaveFIFO5b_sched_tb -gG_SKIP=16
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity slaveFIFO5b_sched_tb is
   generic (
      G_SKIP      : integer := 0;      -- ctrl_poll_skip
      G_RATE_PPM  : integer := 460000; -- RX (FPGA->PC) stream rate, words/cycle * 1e6 (0.46 = 184 MB/s)
      G_TX_RATE_PPM : integer := -1;   -- TX (PC->FPGA) rate; -1 = same as G_RATE_PPM, 0 = no TX (EP01 empty)
      G_EP01_SKIP : integer := 0;      -- data_out_idle_skip
      G_CYCLES    : integer := 400000; -- simulated cycles (4 ms at 100 MHz)
      G_HOST_GAP  : integer := 0       -- cycles before the FX3 offers the next DMA buffer
   );
end entity;

architecture sim of slaveFIFO5b_sched_tb is
   constant C_BUF      : integer := 1024;          -- words per 4 KB DMA buffer
   constant C_TX_DEPTH : integer := 2048;          -- EP01 8 KB
   constant C_RX_DEPTH : integer := 8192;          -- EP81 32 KB
   constant C_CT_DEPTH : integer := 256;           -- EP0F / EP8F 1 KB
   constant C_TX_PREFILL : integer := 1024;

   signal clk, reset_n : std_logic := '0';
   signal faddr        : std_logic_vector(4 downto 0);
   signal slrd, slwr, sloe, pktend : std_logic;
   signal flaga, flagb : std_logic := '0';

   signal tx_lvl  : integer := 0;    -- FPGA TX FIFO words (socket0)
   signal rx_lvl  : integer := 0;    -- FPGA RX FIFO words (socket2)
   signal ci_lvl  : integer := 0;    -- FPGA control IN FIFO words (socket3)
   signal co_pend : integer := 0;    -- control OUT words waiting in FX3 (socket1)

   -- FX3 buffer model: words left in current buffer (OUT) / free in current buffer (IN)
   type int_arr is array (0 to 3) of integer;
   signal fx_left : int_arr := (others => C_BUF);
   signal fx_gap  : int_arr := (others => 0);

   signal done : boolean := false;
begin
   clk <= not clk after 5 ns when not done;
   reset_n <= '1' after 100 ns;

   dut : entity work.slaveFIFO5b
   generic map (
      num_of_sockets => 4, data_width => 32, data_dma_size => 4096, control_dma_size => 4096,
      data_pct_size => 4096, control_pct_size => 64,
      socket0_wrusedw_size => 12, socket0_rdusedw_size => 12,
      socket1_wrusedw_size => 9,  socket1_rdusedw_size => 9,
      socket2_wrusedw_size => 14, socket2_rdusedw_size => 14,
      socket3_wrusedw_size => 9,  socket3_rdusedw_size => 9,
      socket0_max_wrwords_int => C_TX_DEPTH, socket1_max_wrwords_int => C_CT_DEPTH,
      socket2_max_wrwords_int => C_RX_DEPTH, socket3_max_wrwords_int => C_CT_DEPTH,
      ctrl_poll_skip => G_SKIP, data_out_idle_skip => G_EP01_SKIP)
   port map (
      reset_n => reset_n, clk => clk, clk_out => open, usb_speed => '1', slcs => open,
      fdata => open, faddr => faddr, slrd => slrd, sloe => sloe, slwr => slwr,
      flaga => flaga, flagb => flagb, flagc => '0', flagd => '0', pktend => pktend, EPSWITCH => open,
      socket0_fifo_reset_n => '1', socket0_fifo_data => open, socket0_fifo_q => (others => '0'),
      socket0_fifo_wrusedw => std_logic_vector(to_unsigned(tx_lvl, 12)), socket0_fifo_rdusedw => (others => '0'),
      socket0_fifo_wr => open, socket0_fifo_rd => open,
      socket1_fifo_reset_n => '1', socket1_fifo_data => open, socket1_fifo_q => (others => '0'),
      socket1_fifo_wrusedw => (others => '0'), socket1_fifo_rdusedw => (others => '0'),
      socket1_fifo_wr => open, socket1_fifo_rd => open,
      socket2_fifo_data => open, socket2_fifo_q => (others => '0'),
      socket2_fifo_wrusedw => (others => '0'), socket2_fifo_rdusedw => std_logic_vector(to_unsigned(rx_lvl, 14)),
      socket2_fifo_wr => open, socket2_fifo_rd => open,
      socket3_fifo_data => open, socket3_fifo_q => (others => '0'),
      socket3_fifo_wrusedw => (others => '0'), socket3_fifo_rdusedw => std_logic_vector(to_unsigned(ci_lvl, 9)),
      socket3_fifo_wr => open, socket3_fifo_rd => open,
      GPIF_busy => open);

   -- FX3 flags for the addressed socket. OUT sockets (0,1): buffer ready and > 3 words left
   -- (watermark covering the read pipeline). IN sockets (2,3): buffer free and > 2 words of room.
   flag_p : process(all)
      variable a : integer;
      variable rdy : boolean;
   begin
      a := to_integer(unsigned(faddr(1 downto 0)));
      if a = 1 then
         rdy := co_pend > 0;
      elsif a = 0 and G_TX_RATE_PPM = 0 then
         rdy := false;
      else
         rdy := fx_gap(a) = 0;
      end if;
      if a = 0 or a = 1 then
         if a = 1 then
            flaga <= '1' when rdy else '0';
            flagb <= '1' when co_pend > 3 else '0';
         else
            flaga <= '1' when rdy else '0';
            flagb <= '1' when rdy and fx_left(a) > 3 else '0';
         end if;
      else
         flaga <= '1' when rdy else '0';
         flagb <= '1' when rdy and fx_left(a) > 2 else '0';
      end if;
   end process;

   model : process(clk)
      variable acc_tx, acc_rx : integer := 0;
      variable a : integer;
      variable cyc : integer := 0;
      variable tx_under, rx_over, tx_words, rx_words : integer := 0;
      variable co_t0, ci_t0, co_lat_max, ci_lat_max, co_n, ci_n : integer := 0;
      variable co_wait, ci_wait : boolean := false;
      variable started : boolean := false;
      variable tx_rate : integer;
   begin
      if rising_edge(clk) then
         if reset_n = '1' then
            cyc := cyc + 1;
            a := to_integer(unsigned(faddr(1 downto 0)));
            -- GPIF transfers
            if slrd = '0' then
               if a = 0 then
                  tx_lvl <= tx_lvl + 1; tx_words := tx_words + 1;
                  fx_left(0) <= fx_left(0) - 1;
                  if fx_left(0) = 1 then fx_left(0) <= C_BUF; fx_gap(0) <= G_HOST_GAP; end if;
               elsif a = 1 and co_pend > 0 then
                  co_pend <= co_pend - 1;
               end if;
            end if;
            if slwr = '0' then
               if a = 2 then
                  rx_words := rx_words + 1;
                  fx_left(2) <= fx_left(2) - 1;
                  if fx_left(2) = 1 then fx_left(2) <= C_BUF; fx_gap(2) <= G_HOST_GAP; end if;
               elsif a = 3 and ci_lvl > 0 then
                  ci_lvl <= ci_lvl - 1;
               end if;
            end if;
            if pktend = '0' and a = 2 then
               fx_left(2) <= C_BUF; fx_gap(2) <= G_HOST_GAP;
            end if;
            for i in 0 to 3 loop
               if fx_gap(i) > 0 then fx_gap(i) <= fx_gap(i) - 1; end if;
            end loop;

            -- FPGA side: sample-rate drain / fill (TX starts after a prefill, like the txpct buffer)
            if G_TX_RATE_PPM < 0 then tx_rate := G_RATE_PPM; else tx_rate := G_TX_RATE_PPM; end if;
            acc_tx := acc_tx + tx_rate; acc_rx := acc_rx + G_RATE_PPM;
            if not started and tx_lvl >= C_TX_PREFILL and tx_rate > 0 then started := true; end if;
            if acc_tx >= 1000000 then
               acc_tx := acc_tx - 1000000;
               if started then
                  if tx_lvl > 0 then
                     if slrd = '0' and a = 0 then tx_lvl <= tx_lvl; else tx_lvl <= tx_lvl - 1; end if;
                  else
                     tx_under := tx_under + 1;
                  end if;
               end if;
            end if;
            if acc_rx >= 1000000 then
               acc_rx := acc_rx - 1000000;
               if rx_lvl < C_RX_DEPTH then
                  if slwr = '0' and a = 2 then rx_lvl <= rx_lvl; else rx_lvl <= rx_lvl + 1; end if;
               else
                  rx_over := rx_over + 1;
               end if;
            elsif slwr = '0' and a = 2 and rx_lvl > 0 then
               rx_lvl <= rx_lvl - 1;
            end if;

            -- control traffic: one 16-word packet each way every 20000 cycles, offset
            if cyc mod 20000 = 5000 and not co_wait then
               co_pend <= 16; co_wait := true; co_t0 := cyc;
            end if;
            if co_wait and co_pend = 0 and cyc > co_t0 + 1 then
               co_wait := false; co_n := co_n + 1;
               if cyc - co_t0 > co_lat_max then co_lat_max := cyc - co_t0; end if;
            end if;
            if cyc mod 20000 = 15000 and not ci_wait then
               ci_lvl <= 16; ci_wait := true; ci_t0 := cyc;
            end if;
            if ci_wait and ci_lvl = 0 and cyc > ci_t0 + 1 then
               ci_wait := false; ci_n := ci_n + 1;
               if cyc - ci_t0 > ci_lat_max then ci_lat_max := cyc - ci_t0; end if;
            end if;

            if cyc = G_CYCLES then
               report "RESULT skip=" & integer'image(G_SKIP) & 
                      " ep01skip=" & integer'image(G_EP01_SKIP) & " tx_ppm=" & integer'image(tx_rate) &
                      " rate_ppm=" & integer'image(G_RATE_PPM) & " gap=" & integer'image(G_HOST_GAP) &
                      " | tx_words=" & integer'image(tx_words) & " rx_words=" & integer'image(rx_words) &
                      " tx_under=" & integer'image(tx_under) & " rx_over=" & integer'image(rx_over) &
                      " | ctrl_out n=" & integer'image(co_n) & " maxlat=" & integer'image(co_lat_max) &
                      " ctrl_in n=" & integer'image(ci_n) & " maxlat=" & integer'image(ci_lat_max);
               done <= true;
            end if;
         end if;
      end if;
   end process;
end architecture;
