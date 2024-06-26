-- ----------------------------------------------------------------------------
-- FILE:   tx_top_pkg.vhd
-- DESCRIPTION:  Package of types and procedures used by tx_top modules and testbench.
-- DATE:  June 25, 2024
-- AUTHOR(s):  Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

package tx_top_pkg is

   type T_S_AXIS_IN is record
      ARESET_N :    std_logic;
      ACLK     :    std_logic;
      TREADY   :    std_logic;
   end record T_S_AXIS_IN;

   type T_S_AXIS_OUT is record
      TVALID :    std_logic;
      TDATA  :    std_logic_vector(127 downto 0);
      TLAST  :    std_logic;
   end record T_S_AXIS_OUT;

   type T_S_AXIS is record
      ARESET_N :    std_logic;
      ACLK     :    std_logic;
      TREADY   :    std_logic;
      TVALID   :    std_logic;
      TDATA    :    std_logic_vector(127 downto 0);
      TLAST    :    std_logic;
   end record T_S_AXIS;

   type T_S_AXIS_TDATA_ARRAY is array (natural range <>) of  std_logic_vector(127 downto 0);

   type T_INTEGER_ARRAY is array (natural range <>) of integer;

   -- arbitrary large size, because arrays must be constrained

   type T_DATAARRAY is array(65535 downto 0) of std_logic_vector(15 downto 0);

   procedure p_send_axi_data (
      data                 : std_logic_vector(127 downto 0);
      signal interface_in  : in T_S_AXIS_IN;
      signal interface_out : out T_S_AXIS_OUT
   );

   procedure p_send_data_packet (
      signal interface_in  : in T_S_AXIS_IN;
      signal interface_out : out T_S_AXIS_OUT;
      len                  : integer;
      data_start           : integer;
      timestamp            : std_logic_vector(63 downto 0);
      en_sync              : std_logic
   );

   procedure p_send_data_packet_arr (
      signal interface_in  : in T_S_AXIS_IN;
      signal interface_out : out T_S_AXIS_OUT;
      data_array           : T_S_AXIS_TDATA_ARRAY;
      timestamp            : std_logic_vector(63 downto 0);
      en_sync              : std_logic
   );

   procedure p_test_16bit_data (
      signal interface_in     : in T_S_AXIS_IN;
      signal interface_out    : out T_S_AXIS_OUT;
      signal ai_data_arr      : in T_DATAARRAY;
      signal aq_data_arr      : in T_DATAARRAY;
      signal bi_data_arr      : in T_DATAARRAY;
      signal bq_data_arr      : in T_DATAARRAY;
      signal data_counter     : in integer;
      signal data_counter_rst : out std_logic;
      signal ch_en            : out std_logic_vector(1 downto 0);
      signal sample_width     : out std_logic_vector(1 downto 0);
      num_packets             : in integer;
      packetlen               : in integer
   );

   procedure p_test_12bit_data (
      signal interface_in     : in T_S_AXIS_IN;
      signal interface_out    : out T_S_AXIS_OUT;
      signal ai_data_arr      : in T_DATAARRAY;
      signal aq_data_arr      : in T_DATAARRAY;
      signal bi_data_arr      : in T_DATAARRAY;
      signal bq_data_arr      : in T_DATAARRAY;
      signal data_counter     : in integer;
      signal data_counter_rst : out std_logic;
      signal ch_en            : out std_logic_vector(1 downto 0);
      signal sample_width     : out std_logic_vector(1 downto 0);
      num_packets             : in integer;
      packetlen               : in integer
   );

   procedure p_test_sync (
      signal interface_in     : in T_S_AXIS_IN;
      signal interface_out    : out T_S_AXIS_OUT;
      signal data_counter     : in integer;
      signal data_counter_rst : out std_logic;
      signal ch_en            : out std_logic_vector(1 downto 0);
      signal sample_width     : out std_logic_vector(1 downto 0);
      signal rx_sample_nr     : in std_logic_vector(63 downto 0);
      signal pct_loss_cnt     : in integer;
      signal PCT_SYNC_DIS     : out std_logic;
      num_packets             : in integer;
      packetlen               : in integer
   );

   procedure skip_clocks (
      signal clk : in std_logic;
      num        : integer
   );

   function create_array_mimo_16bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY;

   function create_array_siso_16bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY;

   function slice_conversion (vector : std_logic_vector; top_index : positive; bot_index : integer) return std_logic_vector;

   function create_array_mimo_12bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY;

   function create_array_siso_12bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY;

   function create_array_integer (size : positive; start_val : integer) return T_INTEGER_ARRAY;

end package tx_top_pkg;

package body tx_top_pkg is

   procedure p_send_axi_data (
      data                 : std_logic_vector(127 downto 0);
      signal interface_in  : in T_S_AXIS_IN;
      signal interface_out : out T_S_AXIS_OUT
   ) is

   begin

      assert interface_in.ARESET_N = '1'
         report "Attempted to send AXI data when peripheral is in reset"
         severity failure;

      interface_out.TVALID <= '1';
      interface_out.TDATA  <= data;

      -- The wait time is arbitrary, this is here to avoid race conditions
      -- Where the tb checks values before other modules update them
      wait for 1 ps;

      if (interface_in.TREADY /= '1') then
         while true loop
            wait until rising_edge(interface_in.ACLK);
            -- The wait time is arbitrary, this is here to avoid race conditions
            -- Where the tb checks values before other modules update them
            wait for 1 ps;
            if (interface_in.TREADY = '1') then
               exit;
            end if;
         end loop;
      end if;

      wait until rising_edge(interface_in.ACLK);

      interface_out.TVALID <= '0';
      interface_out.TDATA  <= (others => '0');

   end procedure;

   procedure p_send_data_packet (
      signal interface_in  : in T_S_AXIS_IN;
      signal interface_out : out T_S_AXIS_OUT;
      len                  : integer;
      data_start           : integer;
      timestamp            : std_logic_vector(63 downto 0);
      en_sync              : std_logic
   ) is

      variable counter        : integer;
      variable counter_vector : std_logic_vector(127 downto 0);
      variable header_mod     : std_logic_vector(127 downto 0);

   begin

      interface_out.TLAST <= '0';

      -- Add packet length information to header
      header_mod                := (others => '0');
      header_mod(4)             := not en_sync;
      header_mod(127 downto 64) := timestamp;
      header_mod(23 downto 8)   := std_logic_vector(to_unsigned(len * 16, 16));

      -- Send Header
      p_send_axi_data(header_mod, interface_in, interface_out);
      -- Send Data
      counter := data_start;

      data_send : for k in 0 to len - 1 loop

         if (k = len - 1) then -- Make the last word unique
            p_send_axi_data(128x"ff00ff00ff00ff00ff00ff00ff00ff00", interface_in, interface_out);
         else
            counter_vector := std_logic_vector(to_unsigned(counter, 128));
            p_send_axi_data(counter_vector, interface_in, interface_out);
            counter        := counter + 1;
         end if;

      end loop;

   end procedure;

   -- The function assumes that the array is structured in such a way that
   -- the zeroth quarter of the array contains data for AI channel
   -- first quarter for AQ channel
   -- second quarter for BI channel
   -- third quarter for BQ channel

   function create_array_mimo_16bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY is
      -- Single 128bit cycle contains 8 16bit values
      variable size_in : integer := input_array'length;
      variable size : integer    := input_array'length / 8;
      variable q1point : integer := size_in / 4;
      variable q2point : integer := size_in / 2;
      variable q3point : integer := size_in / 4 + size_in / 2;
      variable result : T_S_AXIS_TDATA_ARRAY(size - 1 downto 0);
      variable counter : integer := 0;
   begin

      assert (size_in mod 8) = 0
         report "16Bit packet sample number must be divisible by 8"
         severity failure;

      for i in 0 to size - 1 loop
         result(i)(15  downto   0) := std_logic_vector(to_unsigned(input_array(counter), 16));            -- AI
         result(i)(31  downto  16) := std_logic_vector(to_unsigned(input_array(counter + q1point), 16));  -- AQ
         result(i)(47  downto  32) := std_logic_vector(to_unsigned(input_array(counter + q2point), 16));  -- BI
         result(i)(63  downto  48) := std_logic_vector(to_unsigned(input_array(counter + q3point), 16));  -- BQ
         counter                   := counter + 1;
         result(i)(79  downto  64) := std_logic_vector(to_unsigned(input_array(counter), 16));            -- AI
         result(i)(95  downto  80) := std_logic_vector(to_unsigned(input_array(counter  + q1point), 16)); -- AQ
         result(i)(111 downto  96) := std_logic_vector(to_unsigned(input_array(counter  + q2point), 16)); -- BI
         result(i)(127 downto 112) := std_logic_vector(to_unsigned(input_array(counter  + q3point), 16)); -- BQ
         counter                   := counter + 1;
      end loop;
      return result;
   end function;

   -- The function assumes that the array is structured in such a way that
   -- the first half of the array contains data for I channel
   -- and the second half for Q

   function create_array_siso_16bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY is
      -- Single 128bit cycle contains 8 16bit values
      variable size_in   : integer := input_array'length;
      variable size      : integer := input_array'length / 8;
      variable halfpoint : integer := size_in / 2;
      variable result    : T_S_AXIS_TDATA_ARRAY(size - 1 downto 0);
      variable counter   : integer := 0;
   begin

      assert (size_in mod 8) = 0
         report "16Bit packet sample number must be divisible by 8"
         severity failure;

      for i in 0 to size - 1 loop
         result(i)(15  downto   0) := std_logic_vector(to_unsigned(input_array(counter), 16));              -- I
         result(i)(31  downto  16) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 16));  -- Q
         counter                   := counter + 1;
         result(i)(47  downto  32) := std_logic_vector(to_unsigned(input_array(counter), 16));              -- I
         result(i)(63  downto  48) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 16));  -- Q
         counter                   := counter + 1;
         result(i)(79  downto  64) := std_logic_vector(to_unsigned(input_array(counter), 16));              -- I
         result(i)(95  downto  80) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 16));  -- Q
         counter                   := counter + 1;
         result(i)(111 downto  96) := std_logic_vector(to_unsigned(input_array(counter), 16));              -- I
         result(i)(127 downto 112) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 16));  -- Q
         counter                   := counter + 1;
      end loop;
      return result;
   end function;

   function slice_conversion (vector : std_logic_vector; top_index : positive; bot_index : integer) return std_logic_vector is
      variable result : std_logic_vector(top_index - bot_index downto 0);
      variable intermediate_vector : std_logic_vector(vector'left downto 0);
   begin
      intermediate_vector := vector;
      result              := intermediate_vector(top_index downto bot_index);
      return result;
   end function;

   function create_array_mimo_12bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY is

      -- Single 128bit cycle contains 8 16bit values
      variable size_in   : integer := input_array'length;
      variable numloops  : integer := input_array'length / 32;
      variable q1point   : integer := size_in / 4;
      variable q2point   : integer := size_in / 2;
      variable q3point   : integer := size_in / 4 + size_in / 2;
      variable result    : T_S_AXIS_TDATA_ARRAY((numloops * 3) - 1 downto 0);
      variable counter   : integer := 0;
      variable j         : integer := 0;
   begin

      assert (size_in mod 32) = 0
         report "12Bit sample number must be divisible by 32"
         severity failure;

      for i in 0 to (numloops) - 1 loop
         result(j + 0)(11  downto   0) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 0)(23  downto  12) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 0)(35  downto  24) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 0)(47  downto  36) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 0)(59  downto  48) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 0)(71  downto  60) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 0)(83  downto  72) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 0)(95  downto  84) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 0)(107 downto  96) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 0)(119 downto 108) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 0)(127 downto 120) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter + q2point), 12)), 7, 0);  -- BI
         result(j + 1)(3   downto   0) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter + q2point), 12)), 11, 8); -- BI
         result(j + 1)(15  downto   4) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 1)(27  downto  16) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 1)(39  downto  28) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 1)(51  downto  40) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 1)(63  downto  52) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 1)(75  downto  64) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 1)(87  downto  76) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 1)(99  downto  88) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 1)(111 downto 100) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 1)(123 downto 112) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 1)(127 downto 124) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter + q1point), 12)), 3, 0);  -- AQ
         result(j + 2)(7   downto   0) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter + q1point), 12)), 11, 4); -- AQ
         result(j + 2)(19  downto   8) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 2)(31  downto  20) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 2)(43  downto  32) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 2)(55  downto  44) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 2)(67  downto  56) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 2)(79  downto  68) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         result(j + 2)(91  downto  80) := std_logic_vector(to_unsigned(input_array(counter), 12));           -- AI
         result(j + 2)(103 downto  92) := std_logic_vector(to_unsigned(input_array(counter + q1point), 12)); -- AQ
         result(j + 2)(115 downto 104) := std_logic_vector(to_unsigned(input_array(counter + q2point), 12)); -- BI
         result(j + 2)(127 downto 116) := std_logic_vector(to_unsigned(input_array(counter + q3point), 12)); -- BQ
         counter                       := counter + 1;
         j                             := j + 3;
      end loop;
      return result;
   end function;

   function create_array_siso_12bit (input_array : T_INTEGER_ARRAY) return T_S_AXIS_TDATA_ARRAY is
      -- Single 128bit cycle contains 8 16bit values
      variable size_in   : integer := input_array'length;
      variable numloops  : integer := input_array'length / 32;
      variable halfpoint : integer := size_in / 2;
      variable result    : T_S_AXIS_TDATA_ARRAY((numloops * 3) - 1 downto 0);
      variable counter   : integer := 0;
      variable j         : integer := 0;
   begin

      assert (size_in mod 32) = 0
         report "12Bit sample number must be divisible by 32"
         severity failure;

      for i in 0 to (numloops) - 1 loop
         result(j + 0)(11  downto   0) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 0)(23  downto  12) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 0)(35  downto  24) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 0)(47  downto  36) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 0)(59  downto  48) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 0)(71  downto  60) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 0)(83  downto  72) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 0)(95  downto  84) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 0)(107 downto  96) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 0)(119 downto 108) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 0)(127 downto 120) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter), 12)), 7, 0);  -- I
         result(j + 1)(3   downto   0) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter), 12)), 11, 8); -- I
         result(j + 1)(15  downto   4) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 1)(27  downto  16) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 1)(39  downto  28) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 1)(51  downto  40) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 1)(63  downto  52) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 1)(75  downto  64) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 1)(87  downto  76) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 1)(99  downto  88) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 1)(111 downto 100) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 1)(123 downto 112) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 1)(127 downto 124) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12)), 3, 0);  -- Q
         result(j + 2)(7   downto   0) := slice_conversion(std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12)), 11, 4); -- Q
         counter                       := counter + 1;
         result(j + 2)(19  downto   8) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 2)(31  downto  20) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 2)(43  downto  32) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 2)(55  downto  44) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 2)(67  downto  56) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 2)(79  downto  68) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 2)(91  downto  80) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 2)(103 downto  92) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         result(j + 2)(115 downto 104) := std_logic_vector(to_unsigned(input_array(counter), 12));              -- I
         result(j + 2)(127 downto 116) := std_logic_vector(to_unsigned(input_array(counter + halfpoint), 12));  -- Q
         counter                       := counter + 1;
         j                             := j + 3;
      end loop;
      return result;
   end function;

   procedure p_send_data_packet_arr (
      signal interface_in  : in T_S_AXIS_IN;
      signal interface_out : out T_S_AXIS_OUT;
      data_array           : T_S_AXIS_TDATA_ARRAY;
      timestamp            : std_logic_vector(63 downto 0);
      en_sync              : std_logic
   ) is

      variable counter        : integer;
      variable counter_vector : std_logic_vector(127 downto 0);
      variable header_mod     : std_logic_vector(127 downto 0);
      variable len            : integer;

   begin

      len := data_array'left + 1;

      interface_out.TLAST <= '0';

      -- Add packet length information to header
      header_mod                := (others => '0');
      header_mod(4)             := not en_sync;
      header_mod(127 downto 64) := timestamp;
      header_mod(23 downto 8)   := std_logic_vector(to_unsigned(len * 16, 16));

      -- Send Header
      p_send_axi_data(header_mod, interface_in, interface_out);
      -- Send Data

      data_send : for k in 0 to len - 1 loop

         p_send_axi_data(data_array(k), interface_in, interface_out);

      end loop;

   end procedure;

   ------------------------------------------------------------------------------
   ---- Procedure to check 16 bit data modes in SISO and MIMO
   ------------------------------------------------------------------------------

   procedure p_test_16bit_data (
      signal interface_in     : in T_S_AXIS_IN;
      signal interface_out    : out T_S_AXIS_OUT;
      signal ai_data_arr      : in T_DATAARRAY;
      signal aq_data_arr      : in T_DATAARRAY;
      signal bi_data_arr      : in T_DATAARRAY;
      signal bq_data_arr      : in T_DATAARRAY;
      signal data_counter     : in integer;
      signal data_counter_rst : out std_logic;
      signal ch_en            : out std_logic_vector(1 downto 0);
      signal sample_width     : out std_logic_vector(1 downto 0);
      num_packets             : in integer;
      packetlen               : in integer
   ) is
      -- variable target_data_counter : integer;
      variable target_data_counter_sisoa : integer;
      variable target_data_counter_sisob : integer;
      variable target_data_counter_mimo : integer;
      variable packet_samples      : integer := packetlen * 8;
      variable siso_cycles         : integer := packet_samples / 2;
      variable mimo_cycles         : integer := packet_samples / 4;
      variable test_samples        : integer := packet_samples * num_packets;
      variable int_array           : T_INTEGER_ARRAY(packet_samples - 1 downto 0);
      variable data_array_siso     : T_S_AXIS_TDATA_ARRAY(packetlen - 1 downto 0);
      variable data_array_mimo     : T_S_AXIS_TDATA_ARRAY(packetlen - 1 downto 0);
      variable j                   : integer;
      -- variable placeholder         : integer;
      variable expected_value      : integer;
      variable actual_value        : integer;
   begin

      -- generate data
      int_array       := create_array_integer(packet_samples, 0);
      data_array_siso := create_array_siso_16bit(int_array);
      data_array_mimo := create_array_mimo_16bit(int_array);
      -- siso outputs 2 samples per cycle, so we need 2x less cycles than samples
      -- mimo outputs 4 samples per cycle, so we need 4x less cycles than samples
      target_data_counter_sisoa := test_samples / 2;
      target_data_counter_sisob := test_samples / 2 + test_samples / 2;
      target_data_counter_mimo  := test_samples / 2 + test_samples / 2 + test_samples / 4;
      -- reset counter
      data_counter_rst <= '1';
      skip_clocks(interface_in.ACLK, 10);
      data_counter_rst <= '0';
      -- start procedure
      -- SISO A
      ch_en        <= "01";
      sample_width <= "00";
      send_sisoa : for i in 0 to num_packets - 1 loop
         p_send_data_packet_arr(interface_in, interface_out, data_array_siso, 64x"0", '0');
      end loop;
      -- wait for sisoA data to arrive before changing ch_en/sample_width
      if (data_counter < target_data_counter_sisoa) then
         wait until data_counter = target_data_counter_sisoa;
      end if;

      -- SISO B
      ch_en        <= "10";
      sample_width <= "00";
      send_sisob : for i in 0 to num_packets - 1 loop
         p_send_data_packet_arr(interface_in, interface_out, data_array_siso, 64x"0", '0');
      end loop;
      -- wait for sisoA data to arrive before changing ch_en/sample_width
      if (data_counter < target_data_counter_sisob) then
         wait until data_counter = target_data_counter_sisob;
      end if;

      -- MIMO
      ch_en        <= "11";
      sample_width <= "00";
      send_mimo : for i in 0 to num_packets - 1 loop
         p_send_data_packet_arr(interface_in, interface_out, data_array_mimo, 64x"0", '0');
      end loop;
      -- wait for sisoA data to arrive before changing ch_en/sample_width
      if (data_counter < target_data_counter_mimo) then
         wait until data_counter = target_data_counter_mimo;
      end if;

      -- loop through and check results
      ------------------------------------------
      -- CHECK SISO A DATA
      ------------------------------------------
      check_siso_a : for i in 0 to target_data_counter_sisoa - 1 loop
         actual_value   := to_integer(unsigned(ai_data_arr(i)));
         expected_value := int_array(i mod siso_cycles);
         assert actual_value = expected_value
            report "SISO AI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(aq_data_arr(i)));
         expected_value := int_array((i mod siso_cycles) + int_array'length / 2);
         assert actual_value = expected_value
            report "SISO AQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value := to_integer(unsigned(bi_data_arr(i)));
         assert actual_value = 0
            report "SISO BI value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

         actual_value := to_integer(unsigned(bq_data_arr(i)));
         assert actual_value = 0
            report "SISO BQ value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

      end loop;
      ------------------------------------------
      -- CHECK SISO B DATA
      ------------------------------------------
      check_siso_b : for i in target_data_counter_sisoa to target_data_counter_sisob - 1 loop
         actual_value := to_integer(unsigned(ai_data_arr(i)));
         assert actual_value = 0
            report "SISO AI value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

         actual_value := to_integer(unsigned(aq_data_arr(i)));
         assert actual_value = 0
            report "SISO AQ value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

         actual_value   := to_integer(unsigned(bi_data_arr(i)));
         expected_value := int_array(i mod siso_cycles); -- mod siso_cycle chould take care of siso A offset as well
         assert actual_value = expected_value
            report "SISO BI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(bq_data_arr(i)));
         expected_value := int_array((i mod siso_cycles) + int_array'length / 2); -- mod siso_cycle chould take care of siso A offset as well
         assert actual_value = expected_value
            report "SISO BQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;
      end loop;
      ------------------------------------------
      -- CHECK MIMO DATA
      ------------------------------------------
      check_mimo : for i in target_data_counter_sisob to target_data_counter_mimo - 1 loop

         actual_value   := to_integer(unsigned(ai_data_arr(i)));
         expected_value := int_array(i mod mimo_cycles);
         assert actual_value = expected_value
            report "MIMO AI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(aq_data_arr(i)));
         expected_value := int_array((i mod mimo_cycles) + int_array'length / 4);
         assert actual_value = expected_value
            report "MIMO AQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(bi_data_arr(i)));
         expected_value := int_array((i mod mimo_cycles) + int_array'length / 4 + int_array'length / 4);
         assert actual_value = expected_value
            report "MIMO BI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(bq_data_arr(i)));
         expected_value := int_array((i mod mimo_cycles) + int_array'length / 4 + int_array'length / 4 + int_array'length / 4);
         assert actual_value = expected_value
            report "MIMO BQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;
      end loop;

   end procedure;

   ------------------------------------------------------------------------------
   ---- Procedure to check 12 bit data modes in SISO and MIMO
   ------------------------------------------------------------------------------

   procedure p_test_12bit_data (
      signal interface_in     : in T_S_AXIS_IN;
      signal interface_out    : out T_S_AXIS_OUT;
      signal ai_data_arr      : in T_DATAARRAY;
      signal aq_data_arr      : in T_DATAARRAY;
      signal bi_data_arr      : in T_DATAARRAY;
      signal bq_data_arr      : in T_DATAARRAY;
      signal data_counter     : in integer;
      signal data_counter_rst : out std_logic;
      signal ch_en            : out std_logic_vector(1 downto 0);
      signal sample_width     : out std_logic_vector(1 downto 0);
      num_packets             : in integer;
      packetlen               : in integer
   ) is
      -- variable target_data_counter : integer;
      variable target_data_counter_sisoa : integer;
      variable target_data_counter_sisob : integer;
      variable target_data_counter_mimo : integer;
      variable packet_samples      : integer := (packetlen / 3) * 32;
      variable siso_cycles         : integer := packet_samples / 2;
      variable mimo_cycles         : integer := packet_samples / 4;
      variable test_samples        : integer := packet_samples * num_packets;
      variable int_array           : T_INTEGER_ARRAY(packet_samples - 1 downto 0);
      variable data_array_siso     : T_S_AXIS_TDATA_ARRAY(packetlen - 1 downto 0);
      variable data_array_mimo     : T_S_AXIS_TDATA_ARRAY(packetlen - 1 downto 0);
      variable j                   : integer;
      -- variable placeholder         : integer;
      variable expected_value      : integer;
      variable actual_value        : integer;
   begin

      assert (packetlen mod 3 = 0)
         report "12Bit Packet length must be divisible by 3!"
         severity failure;

      -- generate data
      -- if you get an error during sim pointing here, complaining about mismatched array sizes
      -- check if packetlen is divisible by 3
      int_array       := create_array_integer(packet_samples, 0);
      data_array_siso := create_array_siso_12bit(int_array);
      data_array_mimo := create_array_mimo_12bit(int_array);
      -- siso outputs 2 samples per cycle, so we need 2x less cycles than samples
      -- mimo outputs 4 samples per cycle, so we need 4x less cycles than samples
      target_data_counter_sisoa := test_samples / 2;
      target_data_counter_sisob := test_samples / 2 + test_samples / 2;
      target_data_counter_mimo  := test_samples / 2 + test_samples / 2 + test_samples / 4;
      -- reset counter
      data_counter_rst <= '1';
      skip_clocks(interface_in.ACLK, 10);
      data_counter_rst <= '0';
      -- start procedure
      -- SISO A
      ch_en        <= "01";
      sample_width <= "10";
      send_sisoa : for i in 0 to num_packets - 1 loop
         p_send_data_packet_arr(interface_in, interface_out, data_array_siso, 64x"0", '0');
      end loop;
      -- wait for sisoA data to arrive before changing ch_en/sample_width
      if (data_counter < target_data_counter_sisoa) then
         wait until data_counter = target_data_counter_sisoa;
      end if;

      -- SISO B
      ch_en        <= "10";
      sample_width <= "10";
      send_sisob : for i in 0 to num_packets - 1 loop
         p_send_data_packet_arr(interface_in, interface_out, data_array_siso, 64x"0", '0');
      end loop;
      -- wait for sisoA data to arrive before changing ch_en/sample_width
      if (data_counter < target_data_counter_sisob) then
         wait until data_counter = target_data_counter_sisob;
      end if;

      -- MIMO
      ch_en        <= "11";
      sample_width <= "10";
      send_mimo : for i in 0 to num_packets - 1 loop
         p_send_data_packet_arr(interface_in, interface_out, data_array_mimo, 64x"0", '0');
      end loop;
      -- wait for sisoA data to arrive before changing ch_en/sample_width
      if (data_counter < target_data_counter_mimo) then
         wait until data_counter = target_data_counter_mimo;
      end if;

      -- loop through and check results
      ------------------------------------------
      -- CHECK SISO A DATA
      ------------------------------------------
      check_siso_a : for i in 0 to target_data_counter_sisoa - 1 loop
         actual_value   := to_integer(unsigned(ai_data_arr(i)));
         expected_value := int_array(i mod siso_cycles) * 16; -- multiply by 16 is equal to std logic vector &"0000"
         assert actual_value = expected_value
            report "SISO AI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(aq_data_arr(i)));
         expected_value := int_array((i mod siso_cycles) + int_array'length / 2) * 16; -- multiply by 16 is equal to std logic vector &"0000";
         assert actual_value = expected_value
            report "SISO AQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value := to_integer(unsigned(bi_data_arr(i)));
         assert actual_value = 0
            report "SISO BI value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

         actual_value := to_integer(unsigned(bq_data_arr(i)));
         assert actual_value = 0
            report "SISO BQ value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

      end loop;
      ------------------------------------------
      -- CHECK SISO B DATA
      ------------------------------------------
      check_siso_b : for i in target_data_counter_sisoa to target_data_counter_sisob - 1 loop
         actual_value := to_integer(unsigned(ai_data_arr(i)));
         assert actual_value = 0
            report "SISO AI value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

         actual_value := to_integer(unsigned(aq_data_arr(i)));
         assert actual_value = 0
            report "SISO AQ value non zero in SISO A mode at data_counter = " & to_string(i)
            severity failure;

         actual_value   := to_integer(unsigned(bi_data_arr(i)));
         expected_value := int_array(i mod siso_cycles) * 16; -- multiply by 16 is equal to std logic vector &"0000"; -- mod siso_cycle chould take care of siso A offset as well
         assert actual_value = expected_value
            report "SISO BI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(bq_data_arr(i)));
         expected_value := int_array((i mod siso_cycles) + int_array'length / 2) * 16; -- multiply by 16 is equal to std logic vector &"0000"; -- mod siso_cycle chould take care of siso A offset as well
         assert actual_value = expected_value
            report "SISO BQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;
      end loop;
      ------------------------------------------
      -- CHECK MIMO DATA
      ------------------------------------------
      check_mimo : for i in target_data_counter_sisob to target_data_counter_mimo - 1 loop

         actual_value   := to_integer(unsigned(ai_data_arr(i)));
         expected_value := int_array(i mod mimo_cycles) * 16; -- multiply by 16 is equal to std logic vector &"0000";
         assert actual_value = expected_value
            report "MIMO AI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(aq_data_arr(i)));
         expected_value := int_array((i mod mimo_cycles) + int_array'length / 4) * 16; -- multiply by 16 is equal to std logic vector &"0000";
         assert actual_value = expected_value
            report "MIMO AQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(bi_data_arr(i)));
         expected_value := int_array((i mod mimo_cycles) + int_array'length / 4 + int_array'length / 4) * 16; -- multiply by 16 is equal to std logic vector &"0000";
         assert actual_value = expected_value
            report "MIMO BI mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;

         actual_value   := to_integer(unsigned(bq_data_arr(i)));
         expected_value := int_array((i mod mimo_cycles) + int_array'length / 4 + int_array'length / 4 + int_array'length / 4) * 16; -- multiply by 16 is equal to std logic vector &"0000";
         assert actual_value = expected_value
            report "MIMO BQ mismatch at data_counter = " & to_string(i) & ". Expected = " & to_string(expected_value) & ", Actual = " & to_string(actual_value)
            severity failure;
      end loop;

   end procedure;

   ------------------------------------------------------------------------------
   ---- Procedure to check synchronisation logic
   ---- samples are not checked, since we assume they were checked before in other
   ---- procedures
   ------------------------------------------------------------------------------

   procedure p_test_sync (
      signal interface_in     : in T_S_AXIS_IN;
      signal interface_out    : out T_S_AXIS_OUT;
      signal data_counter     : in integer;
      signal data_counter_rst : out std_logic;
      signal ch_en            : out std_logic_vector(1 downto 0);
      signal sample_width     : out std_logic_vector(1 downto 0);
      signal rx_sample_nr     : in std_logic_vector(63 downto 0);
      signal pct_loss_cnt     : in integer;
      signal PCT_SYNC_DIS     : out std_logic;
      num_packets             : in integer;
      packetlen               : in integer
   ) is

      -- variable target_data_counter : integer;
      variable target_data_counter_mimo : integer;
      variable packet_samples      : integer := packetlen * 8;
      variable siso_cycles         : integer := packet_samples / 2;
      variable mimo_cycles         : integer := packet_samples / 4;
      variable test_samples        : integer := packet_samples * num_packets;
      variable int_array           : T_INTEGER_ARRAY(packet_samples - 1 downto 0);
      variable data_array_siso     : T_S_AXIS_TDATA_ARRAY(packetlen - 1 downto 0);
      variable data_array_mimo     : T_S_AXIS_TDATA_ARRAY(packetlen - 1 downto 0);
      variable j                   : integer;
      -- variable placeholder         : integer;
      variable expected_value      : integer;
      variable actual_value        : integer;
      variable timestamp           : std_logic_vector(63 downto 0);
      variable pct_loss_start_val  : integer;
      variable ts_offset           : integer := 2000;
   begin
      -- assign value at start of procedure
      pct_loss_start_val := pct_loss_cnt;
      -- generate data
      int_array       := create_array_integer(packet_samples, 0);
      data_array_mimo := create_array_mimo_16bit(int_array);
      -- mimo outputs 4 samples per cycle, so we need 4x less cycles than samples
      -- but we send valid packets two times
      target_data_counter_mimo := (test_samples / 4) + (test_samples / 4);
      -- reset counter
      data_counter_rst <= '1';
      skip_clocks(interface_in.ACLK, 10);
      data_counter_rst <= '0';
      -- start procedure

      -- send packets with timestamps in the future, offset is arbitrary
      PCT_SYNC_DIS <= '0';
      ch_en        <= "11";
      sample_width <= "00";
      send_good_ts0 : for i in 0 to num_packets - 1 loop
         -- TODO: think of something more elegant than "+ i * packetlen * 2"
         --       now it is used to compensate packet writing being faster than reading
         --       may become bad if relationship between clocks is changed
         timestamp := std_logic_vector(unsigned(rx_sample_nr) + ts_offset + i * packetlen * 2);
         p_send_data_packet_arr(interface_in, interface_out, data_array_mimo, timestamp, '1');
      end loop;
      -- send late packets with timestamps in the past, offset is arbitrary
      send_bad_ts : for i in 0 to num_packets - 1 loop
         timestamp := std_logic_vector(unsigned(rx_sample_nr) - 100);
         p_send_data_packet_arr(interface_in, interface_out, data_array_mimo, timestamp, '1');
      end loop;
      -- send packets with timestamps in the future, offset is arbitrary
      -- doing it again to make sure dropped packets did not break anything
      ch_en        <= "11";
      sample_width <= "00";
      send_good_ts1 : for i in 0 to num_packets - 1 loop
         -- TODO: think of something more elegant than "+ i * packetlen * 2"
         --       now it is used to compensate packet writing being faster than reading
         --       may become bad if relationship between clocks is changed
         timestamp := std_logic_vector(unsigned(rx_sample_nr) + ts_offset + i * packetlen * 2);
         p_send_data_packet_arr(interface_in, interface_out, data_array_mimo, timestamp, '1');
      end loop;

      -- wait for data to arrive
      if (data_counter < target_data_counter_mimo) then
         wait until data_counter = target_data_counter_mimo;
      end if;

      -- if we get here, then all data is received, no extra checking is needed

      -- check if dropped packet count is correct
      assert (pct_loss_start_val + num_packets = pct_loss_cnt)
         report "Incorrect number of packets dropped, expected: " & to_string(pct_loss_start_val + num_packets) & ", actual: " & to_string(pct_loss_cnt)
         severity failure;

   end procedure;

   procedure skip_clocks (
      signal clk : in std_logic;
      num        : integer
   ) is

      variable counter : integer := 0;
   begin

      while (counter < num) loop
         wait until rising_edge(clk);
         wait for 1 ps;
         counter := counter + 1;
      end loop;

   end procedure;

   function create_array_integer (size : positive; start_val : integer) return T_INTEGER_ARRAY is
      variable result  : T_INTEGER_ARRAY(size - 1 downto 0);
      variable counter : integer := start_val;
      variable j       : integer := 0;
   begin
      for j in 0 to size - 1 loop
         result(j) := counter;
         counter   := counter + 1;

         if (counter > 4095) then
            counter := 0;
         end if;

      end loop;
      return result;
   end function;

end package body tx_top_pkg;
