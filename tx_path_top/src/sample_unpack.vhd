-- ----------------------------------------------------------------------------
-- FILE:   sample_unpack.vhd
-- DESCRIPTION:  Reads the datastream from pct2data_buf_wr, assumes that
--               incoming data is interleaved.
--               Checks CH_EN and SAMPLE_WIDTH only between packets.
-- DATE:  June 25, 2024
-- AUTHOR(s):  Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- Notes: If invalid CH_EN and/or SAMPLE_WIDTH values are provided,
--        this module will not start reading data and stall.
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity SAMPLE_UNPACK is
   port (
      AXIS_ACLK      : in    std_logic;
      AXIS_ARESET_N  : in    std_logic;
      RESET_N        : in    std_logic;

      S_AXIS_TDATA   : in    std_logic_vector(127 downto 0);
      S_AXIS_TREADY  : out   std_logic;
      S_AXIS_TVALID  : in    std_logic;
      S_AXIS_TLAST   : in    std_logic;

      M_AXIS_TDATA   : out   std_logic_vector(63 downto 0);
      M_AXIS_TREADY  : in    std_logic;
      M_AXIS_TVALID  : out   std_logic;

      CH_EN          : in    std_logic_vector(1 downto 0);
      SAMPLE_WIDTH   : in    std_logic_vector(1 downto 0)
   );
end entity SAMPLE_UNPACK;

architecture RTL of SAMPLE_UNPACK is

   type T_STATE is (WAIT_PACKET, SISO_12BIT, MIMO_12BIT, SISO_16BIT, MIMO_16BIT);

   signal state          : T_STATE;

   signal data_counter   : integer range 0 to 15;
   signal tdata_buffer   : std_logic_vector(127 downto 0);
   signal offset         : integer;
   signal int_rst_n      : std_logic;

begin

   int_rst_n <= RESET_N and AXIS_ARESET_N;

   TDATA_BUF_PROC : process (AXIS_ACLK, int_rst_n) is
   begin

      if (int_rst_n = '0') then
         tdata_buffer <= (others => '0');
      elsif rising_edge(AXIS_ACLK) then
         if (S_AXIS_TREADY = '1' and S_AXIS_TVALID = '1') then
            tdata_buffer <= S_AXIS_TDATA;
         end if;
      end if;

   end process TDATA_BUF_PROC;

   FSM_PROC : process (AXIS_ACLK, int_rst_n) is
   begin

      if (int_rst_n = '0') then
         state <= WAIT_PACKET;
      elsif rising_edge(AXIS_ACLK) then
         -- Default  values
         S_AXIS_TREADY <= '0';
         M_AXIS_TVALID <= '0';

         case state is

            when WAIT_PACKET =>
               data_counter <= 0;

               if (S_AXIS_TVALID = '1') then
                  if (CH_EN = "01") then
                     offset <= 32;                                                                                                                   -- A Channel needs to be at top of M_AXIS_TDATA
                  elsif (CH_EN = "10") then
                     offset <= 0;                                                                                                                    -- B channel needs to be at the bottom of M_AXIS_TDATA
                  end if;

                  if (CH_EN = "11") then                                                                                                             -- A and B MIMO
                     if (SAMPLE_WIDTH = "10") then                                                                                                   -- 12 Bits
                        state <= MIMO_12BIT;                                                                                                         -- go to MIMO 12 Bits state
                     elsif (SAMPLE_WIDTH = "00") then                                                                                                -- 16 Bits
                        state <= MIMO_16BIT;                                                                                                         -- go to MIMO 16 Bits state
                     end if;
                  elsif (CH_EN = "01" or CH_EN = "10") then                                                                                          -- A SISO or B SISO
                     if (SAMPLE_WIDTH = "10") then                                                                                                   -- 12 Bits
                        state <= SISO_12BIT;                                                                                                         -- go to SISO 12 bits state
                     elsif (SAMPLE_WIDTH = "00") then                                                                                                -- 16 Bits
                        state <= SISO_16BIT;                                                                                                         -- go to SISO 16 bits state
                     end if;
                  end if;
               end if;

            -- Actions for WAIT_PACKET state
            when SISO_12BIT =>

               case data_counter is

                  when 0 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(11 downto  0) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(23 downto 12) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 1 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(35 downto 24) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(47 downto 36) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 2 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(59 downto 48) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(71 downto 60) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 3)
                           -- new data will only be present two cycles from now (data_counter = 4)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 3 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(83 downto 72) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(95 downto 84) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 4 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= tdata_buffer(107 downto  96) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= tdata_buffer(119 downto 108) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 5 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(3   downto   0) & tdata_buffer(127 downto 120) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(15  downto   4) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 6 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(27 downto 16) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(39 downto 28) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 7 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(51 downto 40) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(63 downto 52) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 8 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(75  downto  64) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(87  downto  76) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 9)
                           -- new data will only be present two cycles from now (data_counter = 10)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 9 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(99  downto  88) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(111 downto 100) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 10 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= tdata_buffer(123 downto 112) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(7   downto   0) & tdata_buffer(127 downto 124) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 11 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(19  downto   8) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(31  downto  20) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 12 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(43 downto 32) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(55 downto 44) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 13 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(67 downto 56) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(79 downto 68) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 14 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(91  downto  80) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(103 downto  92) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 15)
                           -- new data will only be present two cycles from now (data_counter = 0)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 15 =>
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(115 downto 104) & "0000";
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(127 downto 116) & "0000";
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           if (S_AXIS_TLAST = '1') then                                                                                              -- This was the last datacycle
                              data_counter <= 0;
                              state        <= WAIT_PACKET;
                           else
                              data_counter <= 0;
                           end if;
                        end if;
                     end if;

                  when others =>
                     -- This should not happen, if it does - go to reset state
                     state <= WAIT_PACKET;

               end case;

            -- Actions for SISO_12BIT state
            when MIMO_12BIT =>

               case data_counter is

                  when 0 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(11 downto  0) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(23 downto 12) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(35 downto 24) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(47 downto 36) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 1)
                           -- new data will only be present two cycles from now (data_counter = 2)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 1 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(59 downto 48) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(71 downto 60) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(83 downto 72) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(95 downto 84) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 2 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= tdata_buffer(107 downto  96) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= tdata_buffer(119 downto 108) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(3   downto   0) & tdata_buffer(127 downto 120) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(15  downto   4) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 3 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(27 downto 16) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(39 downto 28) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(51 downto 40) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(63 downto 52) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 4)
                           -- new data will only be present two cycles from now (data_counter = 5)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 4 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(75  downto  64) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(87  downto  76) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(99  downto  88) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(111 downto 100) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 5 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= tdata_buffer(123 downto 112) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(7   downto   0) & tdata_buffer(127 downto 124) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(19  downto   8) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(31  downto  20) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 6 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(43 downto 32) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(55 downto 44) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(67 downto 56) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(79 downto 68) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 7)
                           -- new data will only be present two cycles from now (data_counter = 0)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 7 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(91  downto  80) & "0000";
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(103 downto  92) & "0000";
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(115 downto 104) & "0000";
                        M_AXIS_TDATA(15 downto 0 ) <= S_AXIS_TDATA(127 downto 116) & "0000";
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           if (S_AXIS_TLAST = '1') then                                                                                              -- This was the last datacycle
                              data_counter <= 0;
                              state        <= WAIT_PACKET;
                           else
                              data_counter <= 0;
                           end if;
                        end if;
                     end if;

                  when others =>
                     -- This should not happen, if it does - go to reset state
                     state <= WAIT_PACKET;

               end case;

            -- Actions for MIMO_12BIT state
            when SISO_16BIT =>

               case data_counter is

                  when 0 | 1 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";                                                                      -- AI
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";                                                                      -- AQ
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(15 + (32 * data_counter) downto 0 + (32 * data_counter));       -- BI
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(31 + (32 * data_counter) downto 16 + (32 * data_counter));      -- BQ
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           data_counter <= data_counter + 1;
                        end if;
                     end if;

                  when 2 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";                                                                      -- AI
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";                                                                      -- AQ
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(15 + (32 * data_counter) downto 0 + (32 * data_counter));       -- BI
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(31 + (32 * data_counter) downto 16 + (32 * data_counter));      -- BQ
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 3)
                           -- new data will only be present two cycles from now (data_counter = 0)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 3 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 - offset downto 48 - offset) <= 16x"0";                                                                      -- AI
                        M_AXIS_TDATA(47 - offset downto 32 - offset) <= 16x"0";                                                                      -- AQ
                        M_AXIS_TDATA(31 + offset downto 16 + offset) <= S_AXIS_TDATA(15 + (32 * data_counter) downto 0 + (32 * data_counter));       -- BI
                        M_AXIS_TDATA(15 + offset downto 0  + offset) <= S_AXIS_TDATA(31 + (32 * data_counter) downto 16 + (32 * data_counter));      -- BQ
                        M_AXIS_TVALID                                <= '1';
                        if (M_AXIS_TREADY = '1') then
                           if (S_AXIS_TLAST = '1') then                                                                                              -- This was the last datacycle
                              data_counter <= 0;
                              state        <= WAIT_PACKET;
                           else
                              data_counter <= 0;
                           end if;
                        end if;
                     end if;

                  when others =>
                     -- This should not happen, if it does - go to reset state
                     state <= WAIT_PACKET;

               end case;

            -- Actions for SISO_16BIT state
            when MIMO_16BIT =>

               case data_counter is

                  when 0 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(15 downto 0);                                                                     -- AI
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(31 downto 16);                                                                    -- AQ
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(47 downto 32);                                                                    -- BI
                        M_AXIS_TDATA(15 downto 0)  <= S_AXIS_TDATA(63 downto 48);                                                                    -- BQ
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           -- this will only be read next cycle (data_counter = 1)
                           -- new data will only be present two cycles from now (data_counter = 0)
                           S_AXIS_TREADY <= '1';
                           data_counter  <= data_counter + 1;
                        end if;
                     end if;

                  when 1 =>
                     -- Do nothing if input data is not valid for any reason
                     if (S_AXIS_TVALID = '1') then
                        M_AXIS_TDATA(63 downto 48) <= S_AXIS_TDATA(79 downto 64);                                                                    -- AI
                        M_AXIS_TDATA(47 downto 32) <= S_AXIS_TDATA(95 downto 80);                                                                    -- AQ
                        M_AXIS_TDATA(31 downto 16) <= S_AXIS_TDATA(111 downto 96);                                                                   -- BI
                        M_AXIS_TDATA(15 downto 0)  <= S_AXIS_TDATA(127 downto 112);                                                                  -- BQ
                        M_AXIS_TVALID              <= '1';
                        if (M_AXIS_TREADY = '1') then
                           if (S_AXIS_TLAST = '1') then                                                                                              -- This was the last datacycle
                              state        <= WAIT_PACKET;
                              data_counter <= 0;
                           else
                              data_counter <= 0;
                           end if;
                        end if;
                     end if;

                  when others =>
                     -- This should not happen, if it does - go to reset state
                     state <= WAIT_PACKET;

               end case;

            -- Actions for MIMO_16BIT state
            when others =>
               state <= WAIT_PACKET;                                                                                                                 -- Default case

         end case;

      end if;

   end process FSM_PROC;

-- Implementation of the architecture goes here

end architecture RTL;
