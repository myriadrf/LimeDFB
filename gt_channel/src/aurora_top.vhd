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
    G_DATA_FIFO_LO_THR          : integer := 300; --Deassert write stop when usedw falls below this threshold
    G_DATA_FIFO_HI_THR          : integer := 400; --Assert write stop when usedw is higher than this threshold
    G_CTRL_FIFO_LO_THR          : integer := 300; --...
    G_CTRL_FIFO_HI_THR          : integer := 400;
    G_BUFR_FIFO_LO_THR          : integer := 300;
    G_BUFR_FIFO_HI_THR          : integer := 400
);
port (
    -- AXI TX Interface
    S_AXI_TX_TDATA            : in  std_logic_vector(0 to 31);
    S_AXI_TX_TVALID           : in  std_logic;
    S_AXI_TX_TREADY           : out std_logic;
    S_AXI_TX_TKEEP            : in std_logic_vector(0 to 3);
    S_AXI_TX_TLAST            : in  std_logic;
    -- AXI RX Interface
    M_AXI_RX_TDATA            : out std_logic_vector(0 to 31);
    M_AXI_RX_TVALID           : out std_logic;
    M_AXI_RX_TKEEP            : out std_logic_vector(0 to 3);
    M_AXI_RX_TLAST            : out std_logic;
    -- GT Serial I/O
    RXP                       : in std_logic_vector(0 downto 0);
    RXN                       : in std_logic_vector(0 downto 0);
    TXP                       : out std_logic_vector(0 downto 0);
    TXN                       : out std_logic_vector(0 downto 0);
    -- GT Reference Clock Interface
    GT_REFCLK1                : in  std_logic;
    -- Error Detection Interface
    FRAME_ERR                 : out std_logic;
    HARD_ERR                  : out std_logic;
    SOFT_ERR                  : out std_logic;
    CHANNEL_UP                : out std_logic;
    LANE_UP                   : out std_logic_vector(0 downto 0);
    -- System Interface
    USER_CLK_OUT              : out std_logic;
    SYNC_CLK_OUT              : out std_logic;
    RESET                     : in  std_logic;
    POWER_DOWN                : in  std_logic;
    LOOPBACK                  : in  std_logic_vector(2 downto 0);
    GT_RESET                  : in  std_logic;
    TX_LOCK                   : out std_logic;
    SYS_RESET_OUT             : out std_logic;
    GT_RESET_OUT              : out std_logic;
    INIT_CLK_IN               : in  std_logic;
    TX_RESETDONE_OUT          : out std_logic;
    RX_RESETDONE_OUT          : out std_logic;
    LINK_RESET_OUT            : out std_logic;
    --DRP Ports
    DRPCLK_IN                 : in   std_logic;
    DRPADDR_IN                : in   std_logic_vector(8 downto 0);
    DRPDI_IN                  : in   std_logic_vector(15 downto 0);
    DRPDO_OUT                 : out  std_logic_vector(15 downto 0);
    DRPEN_IN                  : in   std_logic;
    DRPRDY_OUT                : out  std_logic;
    DRPWE_IN                  : in   std_logic;
--____________________________COMMON PORTS_______________________________{
  GT0_PLL0REFCLKLOST_OUT      : out  std_logic;  
  QUAD1_COMMON_LOCK_OUT       : out  std_logic;  
------------------------- Channel - Ref Clock Ports ------------------------
  GT0_PLL0OUTCLK_OUT          : out  std_logic;  
  GT0_PLL1OUTCLK_OUT          : out  std_logic;  
  GT0_PLL0OUTREFCLK_OUT       : out  std_logic;  
  GT0_PLL1OUTREFCLK_OUT       : out  std_logic;  
--____________________________COMMON PORTS_______________________________}
    PLL_NOT_LOCKED_OUT        : out std_logic;
--____________________________FLOW CONTROL PORTS_________________________
  DATA_FIFO_USEDW             : in  std_logic_vector(31 downto 0);--UFC
  CTRL_FIFO_USEDW             : in  std_logic_vector(31 downto 0);--UFC
  BUFR_FIFO_USEDW             : in  std_logic_vector(31 downto 0);--NFC
  DATA_FIFO_STOPWR            : out std_logic;
  CTRL_FIFO_STOPWR            : out std_logic;
  UFC_MISC_SIGNALS_IN         : in  std_logic_vector(29 downto 0):=(others => '0'); --Reserved | IN  = provided to this core
  UFC_MISC_SIGNALS_OUT        : out std_logic_vector(29 downto 0)                   --Reserved | OUT = output by this core

 );
end aurora_top;

architecture Behavioral of aurora_top is

    signal sys_reset        : std_logic;
	signal user_clk			: std_logic;
	
	signal rx_nfc_ready     : std_logic;
	signal rx_nfc_valid     : std_logic;
	signal rx_nfc_data      : std_logic_vector(3 downto 0);
	
	signal ufc_register_out : std_logic_vector(31 downto 0) := (others => '0'); -- | OUT = sent to partner via UFC
	signal ufc_register_in  : std_logic_vector(31 downto 0); -- | IN  = received from partner via UFC
	signal ufc_tx_valid     : std_logic;
	signal ufc_tx_tdata     : std_logic_vector(2 downto 0);
	signal ufc_tx_ready     : std_logic;
	signal ufc_tx_axisdata  : std_logic_vector(31 downto 0);
	signal ufc_rx_tdata     : std_logic_vector(31 downto 0);
--	signal ufc_rx_keep      
    signal ufc_rx_valid     : std_logic;
    signal ufc_rx_last      : std_logic;
    
    signal aurora_tx_data_mux : std_logic_vector(31 downto 0);    
    signal aurora_tx_ready    : std_logic;
--component declarations
    component aurora_8b10b_0
        port   (
         -- TX Stream Interface
                s_axi_tx_tdata            : in  std_logic_vector(0 to 31);
                s_axi_tx_tvalid           : in  std_logic;
                s_axi_tx_tready           : out std_logic;
                s_axi_tx_tkeep            : in std_logic_vector(0 to 3);
                s_axi_tx_tlast            : in  std_logic;
         -- RX Stream Interface
                m_axi_rx_tdata            : out std_logic_vector(0 to 31);
                m_axi_rx_tkeep            : out std_logic_vector(0 to 3);
                m_axi_rx_tvalid           : out std_logic;
                m_axi_rx_tlast            : out std_logic;
        -- Native Flow Control TX Interface
                s_axi_nfc_tx_tvalid       : in std_logic;
                s_axi_nfc_tx_tdata        : in std_logic_vector(0 to 3);
                s_axi_nfc_tx_tready       : out std_logic;
        -- Native Flow Control RX Interface
                m_axi_nfc_rx_tvalid       : out std_logic;
                m_axi_nfc_rx_tdata        : out std_logic_vector(0 to 3);
        -- User Flow Control TX Interface
                s_axi_ufc_tx_tvalid       : in std_logic;
                s_axi_ufc_tx_tdata        : in std_logic_vector(0 to 2);
                s_axi_ufc_tx_tready       : out std_logic;
        -- User Flow Control RX Inteface
                m_axi_ufc_rx_tdata        : out std_logic_vector(0 to 31);
                m_axi_ufc_rx_tkeep        : out std_logic_vector(0 to 3);
                m_axi_ufc_rx_tvalid       : out std_logic;
                m_axi_ufc_rx_tlast        : out std_logic;
        -- GT Serial I/O
                rxp                       : in std_logic_vector(0 downto 0);
                rxn                       : in std_logic_vector(0 downto 0);

                txp                       : out std_logic_vector(0 downto 0);
                txn                       : out std_logic_vector(0 downto 0);
        -- GT Reference Clock Interface
                gt_refclk1                : in std_logic;
        -- Error Detection Interface
                hard_err                  : out std_logic;
                soft_err                  : out std_logic;
                frame_err                 : out std_logic;
        -- Status
                channel_up                : out std_logic;
                lane_up                   : out std_logic_vector(0 downto 0);
        -- System Interface
                user_clk_out              : out std_logic;
                sys_reset_out             : out std_logic;
                gt_reset                  : in std_logic;
                reset                     : in std_logic;
                power_down                : in std_logic;
                loopback                  : in std_logic_vector(2 downto 0);
                init_clk_in               : in  std_logic; 
                pll_not_locked_out        : out std_logic;
                tx_resetdone_out          : out std_logic;
                rx_resetdone_out          : out std_logic;
                link_reset_out            : out std_logic;
         -- DRP
                drpclk_in                 : in   std_logic;
                drpaddr_in                : in   std_logic_vector(8 downto 0);
                drpdi_in                  : in   std_logic_vector(15 downto 0);
                drpdo_out                 : out  std_logic_vector(15 downto 0);
                drpen_in                  : in   std_logic;
                drprdy_out                : out  std_logic;
                drpwe_in                  : in   std_logic;
   	      -- 
                gt_reset_out              :  out  std_logic;
                sync_clk_out              :  out  std_logic;
              --____________________________COMMON PORTS_______________________________{
                gt0_pll0refclklost_out    : out  std_logic;  
                quad1_common_lock_out     : out  std_logic;  
              ------------------------- Channel - Ref Clock Ports ------------------------
                gt0_pll0outclk_out        : out  std_logic;  
                gt0_pll1outclk_out        : out  std_logic;  
                gt0_pll0outrefclk_out     : out  std_logic;  
                gt0_pll1outrefclk_out     : out  std_logic;  
              --____________________________COMMON PORTS_______________________________}
                tx_lock          : out std_logic
            );

    end component;
-----
    component aurora_nfc_gen is
     Generic (
         Lo_limit : integer := 300;
         Hi_limit  : integer := 400    
     );
     Port ( clk : in STD_LOGIC;
            fifo_usedw : in STD_LOGIC_VECTOR (31 downto 0);
            nfc_ready : in STD_LOGIC;
            nfc_valid : out STD_LOGIC;
            nfc_data : out STD_LOGIC_VECTOR(3 downto 0);
            reset_n : in STD_LOGIC);
    end component;
-----
    component aurora_ufc_reg_send 
        Port ( clk             : in STD_LOGIC;
               reset_n         : in STD_LOGIC;
               ufc_tx_valid    : out STD_LOGIC;
               ufc_tx_data     : out STD_LOGIC_VECTOR (2 downto 0);
               ufc_tx_ready    : in STD_LOGIC;
               axis_tx_data    : out STD_LOGIC_VECTOR (31 downto 0);
               reg_input       : in STD_LOGIC_VECTOR (31 downto 0) := (others => '0')
               );
    end component;
-----

begin



    aurora_module_i : aurora_8b10b_0
        port map   (
        -- AXI TX Interface
                   s_axi_tx_tdata          => aurora_tx_data_mux,
                   s_axi_tx_tkeep          => S_AXI_TX_TKEEP,
                   s_axi_tx_tvalid         => S_AXI_TX_TVALID,
                   s_axi_tx_tlast          => S_AXI_TX_TLAST,
                   s_axi_tx_tready         => aurora_tx_ready,--,tx_tready_i,
        -- AXI RX Interface
                   m_axi_rx_tdata          => M_AXI_RX_TDATA,
                   m_axi_rx_tkeep          => M_AXI_RX_TKEEP,
                   m_axi_rx_tvalid         => M_AXI_RX_TVALID,
                   m_axi_rx_tlast          => M_AXI_RX_TLAST,
        -- Native Flow Control TX Interface
                    s_axi_nfc_tx_tvalid    => rx_nfc_valid,
                    s_axi_nfc_tx_tdata     => rx_nfc_data , 
                    s_axi_nfc_tx_tready    => rx_nfc_ready,
        -- Native Flow Control RX Interface
            	    m_axi_nfc_rx_tvalid    => open,
                    m_axi_nfc_rx_tdata     => open,
        -- User Flow Control TX Interface
                    s_axi_ufc_tx_tvalid    => ufc_tx_valid,----,axi_ufc_tx_req_n_i,
                    s_axi_ufc_tx_tdata     => ufc_tx_tdata,--,axi_ufc_tx_ms_i,
                    s_axi_ufc_tx_tready    => ufc_tx_ready, --,axi_ufc_tx_ack_n_i,
        -- User Flow Control RX Inteface
                    m_axi_ufc_rx_tdata     => ufc_rx_tdata,--,axi_ufc_rx_data_i,
                    m_axi_ufc_rx_tkeep     => open,--,axi_ufc_rx_rem_i,
                    m_axi_ufc_rx_tvalid    => ufc_rx_valid,--,axi_ufc_rx_src_rdy_n_i,
                    m_axi_ufc_rx_tlast     => ufc_rx_last,--,axi_ufc_rx_eof_n_i,
        -- GT Serial I/O
                    rxp(0)                 => RXP(0),
                    rxn(0)                 => RXN(0),
                    txp(0)                 => TXP(0),
                    txn(0)                 => TXN(0),
        -- GT Reference Clock Interface
                   gt_refclk1              => GT_REFCLK1 ,
        -- Error Detection Interface
                    hard_err               => HARD_ERR ,
                    soft_err               => SOFT_ERR ,
                    frame_err              => FRAME_ERR,
        -- Status
                    channel_up             => CHANNEL_UP,
                    lane_up(0)             => LANE_UP(0),
        -- System Interface
                    user_clk_out           => user_clk          ,
                    sys_reset_out          => sys_reset         ,
                    reset                  => RESET             ,
                    power_down             => POWER_DOWN        ,
                    loopback               => LOOPBACK          ,
                    gt_reset               => GT_RESET          ,
                    init_clk_in            => INIT_CLK_IN       ,
            	    pll_not_locked_out     => PLL_NOT_LOCKED_OUT,
            	    tx_resetdone_out       => TX_RESETDONE_OUT  ,
            	    rx_resetdone_out       => RX_RESETDONE_OUT  ,
            	    link_reset_out         => LINK_RESET_OUT    ,
        -- DRP
                    drpclk_in              => DRPCLK_IN      ,
                    drpaddr_in             => DRPADDR_IN     ,
                    drpen_in               => DRPEN_IN       ,
                    drpdi_in               => DRPDI_IN       ,
                    drprdy_out             => DRPRDY_OUT     ,
                    drpdo_out              => DRPDO_OUT      ,
                    drpwe_in               => DRPWE_IN       ,
                    gt_reset_out           => GT_RESET_OUT   ,
                    sync_clk_out           => SYNC_CLK_OUT   ,

                  --____________________________COMMON PORTS_______________________________{
                    gt0_pll0refclklost_out =>  GT0_PLL0REFCLKLOST_OUT ,
                    quad1_common_lock_out  =>  QUAD1_COMMON_LOCK_OUT  ,
                  ------------------------- Channel - Ref Clock Ports ------------------------
                    gt0_pll0outclk_out     =>  GT0_PLL0OUTCLK_OUT    ,
                    gt0_pll1outclk_out     =>  GT0_PLL1OUTCLK_OUT    ,
                    gt0_pll0outrefclk_out  =>  GT0_PLL0OUTREFCLK_OUT ,
                    gt0_pll1outrefclk_out  =>  GT0_PLL1OUTREFCLK_OUT ,
                  --____________________________COMMON PORTS_______________________________}
                    tx_lock          => TX_LOCK
                 );

    nfc_control_inst : aurora_nfc_gen
    Generic map (
        Lo_limit => G_BUFR_FIFO_LO_THR,
        Hi_limit => G_BUFR_FIFO_HI_THR
    )
    Port map (
           clk          => user_clk,
           reset_n      => not sys_reset,
           fifo_usedw   => BUFR_FIFO_USEDW,
           nfc_ready    => rx_nfc_ready,
           nfc_valid    => rx_nfc_valid,
           nfc_data     => rx_nfc_data 
    );
	
	ufc_register_value_control : process(DATA_FIFO_USEDW,CTRL_FIFO_USEDW,user_clk)
	begin
		if rising_edge(user_clk) then
			-- if write stop is not asserted and high threshold is reached, assert write stop
			if unsigned(DATA_FIFO_USEDW) > G_DATA_FIFO_HI_THR and ufc_register_out(0) = '0' then
				ufc_register_out(0) <= '1';
			-- if write stop is asserted and low threshold is passed, deassert write stop
			elsif unsigned(DATA_FIFO_USEDW) < G_DATA_FIFO_LO_THR and ufc_register_out(0) = '1' then
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
	
	ufc_sender_inst : aurora_ufc_reg_send 
    Port map ( clk         => user_clk,
           reset_n         => not sys_reset,
           ufc_tx_valid    => ufc_tx_valid,
           ufc_tx_data     => ufc_tx_tdata,
           ufc_tx_ready    => ufc_tx_ready,
           axis_tx_data    => ufc_tx_axisdata,
           reg_input       => ufc_register_out
           );
           
      aurora_tx_data_mux <= S_AXI_TX_TDATA when aurora_tx_ready = '1' else ufc_tx_axisdata;
	
--	 Receive UFC message
	 ufc_receiver : process(user_clk)
     begin
         if rising_edge(user_clk) then
             if ufc_rx_valid = '1' then
                 ufc_register_in <= ufc_rx_tdata;
             end if;    
         end if;
     end process;
     
     UFC_MISC_SIGNALS_OUT <= ufc_register_in(31 downto 2);
     DATA_FIFO_STOPWR     <= ufc_register_in(0);
     CTRL_FIFO_STOPWR     <= ufc_register_in(1); 
     

    S_AXI_TX_TREADY <= aurora_tx_ready;
    SYS_RESET_OUT   <= sys_reset;
	USER_CLK_OUT    <= user_clk;

end Behavioral;
