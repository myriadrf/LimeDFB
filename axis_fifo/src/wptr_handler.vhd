library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;  -- For unsigned/signed operations if needed, and shift

entity wptr_handler is
    generic (
        PTR_WIDTH : positive := 3 -- Parameter PTR_WIDTH with default 3
    );
    port (
        wclk       : in  std_logic;
        wrst_n     : in  std_logic;
        w_en       : in  std_logic;
        g_rptr_sync : in  std_logic_vector(PTR_WIDTH downto 0);
        b_wptr     : out std_logic_vector(PTR_WIDTH downto 0);
        g_wptr     : out std_logic_vector(PTR_WIDTH downto 0);
        usedw      : out std_logic_vector(PTR_WIDTH downto 0);
        full       : out std_logic
    );
end entity wptr_handler;

architecture behavioral of wptr_handler is

    -- Internal signals - similar to 'reg' declarations in SystemVerilog
    signal b_wptr_next  : std_logic_vector(PTR_WIDTH downto 0);
    signal g_wptr_next  : std_logic_vector(PTR_WIDTH downto 0);
    signal b_rptr_sync  : std_logic_vector(PTR_WIDTH downto 0);
    signal wrap_around  : std_logic; -- Although not directly used in final assign, kept for original intent. Can be removed if confirmed unused.
    signal wfull        : std_logic;
    signal add          : std_logic_vector(0 downto 0);

    -- Function gray2bin - VHDL function equivalent
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

    add(0) <= w_en and not full;
    -- Concurrent assignments - equivalent to 'assign' statements
    b_wptr_next <= std_logic_vector(unsigned(b_wptr) + unsigned(add)); -- Addition needs type conversion
    g_wptr_next <= std_logic_vector(shift_right(unsigned(b_wptr_next), 1) xor unsigned(b_wptr_next)); -- Shift and XOR, type conversion for unsigned
    wfull <= '1' when (g_wptr_next = std_logic_vector(not(unsigned(g_rptr_sync(PTR_WIDTH downto PTR_WIDTH-1))) & unsigned(g_rptr_sync(PTR_WIDTH-2 downto 0)))) else '0';
    usedw <= std_logic_vector(unsigned(b_wptr) - unsigned(b_rptr_sync)); -- Subtraction needs type conversion


    -- Synchronous logic (processes) - equivalent to 'always' blocks
    process (wclk, wrst_n)
    begin
        if wrst_n = '0' then
            b_rptr_sync <= (others => '0'); -- Reset to 0
        elsif rising_edge(wclk) then
            b_rptr_sync <= gray2bin(g_rptr_sync);
        end if;
    end process;

    process (wclk, wrst_n)
    begin
        if wrst_n = '0' then
            b_wptr <= (others => '0');
            g_wptr <= (others => '0');
        elsif rising_edge(wclk) then
            b_wptr <= b_wptr_next;
            g_wptr <= g_wptr_next;
        end if;
    end process;

    process (wclk, wrst_n)
    begin
        if wrst_n = '0' then
            full <= '0';
        elsif rising_edge(wclk) then
            full <= wfull;
        end if;
    end process;

end architecture behavioral;
