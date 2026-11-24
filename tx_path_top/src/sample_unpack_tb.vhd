-- FILE: sample_unpack_tb.vhd
-- Run: ghdl -a --std=08 sample_unpack.vhd sample_unpack_tb.vhd; ghdl -e --std=08 sample_unpack_tb;
--      ghdl -r --std=08 sample_unpack_tb -gg_MIMO=1 -gg_IN_P=50 -gg_OUT_P=100   (expect errors=0)
--      g_OUT_P=200 toggles ready every cycle (LMS7002_TX MIMO frame_phase).
-- SAMPLE_UNPACK handshake test: input FWFT FIFO with random bubbles (data held when empty, like
-- LiteX SyncFIFOBuffered), random output back-pressure; every output sample must be the next
-- counter value. SISO (CH_EN=01: 4 samples/word) or MIMO (CH_EN=11: 2 sample pairs/word).
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all; use ieee.math_real.all;
entity sample_unpack_tb is generic (g_MIMO : integer := 0; g_IN_P : integer := 70; g_OUT_P : integer := 100; g_SEED : integer := 1); end;
architecture sim of sample_unpack_tb is
  signal clk : std_logic := '0'; signal rst_n : std_logic := '0';
  signal s_data : std_logic_vector(127 downto 0) := (others => '0');
  signal s_valid, s_ready, m_valid, m_ready : std_logic := '0';
  signal m_data : std_logic_vector(63 downto 0);
  signal ch_en : std_logic_vector(1 downto 0);
  signal errors, nout : integer := 0;
  type t_mem is array (0 to 15) of std_logic_vector(127 downto 0);
begin
  clk <= not clk after 4 ns;
  ch_en <= "11" when g_MIMO = 1 else "01";
  dut : entity work.SAMPLE_UNPACK port map (AXIS_ACLK => clk, AXIS_ARESET_N => rst_n, RESET_N => rst_n,
     S_AXIS_TDATA => s_data, S_AXIS_TREADY => s_ready, S_AXIS_TVALID => s_valid, S_AXIS_TLAST => '0',
     M_AXIS_TDATA => m_data, M_AXIS_TREADY => m_ready, M_AXIS_TVALID => m_valid, CH_EN => ch_en);
  -- producer + FWFT fifo (registered head; data holds when empty)
  prod : process(clk)
    variable s1, s2 : positive := g_SEED; variable r : real;
    variable mem : t_mem; variable wp, rp : integer := 0; variable n : integer := 1;
    variable w : std_logic_vector(127 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '1' then
        if s_valid = '1' and s_ready = '1' then rp := rp + 1; end if;
        uniform(s1, s2, r);
        if (wp - rp) < 16 and r*100.0 < real(g_IN_P) then
          for k in 0 to 7 loop w(16*k+15 downto 16*k) := std_logic_vector(to_unsigned(n + k/2, 16)); end loop;
          if g_MIMO = 0 then  -- 4 samples: I=Q=n..n+3 in 32-bit slots
            for k in 0 to 3 loop w(32*k+15 downto 32*k) := std_logic_vector(to_unsigned(n+k,16));
                                 w(32*k+31 downto 32*k+16) := std_logic_vector(to_unsigned(n+k,16)); end loop;
            n := n + 4;
          else                -- 2 pairs: AI=AQ=BI=BQ=n, n+1
            for k in 0 to 3 loop w(16*k+15 downto 16*k) := std_logic_vector(to_unsigned(n,16));
                                 w(64+16*k+15 downto 64+16*k) := std_logic_vector(to_unsigned(n+1,16)); end loop;
            n := n + 2;
          end if;
          mem(wp mod 16) := w; wp := wp + 1;
        end if;
        if wp > rp then s_valid <= '1'; s_data <= mem(rp mod 16); else s_valid <= '0'; end if;  -- data holds
      end if;
    end if;
  end process;
  cons : process(clk)
    variable s1, s2 : positive := g_SEED + 7; variable r : real; variable e : integer := 1; variable v : integer;
  begin
    if rising_edge(clk) then
      uniform(s1, s2, r);
      if g_OUT_P = 200 then m_ready <= not m_ready;   -- LMS7002_TX MIMO: frame_phase toggle
      elsif r*100.0 < real(g_OUT_P) then m_ready <= '1'; else m_ready <= '0'; end if;
      if m_valid = '1' and m_ready = '1' then
        if g_MIMO = 0 then v := to_integer(unsigned(m_data(63 downto 48))); else v := to_integer(unsigned(m_data(63 downto 48))); end if;
        if v /= e then
          if errors < 8 then report "out " & integer'image(nout) & ": got " & integer'image(v) & " expected " & integer'image(e) severity warning; end if;
          errors <= errors + 1; e := v + 1;
        else e := e + 1; end if;
        nout <= nout + 1;
      end if;
    end if;
  end process;
  stim : process begin
    wait for 50 ns; wait until rising_edge(clk); rst_n <= '1';
    wait for 200 us;
    report "RESULT mimo=" & integer'image(g_MIMO) & " in_p=" & integer'image(g_IN_P) & " out_p=" & integer'image(g_OUT_P) &
           " outputs=" & integer'image(nout) & " errors=" & integer'image(errors);
    finish;
  end process;
end;
