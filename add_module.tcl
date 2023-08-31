# #################################################################
# FILE:          add_module.tcl
# DESCRIPTION:   Script to add LimeIP-HDL module
# DATE:          15:06 2023-07-03
# AUTHOR(s):     Lime Microsystems
# REVISIONS:
# #################################################################

# #################################################################
# NOTES:
# This script adds files from file_list.tcl file to project. 
# 
# #################################################################

source [file join [file dirname [info script]] "file_list.tcl"]

puts "Dependencies"
foreach module $DEP_MODULES {
   puts $module
   source [file join [file dirname [info script]] "../$module/add_module.tcl"]
}

foreach file $DEP_FILES {
   puts $file
   add_files $file
}

puts "Sourcing SYNTH SRC"
foreach file $SYNTH_SRC {
   puts $file
   add_files $file
}

puts "Sourcing SIM SRC"
foreach file $SIM_SRC {
   puts $file
   add_files -fileset sim_1 $file
}

puts "Sourcing IP"
foreach file $IP {
   puts $file
   source [file join [file dirname [info script]] $file]
}