`timescale 1ns / 1ps
//========================================================================
// fdc.v - the Сура's НГМД: a КР1818ВГ93 (WD1793) floppy controller with
// its 8 KB ROM, in expansion page 1.
//
// In a quarter that shows page 1 (Emu80's pk8000_fdc.conf):
//   0000h-1FFFh  the controller's ROM (tang/rom/pk8000_fdc.rom)
//   3FF7h        control (write): bit 7 reset, bit 6 drive, bit 4 side
//   3FF8h-3FFBh  the ВГ93: command/status, track, sector, data
//   3FFCh-3FFFh  four bytes the software writes and reads back through
//                the controller's state: a read answers the byte at
//                {DRQ, INTRQ} - a wait loop in one instruction
// and everything else reads 0FFh.  Writes to the ROM area go to the RAM
// under it, as everywhere (top.v).
//
// The controller is MiSTer's wd1793.sv (MikeJ, Sorgelig), in its
// sector-image mode: a .fdd image of 80 tracks x 2 sides x 5 sectors of
// 1024 bytes (track-side-sector order) on the SD card, read and written
// through the arbiter two 512-byte blocks a sector.  One chip, two
// drives: the drive bit picks which image the transfer goes to, as the
// real select line does, and the chip's track register is whatever the
// last seek left - which is the machine's behaviour too.
//
// The chip wants its rd/wr as levels a few of its clock enables long
// (it edge-detects them on `ce`, here the CPU's 2.5 MHz), so a one-clock
// strobe from the CPU is stretched to sixteen clocks; the data register
// advances on the FALLING edge, so the byte read is the one on the bus
// while the level is up, taken two clocks after the strobe.
//========================================================================
module fdc (
    input             clk,
    input             reset,
    input             ce,           // the CPU's F1: 2.5 MHz
    input             en,           // the OSD's expansion is the floppy

    // the CPU, page-1 space: the offset within the quarter
    input             rd_stb,       // at tphase 7, off valid
    input             wr_stb,       // off and wdata valid
    input      [13:0] off,
    input      [7:0]  wdata,
    output reg [7:0]  rdata,        // valid three clocks after rd_stb

    // the images
    input      [1:0]  mounted,      // one clock each: slot 1, slot 2
    input      [31:0] image_size,
    input      [1:0]  present,
    input      [1:0]  wprot,

    // the SD path: client 1 + drive
    output            drive,
    output            sd_rd,
    output            sd_wr,
    output     [31:0] sd_sector,
    input             sd_ack,
    input             sd_done,
    input             outen,
    input      [8:0]  outaddr,
    input      [7:0]  outbyte,
    output     [7:0]  inbyte,

    output            busy          // for an LED
);

//------------------------------------------------------------------------
// Decode
//------------------------------------------------------------------------
wire in_rom  = (off[13] == 1'b0);                 // 0000h-1FFFh
wire in_regs = (off[13:4] == 10'h3FF);            // 3FF0h-3FFFh
wire is_ctrl = in_regs && (off[3:0] == 4'h7);
wire is_wd   = in_regs && (off[3:2] == 2'b10);    // 8..B
wire is_st   = in_regs && (off[3:2] == 2'b11);    // C..F

reg  [13:0] off_r = 14'd0;
reg  [7:0]  wd_din = 8'd0;
reg  [4:0]  rd_hold = 5'd0, wr_hold = 5'd0;
reg  [6:0]  rst_hold = 7'd0;
reg  [1:0]  rd_pipe = 2'd0;
reg         drive_r = 1'b0, side_r = 1'b0;
reg  [7:0]  st_bytes [0:3];
integer i;
initial for (i = 0; i < 4; i = i + 1) st_bytes[i] = 8'h00;

assign drive = drive_r;

//------------------------------------------------------------------------
// The ROM
//------------------------------------------------------------------------
wire [15:0] rom_word;
fdc_rom rom (
    .dout (rom_word),
    .clk  (clk),
    .ce   (1'b1),
    .reset(1'b0),
    .ad   (off_r[12:1])
);

//------------------------------------------------------------------------
// The chip
//------------------------------------------------------------------------
wire [7:0] wd_dout;
wire       wd_drq, wd_intrq, wd_busy;
wire       wd_rd = (rd_hold != 5'd0);
wire       wd_wr = (wr_hold != 5'd0);
wire       wd_io = en && (wd_rd || wd_wr);

wd1793 #(.RWMODE(1), .EDSK(0)) chip (
    .clk_sys     (clk),
    .ce          (ce),
    .reset       (reset || (rst_hold != 7'd0)),
    .io_en       (wd_io),
    .rd          (wd_rd),
    .wr          (wd_wr),
    .addr        (off_r[1:0]),
    .din         (wd_din),
    .dout        (wd_dout),
    .drq         (wd_drq),
    .intrq       (wd_intrq),
    .busy        (wd_busy),
    .wp          (wprot[drive_r]),
    .size_code   (3'd3),           // 5 x 1024
    .layout      (1'b0),           // track, side, sector
    .side        (side_r),
    .ready       (present[drive_r]),
    .img_mounted (mounted[0] | mounted[1]),
    .img_size    (image_size),
    .prepare     (),
    .sd_lba      (sd_sector),
    .sd_rd       (sd_rd),
    .sd_wr       (sd_wr),
    .sd_ack      (sd_ack),
    .sd_buff_addr(outaddr),
    .sd_buff_dout(outbyte),
    .sd_buff_din (inbyte),
    .sd_buff_wr  (outen && sd_ack),
    .input_active(1'b0),
    .input_addr  (20'd0),
    .input_data  (8'd0),
    .input_wr    (1'b0),
    .buff_addr   (),
    .buff_read   (),
    .buff_din    (8'd0)
);

assign busy = wd_busy;

//------------------------------------------------------------------------
// The bus
//------------------------------------------------------------------------
always @(posedge clk) begin
    rd_pipe <= {rd_pipe[0], rd_stb && en};
    if (rd_hold  != 5'd0) rd_hold  <= rd_hold  - 5'd1;
    if (wr_hold  != 5'd0) wr_hold  <= wr_hold  - 5'd1;
    if (rst_hold != 7'd0) rst_hold <= rst_hold - 7'd1;

    if (reset) begin
        drive_r <= 1'b0; side_r <= 1'b0; rd_hold <= 5'd0; wr_hold <= 5'd0; rst_hold <= 7'd0;
    end else begin
        if (rd_stb && en) begin
            off_r <= off;
            if (is_wd) rd_hold <= 5'd16;
        end
        if (wr_stb && en) begin
            off_r  <= off;
            wd_din <= wdata;
            if (is_wd)   wr_hold <= 5'd16;
            if (is_ctrl) begin
                drive_r <= wdata[6];
                side_r  <= wdata[4];
                if (wdata[7]) rst_hold <= 7'd127;
            end
            if (is_st) st_bytes[off[1:0]] <= wdata;
        end
    end

    // the answer, two clocks after the strobe: the ROM word is there, the
    // chip's register is on its bus, the status byte is a lookup
    if (rd_pipe[1]) begin
        if (!in_rom_r && !in_regs_r) rdata <= 8'hFF;
        else if (in_rom_r) rdata <= off_r[0] ? rom_word[15:8] : rom_word[7:0];
        else if (is_wd_r)  rdata <= wd_dout;
        else if (is_st_r)  rdata <= st_bytes[{wd_drq, wd_intrq}];
        else               rdata <= 8'hFF;
    end
end

wire in_rom_r  = (off_r[13] == 1'b0);
wire in_regs_r = (off_r[13:4] == 10'h3FF);
wire is_wd_r   = in_regs_r && (off_r[3:2] == 2'b10);
wire is_st_r   = in_regs_r && (off_r[3:2] == 2'b11);

endmodule
