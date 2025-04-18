-- ----------------------------------------------------------------------------	
-- FILE:    sample_padder.vhd
-- DESCRIPTION:	pads 12 bit samples to 16 bit format
-- DATE:	April 18, 2025
-- AUTHOR(s):	Lime Microsystems
-- REVISIONS:
-- ----------------------------------------------------------------------------	
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
-- Entity declaration
-- ----------------------------------------------------------------------------
entity sample_padder is
  port (
      --input ports 
      CLK       		: in  std_logic;
      RESET_N   		: in  std_logic;
		--
		S_AXIS_TVALID  : in  std_logic;
		S_AXIS_TDATA   : in  std_logic_vector(127 downto 0);
		S_AXIS_TREADY  : out std_logic;
		S_AXIS_TLAST	: in  std_logic;
		--
		M_AXIS_TDATA   : out std_logic_vector(127 downto 0);
		M_AXIS_TVALID  : out std_logic;
		M_AXIS_TREADY  : in  std_logic;
		M_AXIS_TLAST	: out std_logic;
		--
		BYPASS			: in std_logic
      );
end sample_padder;

-- ----------------------------------------------------------------------------
-- Architecture
-- ----------------------------------------------------------------------------
architecture arch of sample_padder is

   type t_array_3x128 is array (0 to 2) of std_logic_vector(127 downto 0);
   type t_array_4x128 is array (0 to 3) of std_logic_vector(127 downto 0);

   signal in_shift_reg  : t_array_3x128;
   signal out_shift_reg : t_array_4x128;

   signal in_shift_cnt      : unsigned(3 downto 0);
   signal in_shift_reg_full : std_logic;

   signal out_reg_load           : std_logic;
   signal out_reg_load_ack       : std_logic;
   signal out_reg_empty          : std_logic;
   signal out_reg_almost_empty   : std_logic; 
	signal out_reg_shift_cnt      : unsigned(3 downto 0);

begin


   -- ----------------------------------------------------------------------------
   -- Input shift register, for storing incoming data
   -- ----------------------------------------------------------------------------
   -- Combinational flags for input buffer
   in_shift_reg_full <= '1' when in_shift_cnt >= 3 else '0';

   -- Input buffer
   process (CLK, RESET_N)
   begin
      if RESET_N = '0' then
         in_shift_reg <=(others=>(others=>'0'));
      elsif rising_edge(CLK) then
         if in_shift_reg_full ='0' AND S_AXIS_TVALID = '1' then 
            in_shift_reg(0) <= S_AXIS_TDATA;
            in_shift_reg(1) <= in_shift_reg(0);
            in_shift_reg(2) <= in_shift_reg(1);
         end if;
      end if;
   end process;

   -- Counter for input buffer to determine when it is full. 
	-- Counter is reset to 0 when content from input reg is loaded to output reg
   process (CLK, RESET_N)
   begin
      if RESET_N = '0' then
         in_shift_cnt      <= (others=>'0');
      elsif rising_edge(CLK) then
         if in_shift_reg_full ='0' AND S_AXIS_TVALID = '1' then 
            in_shift_cnt <= in_shift_cnt + 1;
         else 
            if out_reg_load_ack = '1' then 
               in_shift_cnt <= (others=>'0');
            else 
               in_shift_cnt <= in_shift_cnt;
            end if;
         end if;
      end if;
   end process;

   
   -- ----------------------------------------------------------------------------
   -- Output shift register, for storing outgoing data
   -- ----------------------------------------------------------------------------
   -- Combinational flags for output buffer
   out_reg_empty        <= '0' when out_reg_shift_cnt > 0 else '1';
   out_reg_almost_empty <= '1' when out_reg_shift_cnt = 1 and M_AXIS_TREADY = '1' else '0';
   out_reg_load_ack     <= out_reg_load AND (out_reg_almost_empty OR out_reg_empty);


   --Counter for output buffer to determine almost empty/empty states
	--Counter is set to 4 words when output register is loaded
   process (CLK, RESET_N)
   begin
      if RESET_N = '0' then
         out_reg_shift_cnt <= (others=>'0');
      elsif rising_edge(CLK) then
         if out_reg_load_ack = '1' then 
            out_reg_shift_cnt <= x"4";
         else 
            if M_AXIS_TREADY = '1' AND out_reg_shift_cnt > 0 then
               out_reg_shift_cnt <= out_reg_shift_cnt - 1;
            end if;
         end if;
      end if;
   end process;

   
   -- Output buffer load request signal
   process (CLK, RESET_N)
   begin
      if RESET_N = '0' then
         out_reg_load <= '0';
      elsif rising_edge(CLK) then

         if S_AXIS_TVALID = '1' and in_shift_cnt = 2 then 
            out_reg_load <= '1';
         elsif out_reg_load_ack = '1' then 
            out_reg_load <= '0';
         else 
            out_reg_load <= out_reg_load;
         end if;

      end if;
   end process;


   -- Output buffer where samples are padded and shifted out
   process (CLK, RESET_N)
   begin
      if RESET_N = '0' then
         out_shift_reg <=(others=>(others=>'0'));
      elsif rising_edge(CLK) then
         if (out_reg_load = '1' AND (out_reg_almost_empty='1' OR out_reg_empty='1')) then 

            out_shift_reg(3)(127 downto 112) <= in_shift_reg(2)(95  downto 84 ) & "0000";
				out_shift_reg(3)(111 downto 96 ) <= in_shift_reg(2)(83  downto 72 ) & "0000";
				out_shift_reg(3)(95  downto 80 ) <= in_shift_reg(2)(71  downto 60 ) & "0000";
				out_shift_reg(3)(79  downto 64 ) <= in_shift_reg(2)(59  downto 48 ) & "0000";
				out_shift_reg(3)(63  downto 48 ) <= in_shift_reg(2)(47  downto 36 ) & "0000";
				out_shift_reg(3)(47  downto 32 ) <= in_shift_reg(2)(35  downto 24 ) & "0000";
				out_shift_reg(3)(31  downto 16 ) <= in_shift_reg(2)(23  downto 12 ) & "0000";
				out_shift_reg(3)(15  downto 0  ) <= in_shift_reg(2)(11  downto 0  ) & "0000";

				out_shift_reg(2)(127 downto 112) <= in_shift_reg(1)(63  downto 52 ) & "0000";
				out_shift_reg(2)(111 downto 96 ) <= in_shift_reg(1)(51  downto 40 ) & "0000";
				out_shift_reg(2)(95  downto 80 ) <= in_shift_reg(1)(39  downto 28 ) & "0000";
				out_shift_reg(2)(79  downto 64 ) <= in_shift_reg(1)(27  downto 16 ) & "0000";
				out_shift_reg(2)(63  downto 48 ) <= in_shift_reg(1)(15  downto 4  ) & "0000";
				out_shift_reg(2)(47  downto 32 ) <= in_shift_reg(1)(3   downto 0  ) & in_shift_reg(2)(127 downto 120) & "0000";
				out_shift_reg(2)(31  downto 16 ) <= in_shift_reg(2)(119 downto 108) & "0000";
				out_shift_reg(2)(15  downto 0  ) <= in_shift_reg(2)(107 downto 96 ) & "0000";

				out_shift_reg(1)(127 downto 112) <= in_shift_reg(0)(31  downto 20 ) & "0000";
				out_shift_reg(1)(111 downto 96 ) <= in_shift_reg(0)(19  downto 8  ) & "0000";
				out_shift_reg(1)(95  downto 80 ) <= in_shift_reg(0)(7   downto 0  ) & in_shift_reg(1)(127 downto 124) & "0000";
				out_shift_reg(1)(79  downto 64 ) <= in_shift_reg(1)(123 downto 112) & "0000";
				out_shift_reg(1)(63  downto 48 ) <= in_shift_reg(1)(111 downto 100) & "0000";
				out_shift_reg(1)(47  downto 32 ) <= in_shift_reg(1)(99  downto 88 ) & "0000";
				out_shift_reg(1)(31  downto 16 ) <= in_shift_reg(1)(87  downto 76 ) & "0000";
				out_shift_reg(1)(15  downto 0  ) <= in_shift_reg(1)(75  downto 64 ) & "0000";
			
				out_shift_reg(0)(127 downto 112) <= in_shift_reg(0)(127 downto 116) & "0000";
				out_shift_reg(0)(111 downto 96 ) <= in_shift_reg(0)(115 downto 104) & "0000";
				out_shift_reg(0)(95  downto 80 ) <= in_shift_reg(0)(103 downto 92 ) & "0000";
				out_shift_reg(0)(79  downto 64 ) <= in_shift_reg(0)(91  downto 80 ) & "0000";
				out_shift_reg(0)(63  downto 48 ) <= in_shift_reg(0)(79  downto 68 ) & "0000";
				out_shift_reg(0)(47  downto 32 ) <= in_shift_reg(0)(67  downto 56 ) & "0000";
				out_shift_reg(0)(31  downto 16 ) <= in_shift_reg(0)(55  downto 44 ) & "0000";
				out_shift_reg(0)(15  downto 0  ) <= in_shift_reg(0)(43  downto 32 ) & "0000";
         else 
            if M_AXIS_TREADY = '1' and out_reg_empty = '0' then
               out_shift_reg(0) <= (others=>'0');
               out_shift_reg(1) <= out_shift_reg(0);
               out_shift_reg(2) <= out_shift_reg(1);
               out_shift_reg(3) <= out_shift_reg(2);
            end if;
         end if;
      end if;
   end process;


   -- ----------------------------------------------------------------------------
   -- Output ports
   -- ----------------------------------------------------------------------------
   S_AXIS_TREADY <= not in_shift_reg_full when BYPASS = '0' else M_AXIS_TREADY;
   M_AXIS_TVALID <= not out_reg_empty     when BYPASS = '0' else S_AXIS_TVALID;
   M_AXIS_TDATA  <= out_shift_reg(3)      when BYPASS = '0' else S_AXIS_TDATA;
	M_AXIS_TLAST  <= '0' 						when BYPASS = '0' else S_AXIS_TLAST;




end arch;   



