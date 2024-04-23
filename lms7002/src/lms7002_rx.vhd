-- ----------------------------------------------------------------------------
-- FILE:          lms7002_rx.vhd
-- DESCRIPTION:   Receive interface for LMS7002 IC
-- DATE:          09:51 2024-02-12
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

entity LMS7002_RX is
   generic (
      G_IQ_WIDTH           : integer   := 12;
      G_M_AXIS_FIFO_WORDS  : integer   := 16
   );
   port (
      CLK               : in    std_logic;
      RESET_N           : in    std_logic;
      FROM_FPGACFG      : in    t_FROM_FPGACFG;
      -- Mode settings
      MODE              : in    std_logic;                              -- JESD207: 1; TRXIQ: 0
      TRXIQPULSE        : in    std_logic;                              -- trxiqpulse on: 1; trxiqpulse off: 0
      DDR_EN            : in    std_logic;                              -- DDR: 1; SDR: 0
      MIMO_EN           : in    std_logic;                              -- SISO: 1; MIMO: 0
      CH_EN             : in    std_logic_vector(1 downto 0);           -- "01" - Ch. A, "10" - Ch. B, "11" - Ch. A and Ch. B.
      FIDM              : in    std_logic;                              -- Frame start at fsync = 0, when 0. Frame start at fsync = 1, when 1.
      -- Tx interface data
      DIQ_H             : in    std_logic_vector(G_IQ_WIDTH downto 0);  -- fsync + DIQ
      DIQ_L             : in    std_logic_vector(G_IQ_WIDTH downto 0);  -- fsync + DIQ
      --! @virtualbus s_axis_tx @dir in Transmit AXIS bus
      M_AXIS_ARESET_N   : in    std_logic;                              --! AXIS reset
      M_AXIS_ACLK       : in    std_logic;                              --! AXIS clock
      M_AXIS_TVALID     : out   std_logic;                              --! AXIS valid transfer
      M_AXIS_TDATA      : out   std_logic_vector(63 downto 0);          --! AXIS data
      M_AXIS_TREADY     : in    std_logic;                              --! AXIS ready
      M_AXIS_TLAST      : out   std_logic                               --! AXIS last packet boundary @end
   );
end entity LMS7002_RX;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------

architecture ARCH of LMS7002_RX is

   -- declare signals,  components here
   signal diq_h_reg      : std_logic_vector(G_IQ_WIDTH downto 0);  -- DIQ + fsync
   signal diq_l_reg      : std_logic_vector(G_IQ_WIDTH downto 0);  -- DIQ + fsync

   signal ai             : std_logic_vector(G_IQ_WIDTH - 1 downto 0);
   signal aq             : std_logic_vector(G_IQ_WIDTH - 1 downto 0);
   signal bi             : std_logic_vector(G_IQ_WIDTH - 1 downto 0);
   signal bq             : std_logic_vector(G_IQ_WIDTH - 1 downto 0);
   signal ai_reg, aq_reg : std_logic_vector(G_IQ_WIDTH - 1 downto 0);
   signal frame_valid    : std_logic;

   type T_TXIQ_MODE is (MIMO_DDR, SISO_DDR, TXIQ_PULSE, SISO_SDR);

   signal txiq_mode      : T_TXIQ_MODE;

begin

   -- Internal signal to know which mode is set
   process (all) is
   begin

      if (TRXIQPULSE = '1') then
         txiq_mode <= TXIQ_PULSE;
      else
         if (MIMO_EN = '1' and DDR_EN = '1') then
            txiq_mode <= MIMO_DDR;
         elsif (MIMO_EN = '0' and DDR_EN = '1') then
            txiq_mode <= SISO_DDR;
         else
            txiq_mode <= SISO_SDR;
         end if;
      end if;

   end process;

   -- Input register
   process (CLK) is
   begin

      if rising_edge(CLK) then
         diq_h_reg <= DIQ_H;
         diq_l_reg <= DIQ_L;
      end if;

   end process;

   -- AI and AQ capture
   process (CLK) is
   begin

      if rising_edge(CLK) then
         if (DIQ_H(DIQ_H'left) = '0' and DIQ_L(DIQ_L'left)='0' and txiq_mode = MIMO_DDR) then
            ai <= DIQ_L(G_IQ_WIDTH - 1 downto 0);
            aq <= DIQ_H(G_IQ_WIDTH - 1 downto 0);
         elsif (DIQ_H(DIQ_H'left) = '1' and DIQ_L(DIQ_L'left)='0' and (txiq_mode = SISO_DDR or txiq_mode = TXIQ_PULSE)) then
            ai <= DIQ_L(G_IQ_WIDTH - 1 downto 0);
            aq <= DIQ_H(G_IQ_WIDTH - 1 downto 0);
         else
            ai <= ai;
            aq <= aq;
         end if;
      end if;

   end process;

   -- BI and BQ capture
   process (CLK) is
   begin

      if rising_edge(CLK) then
         if (DIQ_H(DIQ_H'left) = '1' and DIQ_L(DIQ_L'left)='1') then
            bi <= DIQ_L(G_IQ_WIDTH - 1 downto 0);
            bq <= DIQ_H(G_IQ_WIDTH - 1 downto 0);
         else
            bi <= bi;
            bq <= bq;
         end if;
      end if;

   end process;

   -- Internal IQ frame valid signal. For e.g one frame is AI AQ BI BQ samples in MIMO DDR mode
   process (CLK, RESET_N) is
   begin

      if (RESET_N = '0') then
         frame_valid <= '0';
      elsif rising_edge(CLK) then
         if (DIQ_H(DIQ_H'left) = '1' and DIQ_L(DIQ_L'left)='1' and txiq_mode = MIMO_DDR) then
            frame_valid <= '1';
         elsif (DIQ_H(DIQ_H'left) = '1' and DIQ_L(DIQ_L'left)='0' and txiq_mode = SISO_DDR) then
            frame_valid <= '1';
         elsif (diq_h_reg(DIQ_H'left) = '1' and diq_l_reg(DIQ_L'left)='0' and DIQ_H(DIQ_H'left) = '1' and DIQ_L(DIQ_L'left)='1' and txiq_mode = TXIQ_PULSE) then
            frame_valid <= '1';
         else
            frame_valid <= '0';
         end if;
      end if;

   end process;

   -- ----------------------------------------------------------------------------
   -- Output ports
   -- ----------------------------------------------------------------------------
   M_AXIS_TVALID              <= frame_valid;
   m_axis_tdata(63 downto 48) <= ai & "0000";
   m_axis_tdata(47 downto 32) <= aq & "0000";
   m_axis_tdata(31 downto 16) <= bi & "0000";
   m_axis_tdata(15 downto  0) <= bq & "0000";
   M_AXIS_TLAST               <= '0';

end architecture ARCH;


