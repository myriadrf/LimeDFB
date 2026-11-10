-- ----------------------------------------------------------------------------
-- FILE:          host_tcd_rx_buffer.vhd
-- DESCRIPTION:   Four-channel HostTCD acquisition buffer and IQ formatter
-- SPDX-License-Identifier: Apache-2.0
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- Four acquisition banks, eight 32-bit RAM lanes per bank.
-- RAM contents are not reset. External ownership FIFOs protect CDC access.
-- Write and read resets are synchronous and active high.
-- RAM writes are pipelined by one acquisition clock. The external ownership
-- FIFO accepts the completed-slot descriptor on the final RAM commit edge;
-- its CDC latency prevents the processing side from observing uncommitted data.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity host_tcd_rx_buffer is
    generic (
        -- Slots are shared sample intervals across all four channel banks.
        -- Each slot holds SLOT_SAMPLES complex IQ16 samples per channel.
        SLOT_SAMPLES : positive := 1024;
        SLOT_COUNT   : positive := 4
    );
    port (
        -- Acquisition clock domain
        wr_clk         : in  std_logic;
        wr_reset       : in  std_logic;
        wr_flush       : in  std_logic;
        capture_enable : in  std_logic;
        frame_valid    : in  std_logic;
        frame_data     : in  std_logic_vector(127 downto 0);
        sample_tick    : out std_logic_vector(63 downto 0);
        dropped_frames : out std_logic_vector(31 downto 0);
        slot_valid     : out std_logic;
        slot_ready     : in  std_logic;
        slot_index     : out integer range 0 to SLOT_COUNT - 1;
        slot_tick      : out std_logic_vector(63 downto 0);
        slot_gap       : out std_logic;
        release_valid  : in  std_logic;
        release_slot   : in  integer range 0 to SLOT_COUNT - 1;
        -- Processing clock domain
        rd_clk          : in  std_logic;
        rd_reset        : in  std_logic;
        command_valid   : in  std_logic;
        command_ready   : out std_logic;
        command_slot    : in  integer range 0 to SLOT_COUNT - 1;
        command_channel : in  integer range 0 to 3;
        command_iq12    : in  std_logic;
        source_valid    : out std_logic;
        source_ready    : in  std_logic;
        source_data     : out std_logic_vector(255 downto 0);
        source_last     : out std_logic
    );
end entity host_tcd_rx_buffer;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture rtl of host_tcd_rx_buffer is
    constant ROWS : positive := SLOT_SAMPLES / 8;

    type bank_data_t is array (0 to 3) of std_logic_vector(255 downto 0);

    signal bank_data    : bank_data_t;
    signal tick         : unsigned(63 downto 0) := (others => '0');
    signal drops        : unsigned(31 downto 0) := (others => '0');
    signal free_slots   : std_logic_vector(SLOT_COUNT - 1 downto 0) := (others => '1');
    signal wr_slot      : integer range 0 to SLOT_COUNT - 1 := 0;
    signal wr_offset    : integer range 0 to SLOT_SAMPLES - 1 := 0;
    signal writing      : std_logic := '0';
    signal gap_pending  : std_logic := '0';
    signal pending      : std_logic := '0';
    signal first_tick   : std_logic_vector(63 downto 0);
    signal first_gap    : std_logic;
    signal write_fire   : std_logic;
    signal read_fire    : std_logic := '0';
    signal read_pending : std_logic := '0';
    signal pack_pending : std_logic := '0';
    signal packed_data  : std_logic_vector(255 downto 0);
    signal busy         : std_logic := '0';
    signal iq12         : std_logic := '0';
    signal rd_slot      : integer range 0 to SLOT_COUNT - 1 := 0;
    signal rd_channel   : integer range 0 to 3 := 0;
    signal rd_row       : integer range 0 to ROWS - 1 := 0;
    signal rows_left    : integer range 0 to ROWS := 0;
    signal words_left   : integer range 0 to SLOT_SAMPLES / 8 := 0;
    -- Four DMA words cover RAM/packing latency plus a registered credit update while
    -- sustaining one IQ16 output beat per processing clock without stalls.
    signal reservoir    : std_logic_vector(1023 downto 0) := (others => '0');
    -- Every packed read contains three (IQ12) or four (IQ16) 64-bit units.
    -- Credits include both the synchronous RAM read and packing stage in flight.
    signal unit_count   : integer range 0 to 16 := 0;
    signal used_units   : integer range 0 to 16 := 0;
    signal chunk_units  : integer range 3 to 4;
    signal output_fire  : std_logic;

begin
    assert SLOT_SAMPLES mod 32 = 0 report "SLOT_SAMPLES must be a multiple of 32" severity failure;
    sample_tick    <= std_logic_vector(tick);
    dropped_frames <= std_logic_vector(drops);
    slot_valid     <= pending;
    write_fire <= '1' when wr_flush = '0' and capture_enable = '1' and frame_valid = '1'
                     and (writing = '1' or (free_slots(wr_slot) = '1'
                     and (pending = '0' or slot_ready = '1'))) else '0';

    -- ----------------------------------------------------------------------------
    -- Acquisition and slot ownership
    -- ----------------------------------------------------------------------------
    acquisition_proc : process(wr_clk)
        variable available : std_logic_vector(SLOT_COUNT - 1 downto 0);
    begin
        if rising_edge(wr_clk) then
            -- The TX timing reference runs even if acquisition is disabled/full.
            if frame_valid = '1' then
                tick <= tick + 1;
            end if;
            if wr_reset = '1' then
                tick <= (others => '0');
            end if;
            if wr_reset = '1' or wr_flush = '1' then
                free_slots <= (others => '1');
                wr_slot <= 0;
                wr_offset <= 0;
                writing <= '0';
                pending <= '0';
                gap_pending <= '0';
                drops <= (others => '0');
            else
                available := free_slots;
                if release_valid = '1' then
                    available(release_slot) := '1';
                end if;
                if pending = '1' and slot_ready = '1' then
                    pending <= '0';
                end if;
                if capture_enable = '0' then
                    if writing = '1' then
                        available(wr_slot) := '1';
                        gap_pending <= '1';
                    end if;
                    writing <= '0';
                    wr_offset <= 0;
                elsif frame_valid = '1' then
                    if write_fire = '1' then
                        if writing = '0' then
                            available(wr_slot) := '0';
                            first_tick <= std_logic_vector(tick);
                            first_gap <= gap_pending;
                            gap_pending <= '0';
                            writing <= '1';
                        end if;
                        if wr_offset = SLOT_SAMPLES - 1 then
                            slot_index <= wr_slot;
                            slot_tick <= first_tick;
                            slot_gap <= first_gap;
                            pending <= '1';
                            writing <= '0';
                            wr_offset <= 0;
                            if wr_slot = SLOT_COUNT - 1 then
                                wr_slot <= 0;
                            else
                                wr_slot <= wr_slot + 1;
                            end if;
                        else
                            wr_offset <= wr_offset + 1;
                        end if;
                    else
                        drops <= drops + 1;
                        gap_pending <= '1';
                    end if;
                end if;
                free_slots <= available;
            end if;
        end if;
    end process acquisition_proc;

    -- ----------------------------------------------------------------------------
    -- Channel RAM banks
    -- ----------------------------------------------------------------------------
    banks_gen : for ch in 0 to 3 generate
        lanes_gen : for lane in 0 to 7 generate
            type ram_t is array (0 to SLOT_COUNT * ROWS - 1) of std_logic_vector(31 downto 0);
            signal ram : ram_t;
            signal wr_en_r   : std_logic := '0';
            signal wr_addr_r : integer range 0 to SLOT_COUNT * ROWS - 1 := 0;
            signal wr_data_r : std_logic_vector(31 downto 0);
            attribute ram_style : string;
            attribute ram_style of ram : signal is "block";
            attribute ramstyle : string;
            attribute ramstyle of ram : signal is "M10K";
        begin
            -- Keep frame admission/free-slot/FIFO-ready logic away from the
            -- physical RAM enable. Each lane owns a local registered write port.
            ram_write_pipeline_proc : process(wr_clk)
            begin
                if rising_edge(wr_clk) then
                    wr_en_r <= '0';
                    if wr_reset = '0' and write_fire = '1' and wr_offset mod 8 = lane then
                        wr_en_r   <= '1';
                        wr_addr_r <= wr_slot * ROWS + wr_offset / 8;
                        wr_data_r <= frame_data(32 * ch + 31 downto 32 * ch);
                    end if;
                end if;
            end process ram_write_pipeline_proc;

            ram_write_proc : process(wr_clk)
            begin
                if rising_edge(wr_clk) then
                    if wr_en_r = '1' then
                        ram(wr_addr_r) <= wr_data_r;
                    end if;
                end if;
            end process ram_write_proc;

            ram_read_proc : process(rd_clk)
            begin
                if rising_edge(rd_clk) then
                    if read_fire = '1' and rd_channel = ch then
                        bank_data(ch)(32 * lane + 31 downto 32 * lane) <= ram(rd_slot * ROWS + rd_row);
                    end if;
                end if;
            end process ram_read_proc;
        end generate lanes_gen;
    end generate banks_gen;

    -- ----------------------------------------------------------------------------
    -- Read capacity and output interface
    -- ----------------------------------------------------------------------------
    command_ready <= not busy;
    chunk_units   <= 3 when iq12 = '1' else 4;

    -- Registered reservation count breaks the combinational path from downstream
    -- ready through capacity arithmetic to the RAM/read-address enables. Space
    -- freed this cycle becomes available on the next cycle.
    read_fire <= '1' when busy = '1' and rows_left /= 0 and
                 ((iq12 = '1' and used_units <= 13) or
                  (iq12 = '0' and used_units <= 12)) else '0';

    source_valid <= '1' when busy = '1' and unit_count >= 4 else '0';
    source_data  <= reservoir(255 downto 0);
    source_last  <= '1' when words_left = 1 else '0';
    output_fire  <= '1' when busy = '1' and unit_count >= 4 and source_ready = '1' else '0';

    -- ----------------------------------------------------------------------------
    -- Synchronous read pipeline and IQ formatter
    -- ----------------------------------------------------------------------------
    -- Separate channel selection and IQ truncation from reservoir insertion.
    -- This breaks the routed bank-select fanout through the append/output mux.
    packing_proc : process(rd_clk)
        variable packed : std_logic_vector(255 downto 0);
    begin
        if rising_edge(rd_clk) then
            if rd_reset = '1' then
                pack_pending <= '0';
            else
                pack_pending <= read_pending;
                if read_pending = '1' then
                    packed := bank_data(rd_channel);
                    if iq12 = '1' then
                        packed := (others => '0');
                        for i in 0 to 15 loop
                            packed(12 * i + 11 downto 12 * i) := bank_data(rd_channel)(16 * i + 15 downto 16 * i + 4);
                        end loop;
                    end if;
                    packed_data <= packed;
                end if;
            end if;
        end if;
    end process packing_proc;

    readout_proc : process(rd_clk)
        variable unit_level : integer range 0 to 16;
        variable credit : integer range 0 to 16;
        variable data   : std_logic_vector(1023 downto 0);
        variable packed : std_logic_vector(255 downto 0);
    begin
        if rising_edge(rd_clk) then
            if rd_reset = '1' then
                busy <= '0';
                read_pending <= '0';
                rows_left <= 0;
                unit_count <= 0;
                used_units <= 0;
                words_left <= 0;
                reservoir <= (others => '0');
            else
                read_pending <= read_fire;
                unit_level := unit_count;
                credit := used_units;
                data := reservoir;
                if busy = '0' and command_valid = '1' then
                    busy <= '1';
                    rd_slot <= command_slot;
                    rd_channel <= command_channel;
                    iq12 <= command_iq12;
                    rd_row <= 0;
                    rows_left <= ROWS;
                    if command_iq12 = '1' then
                        words_left <= SLOT_SAMPLES * 3 / 32;
                    else
                        words_left <= SLOT_SAMPLES / 8;
                    end if;
                end if;
                if output_fire = '1' then
                    data := std_logic_vector(shift_right(unsigned(data), 256));
                    unit_level := unit_level - 4;
                    credit := credit - 4;
                    words_left <= words_left - 1;
                    if words_left = 1 then
                        busy <= '0';
                    end if;
                end if;
                if pack_pending = '1' then
                    packed := packed_data;
                    -- Append only at 64-bit boundaries. Explicit constant shifts
                    -- replace a bit-addressed variable barrel shifter and its carry path.
                    case unit_level is
                        when 0 => data(255 downto 0)   := data(255 downto 0) or packed;
                        when 1 => data(319 downto 64)  := data(319 downto 64) or packed;
                        when 2 => data(383 downto 128) := data(383 downto 128) or packed;
                        when 3 => data(447 downto 192) := data(447 downto 192) or packed;
                        when 4 => data(511 downto 256) := data(511 downto 256) or packed;
                        when 5 => data(575 downto 320) := data(575 downto 320) or packed;
                        when 6 => data(639 downto 384) := data(639 downto 384) or packed;
                        when 7 => data(703 downto 448) := data(703 downto 448) or packed;
                        when 8 => data(767 downto 512) := data(767 downto 512) or packed;
                        when 9 => data(831 downto 576) := data(831 downto 576) or packed;
                        when 10 => data(895 downto 640) := data(895 downto 640) or packed;
                        when 11 => data(959 downto 704) := data(959 downto 704) or packed;
                        when 12 => data(1023 downto 768) := data(1023 downto 768) or packed;
                        -- Thirteen occupied units can only accept an IQ12 read.
                        when 13 => data(1023 downto 832) := data(1023 downto 832) or packed(191 downto 0);
                        when others => null;
                    end case;
                    unit_level := unit_level + chunk_units;
                end if;
                if read_fire = '1' then
                    credit := credit + chunk_units;
                    rows_left <= rows_left - 1;
                    if rd_row /= ROWS - 1 then
                        rd_row <= rd_row + 1;
                    end if;
                end if;
                reservoir <= data;
                unit_count <= unit_level;
                used_units <= credit;
            end if;
        end if;
    end process readout_proc;
end architecture rtl;
