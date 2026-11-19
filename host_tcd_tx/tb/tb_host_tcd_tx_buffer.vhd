-- SPDX-License-Identifier: Apache-2.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_host_tcd_tx_buffer is
    generic (TEST_SLOT_SAMPLES : positive := 32; STALL_OUTPUT : boolean := true);
end entity;
architecture test of tb_host_tcd_tx_buffer is
    constant N : positive := TEST_SLOT_SAMPLES;
    signal wc : std_logic := '0'; signal rc : std_logic := '0';
    signal wr,rr : std_logic := '1';
    signal lv,lr,iv,ir,dv,dr,pv,pr,ov,orr,ol,rv,rready : std_logic := '0';
    signal ls,ps,rs : integer range 0 to 1 := 0;
    signal channels : integer range 1 to 4 := 1;
    signal cmap : std_logic_vector(7 downto 0) := x"e4";
    signal packed : std_logic := '0';
    signal mask : std_logic_vector(3 downto 0) := "1111";
    signal din : std_logic_vector(255 downto 0) := (others=>'0');
    signal dout : std_logic_vector(127 downto 0);
    function sample(k,c : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned((65535-k*11-c*137) mod 65536,16)) &
               std_logic_vector(to_unsigned((k*17+c*211) mod 65536,16));
    end function;
begin
    wc <= not wc after 5 ns; rc <= not rc after 3.5 ns;
    dut : entity work.host_tcd_tx_buffer generic map(N,2)
        port map(wc,wr,lv,lr,ls,channels,cmap,packed,iv,ir,din,dv,dr,
                 rc,rr,pv,pr,ps,mask,ov,orr,dout,ol,rv,rready,rs);
    process
        procedure fill(slot,count : integer; mapping : std_logic_vector(7 downto 0); iq : std_logic) is
            variable data : std_logic_vector(N*32-1 downto 0);
            variable s : std_logic_vector(31 downto 0);
            variable bits,phys : integer;
        begin
            wait until falling_edge(wc);
            ls<=slot;channels<=count;cmap<=mapping;packed<=iq;lv<='1';
            loop wait until rising_edge(wc);exit when lr='1';end loop;
            wait until falling_edge(wc);lv<='0';
            bits:=32;if iq='1' then bits:=24;end if;
            for c in 0 to count-1 loop
                phys:=to_integer(unsigned(mapping(2*c+1 downto 2*c)));
                data:=(others=>'0');
                for k in 0 to N-1 loop
                    s:=sample(k,phys);
                    if iq='1' then data(24*k+23 downto 24*k):=s(31 downto 20)&s(15 downto 4);
                    else data(32*k+31 downto 32*k):=s;end if;
                end loop;
                for b in 0 to N*bits/256-1 loop
                    if b mod 5=0 then wait until falling_edge(wc);iv<='0';wait until falling_edge(wc);end if;
                    din<=data(256*b+255 downto 256*b);iv<='1';
                    loop wait until rising_edge(wc);exit when ir='1';end loop;
                    wait until falling_edge(wc);iv<='0';
                end loop;
            end loop;
            loop wait until rising_edge(wc);exit when dv='1';end loop;
            for i in 0 to 5 loop
                wait until rising_edge(wc);
                assert dv='1' and lr='0' and ir='0' report "load escaped before publication" severity failure;
            end loop;
            wait until falling_edge(wc);dr<='1';wait until rising_edge(wc);
            wait until falling_edge(wc);dr<='0';
        end procedure;
        procedure play(slot : integer; selected : std_logic_vector(3 downto 0); iq : std_logic) is
            variable expected : std_logic_vector(127 downto 0);
            variable s : std_logic_vector(31 downto 0);
            variable k,cycle : integer := 0;
            variable held : std_logic_vector(127 downto 0);
            variable held_last,stalled : std_logic := '0';
        begin
            wait until falling_edge(rc);ps<=slot;mask<=selected;pv<='1';orr<='0';
            loop wait until rising_edge(rc);exit when pr='1';end loop;
            wait until falling_edge(rc);pv<='0';
            while k<N loop
                if STALL_OUTPUT and cycle mod 7<3 then orr<='0';else orr<='1';end if;
                wait until rising_edge(rc);
                if stalled='1' then assert ov='1' and dout=held and ol=held_last
                    report "TX output changed during stall" severity failure;end if;
                stalled:='0';
                if ov='1' then
                    if orr='1' then
                        expected:=(others=>'0');
                        for c in 0 to 3 loop
                            if selected(c)='1' then
                                s:=sample(k,c);
                                if iq='1' then s:=s(31 downto 20)&"0000"&s(15 downto 4)&"0000";end if;
                                expected(32*c+31 downto 32*c):=s;
                            end if;
                        end loop;
                        assert dout=expected report "TX IQ/channel/sample mismatch at sample " & integer'image(k) severity failure;
                        if k=N-1 then assert ol='1' report "missing last" severity failure;
                        else assert ol='0' report "early last" severity failure;end if;
                        k:=k+1;
                    else stalled:='1';held:=dout;held_last:=ol;end if;
                end if;
                cycle:=cycle+1;assert cycle<N*10 report "TX playback timeout" severity failure;
                wait until falling_edge(rc);
            end loop;
            for i in 0 to 5 loop
                wait until rising_edge(rc);
                assert rv='1' and rs=slot and pr='0' report "slot release not held" severity failure;
                assert ov='0' report "extra output frame" severity failure;
            end loop;
            wait until falling_edge(rc);rready<='1';wait until rising_edge(rc);
            wait until falling_edge(rc);rready<='0';
        end procedure;
    begin
        wait for 70 ns;wait until falling_edge(wc);wr<='0';wait until falling_edge(rc);rr<='0';
        -- Different slots and formats, then reuse with fewer selected channels.
        fill(0,4,x"e4",'0');fill(1,4,x"72",'1');
        play(0,"1111",'0');play(1,"1111",'1');
        fill(0,2,x"72",'1');play(0,"0101",'1');
        fill(1,1,x"1b",'0');play(1,"1000",'0');
        wait until falling_edge(wc);wr<='1';
        wait until falling_edge(rc);rr<='1';
        wait for 40 ns;
        wait until falling_edge(wc);wr<='0';
        wait until falling_edge(rc);rr<='0';
        fill(0,4,x"e4",'1');play(0,"1111",'1');
        report "PASS: TX IQ16/IQ12, channel mapping, asynchronous clocks, stalls and slot reuse";
        stop;wait;
    end process;
    process begin wait for 2 ms;assert false report "TX test timeout" severity failure;end process;
end architecture;
