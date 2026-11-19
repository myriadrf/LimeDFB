-- ----------------------------------------------------------------------------
-- FILE:          host_tcd_tx_buffer.vhd
-- DESCRIPTION:   Four-channel HostTCD TX sample RAM and IQ unpacker
-- SPDX-License-Identifier: Apache-2.0
-- ----------------------------------------------------------------------------
-- Eight 32-bit lanes per bank. RAM is not reset. The wrapper owns slots and
-- crosses completed/released slot descriptors between independent clocks.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity host_tcd_tx_buffer is
    generic (
        SLOT_SAMPLES : positive := 1024;
        SLOT_COUNT   : positive := 4
    );
    port (
        wr_clk : in std_logic;
        wr_reset : in std_logic;
        load_valid : in std_logic;
        load_ready : out std_logic;
        load_slot : in integer range 0 to SLOT_COUNT - 1;
        load_channels : in integer range 1 to 4;
        load_map : in std_logic_vector(7 downto 0);
        load_iq12 : in std_logic;
        sink_valid : in std_logic;
        sink_ready : out std_logic;
        sink_data : in std_logic_vector(255 downto 0);
        done_valid : out std_logic;
        done_ready : in std_logic;
        rd_clk : in std_logic;
        rd_reset : in std_logic;
        play_valid : in std_logic;
        play_ready : out std_logic;
        play_slot : in integer range 0 to SLOT_COUNT - 1;
        play_mask : in std_logic_vector(3 downto 0);
        source_valid : out std_logic;
        source_ready : in std_logic;
        source_data : out std_logic_vector(127 downto 0);
        source_last : out std_logic;
        release_valid : out std_logic;
        release_ready : in std_logic;
        release_slot : out integer range 0 to SLOT_COUNT - 1
    );
end entity;

architecture rtl of host_tcd_tx_buffer is
    constant ROWS : positive := SLOT_SAMPLES / 8;
    type lane_data_t is array (0 to 31) of std_logic_vector(31 downto 0);
    signal bank_data : lane_data_t;
    signal writing : std_logic := '0';
    signal done : std_logic := '0';
    signal wr_slot : integer range 0 to SLOT_COUNT - 1 := 0;
    signal channels : integer range 1 to 4 := 1;
    signal channel : integer range 0 to 3 := 0;
    signal channel_map : std_logic_vector(7 downto 0);
    signal iq12 : std_logic := '0';
    signal wr_row : integer range 0 to ROWS - 1 := 0;
    signal reservoir : std_logic_vector(511 downto 0) := (others => '0');
    signal beats_left : integer range 0 to SLOT_SAMPLES / 8 := 0;
    signal bit_count : integer range 0 to 512 := 0;
    signal next_reservoir : std_logic_vector(511 downto 0);
    signal next_bit_count : integer range 0 to 512;
    signal row_data : std_logic_vector(255 downto 0);
    signal row_available : std_logic;
    signal commit : std_logic := '0';
    signal commit_channel : integer range 0 to 3 := 0;
    signal commit_address : integer range 0 to SLOT_COUNT * ROWS - 1 := 0;
    signal commit_data : std_logic_vector(255 downto 0);
    signal reading : std_logic := '0';
    signal rd_slot : integer range 0 to SLOT_COUNT - 1 := 0;
    signal rd_offset : integer range 0 to SLOT_SAMPLES - 1 := 0;
    signal rd_mask : std_logic_vector(3 downto 0);
    signal read_fire : std_logic;
    signal output_valid : std_logic := '0';
    signal output_last : std_logic := '0';
    signal output_lane : integer range 0 to 7 := 0;
    signal released : std_logic := '0';
begin
    assert SLOT_SAMPLES mod 32 = 0 report "SLOT_SAMPLES must be a multiple of 32" severity failure;
    load_ready <= not writing and not done and not commit and not wr_reset;
    sink_ready <= '1' when writing = '1' and beats_left > 0 and bit_count <= 256 and wr_reset = '0' else '0';
    done_valid <= done and not wr_reset;

    -- ----------------------------------------------------------------------------
    -- DMA unpacking: one eight-sample row per processing clock.
    -- ----------------------------------------------------------------------------
    unpack_comb : process(all)
        variable data : std_logic_vector(511 downto 0);
        variable count : integer range 0 to 512;
        variable expanded : std_logic_vector(255 downto 0);
    begin
        data := reservoir;
        count := bit_count;
        expanded := reservoir(255 downto 0);
        row_available <= '0';
        if iq12 = '1' then
            for i in 0 to 7 loop
                expanded(32*i+15 downto 32*i) := reservoir(24*i+11 downto 24*i) & "0000";
                expanded(32*i+31 downto 32*i+16) := reservoir(24*i+23 downto 24*i+12) & "0000";
            end loop;
            if count >= 192 then
                row_available <= '1';
                data := (191 downto 0 => '0') & reservoir(511 downto 192);
                count := count - 192;
            end if;
        elsif count >= 256 then
            row_available <= '1';
            data := (255 downto 0 => '0') & reservoir(511 downto 256);
            count := count - 256;
        end if;
        row_data <= expanded;
        if sink_valid = '1' and sink_ready = '1' then
            data := data or std_logic_vector(shift_left(resize(unsigned(sink_data),512),count));
            count := count + 256;
        end if;
        next_reservoir <= data;
        next_bit_count <= count;
    end process;

    unpack_proc : process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            commit <= '0';
            if wr_reset = '1' then
                writing <= '0'; done <= '0'; bit_count <= 0;
            else
                if done = '1' and done_ready = '1' then done <= '0'; end if;
                if load_valid = '1' and load_ready = '1' then
                    writing <= '1'; wr_slot <= load_slot; channels <= load_channels;
                    channel <= 0; channel_map <= load_map; iq12 <= load_iq12;
                    wr_row <= 0; bit_count <= 0; reservoir <= (others => '0');
                    beats_left <= SLOT_SAMPLES / 8;
                    if load_iq12 = '1' then beats_left <= SLOT_SAMPLES * 3 / 32; end if;
                elsif writing = '1' then
                    reservoir <= next_reservoir; bit_count <= next_bit_count;
                    if sink_valid = '1' and sink_ready = '1' then beats_left <= beats_left - 1; end if;
                    if row_available = '1' then
                        commit <= '1'; commit_data <= row_data;
                        commit_address <= wr_slot * ROWS + wr_row;
                        case channel is
                            when 0 => commit_channel <= to_integer(unsigned(channel_map(1 downto 0)));
                            when 1 => commit_channel <= to_integer(unsigned(channel_map(3 downto 2)));
                            when 2 => commit_channel <= to_integer(unsigned(channel_map(5 downto 4)));
                            when 3 => commit_channel <= to_integer(unsigned(channel_map(7 downto 6)));
                        end case;
                        if wr_row = ROWS - 1 then
                            assert next_bit_count = 0 report "TX channel payload has trailing data" severity failure;
                            wr_row <= 0;
                            if channel = channels - 1 then writing <= '0'; done <= '1';
                            else
                                channel <= channel + 1; beats_left <= SLOT_SAMPLES / 8;
                                if iq12 = '1' then beats_left <= SLOT_SAMPLES * 3 / 32; end if;
                            end if;
                        else wr_row <= wr_row + 1; end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------------------------
    -- Simple dual-port RAM: eight independent lanes in each physical bank.
    -- ----------------------------------------------------------------------------
    banks : for b in 0 to 3 generate
        lanes : for l in 0 to 7 generate
            type ram_t is array (0 to SLOT_COUNT * ROWS - 1) of std_logic_vector(31 downto 0);
            signal ram : ram_t;
            attribute ram_style : string;
            attribute ram_style of ram : signal is "block";
        begin
            process(wr_clk)
            begin
                if rising_edge(wr_clk) then
                    if commit = '1' and wr_reset = '0' and commit_channel = b then
                        ram(commit_address) <= commit_data(32*l+31 downto 32*l);
                    end if;
                end if;
            end process;
            process(rd_clk)
            begin
                if rising_edge(rd_clk) then
                    if read_fire = '1' and rd_offset mod 8 = l then
                        bank_data(b*8+l) <= ram(rd_slot * ROWS + rd_offset / 8);
                    end if;
                end if;
            end process;
        end generate;
        source_data(32*b+31 downto 32*b) <= bank_data(b*8+output_lane) when rd_mask(b) = '1' else (others => '0');
    end generate;

    -- ----------------------------------------------------------------------------
    -- Playback: one four-channel frame per clock, stable under backpressure.
    -- ----------------------------------------------------------------------------
    play_ready <= not reading and not output_valid and not released and not rd_reset;
    read_fire <= reading and (not output_valid or source_ready) and not rd_reset;
    source_valid <= output_valid and not rd_reset;
    source_last <= output_last;
    release_valid <= released and not rd_reset;
    release_slot <= rd_slot;
    playback_proc : process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if rd_reset = '1' then
                reading <= '0'; output_valid <= '0'; released <= '0';
            else
                if released = '1' and release_ready = '1' then released <= '0'; end if;
                if play_valid = '1' and play_ready = '1' then
                    reading <= '1'; rd_slot <= play_slot; rd_mask <= play_mask; rd_offset <= 0;
                end if;
                if output_valid = '1' and source_ready = '1' then
                    output_valid <= '0';
                    if output_last = '1' then released <= '1'; end if;
                end if;
                if read_fire = '1' then
                    output_valid <= '1'; output_lane <= rd_offset mod 8;
                    output_last <= '0';
                    if rd_offset = SLOT_SAMPLES - 1 then
                        output_last <= '1'; reading <= '0';
                    else rd_offset <= rd_offset + 1; end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
