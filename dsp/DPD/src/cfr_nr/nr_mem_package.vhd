-- ----------------------------------------------------------------------------	
-- FILE:	nr_mem_package.vhd
-- DESCRIPTION:	Define subtypes and types used in constructing memory arrays.
-- DATE:
-- AUTHOR(s):
-- REVISIONS:
-- ----------------------------------------------------------------------------	

-- ----------------------------------------------------------------------------
library ieee; 
use ieee.std_logic_1164.all;

package nr_mem_package is 
	SUBTYPE mword16 IS STD_LOGIC_VECTOR(15 DOWNTO 0);
    SUBTYPE mword18 IS STD_LOGIC_VECTOR(17 DOWNTO 0);
    SUBTYPE mword25 IS STD_LOGIC_VECTOR(24 DOWNTO 0);
    SUBTYPE mword26 IS STD_LOGIC_VECTOR(25 DOWNTO 0);
    SUBTYPE mword36 IS STD_LOGIC_VECTOR(35 DOWNTO 0);
    TYPE marray32x25 IS ARRAY (31 DOWNTO 0) OF mword25;
    TYPE marray16x26 IS ARRAY (15 DOWNTO 0) OF mword26;
    TYPE marray8x26 IS ARRAY (7 DOWNTO 0) OF mword26;
    TYPE marray4x26 IS ARRAY (3 DOWNTO 0) OF mword26;
    TYPE marray2x26 IS ARRAY (1 DOWNTO 0) OF mword26;
    TYPE marray16x36 IS ARRAY (15 DOWNTO 0) OF mword36;
    TYPE marray16x18 IS ARRAY (15 DOWNTO 0) OF mword18;
    TYPE marray16x16 IS ARRAY (15 DOWNTO 0) OF mword16;
    TYPE marray32x16 IS ARRAY (31 DOWNTO 0) OF mword16;
end nr_mem_package;

