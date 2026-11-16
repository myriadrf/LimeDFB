-- ----------------------------------------------------------------------------
-- FILE:          lime_txpct_fifo_tb.vhd
-- DESCRIPTION:   Minimal testbench for lime_txpct_fifo
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.finish;

entity lime_txpct_fifo_tb is
end entity;

architecture tb of lime_txpct_fifo_tb is

   constant c_CLK_PERIOD         : time     := 10 ns;

   -- Small values make edge cases easy to hit.
   constant c_MAX_FIFO_WORDS     : positive := 16;
   constant c_MAX_PACKETS        : positive := 4;

   -- Set true after pct/m_axis read side is implemented.
   constant c_ENABLE_M_AXIS_TESTS : boolean := TRUE;

   signal clk   : std_logic := '0';
   signal rst   : std_logic := '1';

   signal s_axis_tdata  : std_logic_vector(127 downto 0) := (others => '0');
   signal s_axis_tvalid : std_logic := '0';
   signal s_axis_tready : std_logic;

   signal m_axis_tdata  : std_logic_vector(127 downto 0);
   signal m_axis_tvalid : std_logic;
   signal m_axis_tready : std_logic := '0';

   signal pct_buff_cnt     : std_logic_vector(7 downto 0) := (others => '0');
   signal payload_buff_cnt : std_logic_vector(15 downto 0) := (others => '0');
   signal pct_rd     : std_logic := '0';
   signal pct_clr    : std_logic := '0';
   signal pct_valid  : std_logic;
   signal pct_header : std_logic_vector(127 downto 0);

   procedure wait_clk_cycles (
      signal clk_i : in std_logic;
      constant n   : in natural
   ) is
   begin
      for i in 1 to n loop
         wait until rising_edge(clk_i);
      end loop;
   end procedure;

   procedure reset_dut (
      signal clk_i : in std_logic;
      signal rst_o : out std_logic
   ) is
   begin
      rst_o <= '1';
      wait_clk_cycles(clk_i, 5);
      rst_o <= '0';
      wait_clk_cycles(clk_i, 5);
   end procedure;

   procedure wait_ready_high (
      signal clk_i       : in std_logic;
      signal tready_i    : in std_logic;
      constant max_cycles : in natural;
      constant msg        : in string
   ) is
   begin
      for i in 0 to max_cycles loop
         if tready_i = '1' then
            return;
         end if;
         wait until rising_edge(clk_i);
      end loop;

      assert false
         report msg
         severity failure;
   end procedure;

   procedure wait_ready_low (
      signal clk_i       : in std_logic;
      signal tready_i    : in std_logic;
      constant max_cycles : in natural;
      constant msg        : in string
   ) is
   begin
      for i in 0 to max_cycles loop
         if tready_i = '0' then
            return;
         end if;
         wait until rising_edge(clk_i);
      end loop;

      assert false
         report msg
         severity failure;
   end procedure;

   procedure expect_ready_low_for (
      signal clk_i    : in std_logic;
      signal tready_i : in std_logic;
      constant cycles : in natural;
      constant msg    : in string
   ) is
   begin
      for i in 1 to cycles loop
         wait until rising_edge(clk_i);

         assert tready_i = '0'
            report msg
            severity failure;
      end loop;
   end procedure;

   procedure axis_send_word (
      signal clk_i      : in  std_logic;
      signal tdata_o    : out std_logic_vector(127 downto 0);
      signal tvalid_o   : out std_logic;
      signal tready_i   : in  std_logic;
      constant data_word : in  std_logic_vector(127 downto 0)
   ) is
   begin
      tdata_o  <= data_word;
      tvalid_o <= '1';

      loop
         wait until rising_edge(clk_i);
         exit when tready_i = '1';
      end loop;

      tvalid_o <= '0';
      tdata_o  <= (others => '0');
   end procedure;

   function form_packet_header (
      constant sample_nr_i      : in std_logic_vector(63 downto 0);
      constant sync_dis_i       : in std_logic;
      constant payload_words_i  : in natural
   ) return std_logic_vector is
      variable v_header : std_logic_vector(127 downto 0) := (others => '0');
   begin
      v_header(127 downto 64) := sample_nr_i;

      -- Header stores payload size in bytes at bits 23 downto 8.
      -- One 128-bit AXIS word = 16 bytes.
      v_header(23 downto 8) := std_logic_vector(to_unsigned(payload_words_i * 16, 16));

      v_header(4) := sync_dis_i;

      return v_header;
   end function;

   procedure axis_send_packet (
      signal clk_i              : in  std_logic;
      signal tdata_o            : out std_logic_vector(127 downto 0);
      signal tvalid_o           : out std_logic;
      signal tready_i           : in  std_logic;
      constant sample_nr_i      : in  std_logic_vector(63 downto 0);
      constant sync_dis_i       : in  std_logic;
      constant payload_words_i  : in  natural;
      constant payload_seed_i   : in  natural
   ) is
      constant c_header : std_logic_vector(127 downto 0) :=
         form_packet_header(sample_nr_i, sync_dis_i, payload_words_i);

      variable v_payload : std_logic_vector(127 downto 0);
   begin
      axis_send_word(clk_i, tdata_o, tvalid_o, tready_i, c_header);

      for i in 0 to payload_words_i - 1 loop
         v_payload := std_logic_vector(to_unsigned(payload_seed_i + i, 128));
         axis_send_word(clk_i, tdata_o, tvalid_o, tready_i, v_payload);
      end loop;
   end procedure;

   procedure wait_packet_store_complete (
      signal clk_i        : in std_logic;
      signal tready_i     : in std_logic;
      constant max_cycles : in natural;
      constant msg        : in string
   ) is
   begin
      -- axis_send_packet returns on the last payload handshake edge. The DUT still
      -- needs the following clock edge to commit metadata before the packet write
      -- is truly complete.
      wait until rising_edge(clk_i);

      wait_ready_high(clk_i, tready_i, max_cycles, msg);
   end procedure;

   procedure wait_pct_valid_high (
      signal clk_i       : in std_logic;
      signal pct_valid_i : in std_logic;
      constant max_cycles : in natural;
      constant msg        : in string
   ) is
   begin
      for i in 0 to max_cycles loop
         if pct_valid_i = '1' then
            return;
         end if;
         wait until rising_edge(clk_i);
      end loop;

      assert false
         report msg
         severity failure;
   end procedure;

   procedure wait_pct_header (
      signal clk_i        : in std_logic;
      signal pct_header_i : in std_logic_vector(127 downto 0);
      constant header_i   : in std_logic_vector(127 downto 0);
      constant max_cycles : in natural;
      constant msg        : in string
   ) is
   begin
      for i in 0 to max_cycles loop
         if pct_header_i = header_i then
            return;
         end if;
         wait until rising_edge(clk_i);
      end loop;

      assert false
         report msg
         severity failure;
   end procedure;

   procedure wait_m_axis_valid_high (
      signal clk_i          : in std_logic;
      signal m_axis_valid_i : in std_logic;
      constant max_cycles   : in natural;
      constant msg          : in string
   ) is
   begin
      for i in 0 to max_cycles loop
         if m_axis_valid_i = '1' then
            return;
         end if;
         wait until rising_edge(clk_i);
      end loop;

      assert false
         report msg
         severity failure;
   end procedure;

   procedure pulse_one_clk (
      signal clk_i : in std_logic;
      signal sig_o : out std_logic
   ) is
   begin
      sig_o <= '1';
      wait until rising_edge(clk_i);
      sig_o <= '0';
   end procedure;

   procedure read_packet_no_backpressure (
      signal clk_i             : in  std_logic;
      signal pct_rd_o          : out std_logic;
      signal pct_valid_i       : in  std_logic;
      signal pct_header_i      : in  std_logic_vector(127 downto 0);
      signal m_axis_tdata_i    : in  std_logic_vector(127 downto 0);
      signal m_axis_tvalid_i   : in  std_logic;
      signal m_axis_tready_o   : out std_logic;
      constant sample_nr_i     : in  std_logic_vector(63 downto 0);
      constant sync_dis_i      : in  std_logic;
      constant payload_words_i : in  natural;
      constant payload_seed_i  : in  natural;
      constant msg_i           : in  string
   ) is
      constant c_expected_header : std_logic_vector(127 downto 0) :=
         form_packet_header(sample_nr_i, sync_dis_i, payload_words_i);

      variable v_expected_payload : std_logic_vector(127 downto 0);
   begin
      wait_pct_header(
         clk_i,
         pct_header_i,
         c_expected_header,
         20,
         msg_i & " failed: expected pct_header did not become valid"
      );

      m_axis_tready_o <= '1';

      if sync_dis_i = '0' then
         pulse_one_clk(clk_i, pct_rd_o);
      else
         -- Advance to the first edge where m_axis_tready = '1', so the checks
         -- below sample handshake edges even if m_axis_tvalid was already high.
         wait until rising_edge(clk_i);
      end if;

      for i in 0 to payload_words_i - 1 loop
         wait_m_axis_valid_high(
            clk_i,
            m_axis_tvalid_i,
            20,
            msg_i & " failed: m_axis_tvalid did not assert"
         );

         assert sync_dis_i = '0' or pct_valid_i = '0'
            report msg_i & " failed: pct_valid asserted for sync_dis packet"
            severity failure;

         v_expected_payload :=
            std_logic_vector(to_unsigned(payload_seed_i + i, 128));

         assert m_axis_tdata_i = v_expected_payload
            report msg_i & " failed: m_axis payload data mismatch"
            severity failure;

         wait until rising_edge(clk_i);
      end loop;

      m_axis_tready_o <= '0';
   end procedure;

begin

   clk <= not clk after c_CLK_PERIOD / 2;

   dut0 : entity work.lime_txpct_fifo
      generic map (
         g_MAX_FIFO_WORDS => c_MAX_FIFO_WORDS,
         g_MAX_PACKETS    => c_MAX_PACKETS
      )
      port map (
         clk           => clk,
         rst           => rst,

         s_axis_tdata  => s_axis_tdata,
         s_axis_tvalid => s_axis_tvalid,
         s_axis_tready => s_axis_tready,

         m_axis_tdata  => m_axis_tdata,
         m_axis_tvalid => m_axis_tvalid,
         m_axis_tready => m_axis_tready,

         pct_buff_cnt     => pct_buff_cnt,
         payload_buff_cnt => payload_buff_cnt,
         pct_rd           => pct_rd,
         pct_clr          => pct_clr,
         pct_valid        => pct_valid,
         pct_header       => pct_header
      );

   stimulus : process
      constant c_SHORT_PACKET_WORDS     : natural := 1;
      constant c_LONG_PACKET_WORDS      : natural := 8;
      constant c_TOO_LARGE_PACKET_WORDS : natural := c_MAX_FIFO_WORDS + 1;

      variable v_expected_header : std_logic_vector(127 downto 0);
      variable v_expected_payload : std_logic_vector(127 downto 0);
   begin
      pct_buff_cnt     <= x"00";
      payload_buff_cnt <= (others => '0');
      s_axis_tvalid    <= '0';
      s_axis_tdata  <= (others => '0');
      m_axis_tready <= '0';
      pct_rd        <= '0';
      pct_clr       <= '0';

      -------------------------------------------------------------------------
      -- CASE 1: short packet write
      -------------------------------------------------------------------------
      report "CASE 1: short packet write";

      reset_dut(clk, rst);

      wait_ready_high(
         clk,
         s_axis_tready,
         10,
         "CASE 1 failed: DUT did not become ready after reset"
      );

      axis_send_packet(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         x"0000000000000001",
         '0',
         c_SHORT_PACKET_WORDS,
         16#10#
      );

      wait_packet_store_complete(
         clk,
         s_axis_tready,
         10,
         "CASE 1 failed: DUT did not complete the short packet write"
      );

      -------------------------------------------------------------------------
      -- CASE 2: long packet write
      -------------------------------------------------------------------------
      report "CASE 2: long packet write";

      reset_dut(clk, rst);

      wait_ready_high(
         clk,
         s_axis_tready,
         10,
         "CASE 2 failed: DUT did not become ready after reset"
      );

      axis_send_packet(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         x"0000000000000002",
         '1',
         c_LONG_PACKET_WORDS,
         16#20#
      );

      wait_packet_store_complete(
         clk,
         s_axis_tready,
         10,
         "CASE 2 failed: DUT did not complete the long packet write"
      );

      -------------------------------------------------------------------------
      -- CASE 3: metadata slots full
      -- The DUT prefetches the first committed metadata entry into rd_meta as
      -- soon as it is available. That frees one metadata RAM slot before any
      -- pct_rd/pct_clr, so fill the prefetched entry plus the RAM queue slots.
      -------------------------------------------------------------------------
      report "CASE 3: metadata slots full";

      reset_dut(clk, rst);

      for p in 1 to c_MAX_PACKETS loop
         wait_ready_high(
            clk,
            s_axis_tready,
            10,
            "CASE 3 failed: DUT did not become ready for packet " & integer'image(p)
         );

         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            std_logic_vector(to_unsigned(16#30# + p, 64)),
            '0',
            c_SHORT_PACKET_WORDS,
            16#30# + p
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 3 failed: DUT did not complete packet " & integer'image(p)
         );
      end loop;

      -- Final packet that fills the remaining slot
      axis_send_packet(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         std_logic_vector(to_unsigned(16#30# + c_MAX_PACKETS + 1, 64)),
         '0',
         c_SHORT_PACKET_WORDS,
         16#30# + c_MAX_PACKETS + 1
      );

      wait_clk_cycles(clk, 5);

      assert s_axis_tready = '0'
         report "CASE 3 failed: s_axis_tready should be low when prefetched metadata plus RAM slots are full"
         severity failure;

      expect_ready_low_for(
         clk,
         s_axis_tready,
         10,
         "CASE 3 failed: s_axis_tready reasserted while prefetched metadata plus RAM slots were full"
      );

      -------------------------------------------------------------------------
      -- CASE 4: packet payload does not fit payload memory
      -- Header should be accepted, then DUT should hold s_axis_tready low in
      -- CHECK_PAYLOAD_LENGTH because payload_words > G_MAX_FIFO_WORDS.
      -------------------------------------------------------------------------
      report "CASE 4: oversized payload does not fit";

      reset_dut(clk, rst);

      wait_ready_high(
         clk,
         s_axis_tready,
         10,
         "CASE 4 failed: DUT did not become ready for oversized packet header"
      );

      axis_send_word(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         form_packet_header(
            x"0000000000000005",
            '0',
            c_TOO_LARGE_PACKET_WORDS
         )
      );

      wait_ready_low(
         clk,
         s_axis_tready,
         10,
         "CASE 4 failed: s_axis_tready did not go low after oversized packet header"
      );

      -- Present first payload word. It must not be accepted because tready stays low.
      s_axis_tdata  <= std_logic_vector(to_unsigned(16#50#, 128));
      s_axis_tvalid <= '1';

      expect_ready_low_for(
         clk,
         s_axis_tready,
         20,
         "CASE 4 failed: DUT accepted payload for oversized packet"
      );

      s_axis_tvalid <= '0';
      s_axis_tdata  <= (others => '0');

      -------------------------------------------------------------------------
      -- OPTIONAL CASE 5: read packet through m_axis
      -- Enable only after m_axis/pct_valid/pct_header logic is implemented.
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 5: m_axis readout with backpressure";

         reset_dut(clk, rst);

         v_expected_header :=
            form_packet_header(
               x"0000000000000006",
               '0',
               3
            );

         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000006",
            '0',
            3,
            16#60#
         );

         wait_pct_valid_high(
            clk,
            pct_valid,
            20,
            "CASE 5 failed: pct_valid did not assert after committed packet"
         );

         assert pct_header = v_expected_header
            report "CASE 5 failed: pct_header mismatch"
            severity failure;

         -- Start packet streaming.
         pulse_one_clk(clk, pct_rd);

         -- Consume three payload words with one-cycle backpressure between words.
         for i in 0 to 2 loop
            wait_m_axis_valid_high(
               clk,
               m_axis_tvalid,
               20,
               "CASE 5 failed: m_axis_tvalid did not assert"
            );

            v_expected_payload :=
               std_logic_vector(to_unsigned(16#60# + i, 128));

            assert m_axis_tdata = v_expected_payload
               report "CASE 5 failed: m_axis payload data mismatch"
               severity failure;

            m_axis_tready <= '1';
            wait until rising_edge(clk);
            m_axis_tready <= '0';
            wait_clk_cycles(clk, 1);
         end loop;

         wait_clk_cycles(clk, 3);

         assert m_axis_tvalid = '0'
            report "CASE 5 failed: m_axis_tvalid should deassert after packet read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- OPTIONAL CASE 6: discard packet with pct_clr
      -- Enable only after pct_clr/read-side removal logic is implemented.
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 6: pct_clr discard";

         reset_dut(clk, rst);

         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000007",
            '0',
            2,
            16#70#
         );

         wait_pct_valid_high(
            clk,
            pct_valid,
            20,
            "CASE 6 failed: pct_valid did not assert before clear"
         );

         pulse_one_clk(clk, pct_clr);

         wait_clk_cycles(clk, 5);

         assert pct_valid = '0'
            report "CASE 6 failed: pct_valid should deassert after pct_clr"
            severity failure;

         assert m_axis_tvalid = '0'
            report "CASE 6 failed: m_axis_tvalid should stay low after pct_clr"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- OPTIONAL CASE 7: write/read wraparound without read backpressure
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 7: payload RAM wraparound without read backpressure";

         reset_dut(clk, rst);

         -- First batch writes 15 of 16 payload RAM words.
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000008",
            '0',
            8,
            16#80#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 7 failed: DUT did not complete packet 1 before packet 2"
         );

         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000009",
            '0',
            7,
            16#90#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 7 failed: DUT did not complete packet 2 before readout"
         );

         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"0000000000000008",
            '0',
            8,
            16#80#,
            "CASE 7 packet 1"
         );

         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"0000000000000009",
            '0',
            7,
            16#90#,
            "CASE 7 packet 2"
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            20,
            "CASE 7 failed: DUT did not become ready for wraparound packet 3"
         );

         -- Second batch crosses the payload RAM address boundary.
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"000000000000000A",
            '0',
            6,
            16#A0#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 7 failed: DUT did not complete packet 3 before packet 4"
         );

         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"000000000000000B",
            '0',
            5,
            16#B0#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 7 failed: DUT did not complete packet 4 before readout"
         );

         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"000000000000000A",
            '0',
            6,
            16#A0#,
            "CASE 7 packet 3"
         );

         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"000000000000000B",
            '0',
            5,
            16#B0#,
            "CASE 7 packet 4"
         );

         wait_clk_cycles(clk, 3);

         assert m_axis_tvalid = '0'
            report "CASE 7 failed: m_axis_tvalid should deassert after wraparound reads"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 8: sync_dis packet auto-read with pct_buff_cnt = "000" (0 extra packets)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 8: sync_dis packet auto-read (pct_buff_cnt = 000)";

         pct_buff_cnt     <= x"00";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"000000000000000C",
            '1',
            4,
            16#C0#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 8 failed: DUT did not complete sync_dis packet write"
         );

         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"000000000000000C",
            '1',
            4,
            16#C0#,
            "CASE 8 sync_dis packet"
         );

         wait_clk_cycles(clk, 3);

         assert pct_valid = '0'
            report "CASE 8 failed: pct_valid should stay low for sync_dis packet"
            severity failure;

         assert m_axis_tvalid = '0'
            report "CASE 8 failed: m_axis_tvalid should deassert after sync_dis auto-read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 9: sync_dis buffering with pct_buff_cnt = "001" (1 extra packet, 2 packets total)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 9: sync_dis buffering with pct_buff_cnt = 001";

         pct_buff_cnt     <= x"01";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         -- Send 1st sync_dis packet
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000091",
            '1',
            3,
            16#910#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 9 failed: DUT did not complete packet 1 write"
         );

         -- Verify m_axis_tvalid remains '0' (held due to pre-buffering)
         for i in 1 to 10 loop
            wait until rising_edge(clk);
            assert m_axis_tvalid = '0'
               report "CASE 9 failed: m_axis_tvalid asserted prematurely before buffering threshold reached"
               severity failure;
         end loop;

         -- Send 2nd sync_dis packet (meets threshold of 1 extra packet)
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000092",
            '1',
            3,
            16#920#
         );

         wait_packet_store_complete(
            clk,
            s_axis_tready,
            10,
            "CASE 9 failed: DUT did not complete packet 2 write"
         );

         -- Now streaming should begin; read packet 1 then packet 2
         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"0000000000000091",
            '1',
            3,
            16#910#,
            "CASE 9 packet 1"
         );

         read_packet_no_backpressure(
            clk,
            pct_rd,
            pct_valid,
            pct_header,
            m_axis_tdata,
            m_axis_tvalid,
            m_axis_tready,
            x"0000000000000092",
            '1',
            3,
            16#920#,
            "CASE 9 packet 2"
         );

         wait_clk_cycles(clk, 3);

         assert m_axis_tvalid = '0'
            report "CASE 9 failed: m_axis_tvalid should deassert after reading both packets"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 10: sync_dis buffering with pct_buff_cnt = "010" (2 extra packets, 3 packets total)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 10: sync_dis buffering with pct_buff_cnt = 010";

         pct_buff_cnt     <= x"02";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         -- Packet 1
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"00000000000000A1",
            '1',
            2,
            16#A10#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 10 failed on packet 1 write");

         wait_clk_cycles(clk, 5);
         assert m_axis_tvalid = '0'
            report "CASE 10 failed: m_axis_tvalid asserted after 1 packet when threshold is 3"
            severity failure;

         -- Packet 2
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"00000000000000A2",
            '1',
            2,
            16#A20#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 10 failed on packet 2 write");

         wait_clk_cycles(clk, 5);
         assert m_axis_tvalid = '0'
            report "CASE 10 failed: m_axis_tvalid asserted after 2 packets when threshold is 3"
            severity failure;

         -- Packet 3 (meets threshold)
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"00000000000000A3",
            '1',
            2,
            16#A30#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 10 failed on packet 3 write");

         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000A1", '1', 2, 16#A10#, "CASE 10 packet 1"
         );

         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000A2", '1', 2, 16#A20#, "CASE 10 packet 2"
         );

         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000A3", '1', 2, 16#A30#, "CASE 10 packet 3"
         );

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 10 failed: m_axis_tvalid should deassert after all 3 packets read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 11: sync_dis buffering with pct_buff_cnt = "011" (3 extra packets, 4 packets total)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 11: sync_dis buffering with pct_buff_cnt = 011";

         pct_buff_cnt     <= x"03";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         for p in 1 to 3 loop
            axis_send_packet(
               clk,
               s_axis_tdata,
               s_axis_tvalid,
               s_axis_tready,
               std_logic_vector(to_unsigned(16#B0# + p, 64)),
               '1',
               2,
               16#B00# + p * 16
            );
            wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 11 failed on packet write " & integer'image(p));

            wait_clk_cycles(clk, 5);
            assert m_axis_tvalid = '0'
               report "CASE 11 failed: m_axis_tvalid asserted after " & integer'image(p) & " packets when threshold is 4"
               severity failure;
         end loop;

         -- Packet 4 (meets threshold)
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"00000000000000B4",
            '1',
            2,
            16#B40#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 11 failed on packet 4 write");

         for p in 1 to 4 loop
            read_packet_no_backpressure(
               clk, pct_rd, pct_valid, pct_header,
               m_axis_tdata, m_axis_tvalid, m_axis_tready,
               std_logic_vector(to_unsigned(16#B0# + p, 64)),
               '1',
               2,
               16#B00# + p * 16,
               "CASE 11 packet " & integer'image(p)
            );
         end loop;

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 11 failed: m_axis_tvalid should deassert after all 4 packets read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 12: Stream continuity after initial start (no re-buffering mid-stream)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 12: Stream continuity after initial start";

         pct_buff_cnt     <= x"01";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         -- Pre-buffer 2 packets to start stream
         axis_send_packet(
            clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
            x"00000000000000C1", '1', 2, 16#C10#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 12 failed on packet 1 write");

         axis_send_packet(
            clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
            x"00000000000000C2", '1', 2, 16#C20#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 12 failed on packet 2 write");

         -- Read out packet 1 and 2
         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000C1", '1', 2, 16#C10#, "CASE 12 packet 1"
         );
         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000C2", '1', 2, 16#C20#, "CASE 12 packet 2"
         );

         -- Stream is now active. FIFO is empty.
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 12 failed: FIFO should be empty"
            severity failure;

         -- Send a single subsequent packet (Packet 3)
         axis_send_packet(
            clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
            x"00000000000000C3", '1', 2, 16#C30#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 12 failed on packet 3 write");

         -- It should stream out IMMEDIATELY without waiting for an extra packet because stream is already active!
         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000C3", '1', 2, 16#C30#, "CASE 12 packet 3 (continuous stream)"
         );

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 12 failed: m_axis_tvalid should deassert after packet 3"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 13: Timestamp-synchronized (sync_dis = '0') independence from pct_buff_cnt
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 13: Timestamp-synchronized independence (pct_buff_cnt = 011)";

         pct_buff_cnt     <= x"03";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         -- Send 1 sync_dis = '0' packet
         axis_send_packet(
            clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
            x"00000000000000D1", '0', 3, 16#D10#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 13 failed on packet 1 write");

         -- pct_valid must assert immediately despite pct_buff_cnt = "011"
         wait_pct_valid_high(
            clk,
            pct_valid,
            10,
            "CASE 13 failed: pct_valid did not assert immediately for sync_dis=0 packet"
         );

         read_packet_no_backpressure(
            clk, pct_rd, pct_valid, pct_header,
            m_axis_tdata, m_axis_tvalid, m_axis_tready,
            x"00000000000000D1", '0', 3, 16#D10#, "CASE 13 sync_dis=0 packet"
         );

         wait_clk_cycles(clk, 3);
         assert pct_valid = '0'
            report "CASE 13 failed: pct_valid should deassert after read"
            severity failure;
         assert m_axis_tvalid = '0'
            report "CASE 13 failed: m_axis_tvalid should deassert after read"
            severity failure;

         -- Send another sync_dis = '0' packet and discard with pct_clr
         axis_send_packet(
            clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
            x"00000000000000D2", '0', 2, 16#D20#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 13 failed on packet 2 write");

         wait_pct_valid_high(clk, pct_valid, 10, "CASE 13 failed: pct_valid did not assert for packet 2");
         pulse_one_clk(clk, pct_clr);

         wait_clk_cycles(clk, 5);
         assert pct_valid = '0'
            report "CASE 13 failed: pct_valid should deassert after pct_clr"
            severity failure;
         assert m_axis_tvalid = '0'
            report "CASE 13 failed: m_axis_tvalid should remain low after pct_clr"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 14: Mid-stream reset re-arms buffering
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 14: Mid-stream reset re-arms buffering";

         pct_buff_cnt     <= x"01";
         payload_buff_cnt <= (others => '0');
         -- Start a stream session
         reset_dut(clk, rst);

         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"00000000000000E1", '1', 2, 16#E10#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 14 packet 1");
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"00000000000000E2", '1', 2, 16#E20#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 14 packet 2");

         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"00000000000000E1", '1', 2, 16#E10#, "CASE 14 packet 1");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"00000000000000E2", '1', 2, 16#E20#, "CASE 14 packet 2");

         -- Now assert reset mid-stream
         reset_dut(clk, rst);

         -- Send 1 sync_dis packet
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"00000000000000E3", '1', 2, 16#E30#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 14 packet 3");

         -- Buffering should be armed again: m_axis_tvalid must remain '0'
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 14 failed: buffering did not re-arm after reset"
            severity failure;

         -- Send 2nd packet to trigger readout
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"00000000000000E4", '1', 2, 16#E40#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 14 packet 4");

         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"00000000000000E3", '1', 2, 16#E30#, "CASE 14 packet 3");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"00000000000000E4", '1', 2, 16#E40#, "CASE 14 packet 4");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 14 failed: m_axis_tvalid should deassert"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 15: Zero-length payload packet with sync_dis = '1'
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 15: Zero-length payload packet with sync_dis = '1'";

         pct_buff_cnt     <= x"01";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         -- Send zero-length sync_dis packet
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"00000000000000F1", '1', 0, 16#F10#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 15 packet 1 (zero-length)");

         -- Prebuffering gates output until packet 2
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 15 failed: m_axis_tvalid asserted prematurely for zero-length packet"
            severity failure;

         -- Send packet 2 (2 words)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"00000000000000F2", '1', 2, 16#F20#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 15 packet 2");

         -- Packet 1 should be consumed as empty, and packet 2 payload streamed out
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"00000000000000F2", '1', 2, 16#F20#, "CASE 15 packet 2");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 15 failed: m_axis_tvalid should deassert after packet 2"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 16: Payload FIFO word count gating (payload_buff_cnt = 5 words)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 16: Payload FIFO word count gating (payload_buff_cnt = 5)";

         pct_buff_cnt     <= x"00";
         payload_buff_cnt <= std_logic_vector(to_unsigned(5, payload_buff_cnt'length));
         reset_dut(clk, rst);

         -- Send packet 1 with 2 words (2 words in FIFO < 5 threshold)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000101", '1', 2, 16#1010#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 16 packet 1");

         -- Gating should hold output because 2 words < 5 words
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 16 failed: m_axis_tvalid asserted when payload FIFO words (2) < threshold (5)"
            severity failure;

         -- Send packet 2 with 4 words (total 6 words in FIFO >= 5 threshold)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000102", '1', 4, 16#1020#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 16 packet 2");

         -- Streaming should begin now and read out packet 1 then packet 2
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000101", '1', 2, 16#1010#, "CASE 16 packet 1");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000102", '1', 4, 16#1020#, "CASE 16 packet 2");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 16 failed: m_axis_tvalid should deassert after reading all packets"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 17: Payload FIFO word count gating exact match (payload_buff_cnt = 8)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 17: Payload FIFO word count gating exact match (payload_buff_cnt = 8)";

         pct_buff_cnt     <= x"00";
         payload_buff_cnt <= std_logic_vector(to_unsigned(8, payload_buff_cnt'length));
         reset_dut(clk, rst);

         -- Send single packet with 8 words (meets 8-word threshold exactly)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000111", '1', 8, 16#1110#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 17 packet 1");

         -- Should stream immediately
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000111", '1', 8, 16#1110#, "CASE 17 packet 1");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 17 failed: m_axis_tvalid should deassert after packet 1"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 18: Combined gating (pct_buff_cnt = "001" AND payload_buff_cnt = 6)
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 18: Combined gating (pct_buff_cnt = 001 AND payload_buff_cnt = 6)";

         pct_buff_cnt     <= x"01";
         payload_buff_cnt <= std_logic_vector(to_unsigned(6, payload_buff_cnt'length));
         reset_dut(clk, rst);

         -- Send packet 1 with 8 words (payload count 8 >= 6 satisfied, but packet count 1 < 2 not satisfied)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000121", '1', 8, 16#1210#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 18 packet 1");

         -- Gating should hold output because packet count < 2
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 18 failed: m_axis_tvalid asserted when packet count threshold not met"
            severity failure;

         -- Send packet 2 with 2 words (both packet threshold 2 and payload threshold >= 6 met)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000122", '1', 2, 16#1220#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 18 packet 2");

         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000121", '1', 8, 16#1210#, "CASE 18 packet 1");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000122", '1', 2, 16#1220#, "CASE 18 packet 2");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 18 failed: m_axis_tvalid should deassert after all packets read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 19: Payload FIFO word count gating independence for sync_dis = '0'
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 19: Payload FIFO word count gating independence for sync_dis = 0";

         pct_buff_cnt     <= x"03";
         payload_buff_cnt <= std_logic_vector(to_unsigned(12, payload_buff_cnt'length));
         reset_dut(clk, rst);

         -- Send 1 sync_dis = '0' packet with 2 words (far below 12-word threshold)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000131", '0', 2, 16#1310#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 19 packet 1");

         -- pct_valid must assert immediately regardless of payload_buff_cnt
         wait_pct_valid_high(clk, pct_valid, 10, "CASE 19 failed: pct_valid did not assert for sync_dis=0 packet");

         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000131", '0', 2, 16#1310#, "CASE 19 sync_dis=0 packet");

         wait_clk_cycles(clk, 3);
         assert pct_valid = '0'
            report "CASE 19 failed: pct_valid should deassert"
            severity failure;
         assert m_axis_tvalid = '0'
            report "CASE 19 failed: m_axis_tvalid should deassert"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 20: Reset re-arms payload FIFO word gating
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 20: Reset re-arms payload FIFO word gating";

         pct_buff_cnt     <= x"00";
         payload_buff_cnt <= std_logic_vector(to_unsigned(6, payload_buff_cnt'length));
         reset_dut(clk, rst);

         -- Stream session 1
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000141", '1', 6, 16#1410#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 20 session 1 write");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000141", '1', 6, 16#1410#, "CASE 20 session 1 read");

         -- Reset DUT mid-stream
         reset_dut(clk, rst);

         -- Send packet with 2 words (< 6 words)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000142", '1', 2, 16#1420#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 20 session 2 packet 1");

         -- Buffering should be re-armed: m_axis_tvalid must stay '0'
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 20 failed: payload FIFO gating did not re-arm after reset"
            severity failure;

         -- Send 2nd packet with 4 words (total 6 words >= 6 words)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000143", '1', 4, 16#1430#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 20 session 2 packet 2");

         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000142", '1', 2, 16#1420#, "CASE 20 session 2 packet 1");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000143", '1', 4, 16#1430#, "CASE 20 session 2 packet 2");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 20 failed: m_axis_tvalid should deassert after read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 21: pct_buff_cnt capping when requested value exceeds g_MAX_PACKETS - 1
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 21: pct_buff_cnt capping (pct_buff_cnt = 0xFF / 255 extra packets)";

         pct_buff_cnt     <= x"FF";
         payload_buff_cnt <= (others => '0');
         reset_dut(clk, rst);

         -- Send 3 packets (1 in rd_meta + 2 in metadata_mem: total 3 packets < 4 packets required by capped threshold 3)
         for p in 1 to 3 loop
            axis_send_packet(
               clk,
               s_axis_tdata,
               s_axis_tvalid,
               s_axis_tready,
               std_logic_vector(to_unsigned(16#150# + p, 64)),
               '1',
               2,
               16#1500# + (p * 16#10#)
            );
            wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 21 packet " & integer'image(p));
         end loop;

         -- Verify m_axis_tvalid remains '0' (held because 3 extra packets required)
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 21 failed: m_axis_tvalid asserted prematurely before capped threshold reached"
            severity failure;

         -- Send 4th packet (total 4 packets = 3 extra packets, satisfying capped threshold)
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000154",
            '1',
            2,
            16#1540#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 21 packet 4");

         -- Read all 4 packets
         for p in 1 to 4 loop
            read_packet_no_backpressure(
               clk,
               pct_rd,
               pct_valid,
               pct_header,
               m_axis_tdata,
               m_axis_tvalid,
               m_axis_tready,
               std_logic_vector(to_unsigned(16#150# + p, 64)),
               '1',
               2,
               16#1500# + (p * 16#10#),
               "CASE 21 read packet " & integer'image(p)
            );
         end loop;

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 21 failed: m_axis_tvalid should deassert after reading all packets"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 22: payload_buff_cnt capping when requested value exceeds g_MAX_FIFO_WORDS
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 22: payload_buff_cnt capping (payload_buff_cnt = 0xFFFF / 65535 words)";

         pct_buff_cnt     <= x"00";
         payload_buff_cnt <= x"FFFF";
         reset_dut(clk, rst);

         -- Send packet 1 (8 words) and packet 2 (6 words) -> total 14 words (< 16 words capped threshold)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000161", '1', 8, 16#1610#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 22 packet 1");
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000162", '1', 6, 16#1620#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 22 packet 2");

         -- Gating should hold output because 14 words < 16 words
         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 22 failed: m_axis_tvalid asserted when payload FIFO words (14) < capped threshold (16)"
            severity failure;

         -- Send packet 3 with 2 words -> total 16 words (meets 16-word capped threshold exactly)
         axis_send_packet(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0000000000000163", '1', 2, 16#1630#);
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 22 packet 3");

         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000161", '1', 8, 16#1610#, "CASE 22 packet 1");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000162", '1', 6, 16#1620#, "CASE 22 packet 2");
         read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready, x"0000000000000163", '1', 2, 16#1630#, "CASE 22 packet 3");

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 22 failed: m_axis_tvalid should deassert after reading all packets"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 23: Simultaneous capping of pct_buff_cnt and payload_buff_cnt
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 23: Simultaneous capping of pct_buff_cnt (0xFF) and payload_buff_cnt (0xFFFF)";

         pct_buff_cnt     <= x"FF";
         payload_buff_cnt <= x"FFFF";
         reset_dut(clk, rst);

         -- Send 3 packets with 4 words each (3 packets, 12 words: neither threshold satisfied)
         for p in 1 to 3 loop
            axis_send_packet(
               clk,
               s_axis_tdata,
               s_axis_tvalid,
               s_axis_tready,
               std_logic_vector(to_unsigned(16#170# + p, 64)),
               '1',
               4,
               16#1700# + (p * 16#10#)
            );
            wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 23 packet " & integer'image(p));
         end loop;

         wait_clk_cycles(clk, 10);
         assert m_axis_tvalid = '0'
            report "CASE 23 failed: m_axis_tvalid asserted prematurely"
            severity failure;

         -- Send 4th packet with 4 words (total 4 packets, 16 words: both capped thresholds satisfied)
         axis_send_packet(
            clk,
            s_axis_tdata,
            s_axis_tvalid,
            s_axis_tready,
            x"0000000000000174",
            '1',
            4,
            16#1740#
         );
         wait_packet_store_complete(clk, s_axis_tready, 10, "CASE 23 packet 4");

         for p in 1 to 4 loop
            read_packet_no_backpressure(
               clk,
               pct_rd,
               pct_valid,
               pct_header,
               m_axis_tdata,
               m_axis_tvalid,
               m_axis_tready,
               std_logic_vector(to_unsigned(16#170# + p, 64)),
               '1',
               4,
               16#1700# + (p * 16#10#),
               "CASE 23 read packet " & integer'image(p)
            );
         end loop;

         wait_clk_cycles(clk, 3);
         assert m_axis_tvalid = '0'
            report "CASE 23 failed: m_axis_tvalid should deassert after read"
            severity failure;
      end if;

      -------------------------------------------------------------------------
      -- CASE 24/25: Unreachable thresholds are released when the writer stalls
      --
      -- 5-word packets in a 16-word payload RAM: three packets (15 words) fit,
      -- the fourth does not. With the head packet held, at most 2 further
      -- packets / 15 words are ever buffered, so:
      --   CASE 24: pct_buff_cnt = 3 (cap g_MAX_PACKETS-1) is never reached
      --   CASE 25: payload_buff_cnt = 16 (cap g_MAX_FIFO_WORDS) is never reached
      -- The stream must still start once the 4th packet's payload cannot fit.
      -------------------------------------------------------------------------
      for c in 24 to 25 loop
         if c_ENABLE_M_AXIS_TESTS then
            report "CASE " & integer'image(c) & ": unreachable threshold released on write-side stall";

            if c = 24 then
               pct_buff_cnt     <= x"03";
               payload_buff_cnt <= (others => '0');
            else
               pct_buff_cnt     <= x"00";
               payload_buff_cnt <= std_logic_vector(to_unsigned(16, 16));
            end if;
            reset_dut(clk, rst);

            for p in 1 to 3 loop
               axis_send_packet(
                  clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
                  std_logic_vector(to_unsigned(16#180# + p, 64)),
                  '1', 5, 16#1800# + p * 16#10#
               );
               wait_packet_store_complete(clk, s_axis_tready, 10,
                  "CASE " & integer'image(c) & " failed on packet write " & integer'image(p));
            end loop;

            -- Threshold not met and writer not stalled yet: output must stay gated
            wait_clk_cycles(clk, 10);
            assert m_axis_tvalid = '0'
               report "CASE " & integer'image(c) & " failed: m_axis_tvalid asserted before write-side stall"
               severity failure;

            -- 4th packet header: payload (5 words) does not fit in remaining 1 word -> writer stalls
            axis_send_word(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
               form_packet_header(std_logic_vector(to_unsigned(16#184#, 64)), '1', 5));

            -- Stall must release the gate
            wait_m_axis_valid_high(clk, m_axis_tvalid, 20,
               "CASE " & integer'image(c) & " failed: stream did not start after write-side stall (deadlock)");

            read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready,
               std_logic_vector(to_unsigned(16#181#, 64)), '1', 5, 16#1810#,
               "CASE " & integer'image(c) & " read packet 1");

            -- Space freed: finish 4th packet payload
            for i in 0 to 4 loop
               axis_send_word(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready,
                  std_logic_vector(to_unsigned(16#1840# + i, 128)));
            end loop;
            wait_packet_store_complete(clk, s_axis_tready, 10,
               "CASE " & integer'image(c) & " failed on packet write 4");

            for p in 2 to 4 loop
               read_packet_no_backpressure(clk, pct_rd, pct_valid, pct_header, m_axis_tdata, m_axis_tvalid, m_axis_tready,
                  std_logic_vector(to_unsigned(16#180# + p, 64)), '1', 5, 16#1800# + p * 16#10#,
                  "CASE " & integer'image(c) & " read packet " & integer'image(p));
            end loop;

            wait_clk_cycles(clk, 3);
            assert m_axis_tvalid = '0'
               report "CASE " & integer'image(c) & " failed: m_axis_tvalid should deassert after all packets read"
               severity failure;
         end if;
      end loop;

      report "All enabled lime_txpct_fifo tests passed";
      wait_clk_cycles(clk, 5);
      finish;
   end process;

end architecture;
