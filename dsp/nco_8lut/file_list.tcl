puts file_list
set script_path [file dirname [file normalize [info script]]]
puts $script_path


##################################################################
# Dependencies
##################################################################
set DEP_MODULES [list \
]

set DEP_FILES [ list \
]


##################################################################
# Synthesis files
##################################################################
set SYNTH_SRC [list \
   $script_path/src/bcla4b.vhd       \
   $script_path/src/nco_8lut.vhd     \
]


##################################################################
# Simulation files
##################################################################
set SIM_SRC [list \
   $script_path/src/nco_8lut_tb.vhd   \
]


##################################################################
# IP cores
##################################################################
set IP [list \
]

