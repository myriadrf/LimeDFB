-- ----------------------------------------------------------------------------
-- FILE:          aurora_top.vhd
-- DESCRIPTION:   Top wrapper file Aurora module with included flow control modules
-- DATE:          13:20 2023-06-23
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- ----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity aurora_top is
   generic(
      g_DEBUG                     : string  := "false";
      g_GT_TYPE                   : string  := "GTH"; -- GTH - Ultrascale+; GTP - Artix7; 
      G_DATA_FIFO_LO_THR          : integer :=  64;   -- Deassert write stop when usedw falls below this threshold
      G_DATA_FIFO_HI_THR          : integer := 128;   -- Assert write stop when usedw is higher than this threshold
      G_CTRL_FIFO_LO_THR          : integer := 300;   -- ...
      G_CTRL_FIFO_HI_THR          : integer := 400;
      G_BUFR_FIFO_LO_THR          : integer :=  16;
      G_BUFR_FIFO_HI_THR          : integer :=  32
   );
   port (
      -- AXI TX Interface
      S_AXI_TX_TDATA            : in  std_logic_vector(31 downto 0);
      S_AXI_TX_TVALID           : in  std_logic;
      S_AXI_TX_TREADY           : out std_logic;
      S_AXI_TX_TKEEP            : in std_logic_vector(3 downto 0);
      S_AXI_TX_TLAST            : in  std_logic;
      -- AXI RX Interface
      M_AXI_RX_TDATA            : out std_logic_vector(31 downto 0);
      M_AXI_RX_TVALID           : out std_logic;
      M_AXI_RX_TKEEP            : out std_logic_vector(3 downto 0);
      M_AXI_RX_TLAST            : out std_logic;
      -- GT Serial I/O
      RXP                       : in std_logic_vector(0 downto 0);
      RXN                       : in std_logic_vector(0 downto 0);
      TXP                       : out std_logic_vector(0 downto 0);
      TXN                       : out std_logic_vector(0 downto 0);
      -- GT Reference Clock Interface
      GT_REFCLK                 : in  std_logic;
      -- Error Detection Interface
      LANE_UP                   : out std_logic;
      -- System Interface
      USER_CLK_OUT              : out std_logic;
      RESET                     : in  std_logic;
      GT_RESET                  : in  std_logic;
      INIT_CLK_IN               : in  std_logic;
      --____________________________FLOW CONTROL PORTS_________________________
      DATA_FIFO_USEDW           : in  std_logic_vector(31 downto 0);--UFC
      DATA_FIFO_ALMOST_FULL     : in  std_logic;
      CTRL_FIFO_USEDW           : in  std_logic_vector(31 downto 0);--UFC
      BUFR_FIFO_USEDW           : in  std_logic_vector(31 downto 0);--NFC
      DATA_FIFO_STOPWR          : out std_logic;
      CTRL_FIFO_STOPWR          : out std_logic;
      UFC_MISC_SIGNALS_IN       : in  std_logic_vector(29 downto 0):=(others => '0'); --Reserved | IN  = provided to this core
      UFC_MISC_SIGNALS_OUT      : out std_logic_vector(29 downto 0)                   --Reserved | OUT = output by this core

    );
end aurora_top;

architecture Behavioral of aurora_top is

   signal sys_reset           : std_logic;
   signal user_clk            : std_logic;

   signal rx_nfc_ready        : std_logic;
   signal rx_nfc_valid        : std_logic;
   signal rx_nfc_data         : std_logic_vector(3 downto 0);
   
   signal m_axi_nfc_rx_tvalid : std_logic;
   signal m_axi_nfc_rx_tdata  : std_logic_vector(3 downto 0);
   

   signal ufc_register_out    : std_logic_vector(31 downto 0) := (others => '0'); -- | OUT = sent to partner via UFC
   signal ufc_register_in     : std_logic_vector(31 downto 0); -- | IN  = received from partner via UFC
   signal ufc_tx_valid        : std_logic;
   signal ufc_tx_tdata        : std_logic_vector(2 downto 0);
   signal ufc_tx_ready        : std_logic;
   signal ufc_tx_axisdata     : std_logic_vector(31 downto 0);
   signal ufc_rx_tdata        : std_logic_vector(31 downto 0);     
   signal ufc_rx_valid        : std_logic;
   signal ufc_rx_last         : std_logic;

   signal aurora_tx_data_mux  : std_logic_vector(31 downto 0);    
   signal aurora_tx_ready     : std_logic;

   signal channel_up_int      : std_logic;
   signal lane_up_int         : std_logic;
   
   attribute KEEP : string;
   attribute KEEP of m_axi_nfc_rx_tvalid  : signal is "true";
   attribute KEEP of m_axi_nfc_rx_tdata   : signal is "true";
   

begin



   aurora_module_i : entity work.aurora_8b10b_wrapper
      Generic map(
         g_DEBUG     => g_DEBUG,
         g_GT_TYPE   => g_GT_TYPE
      )
      Port map(
      -- AXI TX Interface
         s_axi_tx_tdata       => aurora_tx_data_mux,
         s_axi_tx_tkeep       => S_AXI_TX_TKEEP,
         s_axi_tx_tvalid      => S_AXI_TX_TVALID,
         s_axi_tx_tlast       => S_AXI_TX_TLAST,
         s_axi_tx_tready      => aurora_tx_ready,--,tx_tready_i,
      -- AXI RX Interface     
         m_axi_rx_tdata       => M_AXI_RX_TDATA,
         m_axi_rx_tkeep       => M_AXI_RX_TKEEP,
         m_axi_rx_tvalid      => M_AXI_RX_TVALID,
         m_axi_rx_tlast       => M_AXI_RX_TLAST,
      -- Native Flow Control TX Interface
         s_axi_nfc_tx_tvalid  => rx_nfc_valid,
         s_axi_nfc_tx_tdata   => rx_nfc_data, 
         s_axi_nfc_tx_tready  => rx_nfc_ready,
      -- Native Flow Control RX Interface
         m_axi_nfc_rx_tvalid  => m_axi_nfc_rx_tvalid,
         m_axi_nfc_rx_tdata   => m_axi_nfc_rx_tdata,
      -- User Flow Control TX Interface
         s_axi_ufc_tx_tvalid  => ufc_tx_valid,----,axi_ufc_tx_req_n_i,
         s_axi_ufc_tx_tdata   => ufc_tx_tdata,--,axi_ufc_tx_ms_i,
         s_axi_ufc_tx_tready  => ufc_tx_ready, --,axi_ufc_tx_ack_n_i,
      -- User Flow Control RX Inteface
         m_axi_ufc_rx_tdata   => ufc_rx_tdata,--,axi_ufc_rx_data_i,
         m_axi_ufc_rx_tkeep   => open,--,axi_ufc_rx_rem_i,
         m_axi_ufc_rx_tvalid  => ufc_rx_valid,--,axi_ufc_rx_src_rdy_n_i,
         m_axi_ufc_rx_tlast   => ufc_rx_last,--,axi_ufc_rx_eof_n_i,
      -- GT Serial I/O
         rxp                  => RXP(0),
         rxn                  => RXN(0),
         txp                  => TXP(0),
         txn                  => TXN(0),
      -- GT Reference Clock Interface
         gt_refclk            => GT_REFCLK,
      -- Status
         lane_up              => lane_up_int,
      -- System Interface
         user_clk_out         => user_clk          ,
         reset                => RESET             ,
         gt_reset             => GT_RESET          ,
         init_clk_in          => INIT_CLK_IN       
      );

   nfc_control_inst : entity work.aurora_nfc_gen
      Generic map (
         g_LO_LIMIT   => G_BUFR_FIFO_LO_THR,
         g_HI_LIMIT   => G_BUFR_FIFO_HI_THR
      )
      Port map (
         clk          => user_clk,
         reset_n      => lane_up_int,
         fifo_usedw   => BUFR_FIFO_USEDW,
         nfc_ready    => rx_nfc_ready,
         nfc_valid    => rx_nfc_valid,
         nfc_data     => rx_nfc_data 
      );

   ufc_register_value_control : process(user_clk, lane_up_int)
   begin
      if lane_up_int = '0' then 
         ufc_register_out <= (others=>'0');
      elsif rising_edge(user_clk) then
         -- if write stop is not asserted and high threshold is reached, assert write stop
         if (unsigned(DATA_FIFO_USEDW) > G_DATA_FIFO_HI_THR OR DATA_FIFO_ALMOST_FULL='1') and ufc_register_out(0) = '0' then
            ufc_register_out(0) <= '1';
         -- if write stop is asserted and low threshold is passed, deassert write stop
         elsif (unsigned(DATA_FIFO_USEDW) < G_DATA_FIFO_LO_THR AND DATA_FIFO_ALMOST_FULL='0') and ufc_register_out(0) = '1' then
            ufc_register_out(0) <= '0';
         else
            ufc_register_out(0) <= ufc_register_out(0);
         end if;
         
         -- if write stop is not asserted and high threshold is reached, assert write stop
         if unsigned(CTRL_FIFO_USEDW) > G_CTRL_FIFO_HI_THR and ufc_register_out(1) = '0' then
            ufc_register_out(1) <= '1';
         -- if write stop is asserted and low threshold is passed, deassert write stop
         elsif unsigned(CTRL_FIFO_USEDW) < G_CTRL_FIFO_LO_THR and ufc_register_out(1) = '1' then
            ufc_register_out(1) <= '0';
         else
            ufc_register_out(1) <= ufc_register_out(1);
         end if;
         
         ufc_register_out(31 downto 2) <= UFC_MISC_SIGNALS_IN;
      end if;
   end process;

   ufc_sender_inst : entity work.aurora_ufc_reg_send 
   Port map (
      clk            => user_clk,
      reset_n        => lane_up_int,
      ufc_tx_valid   => ufc_tx_valid,
      ufc_tx_data    => ufc_tx_tdata,
      ufc_tx_ready   => ufc_tx_ready,
      axis_tx_data   => ufc_tx_axisdata,
      reg_input      => ufc_register_out
   );

   aurora_tx_data_mux <= S_AXI_TX_TDATA when aurora_tx_ready = '1' else ufc_tx_axisdata;

   -- Receive UFC message
   ufc_receiver : process(user_clk, lane_up_int)
   begin
      if lane_up_int = '0' then 
         ufc_register_in <= (others=>'0');
      elsif rising_edge(user_clk) then
         if ufc_rx_valid = '1' then
            ufc_register_in <= ufc_rx_tdata;
         end if;    
      end if;
   end process;
     
   UFC_MISC_SIGNALS_OUT <= ufc_register_in(31 downto 2);
   DATA_FIFO_STOPWR     <= ufc_register_in(0);
   CTRL_FIFO_STOPWR     <= ufc_register_in(1); 
     

   S_AXI_TX_TREADY <= aurora_tx_ready;
   USER_CLK_OUT    <= user_clk;
   LANE_UP         <= lane_up_int;

end Behavioral;
