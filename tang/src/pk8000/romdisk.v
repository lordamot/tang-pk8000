`timescale 1ns / 1ps
//========================================================================
// romdisk.v - the ROM disk cartridge: a file loaded into the SDRAM.
//
// The cartridge (Emu80's Pk8000RomDisk, 384 KB in the configuration it
// ships) sits in expansion page 1: quarters 0 and 1 show the image's
// first 16 KB, quarters 2 and 3 the 16 KB page selected by a write to
// port 77h.  Here the image comes off the SD card (slot 4) when it is
// mounted and is copied into the SDRAM above the machine's 64 KB - a
// sector at a time through the arbiter into a buffer, then a byte per
// CPU slot into memory, with the CPU held in reset meanwhile (`loading`
// goes to top.v's reset).  Up to 1 MB, 64 pages; a 384 KB image takes
// about two seconds.  Reads are then ordinary SDRAM reads through the
// CPU slot at the address this module computes.
//========================================================================
module romdisk (
    input             clk,
    input             reset,
    input      [3:0]  tphase,

    input             mounted,      // one clock: a file (or none) is in slot 4
    input      [31:0] image_size,

    // the SD path (sd_arbiter.v client 4)
    output reg        sd_rd,
    output     [31:0] sd_sector,
    input             sd_ack,
    input             sd_done,
    input             outen,
    input      [8:0]  outaddr,
    input      [7:0]  outbyte,

    // the SDRAM's CPU port while loading
    output            loading,
    output            ld_req,       // at tphase 7
    output     [21:0] ld_adr,
    output reg [7:0]  ld_data,

    // port 77h
    input             p77_wr,
    input      [7:0]  wdata,

    // the address of a read from page 1, quarter q, offset off
    input      [1:0]  q,
    input      [13:0] off,
    output     [21:0] rd_adr,
    output            present
);

localparam [21:0] BASE = 22'h010000;    // above the machine's 64 KB

reg [7:0]  buf_ [0:511];
reg [11:0] nsect  = 12'd0;        // sectors in the image (up to 2048 = 1 MB)
reg [11:0] sec    = 12'd0;        // the one being loaded
reg [9:0]  idx    = 10'd0;        // byte within it being written, 512 = done
reg        busy   = 1'b0;         // loading
reg        fetch  = 1'b0;         // a sector transfer is up
reg        have   = 1'b0;
reg        pres   = 1'b0;
reg [5:0]  page   = 6'd0;

assign present   = pres;
assign loading   = busy;
assign sd_sector = {20'd0, sec};
assign ld_adr    = BASE + {sec, 9'd0} + {13'd0, idx[8:0]};
assign ld_req    = busy && have && (idx < 10'd512) && (tphase == 4'd7);

always @(posedge clk)
    if (outen && sd_ack) buf_[outaddr] <= outbyte;

// the byte for idx, read a clock ahead of the request
always @(posedge clk) ld_data <= buf_[idx[8:0]];

always @(posedge clk) begin
    if (reset) begin
        busy <= 1'b0; fetch <= 1'b0; have <= 1'b0; sd_rd <= 1'b0; pres <= 1'b0; page <= 6'd0;
    end else begin
        if (p77_wr) page <= wdata[5:0];
        if (mounted) begin
            pres  <= 1'b0;
            nsect <= (image_size > 32'h100000) ? 12'd2048 : image_size[20:9] + (image_size[8:0] != 9'd0 ? 12'd1 : 12'd0);
            sec   <= 12'd0;
            idx   <= 10'd0;
            have  <= 1'b0;
            fetch <= 1'b0;
            sd_rd <= 1'b0;
            busy  <= (image_size != 32'd0);
        end else if (busy) begin
            if (sd_ack) sd_rd <= 1'b0;
            if (!have && !fetch) begin
                fetch <= 1'b1; sd_rd <= 1'b1;
            end else if (fetch && sd_done) begin
                fetch <= 1'b0; have <= 1'b1; idx <= 10'd0;
            end else if (have) begin
                if (ld_req) idx <= idx + 10'd1;
                else if (idx == 10'd512) begin
                    have <= 1'b0;
                    if (sec + 12'd1 == nsect) begin busy <= 1'b0; pres <= 1'b1; end
                    else sec <= sec + 12'd1;
                end
            end
        end
    end
end

// quarters 0 and 1: the first page; 2 and 3: the selected one
assign rd_adr = BASE + (q[1] ? {2'd0, page, 14'd0} : 22'd0) + {8'd0, off};

endmodule
