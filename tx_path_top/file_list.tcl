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
   $script_path/src/pct2data_buf_rd.vhd    \
   $script_path/src/pct2data_buf_wr.vhd    \
   $script_path/src/sample_unpack.vhd      \
   $script_path/src/tx_path_top.vhd        \
   $script_path/src/tx_top_pkg.vhd         \
   $script_path/srv/sample_padder.vhd      \
]


##################################################################
# Simulation files
##################################################################
set SIM_SRC [list \
   $script_path/src/tx_top_tb.vhd        \
]


##################################################################
# IP cores
##################################################################
set IP [list \
]

