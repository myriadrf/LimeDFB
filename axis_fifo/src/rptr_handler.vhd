library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rptr_handler is
    generic (
        PTR_WIDTH : positive := 3
    );
    port (
        rclk       : in  std_logic;
        rrst_n     : in  std_logic;
        r_en       : in  std_logic;
        g_wptr_sync : in  std_logic_vector(PTR_WIDTH downto 0);
        b_rptr     : out std_logic_vector(PTR_WIDTH downto 0);
        g_rptr     : out std_logic_vector(PTR_WIDTH downto 0);
        usedw      : out std_logic_vector(PTR_WIDTH downto 0);
        empty      : out std_logic
    );
end entity rptr_handler;

architecture behavioral of rptr_handler is

    -- Internal signals
    signal b_rptr_next  : std_logic_vector(PTR_WIDTH downto 0);
    signal g_rptr_next  : std_logic_vector(PTR_WIDTH downto 0);
    signal b_wptr_sync  : std_logic_vector(PTR_WIDTH downto 0);
    signal rempty       : std_logic;
    signal add          : std_logic_vector(0 downto 0);

    -- Function gray2bin
    function gray2bin (gray : std_logic_vector(PTR_WIDTH downto 0)) return std_logic_vector is
        variable bin : std_logic_vector(PTR_WIDTH downto 0);
    begin
        bin(PTR_WIDTH) := gray(PTR_WIDTH);
        for i in PTR_WIDTH-1 downto 0 loop
            bin(i) := bin(i+1) xor gray(i);
        end loop;
        return bin;
    end function gray2bin;

begin

    -- Concurrent assignments
    add(0) <= r_en and not empty;
    b_rptr_next <= std_logic_vector(unsigned(b_rptr) + unsigned(add));
    g_rptr_next <= std_logic_vector(shift_right(unsigned(b_rptr_next), 1) xor unsigned(b_rptr_next));
    rempty <= '1' when (g_wptr_sync = g_rptr_next) else '0';
    usedw <= std_logic_vector(unsigned(b_wptr_sync) - unsigned(b_rptr));


    -- Synchronous logic (processes)
    process (rclk, rrst_n)
    begin
        if rrst_n = '0' then
            b_wptr_sync <= (others => '0');
        elsif rising_edge(rclk) then
            b_wptr_sync <= gray2bin(g_wptr_sync);
        end if;
    end process;

    process (rclk, rrst_n)
    begin
        if rrst_n = '0' then
            b_rptr <= (others => '0');
            g_rptr <= (others => '0');
        elsif rising_edge(rclk) then
            b_rptr <= b_rptr_next;
            g_rptr <= g_rptr_next;
        end if;
    end process;

    process (rclk, rrst_n)
    begin
        if rrst_n = '0' then
            empty <= '1';  -- Note: Initial value is '1' in reset for empty
        elsif rising_edge(rclk) then
            empty <= rempty;
        end if;
    end process;

end architecture behavioral;
