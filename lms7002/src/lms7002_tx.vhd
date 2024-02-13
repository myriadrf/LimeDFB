-- ----------------------------------------------------------------------------
-- FILE:          lms7002_tx.vhd
-- DESCRIPTION:   Transmit interface for LMS7002 IC
-- DATE:          13:44 2024-02-01
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- 
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fpgacfg_pkg.all;
use work.memcfg_pkg.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity lms7002_tx is
   generic( 
      g_IQ_WIDTH           : integer   := 12
   );
   port (
      clk               : in  std_logic;
      reset_n           : in  std_logic;
      from_fpgacfg      : in  t_FROM_FPGACFG;
      --Mode settings
      mode              : in  std_logic; -- JESD207: 1; TRXIQ: 0
      trxiqpulse        : in  std_logic; -- trxiqpulse on: 1; trxiqpulse off: 0
      ddr_en            : in  std_logic; -- DDR: 1; SDR: 0
      mimo_en           : in  std_logic; -- SISO: 1; MIMO: 0
      ch_en             : in  std_logic_vector(1 downto 0); --"01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B. 
      fidm              : in  std_logic; -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.                 
      --Tx interface data
      diq_h             : out std_logic_vector(g_IQ_WIDTH downto 0); --! fsync + DIQ
      diq_l             : out std_logic_vector(g_IQ_WIDTH downto 0); --! fsync + DIQ
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      s_axis_areset_n   : in  std_logic;  --! AXIS reset
      s_axis_aclk       : in  std_logic;  --! AXIS clock
      s_axis_tvalid     : in  std_logic;  --! AXIS valid transfer
      s_axis_tdata      : in  std_logic_vector(63 downto 0); --! AXIS data
      s_axis_tready     : out std_logic;  --! AXIS ready 
      s_axis_tlast      : in  std_logic   --! AXIS last packet boundary @end
   );
end lms7002_tx;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of lms7002_tx is
--declare signals,  components here


signal s_axis_tready_reg   : std_logic;

type t_DIQ_SHIFT_REG_TYPE is array (0 to 1) of std_logic_vector(15 downto 0);
signal diq_l_reg : t_DIQ_SHIFT_REG_TYPE;
signal diq_h_reg : t_DIQ_SHIFT_REG_TYPE;


alias a_AXIS_FIFO_AI is s_axis_tdata(63 downto 48);
alias a_AXIS_FIFO_AQ is s_axis_tdata(47 downto 32);
alias a_AXIS_FIFO_BI is s_axis_tdata(31 downto 16);
alias a_AXIS_FIFO_BQ is s_axis_tdata(15 downto  0);

signal fsync_l : std_logic_vector(3 downto 0);
signal fsync_h : std_logic_vector(3 downto 0);

signal mux_fsync_L   : std_logic_vector(3 downto 0);
signal mux_fsync_H   : std_logic_vector(3 downto 0);

signal int_fsync_L   : std_logic_vector(3 downto 0);
signal int_fsync_H   : std_logic_vector(3 downto 0);

 
begin

   -- According to axi stream protocol:
   -- A Receiver is permitted to wait for TVALID to be asserted before asserting TREADY. It is permitted that a
   -- Receiver asserts and deasserts TREADY without TVALID being asserted.
   process(clk, reset_n)
   begin 
      if reset_n = '0' then 
         s_axis_tready_reg <= '0';
      elsif rising_edge(clk) then 
         if s_axis_tvalid = '1' then 
            if ddr_en = '1' AND mimo_en = '0' then 
               s_axis_tready_reg <= '1';
            else 
               s_axis_tready_reg <= NOT s_axis_tready_reg;
            end if;
         else 
            s_axis_tready_reg <= '0';
         end if;
      end if;
   end process;
   
   -- diq_l and diq_h shift registers
   process(clk, reset_n)
   begin 
      if reset_n = '0' then 
         diq_h_reg <=(others=>(others=>'0'));
      elsif rising_edge(clk) then 
         if s_axis_tready_reg = '1' AND s_axis_tvalid ='1' then 
            diq_h_reg(0) <= a_AXIS_FIFO_AI;
            diq_h_reg(1) <= a_AXIS_FIFO_BI;
         else 
            diq_h_reg(0) <= diq_h_reg(1);
            diq_h_reg(1) <= (others=>'0');
         end if;
      end if;
   end process;
   
   process(clk, reset_n)
   begin 
      if reset_n = '0' then 
         diq_l_reg <=(others=>(others=>'0'));
      elsif rising_edge(clk) then 
         if s_axis_tready_reg = '1' AND s_axis_tvalid ='1' then 
            diq_l_reg(0) <= a_AXIS_FIFO_AQ;
            diq_l_reg(1) <= a_AXIS_FIFO_BQ;
         else 
            diq_l_reg(0) <= diq_l_reg(1);
            diq_l_reg(1) <= (others=>'0');
         end if;
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- Muxes for fsync signal
-- ----------------------------------------------------------------------------  
   mux_fsync_H <= "1111" when  (mimo_en ='0' AND ddr_en ='1' AND trxiqpulse='0') else 
               "0101";

   mux_fsync_L <= "0000" when  (mimo_en ='0' AND ddr_en = '1') OR trxiqpulse='1'  else 
               "0101";
      
   int_fsync_H <= (not mux_fsync_H(3) & not mux_fsync_H(2) & not mux_fsync_H(1) & not mux_fsync_H(0)) when fidm = '0' else 
               mux_fsync_H;
      
   int_fsync_L <= (not mux_fsync_L(3) & not mux_fsync_L(2) & not mux_fsync_L(1) & not mux_fsync_L(0)) when fidm = '0' else 
               mux_fsync_L;
               
   -- fsync register has more taps than diq shift registers because
   -- when we stop receiving valid diq samples from s_axis bus we want to 
   -- transmit one more frame with zeros on DIQ bus. 
   process(clk, reset_n)
   begin 
      if reset_n = '0' then 
         fsync_l <=(others=>'0');
         fsync_h <=(others=>'0');
      elsif rising_edge(clk) then 
         if s_axis_tready_reg = '1' AND s_axis_tvalid ='1' then 
            fsync_l <= int_fsync_L;
            fsync_h <= int_fsync_H;
         else 
            fsync_l <= '0' & fsync_l(3 downto 1);
            fsync_h <= '0' & fsync_h(3 downto 1);
         end if;
      end if;
   end process;
      
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------     
   
   diq_h <= fsync_h(0) & diq_h_reg(0)(15 downto 4);
   diq_l <= fsync_l(0) & diq_l_reg(0)(15 downto 4);

   s_axis_tready <= s_axis_tready_reg;
   
end arch;   


