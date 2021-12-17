module ramModel #(parameter DATA_WIDTH = 1, // defaults are supposed to fail
		  parameter ADDR_WIDTH = 9) 
   (// Port A
    input   wire                a_clk,
    input   wire                a_wr,
    input   wire [ADDR_WIDTH-1:0] 	a_addr,
    input   wire [DATA_WIDTH-1:0] 	a_din,
    output  reg [DATA_WIDTH-1:0] 	a_dout,
    
    // Port B
    input   wire                b_clk,
    input   wire                b_wr,
    input   wire [ADDR_WIDTH-1:0] 	b_addr,
    input   wire [DATA_WIDTH-1:0] 	b_din,
    output  reg [DATA_WIDTH-1:0] 	b_dout);
   
   // memory
   reg [DATA_WIDTH-1:0] 		mem [(2**ADDR_WIDTH)-1:0];

   // input registers
   reg [ADDR_WIDTH-1:0] 		a_addr_reg;
   reg [ADDR_WIDTH-1:0] 		b_addr_reg;
   reg [DATA_WIDTH-1:0] 		a_din_reg;
   reg [DATA_WIDTH-1:0] 		b_din_reg;
   reg 				a_wr_reg;
   reg 				b_wr_reg;
   
   // Port A
   always @(posedge a_clk) begin
      a_addr_reg <= a_addr;
      a_din_reg <= a_din;
      a_wr_reg <= a_wr;
      a_dout      <= mem[a_addr_reg];
      if(a_wr_reg) begin
         a_dout      <= a_din_reg;
         mem[a_addr_reg] <= a_din_reg;
      end
   end
   
   // Port B
   always @(posedge b_clk) begin
      b_addr_reg <= b_addr;
      b_din_reg <= b_din;
      b_wr_reg <= b_wr;
      b_dout      <= mem[b_addr_reg];
      if(b_wr_reg) begin
         b_dout      <= b_din_reg;
         mem[b_addr_reg] <= b_din_reg;
      end
   end

   initial $readmemh("generated/ram_init.txt", mem, 0, (2**ADDR_WIDTH)-1);
endmodule
