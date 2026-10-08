set root [file dirname [file normalize [info script]]]
cd $root
create_project pbl2_sim $root/vivado -part xc7z020clg484-1 -force
add_files [glob $root/rtl/*.v]
add_files -fileset sim_1 [list $root/tb/tb_rv64.v $root/program.hex]
set_property top tb_rv64 [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
