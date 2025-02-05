puts file_list
set script_path [file dirname [file normalize [info script]]]
puts $script_path


##################################################################
# Dependencies
##################################################################
set DEP_MODULES [list \
   cdc         \
]

set DEP_FILES [ list \

]


##################################################################
# Synthesis files
##################################################################
set SYNTH_SRC [list \
   $script_path/src/rptr_handler.sv       \
   $script_path/src/wptr_handler.sv       \
   $script_path/src/xilinx_simple_dual_port_2_clock_ram.vhd \
   $script_path/src/ram_mem_wrapper.vhd   \
   $script_path/src/axis_fifo.vhd         \
]


##################################################################
# Simulation files
##################################################################
set SIM_SRC [list \
   $script_path/src/axis_fifo_tb.vhd    \
]


##################################################################
# IP cores
##################################################################
set IP [list \
]

