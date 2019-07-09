
/* issia:  by karttu, May 29 2005.
           Last edited Jun 6 2005.
           Read/write controller for
           ISSI IS61LV25616AL Asynchronous Static RAM memory.

           Use only the other chip (IC10).
 */

module issia(input CLK,
             output [17:0] ISSI_ADDR,
             inout [15:0] ISSI_DATA_IO,
             output ISSI_CE1N,
             output ISSI_OEN,
             output ISSI_WEN,
             output ISSI_LB1N,
             output ISSI_UB1N,

             input STARTWRITE,
             input [17:0] ADDR,
             input [15:0] DATAWRITTEN,
             output [15:0] DATAREAD,
             output WRITEREADY
            );


reg [17:0] copy_of_ADDR;
reg [15:0] copy_of_DATAWRITTEN;

parameter  low = 1'b0;
parameter high = 1'b1;

// If the calling module raises STARTWRITE signal, then
// the ISSI_OEN is immediately raised (output disabled),
// and the state will be changed from the default state
// ST_READ to ST_WRITE1 (on the next cycle).
// The ADDR bus should be set to the requested write address,
// and DATAWRITTEN bus to the word to be written
// ALREADY at the time STARTWRITE signal was raised.
// (They are copied to local registers at that time, so it
//  doesn't matter if the calling module will change
//  them during the subsequent write cycles).

parameter [1:0] ST_READ   = 2'b00;
parameter [1:0] ST_WRITE1 = 2'b01;
parameter [1:0] ST_WRITE2 = 2'b11; // In this state we take ISSI_WEN low.
parameter [1:0] ST_WRITE3 = 2'b10; // Here we take it back high and raise WRITEREADY

reg [1:0] state = ST_READ;


assign ISSI_CE1N = low;
assign ISSI_OEN  = (STARTWRITE | (ST_READ != state));
assign ISSI_LB1N = low;
assign ISSI_UB1N = low;
assign ISSI_WEN  = ~(state[1] & state[0]); // (ST_WRITE2 != state);

assign ISSI_ADDR = ((ST_READ == state) ? ADDR : copy_of_ADDR);
assign ISSI_DATA_IO = ((ST_READ == state) ? 16'bzzzzzzzzzzzzzzzz : copy_of_DATAWRITTEN);
assign DATAREAD = ((ST_READ == state) ? ISSI_DATA_IO : 16'b0000000000000000);

assign WRITEREADY = (ST_WRITE3 == state);

always @(posedge CLK)
  begin
    case(state)
      ST_READ:
       begin
        if(STARTWRITE)
         begin
            state[0] <= ~state[0];
            copy_of_ADDR <= ADDR;
            copy_of_DATAWRITTEN <= DATAWRITTEN;
         end
       end
      ST_WRITE1:
       begin
        state[1] <= ~state[1];
       end
      ST_WRITE2:
       begin
        state[0] <= ~state[0];
       end
      ST_WRITE3:
       begin
        state[1] <= ~state[1];
       end
    endcase
  end

endmodule
