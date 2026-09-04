`timescale 1ns / 1ps
//========================================================================
// ay.v - the community's AY-3-8910 sound card, at the Вектор's ports.
//
// MSX's AY sits at A0h-A2h, which on the ПК8000 is the colour RAM, so
// the card Mick built for it (2008) takes the Вектор-06Ц's addresses:
// 15h selects a register, 14h reads or writes it (Emu80's pk8000.conf,
// Psg3910: addr & 1 = the register number).  1.75 MHz.
//
// The chip is UKNC Nano's ym2149.sv (MikeJ / Sorgelig) with its clock
// enable made by a phase accumulator: 7/120 of 30 MHz is 1.75 MHz
// exactly, and the enable gates the sound generation only - the
// registers are written on the system clock and none can be missed.
// SEL is 0 because CE is the chip's own rate (UKNC Nano learned that
// the octave-low way).  The three channels are summed here.
//========================================================================
module ay (
    input             clk,
    input             reset,
    input             en,          // OSD 'y': off answers nothing and plays nothing
    input      [7:0]  adr,         // A7..A0 of the IN/OUT
    input             io_rd,
    input             io_wr,
    input      [7:0]  wdata,
    output reg [7:0]  rdata,       // registered on io_rd
    output            hit,         // 14h or 15h, and the card is on
    output     [9:0]  sample       // the three channels summed, 0..765
);

assign hit = en && (adr[7:1] == 7'b0001010);   // 14h, 15h

// the bus of the chip: a strobe of one clock is enough for ym2149.sv,
// which registers on every clock
wire wr_reg  = io_wr && hit &&  adr[0];        // 15h: register number
wire wr_data = io_wr && hit && !adr[0];        // 14h: register value
wire bdir    = wr_reg | wr_data;
wire bc      = wr_reg | (!io_wr);              // read data: BDIR 0, BC 1

// 1.75 MHz from 30: add 7, take a clock at 120
reg [6:0] acc = 7'd0;
wire [7:0] acc_n = {1'b0, acc} + 8'd7;
wire ce = (acc_n >= 8'd120);
always @(posedge clk) acc <= ce ? acc_n[6:0] - 7'd120 : acc_n[6:0];

wire [7:0] do_, ca, cb, cc;

YM2149 chip (
    .CLK      (clk),
    .CE       (ce),
    .RESET    (reset | ~en),
    .BDIR     (bdir),
    .BC       (bc),
    .DI       (wdata),
    .DO       (do_),
    .CHANNEL_A(ca),
    .CHANNEL_B(cb),
    .CHANNEL_C(cc),
    .SEL      (1'b0),
    .MODE     (1'b1),        // the AY-3-8910's volume table
    .ACTIVE   (),
    .IOA_in   (8'd0),
    .IOA_out  (),
    .IOB_in   (8'd0),
    .IOB_out  ()
);

// a read answers a clock after the strobe, when DO has the register
reg rd_d = 1'b0;
always @(posedge clk) begin
    rd_d <= io_rd && hit;
    if (rd_d) rdata <= do_;
end

assign sample = en ? ({2'd0, ca} + {2'd0, cb} + {2'd0, cc}) : 10'd0;

endmodule
