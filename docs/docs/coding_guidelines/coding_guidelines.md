# HDL Coding Guidelines


##  Introduction

The purpose of this document is to establish 
a set of rules that specify the layout, naming conventions and some general 
coding practices for the HDL modules implementation.

If supported by the tools it is prefered to use **VHDL-2008** language version.  

A configuration file for VHDL VSG can be found in Annex 3.
In the event of any discrepancies between the VSG config and guidelines described herein,
the guidelines take precedence.

## 1. Layout

- **Indentation** - spaces must be used insted of tabs (Tab size: 3)
- **White spaces** before and after operators such as =, +, etc.

    #### Example:
    ```vhdl
    if a < cnt then 
       a <= a + 1;
    else 
       a <= a;
    end if;
    ```
- **Aligment** should be used in declarations, assignments, multi-line statements, and end of line comments.

    #### Example:
    ```vhdl
    signal axi_write_cnt  : unsigned(7 downto 0); --Write counter
    signal axi_read_cnt   : unsigned(7 downto 0); --Read counter
    ```

## 2. Naming Conventions

- **All names** must be written in English.
- **Generics** should be uppercase and start with **g_***
    #### Example: 
    ```vhdl
    g_DATA_WIDTH   : integer := 12
    ```
- **Constants** should be uppercase and start with **c_***
    #### Example: 
    ```vhdl
    constant c_AXI_LITE_DATA_WIDTH   : integer := 32;
    ```
- **User defined types** should be uppercase and start with **t_***
    #### Example: 
    ```vhdl
    type t_ERR_COUNT is array (0 to 3) of std_logic_vector(7 downto 0);
    ```
- **Resets** - active hight reset should be named **reset** or **rst**, active low resets - **reset_n** or **rst_n**

- **Clocks** - single clock domain modules should use **clk** name for clock, multiple domain modules should have domain name and ***_clk** ending. 

## 3. Packages and libraries

Default libraries to use:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
```

## 3. Annexes
### Annex 1: VHDL module template
[my_module.vhd](./my_module.rst)

### Annex 2: VHDL testbench template
[my_module_tb.vhd](./my_module_tb.rst)

### Annex 3: Configuration file for VHDL VSG
[vhdl_vsg_cfg.yml](./vhdl_vsg_cfg.rst)



