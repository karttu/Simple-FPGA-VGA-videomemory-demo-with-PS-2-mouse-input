
/* ps2mbits:  by karttu, 25. 3. 2005.
              In normal operation, collect the bits sent
              by PS/2-mouse to the bitsOut vector (in reverse order),
              so that the bit received first (the start bit, always = 0)
              is situated at the rightmost position,
              then the least significant of the data bits
              in the second rightmost, and the one
              received last (the stop bit, always = 1)
              at the leftmost position, i.e. bitsOut[32].

              Rise the signal noMoreBits when enough time
              (here 16384 CLK cycles) has passed since
              the PS2CLK signal last went low 
              i.e. presumably when all the 33 bits (including
              also all the start, parity and stop bits) have
              been received.

              However, if the input signal OUT_BYTE
              is rised, then the state machine will switch
              to the state ST_START_OUTPUT, and not until after
              sending all the 8 bits given in SBYTE,
              together with the associated start, parity
              and stop bits, the state machine will return
              back to its default state ST_READ_BITS.

              Note that in this case the noMoreBits will be
              risen already after the acknowledgement byte and the
              assorted start, parity and stop bits have been
              received into bitsOut[32:22].
              (Unless the mouse starts immediately to send
               its 33-bit position packets?)

              Note that 50 us/20 ns = 2500, 50 us/5 ns = 10000.

              16384 * 20 ns = 327680 ns = 328 us = 0.33 ms.

              16384 * 10 ns = 163840 ns = 164 us = 0.16 ms.

              2048 * 20 ns = 40960 ns = 41 us.

   Changes

                26. 4. 2005  karttu
                  Added n_bits_read, so that the "caller"
                  can check whether the "whole packet"
                  (e.g. 11 or 33 bits) were received.

 */

module ps2mbits(CLK,OUT_BYTE,SBYTE,PS2CLK,PS2DATA,bitsOut,noMoreBits,n_bits_read);

parameter n_bits = 33;

input CLK;
input OUT_BYTE; // SBYTE contains a new byte to send?
input [7:0] SBYTE; // A byte sent to the mouse.
inout PS2CLK;
inout PS2DATA;
output [n_bits-1:0] bitsOut;
reg [n_bits-1:0] bitsOut = 0;
output noMoreBits;

reg noMoreBitsReg = 0;
output n_bits_read;
reg [5:0] n_bits_read = 0; // max 63 with this.

parameter [3:0] ST_READ_BITS       = 4'b0000;
parameter [3:0] ST_START_OUTPUT    = 4'b0100;
parameter [3:0] ST_KEEP_CLOCK_LOW  = 4'b0101;
parameter [3:0] ST_KEEP_BOTH_LOW   = 4'b0111; // Bring also the data low.
parameter [3:0] ST_SEND_BITS       = 4'b0110;
parameter [3:0] ST_WAIT_DEV_ACK1   = 4'b1100;
parameter [3:0] ST_WAIT_DEV_ACK2   = 4'b1000;


reg [3:0] state = ST_READ_BITS;

// From msb to lsb: parity bit + byte sent to mouse + 0 (start bit):
reg [9:0] mbyte = 0;

assign PS2CLK  = (state[0] ? 1'b0 : 1'bz);
assign PS2DATA = (state[1] ? mbyte[0] : 1'bz);

wire s_ps2clk;
wire s_ps2data;
reg prev_s_ps2clk = 0;
reg prev_s_ps2data = 0;

syncinp SYNCPS2CLK(CLK,PS2CLK,s_ps2clk);
syncinp SYNCPS2DATA(CLK,PS2DATA,s_ps2data);


parameter cycle1310us = 16; // 2^16 = 65536, 65536*20 ns = 1.31 ms.
parameter cycle655us = 15; // 2^15 = 32768, 32768*20 ns = 655,360 us.
parameter cycle328us = 14; // 2^14 = 16384, 16384*20 ns = 328 us.
parameter cycle20us = 10; // 2^10 = 1024, 1024*20 ns = 20,4 us.

reg [cycle1310us-1:0] cntr = 0;
wire [cycle1310us-1:0] cntr1310us = cntr[cycle1310us-1:0];
wire [cycle655us-1:0] cntr655us = cntr[cycle655us-1:0];
wire [cycle328us-1:0] cntr328us = cntr[cycle328us-1:0];
wire [cycle20us-1:0] cntr20us = cntr[cycle20us-1:0];
wire [3:0] n_bits_sent = cntr[cycle20us+3:cycle20us];


// Raise noMoreBits signal in read mode when enough time has passed
// since the mouse clock signal last went low, i.e. when cntr = 1111...1111:
assign noMoreBits = ((ST_READ_BITS == state) & &cntr655us);

always @(posedge CLK)
  begin
    if(OUT_BYTE)
// Switch to output mode, with the new byte to be sent grabbed from SBYTE.
     begin
      mbyte <= {(~^SBYTE),SBYTE,1'b0}; // parity, 8 data bits, start bit (= 0).
      state <= ST_START_OUTPUT;
      cntr <= 0;
      noMoreBitsReg <= 0;
      n_bits_read <= 0;
     end
    else // It is the clock ticking.
     begin
      case(state)
        ST_READ_BITS:
         begin
          prev_s_ps2clk <= s_ps2clk;
  
          if(cntr) cntr <= cntr + 1;
      
          if(~s_ps2clk && prev_s_ps2clk) // Mouse clock just WENT low?
           begin // Collect the next data-bit (queued in reverse order):
            bitsOut[n_bits-1:0] <= {s_ps2data, bitsOut[n_bits-1:1]};
            cntr <= 1; // "Mark" the counter to be incrementable.
            n_bits_read <= (noMoreBitsReg ? 1 : n_bits_read + 1);
            noMoreBitsReg <= 0; // On the contrary, more bits _are_ coming now!
           end

// Raise noMoreBits signal when enough time (1.31 ms) has passed since
// the mouse clock signal last went low:
          if(&cntr655us) noMoreBitsReg <= 1; // Is rised if cntr = 1111...1111;
         end
        ST_START_OUTPUT: // Unnecessary state?
         begin
          cntr <= cntr + 1;
          state <= (&cntr328us ? ST_KEEP_CLOCK_LOW : ST_START_OUTPUT);
         end
        ST_KEEP_CLOCK_LOW: // Stay 16384 cycles (328 us) here.
         begin
          cntr <= cntr + 1;
          state <= (&cntr328us ? ST_KEEP_BOTH_LOW : ST_KEEP_CLOCK_LOW);
         end
        ST_KEEP_BOTH_LOW: // Stay 1024 cycles (20 us) here.
         begin
          cntr <= cntr + 1;
//        state <= (&cntr20us ? ST_SEND_BITS : ST_KEEP_BOTH_LOW);
          if(&cntr20us) // After our 20us round is up.
           begin
             state <= ST_SEND_BITS; // Switch to the next state,
             cntr <= 0;             // and reset the whole counter.
             prev_s_ps2clk <= 1; // Give an illusion that the clock was high.
           end
         end
        ST_SEND_BITS:
         begin
// Here we wait first for the mouse clock to go high,
// (unless we have just switched from the previous state)
// then wait it to go low, and after that we will wait 20 us
// before we shift the bits that are sent to the data line.
          prev_s_ps2clk <= s_ps2clk;
          if(~s_ps2clk)
           begin
            if(prev_s_ps2clk) // Mouse clock just WENT low?
              cntr[0] <= 1; // Start incrementing.
            else if(cntr20us) // Mouse clk has been low for at least 1 cycle.
             begin
              cntr <= cntr + 1; // incs cntr20us and sometimes also n_bits_sent
              if(&cntr20us) // 20 us has passed since the mouse clock went low?
               begin
                mbyte[9:0] <= {mbyte[9],mbyte[9:1]}; // "ASR" mbyte 1 bit right
// If n_bits_sent is 9 (on the next incrementation it would be 10),
// then all the 1+8+1 bits have been sent 
                if(9 == n_bits_sent)
                  begin
                    state <= ST_WAIT_DEV_ACK1;
                    prev_s_ps2clk  <= 1; // Give an illusion that the Clock was high.
                    prev_s_ps2data <= 1; // Give an illusion that the Data was high.
                  end
               end
             end
// Otherwise we are still waiting for the device to bring clock low.
           end
         end
        ST_WAIT_DEV_ACK1:
         begin
// Here we wait first for the mouse to bring the Data low.
// then wait it to bring the Clock low.
          prev_s_ps2clk <= s_ps2clk;
          prev_s_ps2data <= s_ps2data;
          if(~prev_s_ps2data && ~prev_s_ps2clk)
            state <= ST_WAIT_DEV_ACK2;
         end
// And after that we will wait it to release the Data and Clock:
        ST_WAIT_DEV_ACK2:
         begin
          if(s_ps2data && s_ps2clk)
            state <= ST_READ_BITS;
         end
      endcase
     end
  

  end
endmodule

