vlib work
vdel -all
vlib work

vlog 1024Mb_ddr3_parameters.sv +acc
vlog DDR3_Mem_Cont_pkg.sv +acc

vlog ddr3.sv +acc

vlog Write_Burst.sv +acc
vlog Counter.sv +acc
vlog Read_Burst.sv +acc

vlog DDR3_Mem_Cont.sv +acc
vlog interface.sv +acc

vlog testbench.sv +acc

vsim -voptargs=+acc work.top

run -all