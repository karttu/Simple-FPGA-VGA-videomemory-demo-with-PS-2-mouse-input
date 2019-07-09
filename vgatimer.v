/*
   Renamed from the original vga_vtim.v
   to vgatimer.v by karttu, 24. 4. 2005.

   For the original Richard Herveille's source, see:
   http://www.opencores.org/projects.cgi/web/vga_lcd/overview

 */
/////////////////////////////////////////////////////////////////////
////                                                             ////
////  WISHBONE rev.B2 compliant VGA/LCD Core; Timing Generator   ////
////  Video Timing Generator                                     ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
////  Downloaded from: http://www.opencores.org/projects/vga_lcd ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001 Richard Herveille                        ////
////                    richard@asics.ws                         ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////


//synopsys translate_off
`include "timescale.v"
//synopsys translate_on

module vgatimer(clk, ena, rst, Tsync, Tgdel, Tgate, Tlen, Sync, Gate, Done);
	// inputs & outputs
	input clk; // master clock
	input ena; // count enable
	input rst; // synchronous active high reset

	input [ 7:0] Tsync; // sync duration
	input [ 7:0] Tgdel; // gate delay
	input [15:0] Tgate; // gate length
	input [15:0] Tlen;  // line time / frame time

	output Sync; // synchronization pulse
	output Gate; // gate
	output Done; // done with line/frame
	reg Sync;
	reg Gate;
	reg Done;

	//
	// module body
	//

	// generate timing statemachine
	reg  [15:0] cnt, cnt_len;
	wire [16:0] cnt_nxt, cnt_len_nxt;
	wire        cnt_done, cnt_len_done;

	assign cnt_nxt = {1'b0, cnt} -17'h1;
	assign cnt_done = cnt_nxt[16];

	assign cnt_len_nxt = {1'b0, cnt_len} -17'h1;
	assign cnt_len_done = cnt_len_nxt[16];

	parameter [4:0] idle_state = 5'b00001;
	parameter [4:0] sync_state = 5'b00010;
	parameter [4:0] gdel_state = 5'b00100;
	parameter [4:0] gate_state = 5'b01000;
	parameter [4:0] len_state  = 5'b10000;

	reg [4:0] state = idle_state;

	always @(posedge clk)
	  if (rst)
	    begin
	        state   <= #1 idle_state;
	        cnt     <= #1 16'h0;
	        cnt_len <= #1 16'b0;
	        Sync    <= #1 1'b0;
	        Gate    <= #1 1'b0;
	        Done    <= #1 1'b0;
	    end
	  else if (ena)
	    begin
	        cnt     <= #1 cnt_nxt[15:0];
	        cnt_len <= #1 cnt_len_nxt[15:0];

	        Done    <= #1 1'b0;

	        case (state) // synopsys full_case parallel_case
	          idle_state:
	            begin
	                state   <= #1 sync_state;
	                cnt     <= #1 Tsync;
	                cnt_len <= #1 Tlen;

	                Sync    <= #1 1'b1;
	            end

	          sync_state:
	            if (cnt_done)
	              begin
	                  state <= #1 gdel_state;
	                  cnt   <= #1 Tgdel;

	                  Sync  <= #1 1'b0;
	              end

	          gdel_state:
	            if (cnt_done)
	              begin
	                  state <= #1 gate_state;
	                  cnt   <= #1 Tgate;

	                  Gate  <= #1 1'b1;
	              end

	          gate_state:
	            if (cnt_done)
	              begin
	                  state <= #1 len_state;

	                  Gate  <= #1 1'b0;
	              end

	          len_state:
	            if (cnt_len_done)
	              begin
	                  state   <= #1 sync_state;
	                  cnt     <= #1 Tsync;
	                  cnt_len <= #1 Tlen;

	                  Sync    <= #1 1'b1;
	                  Done    <= #1 1'b1;
	              end

	        endcase
	    end
endmodule
