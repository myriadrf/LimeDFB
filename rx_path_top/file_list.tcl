puts file_list
set script_path [file dirname [file normalize [info script]]]
puts $script_path


##################################################################
# Dependencies
##################################################################
set DEP_MODULES [list \
   fifo_axis   \
]

set DEP_FILES [ list \
   $script_path/../axis/src/axis_pkg.vhd \
]


##################################################################
# Synthesis files
##################################################################
set SYNTH_SRC [list \
   $script_path/src/axis_nto1_converter.vhd   \
   $script_path/src/bit_pack.vhd              \
   $script_path/src/data2packets_fsm.vhd      \
   $script_path/src/iq_stream_combiner.vhd    \
   $script_path/src/pack_48_to_64.vhd         \
   $script_path/src/pack_56_to_64.vhd         \
   $script_path/src/rx_path_top.vhd           \

   
   
   
]


##################################################################
# Simulation files
##################################################################
set SIM_SRC [list \
   $script_path/src/rx_path_top_tb.vhd        \
]


##################################################################
# IP cores
##################################################################
set IP [list \
]

