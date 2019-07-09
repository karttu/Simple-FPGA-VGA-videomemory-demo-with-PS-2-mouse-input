/* Module muskpak1.v - Written by Antti Karttunen, 30 May 2005 -
          Last edited 31. May 2005.

          This module reads packets from PS/2 Mouse,
          discards the invalid ones, updates the cursor_x
          and cursor_y based on valid packets,
          and whenever w_mouse_left_button is pressed,
          stores the current coordinates together with
          the drawing colour (given in 3-bit chosen_color RGB-input)
          to the FIFO, of which the output-port side is exposed
          to the calling module.

          This automatically sends "Enable Data Reporting"
          command (i.e. a hex. byte "F4") to the mouse,
          at the beginning, and with an explicit RESET.

 */


module muskpak1(input CLK,
                input RST,
                inout PS2CLK,
                inout PS2DATA,

                input [2:0] chosen_color,

                input [9:0] RES_HOR, // Give as 640
                input [9:0] RES_VER, // and 480.

                output [9:0] o_cursor_x,
                output [9:0] o_cursor_y,

                output [7:0] o_disp_mouse_x,
                output [7:0] o_disp_mouse_y,
                output [7:0] o_disp_mouse_s,
                output o_parityOK_x,
                output o_parityOK_y,
                output o_parityOK_s,
                output fifo_empty,
                output fifo_full,

                output [31:0] FIFO_DOB, // The 32-bit read-port of FIFO.
                output [3:0] FIFO_DOPB, // The extra 4-bit read-port of FIFO.
                input [8:0] FIFO_ADDR_OUT,  // The 9-bit address for read-side.
                output [8:0] O_FIFO_ADDR_IN  // The 9-bit address for write-side. (for debugging)
               );



reg [9:0] cursor_x = 0; // Allow range 0-1023. (in practice 0-639)
reg [9:0] cursor_y = 0; // Allow range 0-1023. (in practice 0-479)

/* Parameters, wires and registers involved with the mouse. */

reg mouse_initialized = 0;
wire init_mouse = (!mouse_initialized);

parameter n_bits = 33;
wire [n_bits-1:0] mousebits;

wire [7:0] w_mouse_y = mousebits[30:23];
wire [7:0] w_mouse_x = mousebits[19:12];
wire [7:0] w_mouse_s = mousebits[8:1];

wire w_mouse_left_button   = w_mouse_s[0];
wire w_mouse_right_button  = w_mouse_s[1];
wire w_mouse_middle_button = w_mouse_s[2];
wire w_mouse_neg_x         = w_mouse_s[4];
wire w_mouse_neg_y         = w_mouse_s[5];
wire w_mouse_overflow_x    = w_mouse_s[6];
wire w_mouse_overflow_y    = w_mouse_s[7];


wire pbit_mouse_y = mousebits[31];
wire pbit_mouse_x = mousebits[20];
wire pbit_mouse_s = mousebits[9];

wire parityOK_y = (pbit_mouse_y == (~^w_mouse_y));
wire parityOK_x = (pbit_mouse_x == (~^w_mouse_x));
wire parityOK_s = (pbit_mouse_s == (~^w_mouse_s));

wire noMoreBits;
wire [5:0] n_bits_read;

reg [7:0] disp_mouse_y = 8'b0;
reg [7:0] disp_mouse_x = 8'b0;
reg [7:0] disp_mouse_s = 8'b0;

parameter [7:0] SBYTE = 8'hF4;


assign o_cursor_x = cursor_x;
assign o_cursor_y = cursor_y;
assign o_disp_mouse_x = disp_mouse_x;
assign o_disp_mouse_y = disp_mouse_y;
assign o_disp_mouse_s = disp_mouse_s;
assign o_parityOK_x = parityOK_x;
assign o_parityOK_y = parityOK_y;
assign o_parityOK_s = parityOK_s;

ps2mbits PS2MBITS(CLK,init_mouse,SBYTE,PS2CLK,PS2DATA,mousebits,noMoreBits,n_bits_read);


wire mouse_packet_received_OK
   = (noMoreBits && (33 == n_bits_read)
                 && parityOK_s && parityOK_x && parityOK_y
                 && !w_mouse_overflow_x && !w_mouse_overflow_y);


/******************************** FIFO ********************************/

reg [8:0] fifo_addr_in = 0;
assign O_FIFO_ADDR_IN = fifo_addr_in;

assign fifo_empty = (FIFO_ADDR_OUT == fifo_addr_in);
assign fifo_full = (fifo_addr_in == (FIFO_ADDR_OUT-1));

reg [31:0] prev_coordpacket = 32'hFFFFFFFF;
wire [31:0] coordpacket = {9'b000000000,chosen_color,cursor_x,cursor_y};
wire fifo_we = (!fifo_full & mouse_packet_received_OK & w_mouse_left_button & (prev_coordpacket != coordpacket));

wire  [3:0] nc4a;
wire [31:0] nc32;

wire low          = 1'b0;
wire  [3:0] low4  = 4'b0000;
wire [31:0] low32 = 32'h00000000;
wire         high = 1'b1;



RAMB16_S36_S36 FIFO(.DOA(nc32), // not connected
                    .DOB(FIFO_DOB),
                    .DOPA(nc4a), // not connected
                    .DOPB(FIFO_DOPB), // not connected
                    .ADDRA(fifo_addr_in),
                    .ADDRB(FIFO_ADDR_OUT),
                    .CLKA(CLK),
                    .CLKB(CLK),
                    .DIA(coordpacket),
                    .DIB(low32),
                    .DIPA(low4),
                    .DIPB(low4),
                    .ENA(RST | fifo_we),
                    .ENB(high),
                    .SSRA(RST),
                    .SSRB(RST),
                    .WEA(fifo_we),
                    .WEB(low)
                   );




// Be clever: Sign-extend w_mouse_x (or _y) with the corresponding sign-bit
// before adding it to 10-bit cursor location.
wire [9:0] cursor_x_next = cursor_x + {w_mouse_neg_x,w_mouse_neg_x,w_mouse_x};
wire [9:0] cursor_y_next = cursor_y - {w_mouse_neg_y,w_mouse_neg_y,w_mouse_y};


always @(posedge CLK)
  begin
   if(RST)
    begin
      cursor_x <= RES_HOR/2;
      cursor_y <= RES_VER/2;
      mouse_initialized <= 0;
      prev_coordpacket <= 32'hFFFFFFFF;
      fifo_addr_in <= 0;
    end
   else
    begin
      mouse_initialized <= 1;
// Does the internal Block RAM need some kind
// of setup-time?
      fifo_addr_in <= fifo_addr_in + fifo_we;
 
      if(mouse_packet_received_OK)
       begin
        disp_mouse_y <= w_mouse_y;
        disp_mouse_x <= w_mouse_x;
        disp_mouse_s <= w_mouse_s;

        prev_coordpacket <= coordpacket;

// Set the (possibly) new position for cursor, with a bounds checking:

        if(cursor_x_next < cursor_x)
         begin
   // But avoid wrapping over the right side:
           if(w_mouse_neg_x) cursor_x <= cursor_x_next;
         end
        else // cursor_x_next >= cursor_x
         begin
   // Avoid two cases here: a) wrap over the left side
   // b) move too far to the right:
           if(~w_mouse_neg_x && (cursor_x_next < RES_HOR))
             cursor_x <= cursor_x_next;
         end
   
        if(cursor_y_next < cursor_y)
         begin
   // But avoid wrapping over the bottom:
           if(~w_mouse_neg_y) cursor_y <= cursor_y_next;
         end
        else // cursor_y_next >= cursor_y
         begin
   // Avoid two cases here: a) wrap over the top
   // b) move too far to the bottom:
           if(w_mouse_neg_y && (cursor_y_next < RES_VER))
             cursor_y <= cursor_y_next;
         end
   
       end
    end
  end

endmodule
