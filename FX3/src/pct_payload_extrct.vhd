-- ----------------------------------------------------------------------------	
-- FILE: 	pct_payload_extrct.vhd
-- DESCRIPTION:	extracts only data payload from stream packet
-- DATE:	June 17, 2016
-- AUTHOR(s):	Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------	
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity pct_payload_extrct is
	generic (data_w			: integer := 32;
				header_size		: integer := 16; --pct header size in bytes 
				pct_size			: integer := 4096 --pct size in bytes
		);
  port (
      --input ports 
		clk					: in std_logic;
		reset_n				: in std_logic;
		pct_data				: in std_logic_vector(data_w-1 downto 0);
		pct_wr				: in std_logic;
		pct_payload_data	: out std_logic_vector(data_w-1 downto 0);
		pct_payload_valid	: out std_logic;
		pct_payload_dest	: out std_logic_vector(1 downto 0)
	

      --output ports 
        
        );
end pct_payload_extrct;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of pct_payload_extrct is
--declare signals,  components here
signal wr_cnt : unsigned (15 downto 0);

signal hdr_payload_reg	: std_logic_vector(data_w-1 downto 0);
 
signal payload_dest_reg	: std_logic_vector(1 downto 0);
signal payload_size_reg	: std_logic_vector(15 downto 0);
-- last word index of the packet, registered: (payload_size + header_size)*8/data_w - 1.
-- It is computed from the header word captured at wr_cnt = 0 and is not used before
-- wr_cnt = 4 (payload valid) or the end of the packet (wr_cnt wrap); the combinational
-- version fed the FIFO write enable and was a failing sys-clock path.
signal last_word_reg		: unsigned(16 downto 0);
signal payload_valid_int	: std_logic;

  
begin

-- ----------------------------------------------------------------------------
-- Pcket write operation counter
-- ----------------------------------------------------------------------------
  process(reset_n, clk)
    begin
      if reset_n='0' then
        wr_cnt<=(others=>'0'); 
      elsif (clk'event and clk = '1') then
 	      if pct_wr='1' then	
				if wr_cnt < last_word_reg then 
					wr_cnt<=wr_cnt+1;
				else 
					wr_cnt<=(others=>'0');
				end if; 
			else 
				wr_cnt<=wr_cnt;
			end if;
 	    end if;
    end process;

-- ----------------------------------------------------------------------------
-- to capture header values
-- ----------------------------------------------------------------------------
  process(reset_n, clk)
    begin
		if reset_n='0' then
			hdr_payload_reg<=(others=>'1');
		elsif (clk'event and clk = '1') then
			if wr_cnt=0 and pct_wr='1' then 
				hdr_payload_reg<=pct_data;
			else 
				hdr_payload_reg<=hdr_payload_reg;
			end if;
		end if;
    end process;

payload_dest_reg<=hdr_payload_reg(6 downto 5);
payload_size_reg<=hdr_payload_reg(23 downto 8);

  process(reset_n, clk)
    begin
		if reset_n='0' then
			-- same value as derived from the reset header (all ones)
			last_word_reg <= to_unsigned((65535 + header_size)*8/data_w - 1, last_word_reg'length);
		elsif (clk'event and clk = '1') then
			last_word_reg <= to_unsigned((to_integer(unsigned(payload_size_reg))+header_size)*8/data_w - 1, last_word_reg'length);
		end if;
    end process;


-- ----------------------------------------------------------------------------
-- payload_wr signal process
-- ----------------------------------------------------------------------------
process (wr_cnt,last_word_reg, pct_wr)
begin 
		if wr_cnt>3 and wr_cnt<=last_word_reg then 
			payload_valid_int<= pct_wr;
		else 
			payload_valid_int<= '0';
		end if;		 
end process;

-- registered outputs (one cycle latency; there is no back-pressure on this stream)
  process(reset_n, clk)
    begin
		if reset_n='0' then
			pct_payload_valid <= '0';
			pct_payload_data  <= (others=>'0');
			pct_payload_dest  <= (others=>'0');
		elsif (clk'event and clk = '1') then
			pct_payload_valid <= payload_valid_int;
			pct_payload_data  <= pct_data;
			pct_payload_dest  <= payload_dest_reg;
		end if;
    end process;

end arch;   






