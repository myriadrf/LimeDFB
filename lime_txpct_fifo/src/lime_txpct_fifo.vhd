-- ----------------------------------------------------------------------------
-- FILE:          lime_txpct_fifo.vhd
-- DESCRIPTION:   Packet FIFO with RAM-backed payload storage
-- DATE:          May 5 2026
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity lime_txpct_fifo is
   generic (
      g_MAX_FIFO_WORDS  : positive := 1024;
      g_MAX_PACKETS     : positive := 4
   );
   port (
      clk   : in  std_logic;
      rst   : in  std_logic;

      ----------------------------------------------------------------------------
      -- AXI-Stream input
      -- First beat  = 128-bit header
      -- Next beats  = 128-bit payload words
      ----------------------------------------------------------------------------
      s_axis_tdata  : in  std_logic_vector(127 downto 0);
      s_axis_tvalid : in  std_logic;
      s_axis_tready : out std_logic;

      ----------------------------------------------------------------------------
      -- AXI-Stream output
      -- All beats  = 128-bit payload words
      ----------------------------------------------------------------------------
      m_axis_tdata  : out std_logic_vector(127 downto 0);
      m_axis_tvalid : out std_logic;
      m_axis_tready : in  std_logic;

      ----------------------------------------------------------------------------
      -- Control / immediate access to oldest committed packet
      ----------------------------------------------------------------------------
      -- Pulse high for one clk cycle to start streaming the current packet.
      pct_rd      : in  std_logic;
      -- Pulse high for one clk cycle to discard the current packet.
      pct_clr     : in  std_logic;
      pct_valid   : out std_logic;
      pct_header  : out std_logic_vector(127 downto 0)

    );
end entity;


-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture rtl of lime_txpct_fifo is

   constant c_AXIS_DATA_WIDTH : positive := 128;


   --  The following function calculates the address width based on specified RAM depth
   function clogb2(depth : natural) return integer is
      variable v       : natural := depth - 1;
      variable ret_val : integer := 0;
   begin
      while v > 0 loop
         ret_val := ret_val + 1;
         v       := v / 2;
      end loop;
   
      return ret_val;
   end function;


   constant c_META_MEM_ADDR_WIDTH         : positive := clogb2(g_MAX_PACKETS);
   constant c_PAYLOAD_MEM_ADDR_WIDTH      : integer  := clogb2(g_MAX_FIFO_WORDS);
   constant c_PACKET_PAYLOAD_SIZE_WIDTH   : positive := 16;
   

   signal s_axis_handshake       : std_logic;
   signal s_axis_tready_reg      : std_logic;


   type t_STORE_STATE_TYPE is (ST_IDLE, ST_WAIT_HEADER, ST_CHECK_PAYLOAD_LENGTH, ST_STORE_PAYLOAD, ST_STORE_META);
   signal current_store_state, next_store_state : t_STORE_STATE_TYPE;

   type t_READ_STATE_TYPE is (RD_IDLE, RD_META_CHECK, RD_READ_PAYLOAD, RD_DONE);
   signal current_read_state, next_read_state : t_READ_STATE_TYPE;


   signal store_cnt                    : unsigned(c_PACKET_PAYLOAD_SIZE_WIDTH-1 downto 0);
   signal store_pckt_hdr_accepted      : std_logic;
   signal store_pckt_payload_will_fit  : std_logic;


   -- metadata_ram signals
   constant c_META_RAM_DATA_WIDTH : positive := c_PAYLOAD_MEM_ADDR_WIDTH + 1 + c_PACKET_PAYLOAD_SIZE_WIDTH + 64;
   subtype t_meta_mem_data   is std_logic_vector(c_META_RAM_DATA_WIDTH-1 downto 0);
   subtype t_meta_mem_addr   is std_logic_vector(c_META_MEM_ADDR_WIDTH-1 downto 0);


   signal meta_mem_wr_en           : std_logic;
   signal meta_mem_wr_addr         : t_meta_mem_addr;
   signal meta_mem_wr_data         : t_meta_mem_data;
   signal meta_mem_rd_en           : std_logic := '0';
   signal meta_mem_rd_addr         : t_meta_mem_addr :=(others=>'0');
   signal meta_mem_rd_data         : t_meta_mem_data;
   signal meta_mem_used_count      : unsigned(c_META_MEM_ADDR_WIDTH downto 0); --Complete packets available to read side
   signal meta_mem_reserved_count  : unsigned(c_META_MEM_ADDR_WIDTH downto 0); --Slots reserved, including packet currently being stored 
   signal meta_mem_full            : std_logic;


   -- payload_ram signals
   subtype t_payload_mem_addr   is std_logic_vector(c_PAYLOAD_MEM_ADDR_WIDTH-1 downto 0);

   signal payload_mem_wr_en           : std_logic;
   signal payload_mem_wr_addr         : t_payload_mem_addr;
   signal payload_mem_wr_data         : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
   signal payload_mem_rd_en           : std_logic := '0';
   signal payload_mem_rd_en_d         : std_logic;
   signal payload_mem_rd_addr         : t_payload_mem_addr;
   signal payload_mem_rd_data         : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
   signal payload_mem_used_count      : unsigned(c_PAYLOAD_MEM_ADDR_WIDTH downto 0);


   -- metadata
   type t_packet_meta is record
      payload_addr_begin   : t_payload_mem_addr;
      sync_dis             : std_logic;
      payload_words        : std_logic_vector(c_PACKET_PAYLOAD_SIZE_WIDTH-1 downto 0);
      sample_nr            : std_logic_vector(63 downto 0);
   end record;


   -- Helper function to assign t_packet_meta record to std_logic_vector
   function pack_meta(meta : t_packet_meta) return t_meta_mem_data is
   begin
      return
         meta.payload_addr_begin &
         meta.sync_dis          &
         meta.payload_words     &
         meta.sample_nr;
   end function;

   function unpack_meta(data : t_meta_mem_data) return t_packet_meta is
   variable ret : t_packet_meta;
   begin
   ret.payload_addr_begin :=
      data(c_META_RAM_DATA_WIDTH-1 downto
           c_META_RAM_DATA_WIDTH-c_PAYLOAD_MEM_ADDR_WIDTH);

   ret.sync_dis :=
      data(64 + c_PACKET_PAYLOAD_SIZE_WIDTH);

   ret.payload_words :=
      data(64 + c_PACKET_PAYLOAD_SIZE_WIDTH - 1 downto 64);

   ret.sample_nr :=
      data(63 downto 0);

   return ret;
   end function;



   function reconstruct_header(meta : t_packet_meta) return std_logic_vector is
      variable ret           : std_logic_vector(127 downto 0);
      variable payload_bytes : unsigned(15 downto 0);
   begin
      ret := (others => '0');

      -- Original header sample number
      ret(127 downto 64) := meta.sample_nr;

      -- Convert payload words back to payload bytes.
      -- payload_words = payload_bytes / 16
      -- payload_bytes = payload_words * 16
      payload_bytes := shift_left(unsigned(meta.payload_words), 4);
      ret(23 downto 8) := std_logic_vector(payload_bytes);

      -- sync_dis bit
      ret(4) := meta.sync_dis;

      return ret;
   end function;


   signal wr_meta          : t_packet_meta;
   signal rd_meta          : t_packet_meta;
   signal rd_meta_valid    : std_logic:='0';
   signal rd_meta_pop      : std_logic;
   signal rd_meta_pending  : std_logic;

   signal m_axis_tdata_int     : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
   signal m_axis_tvalid_int    : std_logic;
   signal m_axis_handshake     : std_logic;


   signal payload_last_word    : std_logic;
   signal payload_discard      : std_logic;

   -- Number of payload RAM read requests issued for current packet
   signal payload_rd_req_cnt    : unsigned(c_PACKET_PAYLOAD_SIZE_WIDTH-1 downto 0);

   -- Number of AXI words accepted by downstream for current packet
   signal payload_tx_cnt        : unsigned(c_PACKET_PAYLOAD_SIZE_WIDTH-1 downto 0);

   signal payload_buf0          : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
   signal payload_buf1          : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
   signal payload_buf_count     : unsigned(1 downto 0);

   signal payload_buf_push      : std_logic;
   signal payload_axis_pop      : std_logic;
   signal payload_can_issue     : std_logic;
   signal payload_read_start    : std_logic;
   signal payload_is_empty      : std_logic;

begin


   -- ----------------------------------------------------------------------------
   -- Packet metadata memory
   -- ----------------------------------------------------------------------------
   metadata_mem_i : entity work.simple_dual_port_ram
      generic map (
         DATA_WIDTH => c_META_RAM_DATA_WIDTH,
         ADDR_WIDTH => c_META_MEM_ADDR_WIDTH,
         AMD_RAM_STYLE => "block"
      )
      port map (
         wr_clk  => clk,
         wr_en   => meta_mem_wr_en,
         wr_addr => meta_mem_wr_addr,
         wr_data => meta_mem_wr_data,
         rd_clk  => clk,
         rd_en   => meta_mem_rd_en,
         rd_addr => meta_mem_rd_addr,
         rd_data => meta_mem_rd_data
   );


   -- Meta data memory write handling
   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            meta_mem_wr_en             <= '0';
            meta_mem_wr_addr           <= (others=>'0');
            meta_mem_wr_data           <= (others=>'0');

         else
            if current_store_state = ST_STORE_META then 
               meta_mem_wr_en <= '1';
               meta_mem_wr_data <= pack_meta(wr_meta);
            else 
               meta_mem_wr_en <= '0';
            end if;

            if meta_mem_wr_en = '1' then 
               meta_mem_wr_addr <= std_logic_vector(unsigned(meta_mem_wr_addr) + 1);
            else 
               meta_mem_wr_addr <= meta_mem_wr_addr;
            end if;

         end if;
      end if;
   end process;


   -- meta_mem_reserved_count - allocated slots incl. in-progress packet, used for backpressure.
   -- meta_mem_used_count -  committed packets only, used for read-side packet availability.
   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            meta_mem_used_count     <= (others => '0');
            meta_mem_reserved_count <= (others => '0');
         else
            -- Used-count update
            if meta_mem_wr_en = '1' and meta_mem_rd_en = '0' then
                meta_mem_used_count <= meta_mem_used_count + 1;

            elsif meta_mem_wr_en = '0' and meta_mem_rd_en = '1' then
                meta_mem_used_count <= meta_mem_used_count - 1;

            else
                meta_mem_used_count <= meta_mem_used_count;
            end if;

            -- Slots reserved update
            if store_pckt_hdr_accepted = '1' and meta_mem_rd_en = '0' then
                meta_mem_reserved_count <= meta_mem_reserved_count + 1;

            elsif store_pckt_hdr_accepted = '0' and meta_mem_rd_en = '1' then
                meta_mem_reserved_count <= meta_mem_reserved_count - 1;

            else
                meta_mem_reserved_count <= meta_mem_reserved_count;
            end if;
         end if;
      end if;
   end process;


   meta_mem_full                 <= '0' when meta_mem_reserved_count < g_MAX_PACKETS else '1';
   store_pckt_hdr_accepted       <= '1' when current_store_state = ST_WAIT_HEADER and s_axis_handshake = '1' else '0';
   store_pckt_payload_will_fit   <= '1' when unsigned(wr_meta.payload_words) <= (g_MAX_FIFO_WORDS - payload_mem_used_count) else '0';


   meta_mem_rd_en <= '1' when rd_meta_valid = '0' AND rd_meta_pending = '0' AND  meta_mem_used_count /= 0 else '0';

   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            meta_mem_rd_addr <= (others=>'0');
         else
            if meta_mem_rd_en = '1' then 
               meta_mem_rd_addr <= std_logic_vector(unsigned(meta_mem_rd_addr)+1);
            end if;
         end if;
      end if;
   end process;


   -- ----------------------------------------------------------------------------
   -- Packet Payload memory
   -- ----------------------------------------------------------------------------
   payload_mem_i : entity work.simple_dual_port_ram
      generic map (
         DATA_WIDTH => c_AXIS_DATA_WIDTH,
         ADDR_WIDTH => c_PAYLOAD_MEM_ADDR_WIDTH,
         AMD_RAM_STYLE => "block"
      )
      port map (
         wr_clk  => clk,
         wr_en   => payload_mem_wr_en,
         wr_addr => payload_mem_wr_addr,
         wr_data => payload_mem_wr_data,
         rd_clk  => clk,
         rd_en   => payload_mem_rd_en,
         rd_addr => payload_mem_rd_addr,
         rd_data => payload_mem_rd_data
      );


   -- Payload mem write enable and data 
   process (clk)
   begin
      if rising_edge(clk) then
         -- Registered s_axis_tdata to have better performance
         payload_mem_wr_data <= s_axis_tdata;

         if current_store_state = ST_STORE_PAYLOAD AND s_axis_handshake = '1' then
            payload_mem_wr_en <= '1';
         else 
            payload_mem_wr_en <= '0';
         end if;

      end if;
   end process;


   -- Payload mem address
   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            payload_mem_wr_addr <= (others=>'0');
         else
            if payload_mem_wr_en = '1' then 
               payload_mem_wr_addr <= std_logic_vector(unsigned(payload_mem_wr_addr) + 1);
            end if;
         end if;
      end if;
   end process;
   

   -- Payload mem space used
   process (clk)
      variable v_used : unsigned(payload_mem_used_count'range);
   begin
      if rising_edge(clk) then
         if rst = '1' then
            payload_mem_used_count <= (others => '0');
         else

            v_used := payload_mem_used_count;

            if payload_mem_wr_en = '1' then
               v_used := v_used + 1;
            end if;

            -- Release one word when payload RAM read is issued
            if payload_mem_rd_en = '1' then
               v_used := v_used - 1;
            end if;

            -- Release entire packet when discarded
            if payload_discard = '1' then
               v_used := v_used - resize(unsigned(rd_meta.payload_words), v_used'length);
            end if;

            payload_mem_used_count <= v_used;

         end if;
      end if;
   end process;


   -- Payload RAM read logic
   PAYLOAD_ISSUE_COMB : process(all)
      variable v_occ_after : integer range 0 to 3;
   begin
      payload_can_issue <= '0';

      v_occ_after := to_integer(payload_buf_count);

      -- AXI pop frees one buffer slot this clock
      if payload_axis_pop = '1' then
         if v_occ_after > 0 then
            v_occ_after := v_occ_after - 1;
         end if;
      end if;

      -- RAM data returning this clock consumes one buffer slot
      if payload_buf_push = '1' then
         v_occ_after := v_occ_after + 1;
      end if;

      if current_read_state = RD_READ_PAYLOAD then
         if payload_rd_req_cnt < unsigned(rd_meta.payload_words) then
            if v_occ_after < 2 then
               payload_can_issue <= '1';
            end if;
         end if;
      end if;
   end process;

   payload_mem_rd_en <= payload_can_issue;


   -- Payload read address and counters
   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then

            payload_mem_rd_addr <= (others => '0');
            payload_mem_rd_en_d <= '0';

            payload_rd_req_cnt  <= (others => '0');
            payload_tx_cnt      <= (others => '0');

         else

            -- Delay RAM read request by one clock to mark valid RAM output
            payload_mem_rd_en_d <= payload_mem_rd_en;

            -- Packet payload read start, either explicit pct_rd or automatic sync_dis
            if payload_read_start = '1' then
               payload_mem_rd_addr <= rd_meta.payload_addr_begin;
               payload_rd_req_cnt  <= (others => '0');
               payload_tx_cnt      <= (others => '0');

            else

               -- Issue payload RAM read
               -- RAM samples old payload_mem_rd_addr on this clock edge.
               if payload_mem_rd_en = '1' then
                  payload_mem_rd_addr <= std_logic_vector(unsigned(payload_mem_rd_addr) + 1);
                  payload_rd_req_cnt  <= payload_rd_req_cnt + 1;
               end if;

               -- Downstream accepted one AXI word
               if m_axis_handshake = '1' then
                  payload_tx_cnt <= payload_tx_cnt + 1;
               end if;

            end if;

            if current_read_state = RD_DONE then
               payload_rd_req_cnt <= (others => '0');
               payload_tx_cnt     <= (others => '0');
            end if;

         end if;
      end if;
   end process;


   -- ----------------------------------------------------------------------------
   -- Packet Write logic
   -- ----------------------------------------------------------------------------

   -- Helper signals 
   s_axis_handshake        <= s_axis_tvalid AND s_axis_tready_reg;


   -- Packet store State machine
   STORE_FSM_F : process (clk) is
   begin
      if rising_edge(clk) then
         if (rst = '1') then
            current_store_state <= ST_IDLE;
         else 
            current_store_state <= next_store_state;
         end if;
      end if;

   end process STORE_FSM_F;


   -- Packet store state machine combo
   STORE_FSM : process (all) is
   begin

      next_store_state <= current_store_state;

      case current_store_state is

         when ST_IDLE => -- state
            next_store_state <= ST_WAIT_HEADER;

         when ST_WAIT_HEADER => 
            if s_axis_handshake ='1' then 
               next_store_state <= ST_CHECK_PAYLOAD_LENGTH;
            end if;

         when ST_CHECK_PAYLOAD_LENGTH =>
            if store_pckt_payload_will_fit = '1' then 
               if unsigned(wr_meta.payload_words) = 0 then -- zero length payload should not be allowed from host, but just in case
                  next_store_state <= ST_STORE_META;
               else
                  next_store_state <= ST_STORE_PAYLOAD;
               end if;
            end if;

         when ST_STORE_PAYLOAD => 
            if s_axis_handshake = '1' then 
               if store_cnt >= unsigned(wr_meta.payload_words) - 1  then 
                  next_store_state <= ST_STORE_META;
               end if;
            end if;

         when ST_STORE_META => 
            next_store_state <= ST_WAIT_HEADER;

         when others =>
            next_store_state <= ST_IDLE;

      end case;

   end process STORE_FSM;


   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then 
            s_axis_tready_reg <= '0';
         -- Using next_store_state intentionally to deassert s_axis_tready
         -- immediately after the last payload word.
         elsif next_store_state = ST_WAIT_HEADER AND meta_mem_full = '0' then 
            s_axis_tready_reg <= '1';
         elsif next_store_state = ST_STORE_PAYLOAD then 
            s_axis_tready_reg <= '1';
         else 
            s_axis_tready_reg <= '0';
         end if;
      end if;
   end process;


   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            store_cnt <= (others=>'0');
         else

            if current_store_state = ST_STORE_PAYLOAD then
               if s_axis_handshake = '1' then
                  store_cnt <= store_cnt + 1;
               else 
                  store_cnt <= store_cnt;
               end if;
            else 
               store_cnt <= (others=>'0');
            end if;
            
         end if;
      end if;
   end process;


   -- Storing wr metadata in temp register
   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            wr_meta.payload_addr_begin  <= (others=>'0');
            wr_meta.sync_dis           <= '0';
            wr_meta.payload_words      <= (others=>'0');
            wr_meta.sample_nr          <= (others=>'0');
         else
            if current_store_state = ST_WAIT_HEADER AND s_axis_handshake = '1' then 
               wr_meta.payload_addr_begin  <= payload_mem_wr_addr;
               wr_meta.sync_dis           <= s_axis_tdata(4);
               --Payload size is in bytes. Stored in  23 downto 8 range. Dividing by 16 to get payload in words
               wr_meta.payload_words      <= "0000" & s_axis_tdata(23 downto 12); 
               wr_meta.sample_nr          <= s_axis_tdata(127 downto 64);
            end if;
         end if;
      end if;
   end process;


   -- ----------------------------------------------------------------------------
   -- Packet Read logic
   -- ----------------------------------------------------------------------------


   payload_discard   <= '1' when current_read_state = RD_META_CHECK and
                            rd_meta_valid = '1' and
                            rd_meta.sync_dis = '0' and
                            pct_clr = '1'
                        else '0';

   payload_last_word <= '1' when unsigned(rd_meta.payload_words) /= 0 and
                                 payload_tx_cnt = unsigned(rd_meta.payload_words) - 1
                        else '0';


   payload_is_empty <= '1' when unsigned(rd_meta.payload_words) = 0 else '0';


   -- Intended behavior for payload read:
   --    sync_dis = 0, pct_clr = 1:
   --    discard packet
   --
   --    sync_dis = 0, pct_rd = 1, pct_clr = 0:
   --    stream packet
   --
   --    sync_dis = 1:
   --    auto-stream packet, regardless of pct_rd/pct_clr
   payload_read_start <= '1' when current_read_state = RD_META_CHECK and
                               rd_meta_valid = '1' and
                               (
                                  rd_meta.sync_dis = '1' or
                                  (pct_clr = '0' and pct_rd = '1')
                               )
                         else '0';


   -- Packet read State machine
   READ_FSM_F : process (clk) is
   begin
      if rising_edge(clk) then
         if (rst = '1') then
            current_read_state <= RD_IDLE;
         else 
            current_read_state <= next_read_state;
         end if;
      end if;

   end process READ_FSM_F;


   -- Packet read state machine combo
   READ_FSM : process (all) is
   begin

      next_read_state <= current_read_state;

      case current_read_state is

         when RD_IDLE => -- state
            if rd_meta_valid = '1' then
               next_read_state <= RD_META_CHECK;
            end if;

         when RD_META_CHECK => 
            if payload_discard = '1' then
               next_read_state <= RD_DONE;
            elsif payload_read_start = '1' then
               if payload_is_empty = '1' then
                  next_read_state <= RD_DONE;
               else
                  next_read_state <= RD_READ_PAYLOAD;
               end if;
            end if;

         when RD_READ_PAYLOAD => 
         if payload_last_word = '1' and m_axis_handshake = '1' then
            next_read_state <= RD_DONE;
         end if;

         when RD_DONE => 
            next_read_state <= RD_IDLE;

         when others =>
            next_read_state <= RD_IDLE;

      end case;

   end process READ_FSM;


   rd_meta_pop <= '1' when current_read_state = RD_DONE else '0';


   process (clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            rd_meta_valid     <= '0';
            rd_meta_pending   <= '0';
            
            rd_meta.payload_addr_begin  <= (others=>'0');
            rd_meta.sync_dis           <='0';
            rd_meta.payload_words      <= (others=>'0'); 
            rd_meta.sample_nr          <= (others=>'0');
   
         else

            -- Issue metadata RAM read
            if meta_mem_rd_en = '1' then
               rd_meta_pending  <= '1';
            -- One-cycle RAM latency: data is valid while rd_meta_pending was high
            elsif rd_meta_pending = '1' then
               rd_meta_pending <= '0';
            end if;

            -- Capture metadata after RAM latency
            if rd_meta_pending = '1' then
               rd_meta       <= unpack_meta(meta_mem_rd_data);
               rd_meta_valid <= '1';
            end if;

            -- Clear current metadata when packet is consumed/discarded
            if rd_meta_pop = '1' then
               rd_meta_valid <= '0';
            end if;
            
         end if;
      end if;
   end process;


   -- ----------------------------------------------------------------------------
   -- m_axis handling
   -- ----------------------------------------------------------------------------
   m_axis_tdata_int  <= payload_buf0;
   m_axis_tvalid_int <= '1' when payload_buf_count /= "00" else '0';

   m_axis_handshake <= m_axis_tvalid_int and m_axis_tready;

   payload_axis_pop <= m_axis_handshake;

   -- payload_mem_rd_data is valid one clock after payload_mem_rd_en
   payload_buf_push <= payload_mem_rd_en_d;


   -- 2-entry AXI output buffer
   process(clk)
      variable v_buf0  : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
      variable v_buf1  : std_logic_vector(c_AXIS_DATA_WIDTH-1 downto 0);
      variable v_count : integer range 0 to 2;
   begin
      if rising_edge(clk) then
         if rst = '1' then

            payload_buf0      <= (others => '0');
            payload_buf1      <= (others => '0');
            payload_buf_count <= (others => '0');

         else

            v_buf0  := payload_buf0;
            v_buf1  := payload_buf1;
            v_count := to_integer(payload_buf_count);

            -- Pop accepted AXI word
            if payload_axis_pop = '1' then
               if v_count = 2 then
                  v_buf0 := v_buf1;
               end if;

               if v_count > 0 then
                  v_count := v_count - 1;
               end if;
            end if;

            -- Push newly returned RAM word
            if payload_buf_push = '1' then
               if v_count = 0 then
                  v_buf0 := payload_mem_rd_data;
               elsif v_count = 1 then
                  v_buf1 := payload_mem_rd_data;
               end if;

               if v_count < 2 then
                  v_count := v_count + 1;
               end if;
            end if;

            -- Safety clear after packet completion or discard
            if current_read_state = RD_DONE then
               v_count := 0;
            end if;

            payload_buf0      <= v_buf0;
            payload_buf1      <= v_buf1;
            payload_buf_count <= to_unsigned(v_count, payload_buf_count'length);

         end if;
      end if;
   end process;


   -- ----------------------------------------------------------------------------
   -- Output assignment
   -- ----------------------------------------------------------------------------
   s_axis_tready <= s_axis_tready_reg;

   -- pct_valid is not asserted when sync_dis is set in the packet header;
   -- the packet is automatically read in this case.
   pct_valid <= '1' when current_read_state = RD_META_CHECK and
                      rd_meta_valid = '1' and
                      rd_meta.sync_dis = '0'
             else '0';
   pct_header <= reconstruct_header(rd_meta);

   m_axis_tdata  <= m_axis_tdata_int;
   m_axis_tvalid <= m_axis_tvalid_int;

   
end architecture rtl;
