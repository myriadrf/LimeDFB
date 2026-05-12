-- ----------------------------------------------------------------------------
-- FILE:          tb_simple_dual_port_ram.vhd
-- DESCRIPTION:   Testbench for simple_dual_port_ram
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

library std;
use std.env.all;

entity tb_simple_dual_port_ram is
end entity;

architecture sim of tb_simple_dual_port_ram is

    constant DATA_WIDTH : positive := 16;
    constant ADDR_WIDTH : positive := 5;
    constant RAM_DEPTH  : positive := 2 ** ADDR_WIDTH;

    constant CLK_PERIOD : time := 10 ns;

    subtype data_t is std_logic_vector(DATA_WIDTH-1 downto 0);
    type mem_t is array (0 to RAM_DEPTH-1) of data_t;

    signal clk : std_logic := '0';

    signal wr_en   : std_logic := '0';
    signal wr_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal wr_data : data_t := (others => '0');

    signal rd_en   : std_logic := '0';
    signal rd_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal rd_data : data_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.simple_dual_port_ram
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            AMD_RAM_STYLE => "block"
        )
        port map (
            wr_clk  => clk,
            wr_en   => wr_en,
            wr_addr => wr_addr,
            wr_data => wr_data,

            rd_clk  => clk,
            rd_en   => rd_en,
            rd_addr => rd_addr,
            rd_data => rd_data
        );

    stim_proc : process

        variable ref_mem : mem_t := (others => (others => '0'));

        function to_data(n : natural) return data_t is
        begin
            return std_logic_vector(to_unsigned(n mod (2 ** DATA_WIDTH), DATA_WIDTH));
        end function;

        procedure check_data(
            constant test_name : in string;
            constant actual    : in data_t;
            constant expected  : in data_t
        ) is
        begin
            assert actual = expected
                report test_name &
                       ": expected 0x" & to_hstring(expected) &
                       ", got 0x" & to_hstring(actual)
                severity failure;
        end procedure;

        procedure write_word(
            constant addr : in natural;
            constant data : in natural
        ) is
        begin
            wr_en   <= '1';
            wr_addr <= to_unsigned(addr, ADDR_WIDTH);
            wr_data <= to_data(data);

            rd_en   <= '0';
            rd_addr <= (others => '0');

            wait until rising_edge(clk);
            wait for 1 ns;

            ref_mem(addr) := to_data(data);

            wr_en <= '0';
        end procedure;

        procedure read_word(
            constant test_name : in string;
            constant addr      : in natural
        ) is
        begin
            wr_en <= '0';

            rd_en   <= '1';
            rd_addr <= to_unsigned(addr, ADDR_WIDTH);

            wait until rising_edge(clk);
            wait for 1 ns;

            check_data(test_name, rd_data, ref_mem(addr));

            rd_en <= '0';
        end procedure;

        procedure write_and_read_different_addr(
            constant test_name : in string;
            constant waddr     : in natural;
            constant wdata     : in natural;
            constant raddr     : in natural
        ) is
        begin
            assert waddr /= raddr
                report "Testbench error: write/read same address avoided for portable behavior"
                severity failure;

            wr_en   <= '1';
            wr_addr <= to_unsigned(waddr, ADDR_WIDTH);
            wr_data <= to_data(wdata);

            rd_en   <= '1';
            rd_addr <= to_unsigned(raddr, ADDR_WIDTH);

            wait until rising_edge(clk);
            wait for 1 ns;

            check_data(test_name, rd_data, ref_mem(raddr));

            ref_mem(waddr) := to_data(wdata);

            wr_en <= '0';
            rd_en <= '0';
        end procedure;

    begin

        report "Starting simple_dual_port_ram self-checking testbench";

        wait for 3 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- Initial write
        ----------------------------------------------------------------
        for i in 0 to RAM_DEPTH-1 loop
            write_word(i, 16#1000# + i);
        end loop;

        ----------------------------------------------------------------
        -- Readback check
        ----------------------------------------------------------------
        for i in 0 to RAM_DEPTH-1 loop
            read_word("initial readback addr " & integer'image(i), i);
        end loop;

        ----------------------------------------------------------------
        -- Simultaneous write and read on different addresses
        ----------------------------------------------------------------
        for i in 0 to RAM_DEPTH-2 loop
            write_and_read_different_addr(
                "simultaneous write/read cycle " & integer'image(i),
                i,
                16#2000# + i,
                i + 1
            );
        end loop;

        ----------------------------------------------------------------
        -- Final readback
        ----------------------------------------------------------------
        for i in 0 to RAM_DEPTH-1 loop
            read_word("final readback addr " & integer'image(i), i);
        end loop;

        report "simple_dual_port_ram self-checking testbench PASSED";

        stop;

    end process;

end architecture;
