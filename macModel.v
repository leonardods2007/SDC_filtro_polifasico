// see http://www.altera.com/literature/hb/qts/qts_qii51007.pdf
// example 14.6 for register placement
module macModel (accum_sload,
		 clk,
		 dataa,
		 datab,
		 result);
   parameter WIDTH_IN=1; // default is supposed to fail   
   parameter WIDTH_OUT=1;
   
   input	                     accum_sload;
   input 			     clk;
   input signed [WIDTH_IN-1:0] 	     dataa;
   input signed [WIDTH_IN-1:0] 	     datab;
   output reg signed [WIDTH_OUT-1:0] result = 0;
   
   reg signed [WIDTH_IN-1:0] 	     dataa_reg; 
   reg signed [WIDTH_IN-1:0] 	     datab_reg; 
   reg 				     accum_sload_reg;
   
   wire [WIDTH_OUT-1:0] 	     multa;
   reg [WIDTH_OUT-1:0] 		     multa_reg; 
   
   wire [WIDTH_OUT-1:0] 	     adderOut;

   assign multa = dataa_reg * datab_reg;
   assign adderOut = multa_reg + result;
   
   always @(posedge clk) begin
      dataa_reg <= dataa;              // first pipeline stage
      datab_reg <= datab;              // first pipeline stage
      accum_sload_reg <= accum_sload;  // first pipeline stage

      multa_reg <= multa; // second pipeline stage      
      
      if (accum_sload_reg) 
	result <= multa_reg; // third pipeline stage
      else
	result <= adderOut; // third pipeline stage
   end
endmodule
