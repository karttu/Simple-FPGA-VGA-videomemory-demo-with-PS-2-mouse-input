
/* shw4spec:  by karttu, Apr 26 2005.
              Show four hexters specified as (inverted)
              7-segment bit masks given in MASKS[0:3] in the
              four 7-segment LED display of Spartan-3 board.
              Show also additional information DP3-DP0
              (for example: parity bits) in their
              decimal points (note that they are inverted!).

   For some reason input [3:0] HEX [3:0] does not work!
   Modified from show4hex.v, and reversed its argument order,
   so that now the four nybbles are given in the same order
   as they are shown in four 7-segment digits.
 */

module shw4spec(input CLK,
                input [3:0] HEX3,
                input [3:0] HEX2,
                input [3:0] HEX1,
                input [3:0] HEX0,
                input DP3,
                input DP2,
                input DP1,
                input DP0,
                output [7:0] SEG_OUT,
                output [3:0] DIGIT_OUT);

function [6:0] HEX2LED;
  input [3:0] HEX;

  begin
     case (HEX)
	4'b0001 : HEX2LED = 7'b1111001;	//1
	4'b0010 : HEX2LED = 7'b0100100;	//2
	4'b0011 : HEX2LED = 7'b0110000;	//3
	4'b0100 : HEX2LED = 7'b0011001;	//4
	4'b0101 : HEX2LED = 7'b0010010;	//5
	4'b0110 : HEX2LED = 7'b0000010;	//6
	4'b0111 : HEX2LED = 7'b1111000;	//7
	4'b1000 : HEX2LED = 7'b0000000;	//8
	4'b1001 : HEX2LED = 7'b0010000;	//9
	4'b1010 : HEX2LED = 7'b0001000;	//A
	4'b1011 : HEX2LED = 7'b0000011;	//b
	4'b1100 : HEX2LED = 7'b1000110;	//C
	4'b1101 : HEX2LED = 7'b0100001;	//d
	4'b1110 : HEX2LED = 7'b0000110;	//E
	4'b1111 : HEX2LED = 7'b0001110;	//F
	default : HEX2LED = 7'b1000000;	//0
     endcase
  end
endfunction

parameter msb = 16;
reg [msb:0] delay_counter = 0;

wire [1:0] d = delay_counter[msb:msb-1];

assign SEG_OUT[7] = (0 == d ? DP0 : 1 == d ? DP1 : 2 == d ? DP2 : DP3);
assign SEG_OUT[6:0] = HEX2LED(0 == d ? HEX0 : 1 == d ? HEX1 : 2 == d ? HEX2 : HEX3);

assign DIGIT_OUT = (0 == d) ? 4'b1110 : (1 == d) ? 4'b1101 : (2 == d) ? 4'b1011 : 4'b0111;

always @(posedge CLK)
  begin
    delay_counter <= delay_counter+1; // Wraps around, eventually.
  end

endmodule
