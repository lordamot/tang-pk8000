`timescale 1ns / 1ps
//========================================================================
// video.v - the ПК8000's display controller, and the HDMI raster it is
// shown on.
//
// The machine's raster is 320 pixel slots of 200 ns a line (64 us) and
// 308 lines a frame - 50.73 Hz - with the picture on lines 71..262 and,
// across the line, either 256 pixels of 32 tiles (modes 1 and 2) in
// slots 32..287, or 240 pixels of 40 six-wide characters (mode 0) in
// slots 40..279; the rest is border in the colour of port 88h's high
// nibble.  Mode 3 is border only.  All of that is Emu80's model of the
// machine, which is the best account there is; the line and frame
// lengths are what its author measured.
//
// Each line is rendered into a line buffer, one 4-bit colour a slot, as
// the beam would have drawn it - the border colour, the foreground
// colour and the blanking bit are all read live, so a program that
// changes them mid-line gets the same stripe it gets on the machine.
// The tile data comes out of SDRAM one tile ahead through the video
// slot of the controller's timetable (sdram.v): a tile is 48 clocks
// (36 in mode 0), one slot every 12, and the fetch of a tile is two
// dependent reads (name, pattern) or three (name, pattern, colour).
//
// The HDMI side reads that buffer back twice, so every machine line is
// two output lines of 32 us: 960 clocks at 30 MHz, three a slot.  That
// makes a 768 x 576 picture in a 960 x 616 frame at 31.25 kHz and 50.73
// Hz - not a CEA mode, but a monitor takes it as it took UKNC Nano's
// 51 Hz.  The active window is slots 32..287 of the line and machine
// lines 19..306, which shows the 256-wide picture with the border round
// it and a 40-column picture with eight more slots of border a side.
//
//   out_h 0..959  : DE 96..863, front porch 864..879, HSYNC 880..911,
//                   back porch 912..959 and 0..95 (144 clocks: the data
//                   island in hdmi_tx.v needs 122 with three packets)
//   out_v 0..615  : VSYNC 4..9, DE 38..613
//
// Colours are the machine's four bits {R, B, G, I}: a component is 0A8h
// or 0FFh by I, and 0 without its bit.  Emu80's palette, MAME's within
// a shade.
//========================================================================
module video (
    input             clk,
    input             reset,
    input      [10:0] hcnt,         // 0..1919, phase-locked to tphase
    input      [8:0]  vcnt,         // 0..307
    input      [3:0]  tphase,

    // the registers, live
    input      [1:0]  mode,         // 0 text 40, 1 text 32, 2 graphics, 3 border only
    input      [1:0]  bank,         // which 16 KB quarter holds the screen
    input      [3:0]  txt_base,     // port 90h [3:0]
    input      [3:0]  sg_base,      // port 91h [3:0] (bit 0 unused)
    input             gr_base,      // ~port 92h [3]
    input             col_base,     // ~port 93h [3]
    input      [7:0]  color88,      // port 88h: fg low, bg (border) high
    input             blanking,     // port 86h bit 4 low

    // the mode-1 colour RAM, ports A0h-BFh
    input             col_we,
    input      [4:0]  col_adr,
    input      [7:0]  col_wdata,
    output     [7:0]  col_rdata,

    // the SDRAM's video port
    output reg        vid_req,
    output reg [15:0] vid_adr,
    input      [7:0]  vid_rdata,
    input             vid_ack,

    // to the encoder, one clock a pixel
    output reg        hs,
    output reg        vs,
    output reg        de,
    output reg [7:0]  r,
    output reg [7:0]  g,
    output reg [7:0]  b,

    // to the CPU's wait model
    output            stall_wide,   // a 40-column mode in the active part of a line
    output            border_wide,  // a 40-column mode at all
    // the frame interrupt: one clock at the start of line 263
    output            frame_irq
);

//------------------------------------------------------------------------
// Where the picture is on the line, by mode
//------------------------------------------------------------------------
wire        wide     = (mode == 2'd0) || (mode == 2'd3);
wire [10:0] x0       = wide ? 11'd240 : 11'd192;     // first active clock
wire [10:0] x1       = wide ? 11'd1680 : 11'd1728;   // one past the last
wire [5:0]  w6       = wide ? 6'd36  : 6'd48;        // clocks a tile
wire [8:0]  line     = vcnt - 9'd71;                 // 0..191 when active
wire        v_active = (vcnt >= 9'd71) && (vcnt <= 9'd262);
wire        h_active = (hcnt >= x0) && (hcnt < x1);

assign stall_wide  = wide && h_active;
assign border_wide = wide;
assign frame_irq   = (vcnt == 9'd263) && (hcnt == 11'd0);

//------------------------------------------------------------------------
// The colour RAM of mode 1: 32 bytes, {bg, fg} by name>>3.  Written
// only while blanking (the machine cannot get at it while the display
// reads it; Emu80 gates the write the same way), read by the CPU any
// time.
//------------------------------------------------------------------------
reg [7:0] colram [0:31];
integer ci;
initial for (ci = 0; ci < 32; ci = ci + 1) colram[ci] = 8'h00;

always @(posedge clk)
    if (col_we && blanking) colram[col_adr] <= col_wdata;

assign col_rdata = colram[col_adr];

//------------------------------------------------------------------------
// The fetch, one tile ahead.
//
// A tile period is 3 or 4 T-states.  In the T-states of the period
// before a tile is displayed: T0 name, T1 pattern (and, mode 1, the
// colour byte from colram), T2 colour byte (mode 2).  Each request goes
// out at phase 1 and its byte is back at phase 6 of the same T-state
// (sdram.v), in time for the next request.
//------------------------------------------------------------------------
reg  [1:0]  ftst  = 2'd0;   // T-state within the tile period
reg  [5:0]  ftile = 6'd0;   // the tile being fetched
reg  [7:0]  f_name  = 8'd0;
reg  [7:0]  f_pat   = 8'd0;
reg  [7:0]  f_col   = 8'd0;

wire        fetch_win = (hcnt >= x0 - {5'd0, w6}) && (hcnt < x1 - {5'd0, w6});
wire        f_first   = (hcnt == x0 - {5'd0, w6});
wire        tile_last = (ftst == (wide ? 2'd2 : 2'd3));
wire        tile_end  = tile_last && (tphase == 4'd11);
// the hand-over to the display is a clock before the period ends: the
// display loads on the period's last clock and would otherwise take the
// value of the tile before
wire        hand_over = tile_last && (tphase == 4'd10);

// the quarter of RAM the screen lives in
wire [15:0] scr = {bank, 14'd0};

// row 0..23, line 0..7 within it, and the graphics mode's thirds
wire [4:0] row   = line[7:3];
wire [2:0] lrow  = line[2:0];
wire [1:0] part  = line[7:6];
wire [2:0] row8  = line[5:3];

reg [15:0] a_name, a_pat, a_col;
always @(*) begin
    case (mode)
    2'd0: begin   // 40 columns: 64 bytes a row, bit 0 of the text base ignored
        a_name = scr + {2'd0, txt_base[3:1], 1'b0, 10'd0} + {5'd0, row, 6'd0} + {10'd0, ftile};
        a_pat  = scr + {2'd0, sg_base[3:1], 11'd0} + {5'd0, f_name, 3'd0} + {13'd0, lrow};
        a_col  = 16'd0;
    end
    2'd1: begin   // 32 columns
        a_name = scr + {2'd0, txt_base, 10'd0} + {6'd0, row, 5'd0} + {11'd0, ftile[4:0]};
        a_pat  = scr + {2'd0, sg_base[3:1], 11'd0} + {5'd0, f_name, 3'd0} + {13'd0, lrow};
        a_col  = 16'd0;
    end
    default: begin   // graphics: names under the symbol-generator base, thirds of 800h
        a_name = scr + {2'd0, sg_base[3:1], 11'd0} + {6'd0, part, 8'd0} + {8'd0, row8, 5'd0} + {11'd0, ftile[4:0]};
        a_pat  = scr + {2'd0, gr_base, 13'd0} + {3'd0, part, 11'd0} + {5'd0, f_name, 3'd0} + {13'd0, lrow};
        a_col  = scr + {2'd0, col_base, 13'd0} + {3'd0, part, 11'd0} + {5'd0, f_name, 3'd0} + {13'd0, lrow};
    end
    endcase
end

// what the next tile will show, handed over at the tile boundary
reg [7:0] n_pat = 8'd0;
reg [3:0] n_fg  = 4'd0;
reg [3:0] n_bg  = 4'd0;

always @(posedge clk) begin
    vid_req <= 1'b0;
    if (reset || !v_active || mode == 2'd3) begin
        ftst  <= 2'd0;
        ftile <= 6'd0;
    end else if (f_first) begin
        ftst  <= 2'd0;
        ftile <= 6'd0;
    end else if (fetch_win) begin
        // registered here, so raised on phase 0 to be UP on phase 1, the
        // slot's first clock - raised on phase 1 it was up on phase 2 and
        // sdram.v never took a single request (the first long run drew
        // a black picture over a correct name table)
        if (tphase == 4'd0) begin
            case (ftst)
            2'd0: begin vid_req <= 1'b1; vid_adr <= a_name; end
            2'd1: begin vid_req <= 1'b1; vid_adr <= a_pat;  end
            2'd2: if (mode == 2'd2) begin vid_req <= 1'b1; vid_adr <= a_col; end
            default: ;
            endcase
        end
        if (vid_ack) begin
            case (ftst)
            2'd0: f_name <= vid_rdata;
            2'd1: f_pat  <= vid_rdata;
            2'd2: f_col  <= vid_rdata;
            default: ;
            endcase
        end
        if (tphase == 4'd11) begin
            if (tile_end) begin
                ftst  <= 2'd0;
                ftile <= ftile + 6'd1;
            end else
                ftst <= ftst + 2'd1;
        end
    end
    // the hand-over, a clock before the tile period ends: the pattern is
    // in f_pat by then in every mode and the colour byte for mode 2
    if (hand_over) begin
        n_pat <= f_pat;
        case (mode)
        2'd1: begin n_fg <= colram[f_name[7:3]][3:0]; n_bg <= colram[f_name[7:3]][7:4]; end
        2'd2: begin n_fg <= f_col[3:0];                 n_bg <= f_col[7:4];                 end
        default: begin n_fg <= 4'd0; n_bg <= 4'd0; end
        endcase
    end
end

//------------------------------------------------------------------------
// The render: one colour a slot into the line buffer.
//------------------------------------------------------------------------
reg  [8:0]  slot   = 9'd0;    // 0..319
reg  [2:0]  px6    = 3'd0;    // clock within the slot
reg  [7:0]  d_pat  = 8'd0;
reg  [3:0]  d_fg   = 4'd0;
reg  [3:0]  d_bg   = 4'd0;
reg  [2:0]  d_px   = 3'd0;    // pixel within the tile
wire        d_last = (d_px == (wide ? 3'd5 : 3'd7));

always @(posedge clk) begin
    if (hcnt == 11'd0) begin slot <= 9'd0; px6 <= 3'd0; end
    else if (px6 == 3'd5) begin px6 <= 3'd0; slot <= slot + 9'd1; end
    else px6 <= px6 + 3'd1;

    // tiles begin on clock x0 + k*w6, which is a slot boundary
    if (hcnt == x0 - 11'd1 || (h_active && px6 == 3'd5 && d_last)) begin
        d_pat <= n_pat; d_fg <= n_fg; d_bg <= n_bg; d_px <= 3'd0;
    end else if (h_active && px6 == 3'd5) begin
        d_pat <= {d_pat[6:0], 1'b0};
        d_px  <= d_px + 3'd1;
    end
end

// the colour of this slot, from what is live now
wire       pix_on = d_pat[7];
reg  [3:0] pix;
always @(*) begin
    if (!v_active || !h_active || mode == 2'd3)
        pix = color88[7:4];
    else case (mode)
        2'd0:    pix = pix_on ? color88[3:0] : color88[7:4];
        2'd1:    pix = blanking ? 4'hF : (pix_on ? d_fg : d_bg);
        default: pix = pix_on ? d_fg : d_bg;
    endcase
end

// Two lines of 320: the one being drawn and the one being shown.  (640
// entries was the first size, and {wline, slot} overran it above slot
// 127 of the odd lines - a striped border on alternate output lines.)
reg [3:0] lbuf [0:1023];    // indexed {wline, slot}: 512 a line, 320 used
reg       wline = 1'b0;      // which half is being written
always @(posedge clk) begin
    if (hcnt == 11'd0) wline <= vcnt[0];
    if (px6 == 3'd5) lbuf[{wline, slot}] <= pix;
end

//------------------------------------------------------------------------
// The output raster, two lines an input line.
//------------------------------------------------------------------------
wire        second  = (hcnt >= 11'd960);
wire [9:0]  out_h   = second ? hcnt[9:0] - 10'd960 : hcnt[9:0];
wire [9:0]  out_v   = {vcnt, second};

reg  [8:0]  oslot = 9'd0;
reg  [1:0]  o3    = 2'd0;
always @(posedge clk) begin
    if (out_h == 10'd0) begin oslot <= 9'd0; o3 <= 2'd0; end
    else if (o3 == 2'd2) begin o3 <= 2'd0; oslot <= oslot + 9'd1; end
    else o3 <= o3 + 2'd1;
end

wire de_n  = (out_h >= 10'd96) && (out_h < 10'd864) && (out_v >= 10'd38) && (out_v < 10'd614);
wire hs_n  = (out_h >= 10'd880) && (out_h < 10'd912);
wire vs_n  = (out_v >= 10'd4) && (out_v < 10'd10);

// the read is registered, so the syncs go through one register too
reg [3:0] q;
always @(posedge clk) begin
    q  <= lbuf[{~wline, oslot}];
    hs <= hs_n;
    vs <= vs_n;
    de <= de_n;
end

wire [7:0] lvl = q[0] ? 8'hFF : 8'hA8;
always @(*) begin
    r = q[3] ? lvl : 8'h00;
    b = q[2] ? lvl : 8'h00;
    g = q[1] ? lvl : 8'h00;
end

endmodule
