-- ----------------------------------------------------------------------------
-- FILE:          gpio_top_tb.vhd
-- DESCRIPTION:   testbench module for gpio_top
-- DATE:          Mar 05, 2024
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use std.env.finish;
-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------

entity GPIO_TOP_TB is
end entity GPIO_TOP_TB;

architecture TB of GPIO_TOP_TB is

   constant C_GPIO_WIDTH      : integer := 12;
   signal   gpio_dir          : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_out_val      : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_in_val       : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_override     : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_override_val : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_i            : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_o            : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   signal   gpio_t            : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);

   signal test_val            : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
   -- no functionality, intended to make it easier to interpret waveforms manually
   signal checking            : std_logic;
   signal output_test         : std_logic;
   signal override_test       : std_logic;
   signal input_test          : std_logic;

begin

   inst_dut : entity work.gpio_top
      generic map (
         G_GPIO_WIDTH => C_GPIO_WIDTH
      )
      port map (
         GPIO_DIR          => gpio_dir,
         GPIO_OUT_VAL      => gpio_out_val,
         GPIO_IN_VAL       => gpio_in_val,
         GPIO_OVERRIDE     => gpio_override,
         GPIO_OVERRIDE_VAL => gpio_override_val,
         GPIO_I            => gpio_i,
         GPIO_O            => gpio_o,
         GPIO_T            => gpio_t

      );

   TEST_PROC : process is
   begin

      -- default values
      checking          <= '0';
      gpio_dir          <= (others => '0');
      gpio_out_val      <= (others => '0');
      gpio_override     <= (others => '0');
      gpio_override_val <= (others => '0');
      gpio_i            <= (others => '0');
      output_test       <= '0';
      override_test     <= '0';
      input_test        <= '0';
      wait for 50ns;

      -------------------------------------------------------------
      --- Testing normal gpio output
      -------------------------------------------------------------
      output_test <= '1';

      normal_output_test_loop : for i in 0 to C_GPIO_WIDTH - 1 loop

         test_val     <= (others => '0');
         test_val(i)  <= '1';
         wait for 1ns;
         gpio_out_val <= test_val;           -- set test value

         wait for 1ns;
         checking <= '1';                    -- for easier waveform readability
         -- check gpio read
         assert gpio_in_val = test_val
            report "ERROR: GPIO value read wrong in output mode"
            severity failure;
         -- check port values
         assert gpio_o = test_val
            report "ERROR: GPIO port value wrong in output mode"
            severity failure;
         wait for 1ns;
         checking <= '0';

      end loop;

      output_test <= '0';
      ---------------------------------------------------------------
      --- Testing gpio output override
      ---------------------------------------------------------------
      override_test <= '1';
      gpio_override  <= (others => '1');     -- override all outputs
      gpio_out_val   <= (others => '1');     -- set constant gpio_out value

      override_output_test_loop : for i in 0 to C_GPIO_WIDTH - 1 loop

         test_val          <= (others => '0');
         test_val(i)       <= '1';
         wait for 1ns;
         gpio_override_val <= test_val;      -- set test value
         wait for 1ns;
         checking          <= '1';           -- for easier waveform readability
         -- check gpio read
         assert gpio_in_val = test_val
            report "ERROR: GPIO value read wrong in output override mode"
            severity failure;
         -- check port values
         assert gpio_o = test_val
            report "ERROR: GPIO port value wrong in output override mode"
            severity failure;
         -- check override value
         assert test_val /= gpio_out_val
            report "ERROR: override value matches regular value in output override mode"
            severity failure;

         wait for 1ns;
         checking <= '0';

      end loop;

      override_test <= '0';

      ---------------------------------------------------------------
      --- Testing gpio input
      ---------------------------------------------------------------
      gpio_override_val <= (others => '0');  -- constant value for output override
      gpio_out_val      <= (others => '1');  -- different constant value for normal output
      gpio_dir          <= (others => '1');  -- all gpios set to input
      input_test        <= '1';

      input_test_loop : for i in 0 to C_GPIO_WIDTH - 1 loop

         test_val    <= (others => '0');
         test_val(i) <= '1';
         wait for 1ns;
         gpio_i      <= test_val;            -- set test value
         wait for 1ns;
         checking    <= '1';                 -- for easier waveform readability
         -- check gpio read
         assert gpio_in_val = test_val
            report "ERROR: GPIO value read wrong in input mode"
            severity failure;
         wait for 1ns;
         checking <= '0';

      end loop;

      input_test <= '0';

      report "GPIO_TOP test complete with no errors";
      finish;
      wait;

   end process TEST_PROC;

end architecture TB;
