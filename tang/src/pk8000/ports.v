`timescale 1ns / 1ps
//========================================================================
// ports.v - the ПК8000's I/O page: two КР580ВВ55А, the video registers,
// the colour RAM's window, the joysticks and the keyboard matrix.
//
// The decode is the lower board's (DD21 on sheet 2 of the schematic in
// tang/rom/): A7 set, A6 and A5 clear select the block, A4..A2 pick
//   80h-83h  ВВ55 #1 (DD33): A out - the bank register; B in - the
//            keyboard's data lines; C out - row select [3:0], tape
//            motor [4], tape out [6], the beeper [7]
//   84h-87h  ВВ55 #2 (DD32): A out - [4] graphics, [5] 40 columns,
//            [7:6] the screen's 16 KB quarter; B out - printer data;
//            C - [4] display enable (DSCR), [7] printer strobe; a read
//            of C answers 0FBh (printer not busy), as Emu80 answers it
//   88h      the colour register: fg [3:0], bg and border [7:4]
//   8Ch-8Fh  read: joystick 1 (8Ch) or 2 (8Dh); bit 7 of 8Dh is the
//            tape input
//   90h-93h  the video bases: 90h text, 91h symbol generator, 92h
//            graphics, 93h colour (Emu80's own class names have 92 and
//            93 the other way round, but its configuration and MAME
//            agree with this)
// and A7 with A5 set, A6 clear, is A0h-BFh, the 32 bytes of colour RAM
// for mode 1.  The write-only registers read back what was written,
// which is what both emulators do and what software written on them
// may rely on; the machine's bus would float.
//
// The ВВ55s are modelled in mode 0 with the direction the machine wires
// them for, plus the control word's bit set/reset form on port C, which
// is how the ROM flips single bits like the beeper.
//========================================================================
module ports (
    input             clk,
    input             reset,

    // the CPU's cycle
    input      [7:0]  adr,          // A7..A0 of an IN/OUT
    input             io_rd,        // pulse: an IN, adr valid
    input             io_wr,        // pulse: an OUT, adr and wdata valid
    input      [7:0]  wdata,
    output reg [7:0]  rdata,        // registered on io_rd, held

    // the keyboard matrix, from the MCU: {pressed, row[3:0], col[2:0]} + 1
    input      [7:0]  kbd_byte,
    input             kbd_stb,
    // the joysticks, MiSTeryNano's byte: {..., b2, b1, up, down, left, right}
    input      [7:0]  joy0,
    input      [7:0]  joy1,
    input             joy_swap,
    input             tape_in,

    // to the rest of the machine
    output reg [7:0]  bank_reg,     // port 80h
    output     [1:0]  vmode,        // {graphics, 40 columns} -> 0 text40 1 text32 2 gr 3 blank
    output     [1:0]  vbank,
    output reg [7:0]  color88,
    output reg [3:0]  txt_base,
    output reg [3:0]  sg_base,
    output            gr_base,
    output            col_base,
    output            blanking,
    output            beeper,
    output            tape_out,
    output            tape_motor,
    output reg [7:0]  printer_data,
    output reg        printer_strobe,
    // the colour RAM lives in video.v
    output            col_we,
    output     [4:0]  col_adr,
    output     [7:0]  col_wdata,
    input      [7:0]  col_rdata
);

//------------------------------------------------------------------------
// ВВ55 #1
//------------------------------------------------------------------------
reg [7:0] p1c = 8'h00;            // port C latch

wire [3:0] kbd_row = p1c[3:0];
assign tape_motor  = p1c[4];
assign tape_out    = p1c[6];
assign beeper      = p1c[7];

//------------------------------------------------------------------------
// ВВ55 #2
//------------------------------------------------------------------------
reg [7:0] p2a = 8'h00;
reg [7:0] p2c = 8'h00;

// Emu80's Pk8000Ppi8255Circuit2::setPortA: bit 4 set -> bit 5 ? 3 : 2,
// bit 4 clear -> bit 5 ? 0 : 1.  So the low bit is bit 5 XNOR bit 4.
// The first version had ~bit 5 for both halves and showed border only
// for the ROM's SCREEN 2 (84h = 10h); found by the graphics demo, 4 Sep 2026.
assign vmode    = {p2a[4], ~(p2a[4] ^ p2a[5])};
assign vbank    = p2a[7:6];
assign blanking = ~p2c[4];

// mode 0 is 40 columns and mode 3 border-only, both with bit 5 SET;
// mode 1 is bit 5 clear without graphics.  So the mode number the video
// wants is {graphics, ~bit5}: 00 text40, 01 text32, 10 graphics, 11 blank
// - which is what the assign above says once written out: bit 4 -> the
// high bit, and the low bit is bit 5 inverted.

//------------------------------------------------------------------------
// Video registers
//------------------------------------------------------------------------
reg [7:0] r90 = 8'h00, r91 = 8'h00, r92 = 8'h00, r93 = 8'h00;
always @(*) begin
    txt_base = r90[3:0];
    sg_base  = r91[3:0];
end
assign gr_base  = ~r92[3];
assign col_base = ~r93[3];

//------------------------------------------------------------------------
// The keyboard: ten rows of eight, a row reads as a byte with a pressed
// key low.  Rows 10..15 read all ones, as on the machine.  The byte from
// the MCU is the code for a press and the code with bit 7 for a release
// (usb_host.c's kbd_tx), so bit 7 IS the level the matrix wants.  The
// first version wrote its inverse: every key went down at its release
// and stayed down, the ROM typed each key once at that edge, and a
// Shift was held for ever after its first use - "1+INPRT", "cload"TEST",
// the case inverted after a Shift, all of it (4 Sep 2026).
//------------------------------------------------------------------------
reg [7:0] keys [0:15];
integer ki;
initial for (ki = 0; ki < 16; ki = ki + 1) keys[ki] = 8'hFF;

wire [6:0] kcode = kbd_byte[6:0] - 7'd1;      // codes are row*8+col+1
wire [3:0] krow  = kcode[6:3];
wire [2:0] kcol  = kcode[2:0];

always @(posedge clk) begin
    if (reset) begin
        for (ki = 0; ki < 16; ki = ki + 1) keys[ki] <= 8'hFF;
    end else if (kbd_stb && kbd_byte[6:0] != 7'd0 && krow < 4'd10) begin
        keys[krow][kcol] <= kbd_byte[7];
    end
end

wire [7:0] kbd_data = (kbd_row < 4'd10) ? keys[kbd_row] : 8'hFF;

//------------------------------------------------------------------------
// The joysticks.  MiSTeryNano hands {b2, b1, up, down, left, right} in
// bits 5..0; the machine wants {b2, b1, right, left, down, up}, active
// high, bit 6 clear, and bit 7 of port 8Dh is the tape input.
//------------------------------------------------------------------------
function [5:0] joy_map(input [7:0] j);
    joy_map = {j[5], j[4], j[0], j[1], j[2], j[3]};
endfunction
wire [7:0] joy_a = joy_swap ? joy1 : joy0;
wire [7:0] joy_b = joy_swap ? joy0 : joy1;
wire [7:0] port8c = {1'b0,    1'b0, joy_map(joy_a)};
wire [7:0] port8d = {tape_in, 1'b0, joy_map(joy_b)};

//------------------------------------------------------------------------
// Decode
//------------------------------------------------------------------------
wire blk_io  = adr[7] && !adr[6] && !adr[5];        // 80h-9Fh
wire sel_p1  = blk_io && adr[4:2] == 3'd0;
wire sel_p2  = blk_io && adr[4:2] == 3'd1;
wire sel_88  = blk_io && adr[4:2] == 3'd2;
wire sel_8c  = blk_io && adr[4:2] == 3'd3;
wire sel_90  = blk_io && adr[4:2] == 3'd4;
wire sel_col = adr[7] && !adr[6] && adr[5];         // A0h-BFh

assign col_we    = io_wr && sel_col;
assign col_adr   = adr[4:0];
assign col_wdata = wdata;

// The ВВ55 control word: bit 7 set is a mode word (all outputs reset to
// zero, which is what the ROM does first), clear is bit set/reset on
// port C: bits 3:1 the bit, bit 0 the value.
always @(posedge clk) begin
    if (reset) begin
        bank_reg <= 8'h00; p1c <= 8'h00;
        p2a <= 8'h00; p2c <= 8'h00; printer_data <= 8'h00; printer_strobe <= 1'b1;
        color88 <= 8'h00; r90 <= 8'h00; r91 <= 8'h00; r92 <= 8'h00; r93 <= 8'h00;
    end else if (io_wr) begin
        if (sel_p1) case (adr[1:0])
            2'd0: bank_reg <= wdata;
            2'd2: p1c <= wdata;
            2'd3: if (wdata[7]) begin bank_reg <= 8'h00; p1c <= 8'h00; end
                  else p1c[wdata[3:1]] <= wdata[0];
            default: ;
        endcase
        if (sel_p2) case (adr[1:0])
            2'd0: p2a <= wdata;
            2'd1: printer_data <= wdata;
            2'd2: begin p2c <= wdata; printer_strobe <= wdata[7]; end
            2'd3: if (wdata[7]) begin p2a <= 8'h00; p2c <= 8'h00; printer_data <= 8'h00; end
                  else begin p2c[wdata[3:1]] <= wdata[0]; if (wdata[3:1] == 3'd7) printer_strobe <= wdata[0]; end
            default: ;
        endcase
        if (sel_88) color88 <= wdata;
        if (sel_90) case (adr[1:0])
            2'd0: r90 <= wdata;
            2'd1: r91 <= wdata;
            2'd2: r92 <= wdata;
            2'd3: r93 <= wdata;
        endcase
    end
end

always @(posedge clk)
    if (io_rd) begin
        rdata <= 8'hFF;
        if (sel_p1) case (adr[1:0])
            2'd0: rdata <= bank_reg;
            2'd1: rdata <= kbd_data;
            2'd2: rdata <= p1c;
            default: rdata <= 8'hFF;
        endcase
        if (sel_p2) case (adr[1:0])
            2'd0: rdata <= p2a;
            2'd1: rdata <= printer_data;
            2'd2: rdata <= 8'hFB;
            default: rdata <= 8'hFF;
        endcase
        if (sel_88) rdata <= color88;
        if (sel_8c) rdata <= adr[0] ? port8d : port8c;
        if (sel_90) case (adr[1:0])
            2'd0: rdata <= r90;
            2'd1: rdata <= r91;
            2'd2: rdata <= r92;
            2'd3: rdata <= r93;
        endcase
        if (sel_col) rdata <= col_rdata;
    end

endmodule
