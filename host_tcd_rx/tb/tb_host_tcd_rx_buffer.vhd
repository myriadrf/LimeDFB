-- ----------------------------------------------------------------------------
-- FILE:          tb_host_tcd_rx_buffer.vhd
-- DESCRIPTION:   Self-checking testbench for host_tcd_rx_buffer
-- SPDX-License-Identifier: Apache-2.0
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- Exercises IQ16/IQ12 formatting, independent clocks, backpressure,
-- overflow, slot reuse and acquisition timestamp continuity.
-- Small slots keep simulation waveforms readable.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity tb_host_tcd_rx_buffer is
    generic (
        TEST_SLOT_SAMPLES : positive := 32;
        STALL_OUTPUT       : boolean := true
    );
end entity tb_host_tcd_rx_buffer;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture sim of tb_host_tcd_rx_buffer is
    constant SLOT_SAMPLES  : positive := TEST_SLOT_SAMPLES;
    constant SLOT_COUNT    : positive := 2;
    constant WR_CLK_PERIOD : time := 8 ns;
    constant RD_CLK_PERIOD : time := 14 ns;

    signal wr_clk          : std_logic := '0';
    signal rd_clk          : std_logic := '0';
    signal reset           : std_logic := '1';
    signal wr_flush        : std_logic := '1';
    signal capture_enable  : std_logic := '0';
    signal frame_valid     : std_logic := '0';
    signal frame_data      : std_logic_vector(127 downto 0);
    signal sample_tick     : std_logic_vector(63 downto 0);
    signal dropped_frames  : std_logic_vector(31 downto 0);
    signal slot_valid      : std_logic := '0';
    signal slot_ready      : std_logic := '0';
    signal slot_gap        : std_logic := '0';
    signal release_valid   : std_logic := '0';
    signal slot_index      : integer range 0 to SLOT_COUNT - 1 := 0;
    signal release_slot    : integer range 0 to SLOT_COUNT - 1 := 0;
    signal slot_tick       : std_logic_vector(63 downto 0);
    signal command_valid   : std_logic := '0';
    signal command_ready   : std_logic := '0';
    signal command_iq12    : std_logic := '0';
    signal source_valid    : std_logic := '0';
    signal source_ready    : std_logic := '0';
    signal source_last     : std_logic := '0';
    signal command_slot    : integer range 0 to SLOT_COUNT - 1 := 0;
    signal command_channel : integer range 0 to 3 := 0;
    signal source_data     : std_logic_vector(255 downto 0);

    function sample(index, channel : natural) return std_logic_vector is
        variable v : std_logic_vector(31 downto 0);
    begin
        v(15 downto 0) := std_logic_vector(to_unsigned(((index * 8 + channel * 2) mod 4096) * 16 + 9, 16));
        v(31 downto 16) := std_logic_vector(to_unsigned(((index * 8 + channel * 2 + 1) mod 4096) * 16 + 5, 16));
        return v;
    end function sample;

begin

    -- ----------------------------------------------------------------------------
    -- Independent acquisition and processing clocks
    -- ----------------------------------------------------------------------------
    wr_clk <= not wr_clk after WR_CLK_PERIOD / 2;
    rd_clk <= not rd_clk after RD_CLK_PERIOD / 2;

    -- ----------------------------------------------------------------------------
    -- DUT instance
    -- ----------------------------------------------------------------------------
    dut : entity work.host_tcd_rx_buffer
        generic map (
            SLOT_SAMPLES => SLOT_SAMPLES,
            SLOT_COUNT   => SLOT_COUNT
        )
        port map (
            wr_clk          => wr_clk,
            wr_reset        => reset,
            wr_flush        => wr_flush,
            capture_enable  => capture_enable,
            frame_valid     => frame_valid,
            frame_data      => frame_data,
            sample_tick     => sample_tick,
            dropped_frames  => dropped_frames,
            slot_valid      => slot_valid,
            slot_ready      => slot_ready,
            slot_index      => slot_index,
            slot_tick       => slot_tick,
            slot_gap        => slot_gap,
            release_valid   => release_valid,
            release_slot    => release_slot,
            rd_clk          => rd_clk,
            rd_reset        => reset,
            command_valid   => command_valid,
            command_ready   => command_ready,
            command_slot    => command_slot,
            command_channel => command_channel,
            command_iq12    => command_iq12,
            source_valid    => source_valid,
            source_ready    => source_ready,
            source_data     => source_data,
            source_last     => source_last
        );

    -- ----------------------------------------------------------------------------
    -- Simulation watchdog
    -- ----------------------------------------------------------------------------
    watchdog_proc : process
    begin
        wait for 100 us;
        assert false report "watchdog" severity failure;
    end process watchdog_proc;

    -- ----------------------------------------------------------------------------
    -- Stimulus and output checks
    -- ----------------------------------------------------------------------------
    stimulus_proc : process
        procedure put_frame(index : natural) is
        begin
            wait until falling_edge(wr_clk);
            for c in 0 to 3 loop
                frame_data(32 * c + 31 downto 32 * c) <= sample(index, c);
            end loop;
            frame_valid <= '1';
            wait until rising_edge(wr_clk);
            wait for 1 ns;
        end procedure put_frame;

        procedure stop_frames is
        begin
            wait until falling_edge(wr_clk);
            frame_valid <= '0';
        end procedure stop_frames;

        procedure descriptor(
            constant slot  : in natural;
            constant first : in natural;
            constant gap   : in std_logic
        ) is
        begin
            assert slot_valid = '1' report "missing completed slot" severity failure;
            assert slot_index = slot report "wrong slot index" severity failure;
            assert unsigned(slot_tick) = first report "wrong slot acquisition timestamp" severity failure;
            assert slot_gap = gap report "wrong slot gap flag" severity failure;
            slot_ready <= '1';
            wait until rising_edge(wr_clk);
            wait until falling_edge(wr_clk);
            slot_ready <= '0';
        end procedure descriptor;

        procedure read_channel(
            constant slot     : in natural;
            constant channel  : in natural;
            constant first    : in natural;
            constant packed12 : in boolean
        ) is
            variable expected : std_logic_vector(SLOT_SAMPLES * 32 - 1 downto 0) := (others => '0');
            variable iq       : std_logic_vector(31 downto 0);
            variable words    : natural;
            variable got      : natural;
            variable cycles   : natural;
            variable held     : std_logic_vector(255 downto 0);
            variable stalled  : boolean := false;
        begin
            for i in 0 to SLOT_SAMPLES - 1 loop
                iq := sample(first + i, channel);
                if packed12 then
                    expected(i * 24 + 23 downto i * 24) := iq(31 downto 20) & iq(15 downto 4);
                else
                    expected(i * 32 + 31 downto i * 32) := iq;
                end if;
            end loop;
            if packed12 then
                words := SLOT_SAMPLES * 3 / 32;
            else
                words := SLOT_SAMPLES / 8;
            end if;
            wait until falling_edge(rd_clk);
            command_slot <= slot;
            command_channel <= channel;
            command_valid <= '1';
            if packed12 then
                command_iq12 <= '1';
            else
                command_iq12 <= '0';
            end if;
            loop
                wait until rising_edge(rd_clk);
                exit when command_ready = '1';
            end loop;
            wait until falling_edge(rd_clk);
            command_valid <= '0';
            source_ready <= '0';
            got := 0;
            cycles := 0;
            while got < words loop
                wait until falling_edge(rd_clk);
                if STALL_OUTPUT and cycles mod 7 < 4 then
                    source_ready <= '0';
                else
                    source_ready <= '1';
                end if;
                wait until rising_edge(rd_clk);
                -- Once IQ16 output starts, the registered credit pipeline must
                -- sustain a beat every cycle when downstream never stalls.
                if not STALL_OUTPUT and not packed12 and got > 0 then
                    assert source_valid = '1'
                        report "IQ16 throughput bubble with an always-ready sink"
                        severity failure;
                end if;
                if stalled then
                    assert source_valid = '1' and source_data = held report "output changed under backpressure" severity failure;
                end if;
                stalled := source_valid = '1' and source_ready = '0';
                held := source_data;
                if source_valid = '1' and source_ready = '1' then
                    assert source_data = expected(got * 256 + 255 downto got * 256)
                        report "sample/packing mismatch channel " & integer'image(channel) &
                               " word " & integer'image(got)
                        severity failure;
                    if got = words - 1 then
                        assert source_last = '1' report "missing last" severity failure;
                    else
                        assert source_last = '0' report "early last" severity failure;
                    end if;
                    got := got + 1;
                end if;
                cycles := cycles + 1;
                assert cycles < SLOT_SAMPLES * 4 + 100 report "read timeout" severity failure;
            end loop;
            wait until falling_edge(rd_clk);
            source_ready <= '0';
        end procedure read_channel;
    begin
        wait for 50 ns;
        wait until falling_edge(wr_clk);
        reset <= '0';
        wr_flush <= '0';
        capture_enable <= '1';

        -- Fill both acquisition slots before allowing readout.
        for i in 0 to SLOT_SAMPLES - 1 loop
            put_frame(i);
        end loop;
        stop_frames;
        descriptor(0, 0, '0');
        for i in SLOT_SAMPLES to 2 * SLOT_SAMPLES - 1 loop
            put_frame(i);
        end loop;
        stop_frames;
        descriptor(1, SLOT_SAMPLES, '0');
        -- Both slots are owned by the reader. Incoming frames must not overwrite either.
        for i in 2 * SLOT_SAMPLES to 2 * SLOT_SAMPLES + 7 loop
            put_frame(i);
        end loop;
        stop_frames;
        assert unsigned(dropped_frames) = 8 report "overflow accounting" severity failure;
        assert unsigned(sample_tick) = 2 * SLOT_SAMPLES + 8 report "acquisition counter stopped on overflow" severity failure;

        -- Read IQ16 channels in a different order from acquisition.
        read_channel(0, 2, 0, false);
        read_channel(0, 0, 0, false);
        read_channel(0, 3, 0, false);
        read_channel(0, 1, 0, false);

        -- Release and reuse slot zero, retaining the acquisition gap indication.
        release_slot <= 0;
        release_valid <= '1';
        wait until rising_edge(wr_clk);
        wait until falling_edge(wr_clk);
        release_valid <= '0';
        for i in 2 * SLOT_SAMPLES + 8 to 3 * SLOT_SAMPLES + 7 loop
            put_frame(i);
        end loop;
        stop_frames;
        descriptor(0, 2 * SLOT_SAMPLES + 8, '1');

        -- Read the retained and reused slots using packed IQ12 output.
        read_channel(1, 3, SLOT_SAMPLES, true);
        read_channel(0, 1, 2 * SLOT_SAMPLES + 8, true);

        -- Flush ownership/packing without resetting the TX acquisition timer.
        wait until falling_edge(wr_clk);
        capture_enable <= '0';
        wr_flush <= '1';
        wait for 40 ns;
        assert unsigned(sample_tick) = 3 * SLOT_SAMPLES + 8 report "software flush reset TX time" severity failure;
        wait until falling_edge(wr_clk);
        wr_flush <= '0';
        capture_enable <= '1';
        for i in 3 * SLOT_SAMPLES + 8 to 4 * SLOT_SAMPLES + 7 loop
            put_frame(i);
        end loop;
        stop_frames;
        descriptor(0, 3 * SLOT_SAMPLES + 8, '0');
        read_channel(0, 0, 3 * SLOT_SAMPLES + 8, true);
        report "PASS: IQ16/IQ12, channel mapping, asynchronous clocks, stalls, overflow, wrap and timestamp continuity";
        finish;
    end process stimulus_proc;
end architecture sim;
