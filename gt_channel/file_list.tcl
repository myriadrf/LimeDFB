puts file_list
set script_path [file dirname [file normalize [info script]]]
puts $script_path


##################################################################
# Dependencies
##################################################################
set DEP_MODULES [list \
   fifo_axis
]

set DEP_FILES [ list \
]


##################################################################
# Synthesis files
##################################################################
set SYNTH_SRC [list \
   $script_path/src/aurora_8b10b_wrapper.vhd \
   $script_path/src/aurora_nfc_gen.vhd       \
   $script_path/src/aurora_top.vhd           \
   $script_path/src/aurora_ufc_reg_send.vhd  \
   $script_path/src/ctrl_pkt.vhd             \
   $script_path/src/data_pkt.vhd             \
   $script_path/src/gt_channel_top.vhd       \
   $script_path/src/gt_reset.vhd             \
   $script_path/src/gt_rx_decoder.vhd        \
   $script_path/src/gt_tx_encoder.vhd        \
   $script_path/src/pkg_functions.vhd        \
   $script_path/src/rx_decoder.vhd           \
]


##################################################################
# Simulation files
##################################################################
set SIM_SRC [list \
   $script_path/src/gt_reset_tb.vhd          \
   $script_path/src/gt_txrx_encoder_tb.vhd   \
]


##################################################################
# IP cores
##################################################################
set IP [list \
   $script_path/ip/aurora_8b10b_0/aurora_8b10b_0.tcl                 \
   $script_path/ip/axis_dwidth_128_to_32/axis_dwidth_128_to_32.tcl   \
   $script_path/ip/axis_dwidth_128_to_512/axis_dwidth_128_to_512.tcl \
   $script_path/ip/axis_dwidth_32_to_128/axis_dwidth_32_to_128.tcl   \
   $script_path/ip/axis_interconnect_0/axis_interconnect_0.tcl       \
]

