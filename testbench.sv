`timescale 1ps/1ps
////////////////////// Import DDR3 controller Package/////////////////////////////////////
import DDR3cont_pkg::*;

///////////////////// Randomization Class //////////////////////////////////////////////
class packet;

rand bit 	[ADDR_MCTRL-1:0] 	address;
randc bit 	[8*DQ_BITS-1:0]	 	data;

constraint addr_range{address inside {[0:(2**27)-1]};}
constraint data_range{data dist {[0:7*DQ_BITS-1]:= 5, [7*DQ_BITS:8*DQ_BITS-1] :/100};}

endclass

/////////////////////
class base;

rand packet pckt;

virtual cpu_cont_intf mem_vif;

function new(virtual cpu_cont_intf mem_vif);
this.mem_vif = mem_vif;
endfunction
 
logic [2**BA_BITS-1:0][8*DQ_BITS-1:0] memory_write = 
  {{4{16'h1403}},
   {4{16'h1225}}, 
   {16'bx}, 
   {4{16'h0876}},
   {4{16'h1025}}, 
   {4{16'h6512}}, 
   {4{16'h1385}}, 
   {4{16'h4213}}} ; // Data to be written

  logic [2**BA_BITS-1:0][8*DQ_BITS-1:0] memory_read;
  logic [8*DQ_BITS-1:0] data_read, data_read_1;

  logic [2**BA_BITS-1:0][ADDR_MCTRL-1:0] address = 
  {32'h00341c09, 
   32'h00931886, 
   32'h00901509, 
   32'h00101082, 
   32'h00998c02, 
   32'h00024882, 
   32'h00e1040f, 
   32'h00404282};


    logic [8*DQ_BITS-1:0] random_data;

//=======================Reset task=====================================//  
task reset();
	mem_vif.Reset();
endtask:reset

//=======================Writing to some directed address===============//
task random_writing();
	mem_vif.Write(address[7], memory_write[7]);
	mem_vif.Write(address[6], memory_write[6]);
	mem_vif.Write(address[5], memory_write[5]);
	mem_vif.Write(address[4], memory_write[4]);
	$display("************************Random writing task complete************************");
endtask:random_writing

//=======================Reading from the previously written addresses with out self checking==========//
task random_reading();
	mem_vif.Read(address[7], data_read);
	mem_vif.Read(address[6], data_read);
	mem_vif.Read(address[5], data_read);
	mem_vif.Read(address[4], data_read);
	$display("************************Random reading task complete************************");
endtask:random_reading

//=====================Directed tests==============================//
task directed_test();
    // Simple data write and read to a particular address
	mem_vif.Write(address[1], memory_write[1]);
	mem_vif.Read(address[1], data_read);						
	if ($isunknown(data_read[63:0]))
		$warning("*****************Data read is unknown********************");
	else begin
	assert(memory_write[1] === data_read)
		$display("***********************Scenario 1: Simple Data write and read----Data read has matched with the Data written************************");
	else
		$error("*************************Scenario 1: Corrupt data read************************");
	end
	
	// Overwrite data on the same address
	mem_vif.Write(address[6], memory_write[7]);
	mem_vif.Write(address[6], memory_write[6]);					
	mem_vif.Read(address[6], data_read);
	assert (!$isunknown(data_read[63:0]))
	else	$warning("*****************Data read is unknown********************");
	assert(memory_write[6] == data_read)
		$display("*************************Scenario 2: Overwrite data on the same address----Data read has matched with the Data written************************");
	else
		$error("************************Scenario 2: Corrupt data read************************");
	
	// Consecutive Reads from the same address
	mem_vif.Read(address[7], data_read);
	mem_vif.Read(address[7], data_read_1);						
	assert (!$isunknown(data_read[63:0]))
	else	$warning("*****************Data read is unknown********************");
	assert(data_read_1 == data_read)
		$display("*****************************Scenario 3: Consecutive Reads to the Same address : Succesfull************************");
	else
		$error("*******************************Scenario 3:Consecutive Reads to the Same address : Failed************************");
	
	// Consecutive Reads from the same address which is not written
	mem_vif.Read(address[2], data_read);
	mem_vif.Read(address[2], data_read_1);						
	assert($isunknown({data_read,data_read_1}))
	else	$warning("Simulation issues");
	assert(data_read_1 === data_read)
		$display("*****************************Scenario 4: Consecutive Reads to the Same address which is not writen before are resulting in x************************");
	else
		$error("*******************************Scenario 4:Consecutive Reads to the Same address which is not writen before : Failed************************");
	
	// Writing Unknown values to a address and reading it 
	mem_vif.Write(address[0], memory_write[2]);
	mem_vif.Read(address[0], data_read);
    $display("__________________Data Read = %d____________",data_read);	
	assert($isunknown({data_read,data_read_1})) $display("************************** Succesfull**************");
	else	$warning("Simulation issues");
	assert(data_read === memory_write[2])
		$display("*****************************Scenario 4: Consecutive Reads to the Same address which is not writen before are resulting in x************************");
	else
		$error("*******************************Scenario 4:Consecutive Reads to the Same address which is not writen before : Failed************************");
	
	
	// Same row, different column
	mem_vif.Write(32'h00341cf9, memory_write[2]);				
	mem_vif.Read(32'h00341cf9, data_read);
	assert(!$isunknown(data_read[63:0]))
	else	$warning("*****************Data read is unknown********************");
	assert(memory_write[2] === data_read)
		$display("**********************Scenario 5: Same row , Different column----Data read has matched with the Data written************************");
	else
		$error("************************Scenario 5: Corrupt data read************************");
	
	// Different row, same bank
	mem_vif.Write(32'h00e41cf9, memory_write[2]);				
	mem_vif.Read(32'h00e41cf9, data_read);
	assert(!$isunknown(data_read[63:0]))
	else $warning("*****************Data read is unknown********************");
	assert(memory_write[2] === data_read)
		$display("**********************Scenario 6: Same bank, Different row ----Data read has matched with the Data written************************");
	else
		$error("**********************Scenario 6: Corrupt data read************************");
	
endtask:directed_test

task consecutive_addresses();	
	logic [ADDR_MCTRL-1:0] base_address = 32'h00000000;  
	logic [ADDR_MCTRL-1:0] start_address, actual_address;
	logic [8*DQ_BITS-1:0] read_data;
	
	for (int j=0; j<4; j++)
	begin
		start_address = {base_address[31:15],j[1:0],base_address[12:0]};
		for (int i=0;i<(2**(COL_BITS-3));i++)
		begin 
			random_data = $urandom;
			actual_address = {start_address[31:10],i[6:0],start_address[2:0]};
			mem_vif.Write(actual_address, random_data);   
			mem_vif.Read(actual_address, read_data);
				assert(!$isunknown(data_read[63:0]))
		        else $warning("*****************Data read is unknown********************");
				assert (random_data === read_data)
					$display("********************************Scenario 7: Same row, Consecutive Columns ----Data read has matched with the Data written************************");
				else
					$error("**********************************Scenario 7: Corrupt data read************************");
		end	
		$display("Row %0d access done", j);
	end
endtask:consecutive_addresses

task write_b();
    // Single write to every bank
	for (int i=0;i<(2**BA_BITS);i++)
	begin 
	mem_vif.Write(address[i], memory_write[i]);
	end	
endtask:write_b

task read_b();
    // Read from the written addresses
	for (int i=0;i<(2**BA_BITS);i++)
	begin
	mem_vif.Read(address[i], memory_read[i]);
    assert (!$isunknown(data_read[63:0]))
	else	$warning("*****************Data read is unknown********************");	
	end
endtask:read_b

task compare_b();
	assert(memory_read === memory_write)
		$display("********************************Scenario 8:Data read from all banks has matched with the Data written to all banks************************");
	else 
		$error("*********************************Scenario 8:Corrupt data read from one or more banks************************");
endtask:compare_b

task random_methods();
    logic [8*DQ_BITS-1:0] read_data_random;
	int check = 0;
	
	repeat(10) begin
      pckt = new();
	  if(!pckt.randomize()) $fatal("************************Randomization failed************************");
	  mem_vif.Write(pckt.address, pckt.data);
      mem_vif.Read(pckt.address, read_data_random);
	  assert (!$isunknown(read_data_random[63:0]))
	  else $warning("*****************Data read is unknown********************");
	
	  if(pckt.data == read_data_random)
	   check = check;
	  else
	   check++;
	end
	
	assert(!check)
	  $display("***********************Scenario 9:Correctly read the data written from the randomly generated addresses ***********************");
	else
	  $display("***********************Scenario 9:Randomization Error: Data read from the randomly generated address is not matched with the data written***********************");

endtask:random_methods

task run();
    reset();
    random_writing();           // writing random values to memory model
    random_reading();           // reading the same random values
	directed_test();			// Directed test cases
	consecutive_addresses();	// Write and Read from continuous addresses
	write_b();   				// Single write to every bank
	read_b();					// Read from the written addresses 
	compare_b();	            // Self check to verify written and read data
	random_methods();           // Randomization
endtask:run

endclass:base

/////////////////////////////// My test Program///////////////////////////////////
program my_test(cpu_cont_intf intf);

  //declaring base class instance
  base bs;
   
  initial begin
    bs = new(intf);
    bs.run();
  end
  
endprogram:my_test


////////////////// Top Module ///////////////////////////////
module top();

parameter tck = 2500/2;
parameter ps = 2500/4;
logic i_cpu_ck=1;
logic i_cpu_ck_ps=1;


//===================== Clock Generation========================================================
    // clock generator
    always i_cpu_ck = #tck ~i_cpu_ck;
	always i_cpu_ck_ps = #ps i_cpu_ck;
	

//===================== Interface Instance =====================================================
	cpu_cont_intf cpu_contr(
						.i_cpu_ck(i_cpu_ck)					// Instance of CPU-CONTR Interface
					  );					

	cont_bfm_intf contr_mem(
					  .i_cpu_ck(i_cpu_ck)					// Instance of CONTR-MEM Interface
					);
	

//======================= Controller Instance====================================================
	DDR3_Controller	DDR3(
						  .i_cpu_ck(i_cpu_ck),				// System Clock
					      .i_cpu_ck_ps(i_cpu_ck_ps),
						  .MDPRT_CPU_TO_CONT(cpu_contr.cpu_to_cont_mdprt),			// CPU-CONTR ports
					      .MDPRT_CONT_TO_BFM(contr_mem.cont_to_bfm_mdprt));			// CONTR-MEM ports	

//======================Memory Instance===========================================================

	ddr3 dd3_model (
		.MDPRT_BFM_TO_CONT(contr_mem.bfm_to_cont_mdprt) 	
	);


my_test t1(cpu_contr);

endmodule:top
