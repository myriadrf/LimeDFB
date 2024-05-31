-- ----------------------------------------------------------------------------
-- FILE:          lms7002_ddin.vhd
-- DESCRIPTION:   takes data from lms7002 in double data rate
-- DATE:          Mar 14, 2016
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- Apr 17, 2019 - Added Xilinx support
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library altera_mf; -- altera
   use altera_mf.all;

library UNISIM;
   use unisim.vcomponents.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------

entity LMS7002_DDIN is
   generic (
      G_VENDOR                 : string  := "XILINX"; -- Valid values: "ALTERA", "XILINX"
      G_DEV_FAMILY             : string  := "";       -- Reserved
      G_IQ_WIDTH               : integer := 12;
      G_INVERT_INPUT_CLOCKS    : string  := "ON"
   );
   port (
      -- input ports
      CLK             : in    std_logic;
      RESET_N         : in    std_logic;
      RXIQ            : in    std_logic_vector(G_IQ_WIDTH - 1 downto 0);
      RXIQSEL         : in    std_logic;
      -- output ports
      DATA_OUT_H      : out   std_logic_vector(G_IQ_WIDTH downto 0);
      DATA_OUT_L      : out   std_logic_vector(G_IQ_WIDTH downto 0)
   );
end entity LMS7002_DDIN;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture ARCH of LMS7002_DDIN is

   -- declare signals,  components here
   signal aclr         : std_logic;
   signal datain       : std_logic_vector(G_IQ_WIDTH downto 0);
   signal int_data_q1  : std_logic_vector(G_IQ_WIDTH downto 0);
   signal int_data_q2  : std_logic_vector(G_IQ_WIDTH downto 0);

   component ALTDDIO_IN is
      generic (
         INTENDED_DEVICE_FAMILY       : string := "unused";
         IMPLEMENT_INPUT_IN_LCELL     : string := "ON";
         INVERT_INPUT_CLOCKS          : string := "OFF";
         POWER_UP_HIGH                : string := "OFF";
         WIDTH                        : natural;
         LPM_HINT                     : string := "UNUSED";
         LPM_TYPE                     : string := "altddio_in"
      );
      port (
         ACLR                         : in    std_logic := '0';
         ASET                         : in    std_logic := '0';
         DATAIN                       : in    std_logic_vector(WIDTH - 1 downto 0);
         DATAOUT_H                    : out   std_logic_vector(WIDTH - 1 downto 0);
         DATAOUT_L                    : out   std_logic_vector(WIDTH - 1 downto 0);
         INCLOCK                      : in    std_logic;
         INCLOCKEN                    : in    std_logic := '1';
         SCLR                         : in    std_logic := '0';
         SSET                         : in    std_logic := '0'
      );
   end component;

begin

   aclr <= not RESET_N;

   datain <= RXIQSEL & RXIQ;

   ALTERA_DDR_IN : if G_VENDOR = "ALTERA" generate

      altddio_in_component : ALTDDIO_IN
         generic map (
            INTENDED_DEVICE_FAMILY => G_DEV_FAMILY,
            INVERT_INPUT_CLOCKS    => G_INVERT_INPUT_CLOCKS,
            LPM_HINT               => "UNUSED",
            LPM_TYPE               => "altddio_in",
            POWER_UP_HIGH          => "OFF",
            WIDTH                  => G_IQ_WIDTH + 1
         )
         port map (
            ACLR      => aclr,
            DATAIN    => datain,
            INCLOCK   => CLK,
            DATAOUT_H => DATA_OUT_H,
            DATAOUT_L => DATA_OUT_L
         );

   end generate ALTERA_DDR_IN;

   XILINX_DDR_IN : if G_VENDOR = "XILINX" generate

      XILINX_DDR_IN_REG : for i in 0 to G_IQ_WIDTH generate

         iddr_inst : IDDR
            generic map (
               DDR_CLK_EDGE => "SAME_EDGE_PIPELINED",
               INIT_Q1      => '0',
               INIT_Q2      => '0',
               SRTYPE       => "ASYNC"
            )
            port map (
               Q1 => int_data_q1(i),
               Q2 => int_data_q2(i),
               C  => CLK,
               CE => '1',
               D  => datain(i),
               R  => aclr,
               S  => '0'
            );

      end generate XILINX_DDR_IN_REG;

      DATA_OUT_H <= int_data_q1 when G_INVERT_INPUT_CLOCKS = "OFF" else
                    int_data_q2;
      DATA_OUT_L <= int_data_q2 when G_INVERT_INPUT_CLOCKS = "OFF" else
                    int_data_q1;
   end generate XILINX_DDR_IN;

end architecture ARCH;

