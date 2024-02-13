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

LIBRARY altera_mf; --altera
USE altera_mf.all;
Library UNISIM;
use UNISIM.vcomponents.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity lms7002_ddin is
   generic( 
      g_VENDOR                 : string  := "XILINX"; -- Valid values: "ALTERA", "XILINX"
      g_DEV_FAMILY             : string  := "";       -- Reserved
      g_IQ_WIDTH               : integer := 12;
      g_INVERT_INPUT_CLOCKS    : string  := "ON"
   );
   port (
      --input ports 
      clk             : in std_logic;
      reset_n         : in std_logic;
      rxiq            : in std_logic_vector(g_IQ_WIDTH-1 downto 0);
      rxiqsel         : in std_logic;
      --output ports 
      data_out_h      : out std_logic_vector(g_IQ_WIDTH downto 0);
      data_out_l      : out std_logic_vector(g_IQ_WIDTH downto 0)
   );
end lms7002_ddin;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of lms7002_ddin is
--declare signals,  components here
signal aclr         : std_logic;
signal datain       : std_logic_vector(g_IQ_WIDTH downto 0);
signal int_data_Q1  : std_logic_vector(g_IQ_WIDTH downto 0);
signal int_data_Q2  : std_logic_vector(g_IQ_WIDTH downto 0);


component altddio_in
   generic (
      intended_device_family       :   string := "unused";
      implement_input_in_lcell     :   string := "ON";
      invert_input_clocks          :   string := "OFF";
      power_up_high                :   string := "OFF";
      width                        :   natural;
      lpm_hint                     :   string := "UNUSED";
      lpm_type                     :   string := "altddio_in"
   );
   port(
      aclr                         :   in std_logic := '0';
      aset                         :   in std_logic := '0';
      datain                       :   in std_logic_vector(width-1 downto 0);
      dataout_h                    :   out std_logic_vector(width-1 downto 0);
      dataout_l                    :   out std_logic_vector(width-1 downto 0);
      inclock                      :   in std_logic;
      inclocken                    :   in std_logic := '1';
      sclr                         :   in std_logic := '0';
      sset                         :   in std_logic := '0'
   );
end component;


begin

   aclr<=not reset_n;
   
   datain<=rxiqsel & rxiq;
   
   
   ALTERA_DDR_IN : if g_VENDOR = "ALTERA" generate
      ALTDDIO_IN_component : ALTDDIO_IN
      GENERIC MAP (
         intended_device_family    => g_DEV_FAMILY,
         invert_input_clocks       => g_INVERT_INPUT_CLOCKS,
         lpm_hint                  => "UNUSED",
         lpm_type                  => "altddio_in",
         power_up_high             => "OFF",
         width                     => g_IQ_WIDTH+1
      )
      PORT MAP (
         aclr                      => aclr,
         datain                    => datain,
         inclock                   => clk,
         dataout_h                 => data_out_h,
         dataout_l                 => data_out_l
      );
   end generate;
   
   XILINX_DDR_IN : if g_VENDOR = "XILINX" generate
   
      XILINX_DDR_IN_REG : for i in 0 to g_IQ_WIDTH generate
         IDDR_inst : IDDR
         GENERIC MAP(
            DDR_CLK_EDGE   => "SAME_EDGE_PIPELINED",
            INIT_Q1        => '0',
            INIT_Q2        => '0',
            SRTYPE         => "ASYNC" 
         )
         PORT MAP(
            Q1             => int_data_Q1(i),
            Q2             => int_data_Q2(i),
            C              => clk,
            CE             => '1',
            D              => datain(i),
            R              => aclr,
            S              => '0'      
         );
      end generate;
      
      data_out_h <= int_data_Q1 when g_INVERT_INPUT_CLOCKS = "OFF" else int_data_Q2;
      data_out_l <= int_data_Q2 when g_INVERT_INPUT_CLOCKS = "OFF" else int_data_Q1;
   end generate;
  
end arch;   

