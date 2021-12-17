// Shared-multiplier interpolating/decimating polyphase filter
//
// Flow control between FIR_unit and testbench, needed to support
//  arbitrary interpolation / decimation factors:
// 
// - FIR_unit: idle => 1 requests new sample
// - testbench: strobe_dataIn => 1 flags valid input sample on dataIn
//   this may repeat several times, if DECIM>INTERP
//  - FIR_unit processes (many clock cycles)
//  - FIR_unit: strobe_dataOut => 1 flags valid output sample on dataOut
//    this may repeat several times if INTERP>DECIM
//  - once FIR_unit is out of data, it raises idle and the cycle repeats.

// generic MAC, replace with device-specific implementation
`include "macModel.v"

// generic dual-port RAM, replace with device-specific implementation
`include "ramModel.v"

module FIR_unit(clk_in, dataIn, strobe_dataIn, strobe_dataOut, dataOut, idle);

   //Matlab script generates localparams in "defines.v"
`include "generated/defines.v"
   
   input                              clk_in;
   input signed [WIDTH_IN-1:0] 	      dataIn;
   input 			      strobe_dataIn;
   output reg signed [WIDTH_OUT-1:0]  dataOut;
   output reg 			      strobe_dataOut = 1'b0;
   output 			      idle;
   
   // memory address of FIFO (requires NSTAGES words)
   localparam BASEADDR_FIFO = 0;
   
   // interface to components
   wire [WIDTH_OUT-1:0] 	      macOut;   
   reg [ADDR_LINES-1:0] 	      memA_addr;
   wire [WIDTH_IN-1:0] 		      memA_dataRd;
   reg [WIDTH_IN-1:0] 		      memA_dataWr;
   reg 				      memA_we = 1'b0;
   reg [ADDR_LINES-1:0] 	      memB_addr;
   reg [WIDTH_IN-1:0] 		      memB_dataWr;
   wire [WIDTH_IN-1:0] 		      memB_dataRd;
   reg 				      memB_we = 1'b0;
   reg [PDELAY_SETMAC:0] 	      setMac; // parallel delay line (pipeline trigger)
   reg [PDELAY_READMAC:0] 	      readMac; // parallel delay line (pipeline trigger)
   
   // ---------- main FSM  -----------
   localparam STATE_LOAD = 1'b0;
   localparam STATE_RUN = 1'b1;
   reg 				      state = STATE_LOAD;
   
   assign idle = (state == STATE_LOAD);
   
   reg [NLOAD_NBITS-1:0] 	      nLoad = 1;
   reg [FIFOPTR_NBITS-1:0] 	      fifoPtr = 0;
   reg [COEFFPTR_NBITS-1:0] 	      coeffPtr = 0;
   reg [BANKPTR_NBITS-1:0] 	      bankPtr = 0;
   reg [MACCOUNT_NBITS-1:0] 	      macCount;
   localparam [MACCOUNT_NBITS-1:0]    macCount_NSTAGESMINUSONE = NSTAGES-1;
   localparam coeffPtr_dontCare = {COEFFPTR_NBITS{{1'bx}}};
   
   always @(posedge clk_in) begin
      // advance delay lines
      setMac <= (setMac << 1); 
      readMac <= (readMac << 1); 
      
      case(state)
	STATE_LOAD:
	  begin	          
	     readMac[0] <= 1'b0; // trigger new output sample (latency-corrected)
	     
	     if (strobe_dataIn) begin // got new input
		memA_dataWr <= dataIn; // write to FIFO 
		memA_addr <= BASEADDR_FIFO + fifoPtr;
		memA_we <= 1'b1;		
		nLoad <= nLoad-1;
		if (nLoad == 1) begin // got enough data to create next output?
		   state <= STATE_RUN; // start calculating
		   macCount <= macCount_NSTAGESMINUSONE;
		   setMac[0] <= 1'b1; // next MAC input sets the MAC (latency corrected)
		end else begin
		   // need more input samples
		   fifoPtr <= (fifoPtr == 0) ? NSTAGES-1 : fifoPtr-1; // FIFO backwards to load new sample
		end
	     end else begin
		// waiting for input data
		memA_we <= 1'b0;		
	     end
	  end
	
	STATE_RUN:
	  begin 
	     setMac[0] <= 0; // (may change during same cycle)
	     readMac[0] <= 0; // (may change during same cycle)

	     macCount <= macCount-1; // iterate over stages
	     coeffPtr <= (coeffPtr >= NSTAGES*INTERP) ? coeffPtr_dontCare : // impossible
			 (coeffPtr >= NSTAGES*INTERP-INTERP) ? coeffPtr-NSTAGES*INTERP+INTERP : // overflow, loop back
			 coeffPtr+INTERP; // next stage coeff in current bank

	     // read FIFO
	     memA_addr <= BASEADDR_FIFO + fifoPtr;
	     memA_we <= 1'b0;		
	     memB_addr <= BASEADDR_COEFF + coeffPtr + bankPtr;
	     if (macCount == 0) begin // final stage?		
		readMac[0] <= 1; // valid output (latency corrected)
		if (bankPtr >= INTERP-DECIM_MOD_INTERP) begin
		   // bank pointer overflow from fractional part
		   bankPtr <= bankPtr-INTERP+DECIM_MOD_INTERP;		   
		   
		   // round up
		   nLoad <= CEIL_DECIM_SLASH_INTERP;
		   state <= STATE_LOAD; // STATE_LOAD will setMac <= 1
		   // do not advance FIFO, keep it on the oldest element		   
		end else if (FLOOR_DECIM_SLASH_INTERP > 0) begin // note: constant at compile time
		   // DECIM > INTERP: integer part triggers overflow for every sample. 
		   
		   // fractional part alone does not overflow (this case was handled in the previous section)
		   bankPtr <= bankPtr+DECIM_MOD_INTERP;

		   // Round down
		   // Note, for DECIM==INTERP rounding up/down achieve the same
		   nLoad <= FLOOR_DECIM_SLASH_INTERP;
		   state <= STATE_LOAD; // STATE_LOAD will setMac <= 1
		   // do not advance FIFO, keep it on the oldest element
		end else begin
		   // non-overflowing bank increase
		   bankPtr <= bankPtr+DECIM_MOD_INTERP;
		   
		   // start new output sample on current delay line content
		   setMac[0] <= 1'b1;
		   macCount <= macCount_NSTAGESMINUSONE;
		   fifoPtr <= (fifoPtr == NSTAGES-1) ? 0 : fifoPtr+1; // FIFO forwards for MAC loop
		end
	     end else begin 
		// not final stage... keep MACing
	     	fifoPtr <= (fifoPtr == NSTAGES-1) ? 0 : fifoPtr+1; // FIFO forwards for MAC loop
	     end
	  end
      endcase
   end
   
   // ---------- transfer result  -----------
   // skeleton code, use proper rounding / scaling / saturation instead
   always @(posedge clk_in) begin
      if (readMac[PDELAY_READMAC]) begin
	 dataOut <= macOut[WIDTH_OUT-1:0];
	 strobe_dataOut <= 1'b1;
      end else begin
	 strobe_dataOut <= 1'b0;
      end
   end
   
   // ---------- MAC  -----------
   macModel #(.WIDTH_IN(WIDTH_IN), 
	      .WIDTH_OUT(WIDTH_OUT)) mac_inst 
     (.clk (clk_in),
      .accum_sload (setMac[PDELAY_SETMAC]),
      .dataa (memA_dataRd),
      .datab (memB_dataRd),
      .result (macOut));
   
   // ---------- dual-port memory -----------
   ramModel #(.DATA_WIDTH(WIDTH_IN),
	      .ADDR_WIDTH(ADDR_LINES)) ram_inst
     (.a_clk(clk_in), .a_wr(memA_we), .a_addr(memA_addr), .a_din(memA_dataWr), .a_dout(memA_dataRd),
      .b_clk(clk_in), .b_wr(memB_we), .b_addr(memB_addr), .b_din(memB_dataWr), .b_dout(memB_dataRd));

	
	
	 
	 
endmodule // test


