/* Module vga4word - Written by Antti Karttunen, 30. 5. 2005 -
               Last edited 09. Jun 2005. (Still flaky.)

               This module implements a simple-minded
               VGA-controller for Spartan-3 Starter Kit Board,
               utilizing its "poor man's 3-bit RGB-VGA"
               and ISSI Fast Static Asynchronous RAM as
               its video memory.

               Whenever vidram_client_can_write signal is on
               (i.e. Hgate or Vgate is off) other modules
               can write their display data to the video memory.

               The format for the video memory:

               Each sixteen-bit word contains 4 pixels,
               each pixel having a 3-bit "poor man's RGB"
               value (with an exta zero-bit at the most significant
               position).

               The three least significant bits of the word
               correspond to the leftmost pixel, and the bits 12-14
               to the rightmost pixel of each 4-pixel horizontal strip.
 
               Each horizontal row of 640 pixels fits
               into 160 (= 640/4) 16-bit words.
               The total memory consumption is 160*480 = 76800
               words.

 */


module vga4word(input CLK,
               input RST,

               output [17:0] o_vidram_addr_out,
               input [15:0] vidram_data_out,

               input vidram_client_forced_write,
               output vidram_client_can_write,

               input [9:0] cursor_x,
               input [9:0] cursor_y,
               input test_quilt_pat,
               input hsync_polarity,
               input vsync_polarity,

               output VGA_R,
               output VGA_G,
               output VGA_B,
               output VGA_HSYNC,
               output VGA_VSYNC
              );


reg [17:0] vidram_addr_out = 18'b000000000000000000;
assign o_vidram_addr_out = vidram_addr_out;
// wire [15:0] vidram_data_out;



/* Parameters, wires and registers involved with VGA controller. */


parameter RES_HOR = 640;
parameter RES_VER = 480;

// With 640 & 480 and 5 pixels/16 bit word we get 61440 words, 
// With 640 & 480 and 4 pixels/16 bit word we get 76800 words, 
parameter VIDRAM_UPPER_LIMIT = ((RES_HOR/4)*RES_VER);

// horizontal timing parameters
parameter V_THSYNC = 96-1;  // horizontal sync pulse width (in pixels)
parameter V_THGDEL = 48-1;  // horizontal gate delay (in pixels)
parameter V_THGATE = RES_HOR-1; // hor. gate (number of visible pixels per line)
parameter V_THLEN  = 800-1; // hor. length (tot. number of pixels per line)

// vertical timing parameters
parameter V_TVSYNC = 2-1;   // vertical sync pulse width (in lines)
parameter V_TVGDEL = 29-1;  // vertical gate delay (in lines)
parameter V_TVGATE = RES_VER-1; // vertical gate (# of visible lines per frame)
parameter V_TVLEN  = 521-1;  // vertical length (number of lines per frame)

reg [ 7:0] Thsync = V_THSYNC;
reg [ 7:0] Thgdel = V_THGDEL;
reg [15:0] Thgate = V_THGATE;
reg [15:0] Thlen  = V_THLEN;

reg [ 7:0] Tvsync = V_TVSYNC;
reg [ 7:0] Tvgdel = V_TVGDEL;
reg [15:0] Tvgate = V_TVGATE;
reg [15:0] Tvlen  = V_TVLEN;

reg pix_clk = 0;

reg [9:0] vga_x = 0; // Allow range 0-1023. (in practice 0-639)
reg [9:0] vga_y = 0; // Allow range 0-1023. (in practice 0-479)
reg [9:0] vga_x_plus1 = 1;
reg [9:0] vga_y_plus1 = 1;


wire hsync;
wire vsync;

assign VGA_HSYNC = hsync^hsync_polarity;
assign VGA_VSYNC = vsync^vsync_polarity;


wire eof;
wire Hgate, Vgate;
wire Gate = (Hgate & Vgate);
wire Hdone;

// Take later also pixels_left to the consideration:
// wire vidram_client_can_write = (~Hgate | ~Vgate);
// This gives the "calling module" some extra time to finish
// its calisthenics with video ram, when the ray is still
// on the horizontal front porch (at the left side of the
// topmost row):
assign vidram_client_can_write = (~Vgate);

wire cursor_x_now = ((vga_x == cursor_x) || (vga_x_plus1 == cursor_x));
wire cursor_y_now = ((vga_y == cursor_y) || (vga_y_plus1 == cursor_y));


reg [2:0] pixels_left = 0;
reg [14:0] quartet;



wire current_R = ((cursor_x_now && cursor_y_now)^quartet[2]);
wire current_G = ((cursor_x_now && cursor_y_now)^quartet[1]);
wire current_B = ((cursor_x_now && cursor_y_now)^quartet[0]);


// These three functions generate a nice 20x15 (640/32 x 480/32) quilt pattern.
// The top-left corner should be white (111)

function foo_R;
  input [9:0] x;
  input [9:0] y;
  begin
     foo_R = ~x[5];
  end
endfunction

function foo_G;
  input [9:0] x;
  input [9:0] y;
  begin
     foo_G = ~y[5];
  end
endfunction

function foo_B;
  input [9:0] x;
  input [9:0] y;
  begin
// Use (x[5] == y[5]); for less colours (W R G B) but also less ugly colours!
     foo_B = (x[6] == y[6]);
  end
endfunction


assign VGA_R = Gate & (test_quilt_pat ? foo_R(vga_x,vga_y) : current_R);
assign VGA_G = Gate & (test_quilt_pat ? foo_G(vga_x,vga_y) : current_G);
assign VGA_B = Gate & (test_quilt_pat ? foo_B(vga_x,vga_y) : current_B);


// hookup horizontal timing generator
vgatimer hor_gen(
	.clk(CLK),
	.ena(pix_clk),
	.rst(RST),
	.Tsync(Thsync),
	.Tgdel(Thgdel),
	.Tgate(Thgate),
	.Tlen(Thlen),
	.Sync(hsync),
	.Gate(Hgate),
	.Done(Hdone)
);


// hookup vertical timing generator
wire vclk_ena = Hdone & pix_clk;

vgatimer ver_gen(
	.clk(CLK),
	.ena(vclk_ena),
	.rst(RST),
	.Tsync(Tvsync),
	.Tgdel(Tvgdel),
	.Tgate(Tvgate),
	.Tlen(Tvlen),
	.Sync(vsync),
	.Gate(Vgate),
	.Done(eof)
	);

wire [17:0] vidram_addr_out_next = vidram_addr_out + 1;
wire [2:0] pixels_one_less = pixels_left - 1;


always @(posedge CLK)
 begin
  if(RST)
     begin
       pix_clk <= 0;
       pixels_left <= 0;
       vidram_addr_out <= 0;
     end
   else
     begin
      pix_clk <= ~pix_clk; // Toggle the pixel clock.

// Note how we increment the vidram address on the "even" (non-pix_clk) cycles,
// so that ISSI SRAM has time to return the vidram_data_out for
// the next cycle, when pix_clk=1 and its contents are copied to
// quartet:

      if(~pix_clk)
       begin
         vidram_addr_out <= (~Vgate ? 0 : (((0==pixels_left) && (Hgate))
                                                       ? vidram_addr_out_next
                                                       : vidram_addr_out
                                          )
                            );
       end
      else // On the pix_clk
       begin

        if(Hgate)
         begin   
           if(0 == pixels_left)
             begin
               quartet <= vidram_data_out[14:0];
               pixels_left <= 3;
             end
           else // Shift quartet right by 4 bits (1 pixel):
             begin
               quartet <= {4'b0000,quartet[14:4]};
               pixels_left <= pixels_one_less;
             end
         end

         vga_x       <= (~Hgate ? 0 : vga_x + 1);
         vga_x_plus1 <= (~Hgate ? 1 : vga_x_plus1 + 1);
   
         vga_y       <= (~Vgate ? 0 : vga_y + Hdone);
         vga_y_plus1 <= (~Vgate ? 1 : vga_y_plus1 + Hdone);

       end
     end
 end

endmodule
