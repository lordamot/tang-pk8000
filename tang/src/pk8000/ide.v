`timescale 1ns / 1ps
//========================================================================
// ide.v - the community IDE/CF adapter: a КР580ВВ55А at 50h-53h in
// front of an ATA drive, as Emu80's PpiAtaAdapter and AtaDrive model
// it (the reference for every bit here; the adapter's ROM,
// tang/rom/pk8000_hdd.rom, was written against them and the 2 MB CF
// image the community keeps its software on boots through them).
//
// Port 50h (A, out): [2:0] the ATA register, [4:3] CS (1 = the command
// block), [5] IOW, [6] IOR, [7] reset.  Port 51h (B) and 52h (C) are the
// high and low bytes of the 16-bit data bus, written before IOW rises
// and read after IOR.  A rising IOR on register 0 of the command block
// takes the next data word; a rising IOW on any register writes it.
//
// The drive: LBA only, one device, commands EC (identify), 20/21 (read
// sectors), 30/31 (write sectors), EF (set features: 01 = 8-bit data,
// 81 = 16-bit).  Status is 40h (ready, with an image) | 10h | 08h (DRQ
// while data is owed) - Emu80's, plus 80h (BSY) while a sector is on
// its way from or to the card, which Emu80 never needs and a real drive
// shows.  The data comes from the SD path (slot 3) a sector at a time:
// a read fetches its first sector at the command and the next when the
// software has drained one; a write flushes each sector as it fills.
//========================================================================
module ide (
    input             clk,
    input             reset,
    input             en,          // OSD: the IDE adapter is the expansion

    input      [7:0]  adr,
    input             io_rd,
    input             io_wr,
    input      [7:0]  wdata,
    output reg [7:0]  rdata,
    output            hit,

    input             mounted,     // one clock: an image (or none) in slot 3
    input      [31:0] image_size,
    input             wprot,

    // the SD path (sd_arbiter.v client 3)
    output reg        sd_rd,
    output reg        sd_wr,
    output     [31:0] sd_sector,
    input             sd_ack,
    input             sd_done,
    input             outen,
    input      [8:0]  outaddr,
    input      [7:0]  outbyte,
    output     [7:0]  inbyte
);

assign hit = en && (adr[7:2] == 6'b010100);   // 50h-53h

//------------------------------------------------------------------------
// The image
//------------------------------------------------------------------------
reg         present = 1'b0;
reg  [31:0] size    = 32'd0;         // bytes
wire [31:0] sectors = size[31:9];

// Not under reset: the firmware mounts the images while it holds the
// machine in reset (menu.c sends the files, then R=3, R=0), and a
// mount pulse that arrived during the reset was lost - the IDE BIOS then
// waited at "Reset..." for a drive that never became ready (4 Sep 2026).
always @(posedge clk)
    if (mounted) begin present <= (image_size != 32'd0); size <= image_size; end

//------------------------------------------------------------------------
// The ВВ55 side
//------------------------------------------------------------------------
reg  [7:0] pa = 8'd0;
reg  [7:0] pb = 8'd0;                // data high byte written
reg  [7:0] pc = 8'd0;                // data low byte written
wire [2:0] a_addr = pa[2:0];
wire [1:0] a_cs   = pa[4:3];
wire       a_iow  = pa[5];
wire       a_ior  = pa[6];
wire       a_rst  = pa[7];
reg        iow_d = 1'b0, ior_d = 1'b0, rst_d = 1'b0;

//------------------------------------------------------------------------
// The drive
//------------------------------------------------------------------------
reg  [27:0] lba      = 28'd0;
reg  [7:0]  seccount = 8'd0;
reg  [17:0] counter  = 18'd0;       // bytes owed
reg  [15:0] datareg  = 16'd0;
reg         mode8    = 1'b0;
reg  [7:0]  features = 8'd0;
reg         is_write = 1'b0;
reg         ident    = 1'b0;        // the buffer is the identify block
reg  [8:0]  ptr      = 9'd0;        // byte pointer into the buffer
reg         busy     = 1'b0;        // a sector transfer with the card
reg         need     = 1'b0;        // a sector must be fetched before more data
reg  [27:0] xfer_lba = 28'd0;       // the sector on the card

assign sd_sector = {4'd0, xfer_lba};

wire [7:0] status = {busy, present, 1'b0, 1'b1, (counter != 18'd0) && !busy && !need, 3'b000};

// the sector buffer, written by the card or by the software
reg  [7:0] buf_ [0:511];
reg        hi_pend = 1'b0;           // the high byte of a 16-bit write, a clock behind the low
reg  [8:0] hi_adr  = 9'd0;
reg  [7:0] hi_val  = 8'd0;
wire       buf_we_sd = outen && sd_ack && !is_write;
reg        buf_we_sw = 1'b0;
reg  [8:0] buf_wa    = 9'd0;
reg  [7:0] buf_wd    = 8'd0;
always @(posedge clk) begin
    if (buf_we_sd) buf_[outaddr] <= outbyte;
    else if (buf_we_sw) buf_[buf_wa] <= buf_wd;
end
// the word at ptr, ready a clock after ptr settles; the card's byte for a write
reg [7:0] cur_lo, cur_hi, wr_out;
always @(posedge clk) begin
    cur_lo <= buf_[{ptr[8:1], 1'b0}];
    cur_hi <= buf_[{ptr[8:1], 1'b1}];
    wr_out <= buf_[outaddr];
end
assign inbyte = wr_out;

// the identify block, word by word (Emu80's, LBA)
function [15:0] ident_word(input [7:0] w);
    reg [15:0] v;
    begin
        case (w)
            8'd10: v = "00"; 8'd11: v = "00"; 8'd12: v = "00"; 8'd13: v = "00"; 8'd14: v = "00";
            8'd23: v = "v."; 8'd24: v = "1."; 8'd25: v = "00";
            8'd27: v = "Em"; 8'd28: v = "u8"; 8'd29: v = "0 "; 8'd30: v = "Vi"; 8'd31: v = "rt";
            8'd32: v = "ua"; 8'd33: v = "l "; 8'd34: v = "AT"; 8'd35: v = "A "; 8'd36: v = "Co";
            8'd37: v = "nt"; 8'd38: v = "ro"; 8'd39: v = "ll"; 8'd40: v = "er";
            8'd49: v = 16'h0202;
            8'd57: v = sectors[15:0]; 8'd58: v = sectors[31:16];
            8'd60: v = sectors[15:0]; 8'd61: v = sectors[31:16];
            default: v = 16'h0000;
        endcase
        // strings are stored with the bytes of each word swapped
        ident_word = ((w >= 8'd10 && w <= 8'd14) || (w >= 8'd23 && w <= 8'd25) || (w >= 8'd27 && w <= 8'd40))
                     ? {v[7:0], v[15:8]} : v;
    end
endfunction
wire [15:0] ident_w = ident_word({1'b0, ptr[8:1]});
wire [15:0] cur_w   = ident ? ident_w : {cur_hi, cur_lo};

// what a read of B or C answers
wire [15:0] rd_w = (a_cs != 2'd1) ? (present ? 16'hFFFF : 16'h0000) :
                   (a_addr == 3'd0) ? datareg :
                   (a_addr == 3'd1) ? 16'h0000 :
                   (a_addr == 3'd7) ? {8'h00, status} :
                   (present ? 16'hFFFF : 16'h0000);

//------------------------------------------------------------------------
// The state
//------------------------------------------------------------------------
always @(posedge clk) begin
    buf_we_sw <= 1'b0;
    if (reset || !en) begin
        pa <= 8'd0; pb <= 8'd0; pc <= 8'd0; iow_d <= 1'b0; ior_d <= 1'b0; rst_d <= 1'b0;
        lba <= 28'd0; seccount <= 8'd0; counter <= 18'd0; datareg <= 16'd0; mode8 <= 1'b0;
        features <= 8'd0; is_write <= 1'b0; ident <= 1'b0; ptr <= 9'd0;
        busy <= 1'b0; need <= 1'b0; sd_rd <= 1'b0; sd_wr <= 1'b0;
    end else begin
        if (sd_ack) begin sd_rd <= 1'b0; sd_wr <= 1'b0; end
        if (busy && sd_done) begin
            busy <= 1'b0;
            if (!is_write) begin ptr <= 9'd0; need <= 1'b0; end
            xfer_lba <= xfer_lba + 28'd1;
        end
        // a sector owed and not here: fetch it
        if (need && !busy && !is_write && counter != 18'd0) begin
            busy <= 1'b1; sd_rd <= 1'b1;
        end

        // the ВВ55
        if (io_wr && hit) case (adr[1:0])
            2'd0: pa <= wdata;
            2'd1: pb <= wdata;
            2'd2: pc <= wdata;
            2'd3: if (wdata[7]) begin pa <= 8'd0; pb <= 8'd0; pc <= 8'd0; end
                  else pc[wdata[3:1]] <= wdata[0];
        endcase
        if (io_rd && hit) case (adr[1:0])
            2'd0: rdata <= 8'hFF;
            2'd1: rdata <= rd_w[15:8];
            2'd2: rdata <= rd_w[7:0];
            default: rdata <= 8'hFF;
        endcase

        // the edges of the control bits, a clock after port A changed
        iow_d <= a_iow; ior_d <= a_ior; rst_d <= a_rst;

        if (a_rst && !rst_d) begin
            lba <= 28'd0; seccount <= 8'd0; counter <= 18'd0; datareg <= 16'd0;
            mode8 <= 1'b0; features <= 8'd0; is_write <= 1'b0; ident <= 1'b0; ptr <= 9'd0; need <= 1'b0;
        end

        // IOR rising on the data register: the next word
        if (a_ior && !ior_d && a_cs == 2'd1 && a_addr == 3'd0) begin
            if (counter != 18'd0 && !busy && !need) begin
                datareg <= mode8 ? {8'h00, ptr[0] ? cur_w[15:8] : cur_w[7:0]} : cur_w;
                ptr     <= ptr + (mode8 ? 9'd1 : 9'd2);
                counter <= counter - (mode8 ? 18'd1 : 18'd2);
                // the last byte of a sector: the next one is owed from the card
                if ((ptr + (mode8 ? 9'd1 : 9'd2)) == 9'd0 && !ident) need <= 1'b1;
            end else
                datareg <= present ? 16'hFFFF : 16'h0000;
        end

        // IOW rising: write the register
        if (a_iow && !iow_d && a_cs == 2'd1) case (a_addr)
            3'd0: if (counter != 18'd0 && is_write && !busy) begin
                // the software's word into the buffer, low byte first
                buf_we_sw <= 1'b1; buf_wa <= ptr; buf_wd <= pc;
                if (!mode8) begin
                    // the high byte a clock later: hold it in the pipeline
                    hi_pend <= 1'b1; hi_adr <= ptr + 9'd1; hi_val <= pb;
                end
                ptr     <= ptr + (mode8 ? 9'd1 : 9'd2);
                counter <= counter - (mode8 ? 18'd1 : 18'd2);
                if ((ptr + (mode8 ? 9'd1 : 9'd2)) == 9'd0) begin
                    // a sector full: flush it (or drop it, write-protected)
                    if (!wprot) begin busy <= 1'b1; sd_wr <= 1'b1; end
                    else xfer_lba <= xfer_lba + 28'd1;
                end
            end
            3'd1: features <= pc;
            3'd2: seccount <= pc;
            3'd3: lba[7:0]   <= pc;
            3'd4: lba[15:8]  <= pc;
            3'd5: lba[23:16] <= pc;
            3'd6: lba[27:24] <= pc[3:0];       // bit 4 (device) must be 0, bit 6 LBA is assumed
            3'd7: case (pc)
                8'hEC: begin ident <= 1'b1; is_write <= 1'b0; ptr <= 9'd0; counter <= 18'd512; need <= 1'b0; end
                8'h20, 8'h21: if (present) begin
                    ident <= 1'b0; is_write <= 1'b0; xfer_lba <= lba;
                    counter <= {seccount, 9'd0} + (seccount == 8'd0 ? 18'd131072 : 18'd0);
                    need <= 1'b1;
                end
                8'h30, 8'h31: if (present) begin
                    ident <= 1'b0; is_write <= 1'b1; xfer_lba <= lba; ptr <= 9'd0;
                    counter <= {seccount, 9'd0} + (seccount == 8'd0 ? 18'd131072 : 18'd0);
                    need <= 1'b0;
                end
                8'hEF: if (present) begin
                    if (features == 8'h01) mode8 <= 1'b1;
                    else if (features == 8'h81) mode8 <= 1'b0;
                end
                default: ;
            endcase
        endcase

        // the high byte of a 16-bit write, the clock after the low one
        if (hi_pend) begin
            buf_we_sw <= 1'b1; buf_wa <= hi_adr; buf_wd <= hi_val; hi_pend <= 1'b0;
        end
    end
end

endmodule
