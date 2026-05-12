-- ----------------------------------------------------------------------------
-- FILE:          lime_txpct_fifo_tb.vhd
-- DESCRIPTION:   Minimal testbench for lime_txpct_fifo
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

entity lime_txpct_fifo_tb is
end entity;

architecture tb of lime_txpct_fifo_tb is

   constant c_CLK_PERIOD         : time     := 10 ns;

   -- Small values make edge cases easy to hit.
   constant c_MAX_FIFO_WORDS     : positive := 16;
   constant c_MAX_PACKETS        : positive := 2;

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

         pct_rd        => pct_rd,
         pct_clr       => pct_clr,
         pct_valid     => pct_valid,
         pct_header    => pct_header
      );

   stimulus : process
      constant c_SHORT_PACKET_WORDS     : natural := 1;
      constant c_LONG_PACKET_WORDS      : natural := 8;
      constant c_TOO_LARGE_PACKET_WORDS : natural := c_MAX_FIFO_WORDS + 1;

      variable v_expected_header : std_logic_vector(127 downto 0);
      variable v_expected_payload : std_logic_vector(127 downto 0);
   begin
      s_axis_tvalid <= '0';
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

      wait_ready_high(
         clk,
         s_axis_tready,
         10,
         "CASE 3 failed: DUT did not become ready for packet 1"
      );

      axis_send_packet(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         x"0000000000000003",
         '0',
         c_SHORT_PACKET_WORDS,
         16#30#
      );

      wait_packet_store_complete(
         clk,
         s_axis_tready,
         10,
         "CASE 3 failed: DUT did not complete packet 1 before packet 2"
      );

      axis_send_packet(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         x"0000000000000004",
         '0',
         c_SHORT_PACKET_WORDS,
         16#40#
      );

      wait_packet_store_complete(
         clk,
         s_axis_tready,
         10,
         "CASE 3 failed: DUT did not complete packet 2 before packet 3"
      );

      axis_send_packet(
         clk,
         s_axis_tdata,
         s_axis_tvalid,
         s_axis_tready,
         x"0000000000000005",
         '0',
         c_SHORT_PACKET_WORDS,
         16#50#
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
      -- OPTIONAL CASE 8: sync_dis packet auto-read without pct_valid/pct_rd
      -------------------------------------------------------------------------
      if c_ENABLE_M_AXIS_TESTS then
         report "CASE 8: sync_dis packet auto-read";

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

      report "All enabled lime_txpct_fifo tests passed";
      wait_clk_cycles(clk, 5);
      finish;
   end process;

end architecture;
