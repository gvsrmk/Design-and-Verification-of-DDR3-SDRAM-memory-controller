/***************************************************************************************************************************
*
*    File Name:  DDR3controller_package.sv
* Dependencies:  DDR3controller.sv
*				 
*
*  Description:  Contains generalized parameters for address and Data bits.
*				 Also parameterizes the delays depecding on the memory model specs


*****************************************************************************************************************************/

package DDR3cont_pkg;
//==================================================================================================================================================
	// BIT Parameters
	parameter DM_BITS          =       1; // Set this parameter to control how many Data Mask bits are used
	parameter ADDR_BITS        =      14; // MAX Address Bits
	parameter BA_BITS          =       3; // MAX Bank control Bits
	parameter ROW_BITS         =      14; // Set this parameter to control how many Address bits are used
	parameter COL_BITS         =      10; // Set this parameter to control how many Column bits are used
	parameter DQ_BITS          =       8; // Set this parameter to control how many Data bits are used       **Same as part bit width**
	parameter DQS_BITS         =       1; // Set this parameter to control how many Dqs bits are used
	parameter BURST_L	   	   =	   8; // Burst Length
	parameter ADDR_MCTRL	   =	  32; // Address to the Controller
//==================================================================================================================================================
	// Memory Parameters for Configurations
	parameter T_RAS	 =15;	// From Row Addr to Precharge
	parameter T_RCD	 =6;	// Row to Column Delay
	parameter T_CL	 =6;	// Column to Data Delay
	parameter T_RC	 =21;	// RP to Next RP Delay
	parameter T_BL	 =4;	// Burst Length in cycles
	parameter T_RP	 =6;	// Precharge Time
	parameter T_MRD	 =4;	// Mode register set command cycle time
//==================================================================================================================================================
	// FSM States
	typedef enum logic [3:0] { RESET,POWERUP, MODEREGLOAD, ZQ_CAL, ZQ_CAL_DONE, IDLE_WAIT, ACTIVATE, READ, WRITE, WBURST, RBURST, AUTOPRE, DONE} States; 
//==================================================================================================================================================
    //defining the states for the FSM States
	States state;

endpackage
