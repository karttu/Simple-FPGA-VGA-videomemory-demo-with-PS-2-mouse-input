/* Example 17: by karttu, 30. 5. 2005.
               A simple drawing application
               for PS/2 Mouse & "Poor Man's" VGA monitor.

               Last edited Jun 9 2005.

               Still flaky.

General Strategy:

   FIFO is filled (by a "packet": coords 10+10 bits + color (3 bits) = 23 bits)
   whenever a valid packet, with w_mouse_left_button==1 is received from
   the mouse (regardless of the state of Gate).
   (The module muskpak1 takes care of this).

   FIFO is emptied to VIDRAM when we are outside of Gate.
   (this is done here).
   Note: because five pixels are packed into each word of the
   video ram, we have to read each word
   of the ram we are going to update (i.e. where the coordpacket
   fetched from the FIFO falls) before the update, so that
   we can leave the other pixels of the word intact.


   If FIFO overflows, then the decimal point LED of the leftmost digit is lit.
   (This should not be possible, because of the relative slowness of the mouse)

   VIDRAM is read when we are inside Gate.
   (This is done by vga4word.v module).
   

 */

module esim17(input CLK,
              input RST,
              inout PS2CLK,
              inout PS2DATA,
              output [7:0] SEG_OUT,
              output [3:0] DIGIT_OUT,
              output [7:0] LED_OUT,
              input [7:0] SW_IN,
              input PB_IN0,
              input PB_IN1,
              input PB_IN2,
              output VGA_R,
              output VGA_G,
              output VGA_B,
              output VGA_HSYNC,
              output VGA_VSYNC,

              output [17:0] ISSI_ADDR,
              inout [15:0] ISSI_DATA_IO,
              output ISSI_CE1N,
              output ISSI_CE2N,
              output ISSI_OEN,
              output ISSI_WEN,
              output ISSI_LB1N,
              output ISSI_LB2N,
              output ISSI_UB1N,
              output ISSI_UB2N
             );


assign ISSI_CE2N = 1'b1; // Keep the other ISSIA SRAM chip disabled.
assign ISSI_LB2N = 1'b1;
assign ISSI_UB2N = 1'b1;

parameter VIDRAM_UPPER_LIMIT = 76800; // ((RES_HOR/4)*RES_VER);

parameter [7:0] ST_INIT_VIDRAM            = 8'b00000001;
parameter [7:0] ST_INIT_VIDRAM_FANCY      = 8'b00000010;
parameter [7:0] ST_WAIT_RELEASE_OF_VIDRAM = 8'b00000100;
parameter [7:0] ST_SCAN_FIFO              = 8'b00001000;
parameter [7:0] ST_READ_COORDS            = 8'b00010000;
parameter [7:0] ST_PAUSE                  = 8'b00100000;
parameter [7:0] ST_READ_OLD_VIDWORD       = 8'b01000000;
parameter [7:0] ST_WRITE_WORD             = 8'b10000000;


reg [1:0] pos_in_word;
reg [7:0] state = ST_INIT_VIDRAM;

wire parityOK_y;
wire parityOK_x;
wire parityOK_s;
wire fifo_empty;
wire fifo_full;


wire [7:0] disp_mouse_y;
wire [7:0] disp_mouse_x;
wire [7:0] disp_mouse_s;

parameter [9:0] P_RES_HOR = 640;
parameter [9:0] P_RES_VER = 480;

wire [9:0] cursor_x;
wire [9:0] cursor_y;

wire [31:0] fifo_read_port; // coordpack's are read from these wires.

wire [9:0] coordpack_x = fifo_read_port[19:10];
wire [9:0] coordpack_y = fifo_read_port[9:0];
wire [2:0] coordpack_color = fifo_read_port[22:20];

reg [2:0] color_from_fifo;

wire [3:0] nc4; // Not connected.

reg [8:0] fifo_addr_out = 0;  // The 9-bit address for read-side.
wire [8:0] fifo_addr_in;  // The 9-bit address for write-side of fifo.

muskpak1 MOUSEFIFO(.CLK(CLK),
                .RST(RST),
                .PS2CLK(PS2CLK),
                .PS2DATA(PS2DATA),
//              .chosen_color(3'b100), // Use red for testing.
                .chosen_color({SW_IN[2],SW_IN[1],SW_IN[0]}),

                .RES_HOR(P_RES_HOR),
                .RES_VER(P_RES_VER),

                .o_cursor_x(cursor_x),
                .o_cursor_y(cursor_y),

                .o_disp_mouse_x(disp_mouse_x),
                .o_disp_mouse_y(disp_mouse_y),
                .o_disp_mouse_s(disp_mouse_s),
                .o_parityOK_x(parityOK_x),
                .o_parityOK_y(parityOK_y),
                .o_parityOK_s(parityOK_s),
                .fifo_empty(fifo_empty),
                .fifo_full(fifo_full),

                .FIFO_DOB(fifo_read_port),
                .FIFO_DOPB(nc4),
                .FIFO_ADDR_OUT(fifo_addr_out),
                .O_FIFO_ADDR_IN(fifo_addr_in)
               );


wire [2:0] chosen_background_color = {SW_IN[5],SW_IN[4],SW_IN[3]};
reg [2:0] bgcol0;
reg [2:0] bgcol1;
reg [2:0] bgcol2;
reg [2:0] bgcol3;


assign write_testpat_to_ram = PB_IN1;
assign clear_ram = PB_IN2;

wire [17:0] vga_vidram_addr_out;
reg  [17:0] our_vidram_addr_out = 0;

wire [15:0] vidram_data_out;

reg [17:0] vidram_addr_in = 0;
reg [15:0] vidram_data_in = 0;


wire vidram_client_can_write;

wire vidram_initializing = ((ST_INIT_VIDRAM == state)|(ST_INIT_VIDRAM_FANCY == state));

wire vidram_startwrite = (vidram_initializing | (ST_WRITE_WORD == state));
wire vidram_we = vidram_startwrite;

vga4word VGACNTR(.CLK(CLK),
                 .RST(RST),

                 .o_vidram_addr_out(vga_vidram_addr_out), // <-- vga4word (also incremented there)
                 .vidram_data_out(vidram_data_out), // --> vga4word

                 .vidram_client_forced_write(vidram_initializing), // --> vga4word
                 .vidram_client_can_write(vidram_client_can_write), // <-- vga4word

                 .cursor_x(cursor_x),
                 .cursor_y(cursor_y),
                 .test_quilt_pat(PB_IN0),
                 .hsync_polarity(SW_IN[7]),
                 .vsync_polarity(SW_IN[6]),

                 .VGA_R(VGA_R),
                 .VGA_G(VGA_G),
                 .VGA_B(VGA_B),
                 .VGA_HSYNC(VGA_HSYNC),
                 .VGA_VSYNC(VGA_VSYNC)
                );


issia VIDRAM(.CLK(CLK),
             .ISSI_ADDR(ISSI_ADDR),
             .ISSI_DATA_IO(ISSI_DATA_IO),
             .ISSI_CE1N(ISSI_CE1N),
             .ISSI_OEN(ISSI_OEN),
             .ISSI_WEN(ISSI_WEN),
             .ISSI_LB1N(ISSI_LB1N),
             .ISSI_UB1N(ISSI_UB1N),
             .STARTWRITE(vidram_startwrite),
             .ADDR(vidram_we ? vidram_addr_in
                             : ((vidram_client_can_write | vidram_initializing)
                                              ? our_vidram_addr_out : vga_vidram_addr_out)),
             .DATAWRITTEN(vidram_data_in),
             .DATAREAD(vidram_data_out),
             .WRITEREADY(writeready)
            );


/* Leds & 4 7-segment digits for debugging: */

assign LED_OUT = disp_mouse_s;

// Show the coordinates as X & Y:
shw4spec DIGDISPLAY(CLK,
//                  disp_mouse_x[7:4],disp_mouse_x[3:0],disp_mouse_y[7:4],disp_mouse_y[3:0],
//                  (~fifo_full),parityOK_s,parityOK_x,parityOK_y,
//                  fifo_addr_out[7:4],fifo_addr_out[3:0],fifo_addr_in[7:4],fifo_addr_in[3:0],
//                  (~fifo_full),(~fifo_empty),(~vidram_we),(~vidram_client_can_write),
//                  vidram_addr_in[15:12],vidram_addr_in[11:8],vidram_addr_in[7:4],vidram_addr_in[3:0],
//                  vidram_data_out[15:12],vidram_data_out[11:8],vidram_data_out[7:4],vidram_data_out[3:0],
                    vidram_data_in[15:12],vidram_data_in[11:8],vidram_data_in[7:4],vidram_data_in[3:0],
                    (~fifo_full),(~fifo_empty),(~vidram_addr_in[17]),(~vidram_addr_in[16]),
                    SEG_OUT,DIGIT_OUT);



function [15:0] test_pat;
  input [17:0] vidram_addr;
  begin
     test_pat = ~{vidram_addr[15:10],10'b0000000000};
  end
endfunction


function [15:0] new_vidword;
  input [15:0] word; // The old one
  input [1:0] pos; // 0-3.
  input [2:0] triplet;

  begin
    case(pos)
      0: new_vidword = {word[15:4],1'b0,triplet};
      1: new_vidword = {word[15:8],1'b0,triplet,word[3:0]};
      2: new_vidword = {word[15:12],1'b0,triplet,word[7:0]};
      default: new_vidword = {1'b0,triplet,word[11:0]};
    endcase
  end
endfunction

wire [17:0] our_next_vidram_addr = ({1'b0,coordpack_y,7'b0000000}+{3'b000,coordpack_y,5'b00000})
                                    +{10'b0000000000,coordpack_x[9:2]};

wire [17:0] vidram_addr_in_next  = ((clear_ram|write_testpat_to_ram) ? 0 : vidram_addr_in+writeready);

always @(posedge CLK)
  begin
   if(RST)
    begin
      bgcol0 <= chosen_background_color;
      bgcol1 <= chosen_background_color;
      bgcol2 <= chosen_background_color;
      bgcol3 <= chosen_background_color;
      fifo_addr_out <= 0;
      vidram_addr_in <= 0;
      vidram_data_in <= 0;
      state <= ST_INIT_VIDRAM;
    end
   else
    begin
      case(state)
        ST_WAIT_RELEASE_OF_VIDRAM:
         begin
          state <= (~vidram_client_can_write
                          ? ST_WAIT_RELEASE_OF_VIDRAM
                          : (clear_ram ? ST_INIT_VIDRAM
                                       : (write_testpat_to_ram
                                             ? ST_INIT_VIDRAM_FANCY
                                             : ST_SCAN_FIFO
                                         )
                            )
                   );
         end

        ST_INIT_VIDRAM:
         begin
          vidram_data_in <= {1'b0,chosen_background_color,1'b0,chosen_background_color,1'b0,chosen_background_color,1'b0,chosen_background_color};
//                           1'b0,bgcol0,1'b0,bgcol1,1'b0,bgcol2};
          vidram_addr_in <= vidram_addr_in_next;

          if(VIDRAM_UPPER_LIMIT == vidram_addr_in_next)
           begin
             state <= ST_SCAN_FIFO;
           end
         end

        ST_INIT_VIDRAM_FANCY:
         begin
          vidram_addr_in <= vidram_addr_in_next;
          vidram_data_in <= test_pat(vidram_addr_in_next);

          if(VIDRAM_UPPER_LIMIT == vidram_addr_in_next)
           begin
             state <= ST_SCAN_FIFO;
           end
         end

        ST_SCAN_FIFO:
         begin
          state <= (clear_ram ? ST_INIT_VIDRAM
                     : (write_testpat_to_ram ? ST_INIT_VIDRAM_FANCY
                              : (!vidram_client_can_write
                                     ? ST_WAIT_RELEASE_OF_VIDRAM
                                     : (fifo_empty ? ST_SCAN_FIFO
                                                   : ST_READ_COORDS
                                       )
                                )
                       )
                   );
         end

        ST_READ_COORDS: // And set video-ram addresses.
         begin
          our_vidram_addr_out <= our_next_vidram_addr;
          vidram_addr_in  <= our_next_vidram_addr;
          pos_in_word <= coordpack_x[1:0];
          color_from_fifo <= coordpack_color;
          state <= ST_READ_OLD_VIDWORD;
         end

        ST_READ_OLD_VIDWORD: // And mask the new pixel on top of it.
         begin
          fifo_addr_out <= fifo_addr_out+1;
          vidram_data_in
             <= new_vidword(vidram_data_out,pos_in_word,color_from_fifo);
          state <= ST_PAUSE;
         end

        ST_PAUSE: // Allow the SRAM bus to turn around. (Not needed?)
         begin
          state <= ST_WRITE_WORD;
         end

        ST_WRITE_WORD:
         begin
          state <= (!writeready ? ST_WRITE_WORD
                                : (vidram_client_can_write ? ST_SCAN_FIFO
                                                  : ST_WAIT_RELEASE_OF_VIDRAM)
                   );
         end
      endcase

    end
  end

endmodule
