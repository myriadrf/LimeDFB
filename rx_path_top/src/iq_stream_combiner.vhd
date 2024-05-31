-- ----------------------------------------------------------------------------
-- FILE:          iq_stream_combiner.vhd
-- DESCRIPTION:   Combines IQ samples into one bus
-- DATE:          15:11 2024-05-27
-- AUTHOR(s):     Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NOTES:
-- s_axis interfaface is always ready to accept data thus s_axis_tready is connected 
-- to reset_n
--
-- m_axis interface is unable to accept-backpressure. There is no need for it as 
-- this module is designed for continous data stream
-- ----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity iq_stream_combiner is
   port (
      clk               : in  std_logic;
      reset_n           : in  std_logic;   
      s_axis_tvalid     : in  std_logic;
      s_axis_tready     : out std_logic;
      s_axis_tdata      : in  std_logic_vector(63 downto 0);
      s_axis_tkeep      : in  std_logic_vector(7 downto 0);
      m_axis_tvalid     : out std_logic;  
      m_axis_tdata      : out std_logic_vector(63 downto 0);
      m_axis_tkeep      : out std_logic_vector(7 downto 0)
   );
end iq_stream_combiner;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of iq_stream_combiner is
--declare signals,  components here

signal s_axis_tready_reg   : std_logic;
signal m_axis_tdata_reg    : std_logic_vector(s_axis_tdata'LENGTH -1 downto 0);
signal m_axis_tvalid_reg   : std_logic_vector(1 downto 0);

begin

-- ----------------------------------------------------------------------------
-- Combining data bytes into m_axis_tdata bus register
-- ----------------------------------------------------------------------------
   process(clk, reset_n)
   begin 
      if reset_n = '0' then 
         m_axis_tdata_reg <= (others=>'0');
      elsif rising_edge(clk) then 
         if s_axis_tvalid = '1' then
            if s_axis_tkeep = x"FF" then 
               m_axis_tdata_reg <= s_axis_tdata;
            elsif s_axis_tkeep = x"0F" then 
               m_axis_tdata_reg <= m_axis_tdata_reg(31 downto 0) & s_axis_tdata(31 downto 0);
            elsif s_axis_tkeep = x"F0" then
               m_axis_tdata_reg <= m_axis_tdata_reg(31 downto 0) & s_axis_tdata(63 downto 32);
            else 
               m_axis_tdata_reg <= m_axis_tdata_reg;
            end if;
         else 
            m_axis_tdata_reg <= m_axis_tdata_reg;
         end if;
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- m_axis_tvalid signal asserted when all m_axis_tdata bytes are combined
-- ----------------------------------------------------------------------------   
   process(clk, reset_n)
   begin 
      if reset_n = '0' then 
         m_axis_tvalid_reg <= (others=>'0');
      elsif rising_edge(clk) then
         if s_axis_tvalid = '1' then
            if s_axis_tkeep = x"FF" then
               m_axis_tvalid_reg <= "11";
            elsif s_axis_tkeep = x"0F"  OR  s_axis_tkeep = x"F0" then
               if m_axis_tvalid_reg = "11" then 
                  m_axis_tvalid_reg <= '0' & '1';
               else 
                  m_axis_tvalid_reg <= m_axis_tvalid_reg(0) & '1';
               end if;
            else 
               m_axis_tvalid_reg <= m_axis_tvalid_reg(0) & '0';
            end if;
         elsif  m_axis_tvalid_reg = "11" then 
            m_axis_tvalid_reg <= (others=>'0');
         else 
            m_axis_tvalid_reg <= m_axis_tvalid_reg;
         end if;
      end if;
   end process;
   
   
   
   process(clk, reset_n)
   begin
      if reset_n = '0' then 
         s_axis_tready_reg<= '0';
      elsif rising_edge(clk) then 
         s_axis_tready_reg <= '1';
      end if;
   end process;
   
-- ----------------------------------------------------------------------------
-- Output ports
-- ----------------------------------------------------------------------------
   s_axis_tready  <= s_axis_tready_reg;
   
   m_axis_tvalid  <= m_axis_tvalid_reg(1);
   m_axis_tdata   <= m_axis_tdata_reg;
   m_axis_tkeep   <= (others=>'1');
   
   
   
   

  
end arch;   


