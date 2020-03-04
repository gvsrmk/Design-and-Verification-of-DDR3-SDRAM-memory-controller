/***************************************************************************************************************************
*
*    File Name:  DDR3controller.sv
*
* Dependencies:  DDR3controller_package.sv (package defining parameters and states for FSM in the controller)
*				 ddr3.sv (Memory Model)
*
*  Description:   Memory controller for Micron SDRAM DDR3-800 (Double Data Rate 3)
*
*   Functions :  - Performs following operations : 
*
*				   - POWERUP SEQUENCE, ZQ CALIBRATION, MODE REGISTER LOAD
*				   - ACTIVATE , WRITE, READ (Burst mode), PRECHARGE.
*				   - Works according to the timing specification followed by the memory model.
*				   - Timing specs : 6-6-6.

*****************************************************************************************************************************/

//===================================== PACKAGE IMPORT========================================================================
import DDR3cont_pkg::* ;


//===================================== MODULE DECLARATION ===================================================================
module DDR3_Controller (
	input logic            i_cpu_ck   ,							// Main system clock 
	input logic            i_cpu_ck_ps,							// 90degree phase shifted clock
	cpu_cont_intf.cpu_to_cont_mdprt    MDPRT_CPU_TO_CONT,		// Port in controller of type cpu_cont_intf.cpu_to_cont_mdprt
	cont_bfm_intf.cont_to_bfm_mdprt    MDPRT_CONT_TO_BFM		// Port in controller of type cont_bfm_intf.cont_to_bfm_mdprt
);


//===================================== LOCAL VARIABLES=======================================================================

	logic  [31:0] v_count                       ;	// Internal counter variable			
	logic  [31:0] max_count                = 'd0;   // variable to assign max count
	logic  [ 0:0] rst_counter              = 'd0;	// Reset counter variable
	logic         rw_flag,timer_intr            ;	// Flags for R/W and  Timer Interrupt
	logic         t_flag                        ;	// Timer Flag


	logic         dqs_valid                     ;	// DQS valid signal 
	bit           t_dqs_flag,t_dqsn_flag        ;   // internal flags for DQS and DQSN strobe


	logic  [15:0] wdata              [3:0]      ;	// 16 bit Write data
	logic  [15:0] rdata              [3:0]      ;	// 16 bit read data

	logic  [ 7:0] t_dq_local                    ;	//8-bit data coming from Write burst after output valid


	logic  [15:0] wdata_local                   ;	// Local variable for write data
	logic  [15:0] rdata_local                   ;	// Local variable for read data


	logic         en                            ;	// Internal enable signeal


	logic  [31:0] s_addr                        ;	// 27 bit address variable
	logic  [63:0] s_data                        ;	// 64 bit data variable


	logic         s_valid_data_read             ;	// DAta valid during read

	logic  [ 7:0] temp1, temp2                  ;

	logic  [63:0] s_cpu_rd_data                 ;	// internal variable for CPU read operation 
	logic  [63:0] cpu_rd_data                   ;	
	logic         s_cpu_rd_data_valid           ;	// Valid signal for CPU read data
	logic         cpu_rd_data_valid             ;

	
	States        state                         ;   


//============================================================ INSTANTIATIONS============================================================================
// Instantiation of internal counter
	counter i_counter (.clock(i_cpu_ck), .reset(MDPRT_CPU_TO_CONT.i_cpu_reset), .en(en), .max_count(max_count), .done(timer_intr), .count(v_count));

// Instantiate of Write Burst module
	WriteBurst #(8) i_WriteBurst (.clock(i_cpu_ck_ps), .data(wdata_local), .out(t_dq_local), .valid_in(s_valid_data), .valid_out(dq_valid), .reset(MDPRT_CPU_TO_CONT.i_cpu_reset));
	
// Instantiation of read burst module
	ReadBurst #(8) i_ReadBurst (.clock(i_cpu_ck_ps), .data_in(MDPRT_CONT_TO_BFM.dq), .out(rdata_local));

//============================================================ COMBINATIONAL ASSIGNMENTS=================================================================
	assign MDPRT_CONT_TO_BFM.ck   = ~i_cpu_ck;					// Internal clock assignmnet 
	assign MDPRT_CONT_TO_BFM.ck_n = i_cpu_ck;


	assign s_valid_data = (state==WBURST) & (v_count>=0);		// set s_valid_data in order to send the burst to memory	(Write operation)

	always_comb MDPRT_CPU_TO_CONT.o_cpu_data_rdy <= (state==IDLE_WAIT);		// set ready signal from CPU when in IDLE state

//============================================================ SEQUENTIAL LOGIC===========================================================================

	always_ff@(posedge i_cpu_ck)   // Assign internal data and valid signals to CPU read and valid signals	
		begin
			MDPRT_CPU_TO_CONT.o_cpu_rd_data       <= cpu_rd_data;							
			MDPRT_CPU_TO_CONT.o_cpu_rd_data_valid <= s_cpu_rd_data_valid;					 
		end

  
	always_ff @(negedge i_cpu_ck) begin : proc_r_burst  // Read Burst operation. Provide 16 bits to the CPU per clock cycle.
		if(MDPRT_CPU_TO_CONT.i_cpu_reset)										
			cpu_rd_data <= 0;
		else if(state==RBURST) 															
			unique case (v_count)													    
			3       : cpu_rd_data[63:48] <= rdata_local;
			2       : cpu_rd_data[47:32] <= rdata_local;
			1       : cpu_rd_data[31:16] <= rdata_local;
			0       : cpu_rd_data[15:0]  <= rdata_local;
			default : cpu_rd_data <= 0;
		endcase
	end

//=================================================================== STATE TRANSITION BLOCK=========================================================
	always_ff@(posedge i_cpu_ck) begin
		if(MDPRT_CPU_TO_CONT.i_cpu_reset)											
			state <= POWERUP;										// state to POWERUP on reset
		else
			unique case(state)
				POWERUP : begin
					if(timer_intr)									// TXPR cycle meet to escape CKE high
						state <= ZQ_CAL;							// State to ZQ_CAL on timer interrupt
				end

				ZQ_CAL : begin
					if(timer_intr)
						state <= ZQ_CAL_DONE;							// State to CAL_DONE on timer interrupt
				end

				ZQ_CAL_DONE : begin          
					state <= MODEREGLOAD;								// State to MRLOAD on timer interrupt
				end

				MODEREGLOAD : begin
					if(timer_intr)									
						state <= IDLE_WAIT;								// State to IDLE on timer interrupt
				end

				IDLE_WAIT : begin
					if(MDPRT_CPU_TO_CONT.i_cpu_valid)
						state <= ACTIVATE;								// State to ACT if CPU valid signal is high
				end

				ACTIVATE : begin
					if(timer_intr) begin
						if(rw_flag == 1)						    // Check for Read/Write
							state <= WRITE;							
						else
							state <= READ;
					end
				end

				WRITE : begin
					if(timer_intr)
						state <= WBURST;							//  State to WBURST on timer interrupt
				end

				READ : begin
					if(timer_intr)
						state <= RBURST;							// State to READ BURST on timer interrupt
				end

				WBURST : begin
					if(timer_intr)
						state <= AUTOPRE;							// State to PRECHARGE on timer interrupt
				end

				RBURST : begin
					if(timer_intr)
						state <= AUTOPRE;							// State to PRECHARGE on timer interrupt
				end

				AUTOPRE : begin
					if(timer_intr)
						state <= DONE;
				end

				DONE : begin
					state <= IDLE_WAIT;
				end

				default : state <= POWERUP;							// State to POWERUP by default


			endcase
	end


//======================================================== OUTPUT BLOCK=============================================================================
// Begin with reseting the controller outputs to deassert condition.
	always_comb begin
		MDPRT_CONT_TO_BFM.rst_n   = 1'b1;							// deassert reset signal
		MDPRT_CONT_TO_BFM.odt     = 1'b1;						    // Set on die terminal signal
		MDPRT_CONT_TO_BFM.ras_n   = 1'b1;							
		MDPRT_CONT_TO_BFM.cas_n   = 1'b1;
		MDPRT_CONT_TO_BFM.cs_n    = 1'b0;
		MDPRT_CONT_TO_BFM.we_n    = 1'b1;
		MDPRT_CONT_TO_BFM.ba      = 'b0;							// set bank address variable to 0
		MDPRT_CONT_TO_BFM.addr    = 'b0;							// Set memory adddress variable to 0
		MDPRT_CONT_TO_BFM.cke     = 'b1;							// Set Clock enable signal
		t_flag              = 'b0;				
		en                  = 'b0;							// set enable signal to 0
		s_cpu_rd_data_valid = 0;							// Set read data valid to 0
		s_cpu_rd_data       = 0;							// Set cpu data to 0

		case(state)
		// In this mode the DDR is powerup at clock cycle = 5 by setting rst_n to high and odt to 0	
		// After 9 clock cycles, odt is set along with performing chip select
			POWERUP : 
			begin
				// RESET
				max_count         = 'd57;					
				MDPRT_CONT_TO_BFM.rst_n = 1'b0;
				MDPRT_CONT_TO_BFM.cke   = 1'b0;
				MDPRT_CONT_TO_BFM.cs_n  = 1'b1;
				MDPRT_CONT_TO_BFM.odt   = 1'b0;
				en                = 1'b1;
				// POWER UP AND CLOCKING DDR CHIP
				if(v_count>='d5) begin
					MDPRT_CONT_TO_BFM.rst_n = 1'b1;
					MDPRT_CONT_TO_BFM.odt   = 1'b0;
				end
				if(v_count>='d9) begin
					MDPRT_CONT_TO_BFM.cke  = 1'b1;
					MDPRT_CONT_TO_BFM.odt  = 1'b1;
					MDPRT_CONT_TO_BFM.cs_n = 1'b0;
					MDPRT_CONT_TO_BFM.odt  = 1'b0;
				end
			end

			// This state involves setting the A10 bit to enable the Auto Precharge Functionality 
			ZQ_CAL : 
			begin
				max_count       = 'd64;
				en              = 1'b1;
				MDPRT_CONT_TO_BFM.odt = 1'b0;
				// ZQ CALIBRATION PRECHARGING ALL THE BANKS
				if(v_count=='d0) begin               //The combination of values of these bits are a representation of a precharge command
					MDPRT_CONT_TO_BFM.we_n = 1'b0;
					MDPRT_CONT_TO_BFM.ba   = 'd0;
					MDPRT_CONT_TO_BFM.addr = 14'b00010000000000;
					MDPRT_CONT_TO_BFM.odt  = 1'b0;
				end
			end

			// counter is set to max count of 4*T_MRD
			// Enable is set .
			// Mode registers are configured after every T_MRD clock cycle.
			MODEREGLOAD : 
			begin
				MDPRT_CONT_TO_BFM.odt = 1'b0;
				max_count       = 4*T_MRD;
				en              = 1'b1;
				if(v_count=='d0) 
				begin						
				// Mode Register0 with fixed BL8, Sequential read burst type, DLL Reset, and Write recovery 16
					MDPRT_CONT_TO_BFM.ras_n = 1'b0;
					MDPRT_CONT_TO_BFM.cas_n = 1'b0;
					MDPRT_CONT_TO_BFM.we_n  = 1'b0;
					MDPRT_CONT_TO_BFM.ba    = 3'b011;				// Config bank 3
					MDPRT_CONT_TO_BFM.addr  = 14'b0;   
					MDPRT_CONT_TO_BFM.odt   = 1'b0;
				end
				else if(v_count==T_MRD) 
				begin 				
				// Mode Register1 with DLL Enable, RZQ6 40ohm op drive strength, disabled write levelling, AL=0, TDQS disables, Qoff enabled
					MDPRT_CONT_TO_BFM.ras_n = 1'b0;
					MDPRT_CONT_TO_BFM.cas_n = 1'b0;
					MDPRT_CONT_TO_BFM.we_n  = 1'b0;
					MDPRT_CONT_TO_BFM.ba    = 3'b010;				// Config bank 2
					MDPRT_CONT_TO_BFM.addr  = 14'b00000000000000;
					MDPRT_CONT_TO_BFM.odt   = 1'b0;
				end
				else if(v_count==2*T_MRD) 
				begin			
				// Mode Register2 with disabled self refresh, Normal self refresh temperature, 7CK CAS latency 
					MDPRT_CONT_TO_BFM.ras_n = 1'b0;
					MDPRT_CONT_TO_BFM.cas_n = 1'b0;
					MDPRT_CONT_TO_BFM.we_n  = 1'b0;
					MDPRT_CONT_TO_BFM.ba    = 3'b001;	// Config Bank 1
					MDPRT_CONT_TO_BFM.addr  = 14'b00000000010110;
					MDPRT_CONT_TO_BFM.odt   = 1'b0;
				end
				else if(v_count==3*T_MRD) 
				begin 			
				// Mode Register3 with MRP enable,
					MDPRT_CONT_TO_BFM.ras_n = 1'b0;
					MDPRT_CONT_TO_BFM.cas_n = 1'b0;
					MDPRT_CONT_TO_BFM.we_n  = 1'b0;
					MDPRT_CONT_TO_BFM.ba    = 3'b000;
					MDPRT_CONT_TO_BFM.addr  = 14'b00010100011000;				// Config Bank 0
					MDPRT_CONT_TO_BFM.odt   = 1'b0;
				end
			end

			// Reset on die termination
			ZQ_CAL_DONE : MDPRT_CONT_TO_BFM.odt   = 1'b0;			

			// Set the maximum count to T_RCD
			// During ACT, Bank and Row address are provided 
			// ras is assserted.
			// The controller has to wait for a period of Row-Column Delay
			ACTIVATE : 
			begin
				max_count = T_RCD+1;
				en        = 1'b1;
				if(v_count=='d0) begin
					MDPRT_CONT_TO_BFM.ba    = s_addr[12:10];		// 3 Bits for Bank
					MDPRT_CONT_TO_BFM.addr  = s_addr[26:13];		// 14 row address bits
					MDPRT_CONT_TO_BFM.ras_n = 1'b0;				    // check if we_n should be asserted
				end
			end

			// 3LSBs are used for byte selec, which is why they are set to 0. 
			// Hence we obtain burst right from the first byte which reduces the delay
			// byte select is configurable (CRITICAL BYTE FIRST).
			READ : 
			begin
				en              = 1'b1;
				max_count       = T_CL + 4;
				MDPRT_CONT_TO_BFM.odt = 1'b0;
				if(v_count=='d0) begin
					MDPRT_CONT_TO_BFM.we_n  = 1'b1;
					MDPRT_CONT_TO_BFM.ba    = s_addr[12:10];			// provide bank address
					MDPRT_CONT_TO_BFM.addr  = {s_addr[9:3],3'b0};		// 
					MDPRT_CONT_TO_BFM.cas_n = 1'b0;
				end
			end

			WRITE : 
			begin
				en        = 1'b1;
				max_count = T_CL-1+3;
				if(v_count=='d0) begin
					MDPRT_CONT_TO_BFM.we_n  = 1'b0;
					MDPRT_CONT_TO_BFM.ba    = s_addr[12:10];
					MDPRT_CONT_TO_BFM.addr  = {s_addr[9:3],3'b0};
					MDPRT_CONT_TO_BFM.cas_n = 1'b0;
				end
			end

			
			RBURST : 
			begin
				en              = 1'b1;									// Set enable
				max_count       = T_RAS-T_CL-T_RCD+1+2;					// set the max count
				MDPRT_CONT_TO_BFM.odt = 1'b0; 
				if(v_count=='d3) begin
					s_cpu_rd_data_valid <= 1;
				end
			end

			// Write burst is performed using the write buffer. the memory provides 64 bits in chuncks of 8 in 4 clock cycles.
			// At every edge these 8 bits are captured and internally alligned to form 16 bits at the next clock edge.
			// After all 64 bits are obtained, the controller provides the entire 64 bits to the controller 
			WBURST : 
			begin
				rst_counter = 'd0;
				en          = 1'b1;
				max_count   = T_RAS-T_CL-T_RCD+2;
				t_dqsn_flag = 'd0;
				wdata[0]    = s_data[15:0];
				wdata[1]    = s_data[31:16];
				wdata[2]    = s_data[47:32];
				wdata[3]    = s_data[63:48];
				t_flag      = (v_count > 0);
				if(v_count=='d0)
					wdata_local = wdata[0];
				else if(v_count=='d1)
					wdata_local = wdata[1];
				else if(v_count=='d2)
					wdata_local = wdata[2];
				else if(v_count=='d3)
					wdata_local = wdata[3];
			end

			// After every row is read, it is closed by performing auto precharge operation.
			// This is achieved by setting the A10 bit to 1 is the address.
			AUTOPRE : 
			begin
				en        = 1'b1;
				max_count = T_RP;
				if(v_count=='d0) begin
					MDPRT_CONT_TO_BFM.we_n  = 1'b0;
					MDPRT_CONT_TO_BFM.ras_n = 1'b0;
					MDPRT_CONT_TO_BFM.ba    = s_addr[12:10];
					MDPRT_CONT_TO_BFM.addr  = 1<10;
				end
			end
		endcase
	end


//=====================================================TRI STATE LOGIC FOR BIDIRECTIONAL SIGNALS========================================================
// TRISTATING  DQ , DQS
	assign MDPRT_CONT_TO_BFM.dq      = (dq_valid) 	  ? t_dq_local	:'bz ;		// giving t_dq_local of controllet to dq of BFM over the CONT-BFM interface if dq_valid is set during Write burst
	assign MDPRT_CONT_TO_BFM.dqs     = (s_valid_data) ? i_cpu_ck	:'bz ;      // giving strobe signals to CONT-BFM interface
	assign MDPRT_CONT_TO_BFM.dqs_n   = (s_valid_data) ? ~i_cpu_ck	:'bz ; 		// giving phase shifted strobe signals to CONT-BFM interface
	assign MDPRT_CONT_TO_BFM.dm_tdqs = (dq_valid) 	  ? 0 			:'bz ;		// signal to terminate data strobe

// PROC FOR READ WRITE FLAG FROM CPU CMD DURING ACT STATE
	always_ff @(posedge i_cpu_ck or negedge MDPRT_CPU_TO_CONT.i_cpu_reset) begin : proc_rw
		if((MDPRT_CPU_TO_CONT.i_cpu_reset) | (state==DONE)) begin
			rw_flag <= 0;
		end else if (MDPRT_CPU_TO_CONT.i_cpu_valid & MDPRT_CPU_TO_CONT.i_cpu_cmd)
			rw_flag <= 1;;
	end

// PROC FOR internal address and data assignment during the IDLE state
	always_ff @(posedge i_cpu_ck) begin : proc_addr_data_lacth
		if(MDPRT_CPU_TO_CONT.i_cpu_reset) begin
			s_addr <= 0;
			s_data <= 0;
		end else if ((MDPRT_CPU_TO_CONT.i_cpu_valid) & (state==IDLE_WAIT)) begin
			s_addr <= MDPRT_CPU_TO_CONT.i_cpu_addr;
			s_data <= MDPRT_CPU_TO_CONT.i_cpu_wr_data;
		end
	end


//==================================== ASSERTIONS ============================================

//======================= reset assertions =======================
		property resetValid_p;
		@(posedge i_cpu_ck)
		MDPRT_CPU_TO_CONT.i_cpu_reset |-> !MDPRT_CPU_TO_CONT.i_cpu_valid;
	endproperty
	a_resetValid : assert property(resetValid_p);
    
	property resetEnable_p;
		@(posedge i_cpu_ck)
		MDPRT_CPU_TO_CONT.i_cpu_reset |-> !MDPRT_CPU_TO_CONT.i_cpu_enable;
	endproperty
	a_resetEnable : assert property(resetEnable_p);
      
	property resetDeassert_p;
		@(posedge i_cpu_ck)
		MDPRT_CPU_TO_CONT.i_cpu_reset |=> !MDPRT_CPU_TO_CONT.i_cpu_reset;
	endproperty
	a_resetDeassert : assert property(resetDeassert_p);

	property resetEnableAssert_p;
		@(posedge i_cpu_ck)
		MDPRT_CPU_TO_CONT.i_cpu_reset |=> MDPRT_CPU_TO_CONT.i_cpu_enable;
	endproperty
	a_resetEnableAssert : assert property(resetEnableAssert_p);

//================write assertions==================
		

    property waitReady_p;
		  @(posedge i_cpu_ck) disable iff(MDPRT_CPU_TO_CONT.i_cpu_reset)
		  MDPRT_CPU_TO_CONT.o_cpu_data_rdy |=>  MDPRT_CPU_TO_CONT.i_cpu_valid;
		endproperty
		  a_waitReady : assert property(waitReady_p);
		    
		property cmdAssert_p;
		  @(posedge i_cpu_ck)
		  MDPRT_CPU_TO_CONT.o_cpu_data_rdy |=>  MDPRT_CPU_TO_CONT.i_cpu_cmd;
		endproperty
		    a_cmdAssert : assert property(cmdAssert_p);
		    
		      
		property validAssert_p;
		  @(posedge i_cpu_ck) disable iff(MDPRT_CPU_TO_CONT.i_cpu_reset)
		  MDPRT_CPU_TO_CONT.o_cpu_data_rdy |-> ##2 !MDPRT_CPU_TO_CONT.i_cpu_valid;
		endproperty
		  a_validAssert : assert property(validAssert_p);

//================read assertions==================
		

    property waitReady2_p;
		  @(posedge i_cpu_ck) disable iff(MDPRT_CPU_TO_CONT.i_cpu_reset)
		  MDPRT_CPU_TO_CONT.o_cpu_data_rdy |=>  MDPRT_CPU_TO_CONT.i_cpu_valid;
		endproperty
		  a_waitReady2 : assert property(waitReady2_p);
		    
		property cmdAssert2_p;
		  @(posedge i_cpu_ck)
		  MDPRT_CPU_TO_CONT.o_cpu_data_rdy |=>  !MDPRT_CPU_TO_CONT.i_cpu_cmd;
		endproperty
		    a_cmdAssert2 : assert property(cmdAssert2_p);
		    
		      
		property validAssert2_p;
		  @(posedge i_cpu_ck) disable iff(MDPRT_CPU_TO_CONT.i_cpu_reset)
		  MDPRT_CPU_TO_CONT.o_cpu_data_rdy |-> ##2 !MDPRT_CPU_TO_CONT.i_cpu_valid;
		endproperty

		a_validAssert2 : assert property(validAssert2_p);






endmodule:DDR3_Controller
