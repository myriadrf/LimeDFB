-- ----------------------------------------------------------------------------
-- FILE:          pll_ctrl.vhd
-- DESCRIPTION:   PLL control module
-- DATE:          3:32 PM Friday, May 11, 2018
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
--NOTES:
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity pll_ctrl is
   generic (
      N_PLL       : integer :=2
   );
  port (
         -- Status Inputs
      pllcfg_busy       : in  std_logic_vector(N_PLL-1 downto 0);
      pllcfg_done       : in  std_logic_vector(N_PLL-1 downto 0);
         -- PLL Lock flags
      pll_lock          : in  std_logic_vector(N_PLL-1 downto 0);	
         -- PLL Configuratioin Related
      phcfg_mode        : out std_logic;
      phcfg_tst         : out std_logic;
      phcfg_start       : out std_logic_vector(N_PLL-1 downto 0); --
      pllcfg_start      : out std_logic_vector(N_PLL-1 downto 0); --
      pllrst_start      : out std_logic_vector(N_PLL-1 downto 0); --
      phcfg_updn        : out std_logic; --
      cnt_ind           : out std_logic_vector(4 downto 0); --
      cnt_phase         : out std_logic_vector(15 downto 0); --
      pllcfg_data       : out std_logic_vector(143 downto 0);
      auto_phcfg_done   : in  std_logic_vector(N_PLL-1 downto 0);
      auto_phcfg_err    : in  std_logic_vector(N_PLL-1 downto 0);
      auto_phcfg_smpls  : out std_logic_vector(15 downto 0);
      auto_phcfg_step   : out std_logic_vector(15 downto 0);

          -- pllcfg ports
      -- to pllcfg
      -- Status Inputs
      out_pllcfg_busy          : out std_logic;
      out_pllcfg_done          : out std_logic;
      out_phcfg_done           : out std_logic;
      out_phcfg_error          : out std_logic;
      -- PLL Lock flags
      out_pll_lock             : out std_logic_vector(15 downto 0);
      --  from pllcfg
      -- PLL Configuratioin Related
      in_phcfg_start       : in std_logic; --
      in_pllcfg_start      : in std_logic; --
      in_pllrst_start      : in std_logic; --
      in_phcfg_updn        : in std_logic; --
      in_cnt_ind           : in std_logic_vector(4 downto 0); --
      in_pll_ind           : in std_logic_vector(4 downto 0); --
      in_phcfg_mode        : in std_logic;
      in_phcfg_tst         : in std_logic;

      in_cnt_phase         : in std_logic_vector(15 downto 0); --
      in_chp_curr          : in std_logic_vector(2 downto 0); --
      in_pllcfg_vcodiv     : in std_logic; --
      in_pllcfg_lf_res     : in std_logic_vector(4 downto 0); -- (for Cyclone IV)
      in_pllcfg_lf_cap     : in std_logic_vector(1 downto 0); -- (for cyclone IV)

      in_m_odddiv          : in std_logic; --
      in_m_byp             : in std_logic; --
      in_n_odddiv          : in std_logic; --
      in_n_byp             : in std_logic; --

      in_c0_odddiv         : in std_logic; --
      in_c0_byp            : in std_logic; --
      in_c1_odddiv         : in std_logic; --
      in_c1_byp            : in std_logic; --
      in_c2_odddiv         : in std_logic; --
      in_c2_byp            : in std_logic; --
      in_c3_odddiv         : in std_logic; --
      in_c3_byp            : in std_logic; --
      in_c4_odddiv         : in std_logic; --
      in_c4_byp            : in std_logic; --
      in_n_cnt             : in std_logic_vector(15 downto 0); --
      in_m_cnt             : in std_logic_vector(15 downto 0); --
      in_c0_cnt            : in std_logic_vector(15 downto 0); --
      in_c1_cnt            : in std_logic_vector(15 downto 0); --
      in_c2_cnt            : in std_logic_vector(15 downto 0); --
      in_c3_cnt            : in std_logic_vector(15 downto 0); --
      in_c4_cnt            : in std_logic_vector(15 downto 0); --
      in_auto_phcfg_smpls  : in std_logic_vector(15 downto 0);
      in_auto_phcfg_step   : in std_logic_vector(15 downto 0)
      
        );
end pll_ctrl;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of pll_ctrl is
--declare signals,  components here
signal pll_ind			: std_logic_vector(4 downto 0);
signal chp_curr 		: std_logic_vector(2 downto 0);
signal pllcfg_vcodiv	:  std_logic;
signal pllcfg_lf_res	:  std_logic_vector(4 downto 0); 
signal pllcfg_lf_cap	:  std_logic_vector(1 downto 0); 
signal m_odddiv		:  std_logic; --
signal m_byp			:  std_logic; --
signal n_odddiv		:  std_logic; --
signal n_byp			:  std_logic; --
signal c0_odddiv		:  std_logic; --
signal c0_byp			:  std_logic; --
signal c1_odddiv		:  std_logic; --
signal c1_byp			:  std_logic; --
signal c2_odddiv		:  std_logic; --
signal c2_byp			:  std_logic; --
signal c3_odddiv		:  std_logic; --
signal c3_byp			:  std_logic; --
signal c4_odddiv		:  std_logic; --
signal c4_byp			:  std_logic; --
signal n_cnt			:  std_logic_vector(15 downto 0); -- 
signal m_cnt			:  std_logic_vector(15 downto 0); -- 
signal m_frac			:  std_logic_vector(31 downto 0); -- 
signal c0_cnt			:  std_logic_vector(15 downto 0); -- 
signal c1_cnt			:  std_logic_vector(15 downto 0); -- 
signal c2_cnt			:  std_logic_vector(15 downto 0); -- 
signal c3_cnt			:  std_logic_vector(15 downto 0); -- 
signal c4_cnt			:  std_logic_vector(15 downto 0); -- 


signal pllcfg_busy_bit	: std_logic;
signal pllcfg_busy_vect	: std_logic_vector(15 downto 0);

signal pllcfg_done_bit	: std_logic;
signal pllcfg_done_vect	: std_logic_vector(15 downto 0);

signal auto_phcfg_done_bit	   : std_logic;
signal auto_phcfg_done_vect	: std_logic_vector(15 downto 0);

signal auto_phcfg_err_bit	   : std_logic;
signal auto_phcfg_err_vect	   : std_logic_vector(15 downto 0);

signal pll_lock_vect		: std_logic_vector(15 downto 0);

signal phcfg_start_vect	: std_logic_vector(15 downto 0);
signal pllcfg_start_vect: std_logic_vector(15 downto 0);
signal pllrst_start_vect: std_logic_vector(15 downto 0);

signal phcfg_start_bit	: std_logic;
signal pllcfg_start_bit	: std_logic;
signal pllrst_start_bit	: std_logic;

signal pllcfg_data_rev	: std_logic_vector(143 downto 0);

  
begin

pllcfg_busy_vect(N_PLL-1 downto 0)     <= pllcfg_busy;
pllcfg_busy_vect(15 downto N_PLL)      <= (others=>'0');
   
pllcfg_done_vect(N_PLL-1 downto 0)     <= pllcfg_done;
pllcfg_done_vect(15 downto N_PLL)      <= (others=>'0');

auto_phcfg_done_vect(N_PLL-1 downto 0) <= auto_phcfg_done;
auto_phcfg_done_vect(15 downto N_PLL)  <= (others=>'0');

auto_phcfg_err_vect(N_PLL-1 downto 0)  <= auto_phcfg_err;
auto_phcfg_err_vect(15 downto N_PLL)   <= (others=>'0');

pll_lock_vect(N_PLL-1 downto 0)        <= pll_lock;
pll_lock_vect(15 downto N_PLL)         <= (others=>'0');

process(pll_ind, pllcfg_busy_vect, pllcfg_done_vect) begin
	pllcfg_busy_bit<=pllcfg_busy_vect(to_integer(unsigned(pll_ind)));
	pllcfg_done_bit<=pllcfg_done_vect(to_integer(unsigned(pll_ind)));
end process;

process(pll_ind, auto_phcfg_done_vect, auto_phcfg_err_vect) begin
	auto_phcfg_done_bit  <=auto_phcfg_done_vect(to_integer(unsigned(pll_ind)));
	auto_phcfg_err_bit   <=auto_phcfg_err_vect(to_integer(unsigned(pll_ind)));
end process;


process(pll_ind, phcfg_start_bit) begin
	phcfg_start_vect<=(others=>'0');
	phcfg_start_vect(to_integer(unsigned(pll_ind)))<=phcfg_start_bit;
end process;

process(pll_ind, pllcfg_start_bit) begin
	pllcfg_start_vect<=(others=>'0');
	pllcfg_start_vect(to_integer(unsigned(pll_ind)))<=pllcfg_start_bit;
end process;

process(pll_ind, pllrst_start_bit) begin
	pllrst_start_vect<=(others=>'0');
	pllrst_start_vect(to_integer(unsigned(pll_ind)))<=pllrst_start_bit;
end process;


phcfg_start  <= phcfg_start_vect(N_PLL-1 downto 0);
pllcfg_start <= pllcfg_start_vect(N_PLL-1 downto 0);
pllrst_start <= pllrst_start_vect(N_PLL-1 downto 0);


out_pllcfg_busy   <= pllcfg_busy_bit;
out_pllcfg_done   <= pllcfg_done_bit;
out_phcfg_done    <= auto_phcfg_done_bit;
out_phcfg_error   <= auto_phcfg_err_bit;
out_pll_lock      <= pll_lock_vect;

phcfg_start_bit         <= in_phcfg_start;
pllcfg_start_bit        <= in_pllcfg_start;
pllrst_start_bit        <= in_pllrst_start;

phcfg_updn              <= in_phcfg_updn;
cnt_ind                 <= in_cnt_ind;
pll_ind                 <= in_pll_ind;
phcfg_mode              <= in_phcfg_mode;
phcfg_tst               <= in_phcfg_tst;
cnt_phase               <= in_cnt_phase;
chp_curr                <= in_chp_curr;
pllcfg_vcodiv           <= in_pllcfg_vcodiv;
pllcfg_lf_res           <= in_pllcfg_lf_res;
pllcfg_lf_cap           <= in_pllcfg_lf_cap;
m_odddiv                <= in_m_odddiv;
m_byp                   <= in_m_byp;
n_odddiv                <= in_n_odddiv;
n_byp                   <= in_n_byp;
c0_odddiv               <= in_c0_odddiv;
c0_byp                  <= in_c0_byp;
c1_odddiv               <= in_c1_odddiv;
c1_byp                  <= in_c1_byp;
c2_odddiv               <= in_c2_odddiv;
c2_byp                  <= in_c2_byp;
c3_odddiv               <= in_c3_odddiv;
c3_byp                  <= in_c3_byp;
c4_odddiv               <= in_c4_odddiv;
c4_byp                  <= in_c4_byp;
n_cnt                   <= in_n_cnt;
m_cnt                   <= in_m_cnt;
c0_cnt                  <= in_c0_cnt;
c1_cnt                  <= in_c1_cnt;
c2_cnt                  <= in_c2_cnt;
c3_cnt                  <= in_c3_cnt;
c4_cnt                  <= in_c4_cnt;
auto_phcfg_smpls        <= in_auto_phcfg_smpls;
auto_phcfg_step         <= in_auto_phcfg_step;

pllcfg_data_rev<=		  "00" & pllcfg_lf_cap & pllcfg_lf_res  & pllcfg_vcodiv  & "00000" & chp_curr &
	                     n_byp 		& n_cnt (15  downto 8) & --N
                        n_odddiv 	& n_cnt (7 downto 0) &
                        
                        m_byp 		& m_cnt (15  downto 8) & --M 
                        m_odddiv 	& m_cnt (7 downto 0) &
                        
                        c0_byp 		& c0_cnt (15 downto 8) & --c0
                      	c0_odddiv 	& c0_cnt (7  downto 0) &
                      	 
                      	c1_byp 		& c1_cnt (15 downto 8) & --c1
                       	c1_odddiv 	& c1_cnt (7  downto 0) & 
                        
                        c2_byp 		& c2_cnt (15 downto 8) & --c2
                        c2_odddiv 	& c2_cnt (7  downto 0) &
                        
                        c3_byp 		& c3_cnt (15 downto 8) & --c3
                        c3_odddiv 	& c3_cnt (7  downto 0) &
  
                        c4_byp 		& c4_cnt (15 downto 8) & --c4
                        c4_odddiv 	& c4_cnt (7  downto 0) ;
								
								
for_lop : for i in 0 to 143 generate
   pllcfg_data(i) <= pllcfg_data_rev(143-i);  
end generate;								
  
end arch;




