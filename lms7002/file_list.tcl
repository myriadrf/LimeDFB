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
   $script_path/../spicfg/src/fpgacfg_pkg.vhd \
   $script_path/../spicfg/src/memcfg_pkg.vhd  \
   $script_path/../spicfg/src/tstcfg_pkg.vhd  \
]


##################################################################
# Synthesis files
##################################################################
set SYNTH_SRC [list \
   $script_path/src/lms7002_top.vhd       \
   $script_path/src/lms7002_tx.vhd        \
   $script_path/src/lms7002_rx.vhd        \
   $script_path/src/lms7002_ddout.vhd     \
   $script_path/src/lms7002_ddin.vhd      \
   $script_path/src/smpl_cmp.vhd          \
   $script_path/src/txiq_tst_ptrn.vhd     \
]


##################################################################
# Simulation files
##################################################################
set SIM_SRC [list \
   $script_path/src/lms7002_top_tb.vhd    \
]


##################################################################
# IP cores
##################################################################
set IP [list \
]

