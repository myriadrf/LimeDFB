-- ----------------------------------------------------------------------------
-- FILE:    lms7002_ddout.vhd
-- DESCRIPTION:   takes data in SDR and ouputs double data rate
-- DATE:   Mar 14, 2016
-- AUTHOR(s):   Lime Microsystems
-- REVISIONS:
-- Apr 17, 2019 - added Xilinx support
-- ----------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use work.fpgacfg_pkg.all;

library altera_mf;
   use altera_mf.all;

library UNISIM;
   use unisim.vcomponents.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------

entity LMS7002_DDOUT is
   generic (
      VENDOR        : string := "XILINX"; -- valid vals are "ALTERA", "XILINX"
      DEV_FAMILY    : string := "Cyclone IV E";
      IQ_WIDTH      : integer:= 12
   );
   port (
      -- input ports
      CLK           : in    std_logic;
      RESET_N       : in    std_logic;
      DATA_IN_H     : in    std_logic_vector(IQ_WIDTH downto 0);
      DATA_IN_L     : in    std_logic_vector(IQ_WIDTH downto 0);
      -- output ports
      TXIQ          : out   std_logic_vector(IQ_WIDTH - 1 downto 0);
      TXIQSEL       : out   std_logic
   );
end entity LMS7002_DDOUT;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture ARCH of LMS7002_DDOUT is

   -- declare signals,  components here

   signal aclr       : std_logic;
   signal datout     : std_logic_vector(IQ_WIDTH downto 0);

   signal data_reg_l : std_logic_vector(IQ_WIDTH downto 0);
   signal data_reg_h : std_logic_vector(IQ_WIDTH downto 0);

   component ALTDDIO_OUT is
      generic (
         INTENDED_DEVICE_FAMILY   : string := "unused";
         EXTEND_OE_DISABLE        : string := "OFF";
         INVERT_OUTPUT            : string := "OFF";
         OE_REG                   : string := "UNREGISTERED";
         POWER_UP_HIGH            : string := "OFF";
         WIDTH                    : natural;
         LPM_HINT                 : string := "UNUSED";
         LPM_TYPE                 : string := "altddio_out"
      );
      port (
         ACLR         : in    std_logic := '0';
         ASET         : in    std_logic := '0';
         DATAIN_H     : in    std_logic_vector(WIDTH - 1 downto 0);
         DATAIN_L     : in    std_logic_vector(WIDTH - 1 downto 0);
         DATAOUT      : out   std_logic_vector(WIDTH - 1 downto 0);
         OE           : in    std_logic := '1';
         OE_OUT       : out   std_logic_vector(WIDTH - 1 downto 0);
         OUTCLOCK     : in    std_logic;
         OUTCLOCKEN   : in    std_logic := '1';
         SCLR         : in    std_logic := '0';
         SSET         : in    std_logic := '0'
      );
   end component;

begin

   process (CLK) is
   begin

      if rising_edge(CLK) then
         data_reg_l <= DATA_IN_L;
         data_reg_h <= DATA_IN_H;
      end if;

   end process;

   aclr <= not RESET_N;

   ALTERA_DDR_OUT : if VENDOR = "ALTERA" generate

      altddio_out_component : ALTDDIO_OUT
         generic map (
            EXTEND_OE_DISABLE      => "OFF",
            INTENDED_DEVICE_FAMILY => "Cyclone IV E",
            INVERT_OUTPUT          => "OFF",
            LPM_HINT               => "UNUSED",
            LPM_TYPE               => "altddio_out",
            OE_REG                 => "UNREGISTERED",
            POWER_UP_HIGH          => "OFF",
            WIDTH                  => IQ_WIDTH + 1
         )
         port map (
            ACLR     => aclr,
            DATAIN_H => DATA_IN_H,
            DATAIN_L => DATA_IN_L,
            OUTCLOCK => CLK,
            DATAOUT  => datout
         );

   end generate ALTERA_DDR_OUT;

   XILINX_DDR_OUT : if VENDOR = "XILINX" generate

      XILINX_DDR_OUT_REG : for i in 0 to IQ_WIDTH generate

         oddr_inst : ODDR
            generic map (
               DDR_CLK_EDGE => "SAME_EDGE",
               INIT         => '0',
               SRTYPE       => "ASYNC"
            )
            port map (
               Q  => datout(i),
               C  => CLK,
               CE => '1',
               D1 => data_reg_h(i),
               D2 => data_reg_l(i),
               R  => aclr,
               S  => '0'
            );

      end generate XILINX_DDR_OUT_REG;

   end generate XILINX_DDR_OUT;

   TXIQ    <= datout(11 downto 0);
   TXIQSEL <= datout(12);

end architecture ARCH;





