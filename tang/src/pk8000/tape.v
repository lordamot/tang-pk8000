`timescale 1ns / 1ps
//========================================================================
// tape.v - a cassette player for .cas files on the SD card.
//
// The ПК8000 loads from tape the MSX way: the ROM's TAPION waits for a
// run of 2400 Hz, measures it, then reads bytes at 1200 baud - a start
// bit of 0 (one cycle of 1200 Hz), eight data bits LSB first (a 1 is two
// cycles of 2400 Hz), two stop bits of 1 - off the tape input, which is
// bit 7 of port 8Dh.  A .cas file is the byte stream with each header
// tone replaced by the eight bytes 1F A6 DE BA CC 13 7D 74 at an
// 8-aligned position (fMSX's format; MAME's fmsx_cas.cpp is the
// reference for the waveform: 1000 bit-times of silence, 4000 of 1s,
// then the bytes).
//
// The file is slot 0 of the SD path; sectors are fetched through the
// arbiter into a two-sector buffer one ahead of the byte being played.
// The player runs while the OSD says Play, the machine's motor bit (port
// 82h bit 4) is on, a file is mounted and the end is not reached; Rewind
// puts it back to the start.  The tape output (recording) is not
// implemented: CSAVE goes into the sound mix and nowhere else.
//
// short_header: the testbench forces it, because 4000 bit-times is 3.3 s
// of machine time and the ROM needs far fewer to lock; a board leaves it
// at 0.
//========================================================================
module tape (
    input             clk,
    input             reset,

    input             mounted,      // one clock: a file (or none) is in slot 0
    input      [31:0] image_size,
    input             play,         // OSD 'T'
    input             rewind,       // OSD 'e', a level while the button is down
    input             motor,        // port 82h bit 4
    input             short_header,

    // the SD path (sd_arbiter.v client 0)
    output reg        sd_rd,
    output     [31:0] sd_sector,
    input             sd_ack,
    input             sd_done,
    input             outen,
    input      [8:0]  outaddr,
    input      [7:0]  outbyte,

    output reg        tape_bit,     // to port 8Dh bit 7
    output            running,      // for an LED
    output     [23:0] position      // bytes played, for the OSD some day
);

localparam [15:0] HALF_1200 = 16'd12500;    // 30 MHz / 1200 / 2
localparam [15:0] HALF_2400 = 16'd6250;

//------------------------------------------------------------------------
// The buffer: two sectors, by the sector number's parity
//------------------------------------------------------------------------
reg [7:0]  buf_ [0:1023];
reg [23:0] size    = 24'd0;      // bytes in the file (capped at 16 MB)
reg        present = 1'b0;
reg [23:0] pos     = 24'd0;      // the byte being played
reg [14:0] have_sec [0:1];       // which sector each half holds
reg        have     [0:1];
reg [14:0] want_sec = 15'd0;     // the sector being fetched
reg        fetching = 1'b0;

assign sd_sector = {17'd0, want_sec};
assign position  = pos;

wire [14:0] cur_sec  = pos[23:9];
wire [14:0] next_sec = cur_sec + 15'd1;
wire        cur_ok   = have[cur_sec[0]]  && (have_sec[cur_sec[0]]  == cur_sec);
wire        next_ok  = have[next_sec[0]] && (have_sec[next_sec[0]] == next_sec);
wire        next_exists = ({next_sec, 9'd0} < size);

// bytes of the sector arriving
always @(posedge clk)
    if (outen && sd_ack) buf_[{want_sec[0], outaddr}] <= outbyte;

// The file's presence and size are not under reset: the firmware
// mounts while it holds the machine in reset (ide.v says more).
always @(posedge clk)
    if (mounted) begin
        present <= (image_size != 32'd0);
        size    <= image_size[31:24] != 8'd0 ? 24'hFFFFFF : image_size[23:0];
    end

always @(posedge clk) begin
    if (reset) begin
        have[0] <= 1'b0; have[1] <= 1'b0; have_sec[0] <= 15'd0; have_sec[1] <= 15'd0;
        fetching <= 1'b0; sd_rd <= 1'b0;
    end else begin
        if (mounted) begin
            have[0]  <= 1'b0; have[1] <= 1'b0;
            fetching <= 1'b0; sd_rd <= 1'b0;
        end
        if (rewind) begin
            have[0] <= 1'b0; have[1] <= 1'b0;
        end
        if (sd_ack) sd_rd <= 1'b0;
        if (fetching) begin
            if (sd_done) begin
                fetching <= 1'b0;
                have[want_sec[0]]     <= 1'b1;
                have_sec[want_sec[0]] <= want_sec;
            end
        end else if (present && !rewind) begin
            if (!cur_ok) begin
                want_sec <= cur_sec; fetching <= 1'b1; sd_rd <= 1'b1;
            end else if (!next_ok && next_exists) begin
                want_sec <= next_sec; fetching <= 1'b1; sd_rd <= 1'b1;
            end
        end
    end
end

//------------------------------------------------------------------------
// The player
//------------------------------------------------------------------------
localparam [3:0] P_IDLE = 4'd0, P_LOOK = 4'd1, P_CMP = 4'd2, P_SILENCE = 4'd3,
                 P_HEADER = 4'd4, P_BYTE = 4'd5, P_BIT = 4'd6, P_NEXT = 4'd7;

reg [3:0]  pstate  = P_IDLE;
reg [2:0]  cmp_i   = 3'd0;
reg        is_hdr  = 1'b0;
reg [7:0]  cur     = 8'd0;       // the byte being sent
reg [3:0]  bit_n   = 4'd0;       // 0 start, 1..8 data, 9..10 stop
reg        bit_v   = 1'b0;       // the bit being sent
reg [2:0]  half_n  = 3'd0;       // half-periods left in the bit
reg [15:0] half_c  = 16'd0;      // clocks left in the half-period
reg [12:0] hdr_n   = 13'd0;      // header bit-times left
reg [7:0]  rbyte;

wire [9:0] rd_adr = (pstate == P_CMP) ? {cur_sec[0], pos[8:3], cmp_i} : {cur_sec[0], pos[8:0]};
always @(posedge clk) rbyte <= buf_[rd_adr];

function [7:0] magic(input [2:0] i);
    case (i)
        3'd0: magic = 8'h1F; 3'd1: magic = 8'hA6; 3'd2: magic = 8'hDE; 3'd3: magic = 8'hBA;
        3'd4: magic = 8'hCC; 3'd5: magic = 8'h13; 3'd6: magic = 8'h7D; default: magic = 8'h74;
    endcase
endfunction

wire go = play && motor && present && cur_ok && (pos < size) && !rewind;
assign running = go && (pstate != P_IDLE);

// a bit's shape: 1 = four half-periods of 2400 Hz, 0 = two of 1200 Hz
task start_bit(input v);
    begin
        bit_v  <= v;
        half_n <= v ? 3'd4 : 3'd2;
        half_c <= v ? HALF_2400 : HALF_1200;
    end
endtask

always @(posedge clk) begin
    if (reset || rewind || mounted) begin
        pstate   <= P_IDLE;
        pos      <= 24'd0;
        tape_bit <= 1'b0;
    end else if (!go) begin
        // paused: keep the position, hold the level
        if (pstate != P_IDLE && pstate != P_HEADER && pstate != P_SILENCE) ;   // resume where we were
    end else case (pstate)
        P_IDLE: begin
            pstate <= P_LOOK;
        end
        P_LOOK: begin
            // at an 8-aligned position, is a header here?
            if (pos[2:0] == 3'd0) begin cmp_i <= 3'd0; is_hdr <= 1'b1; pstate <= P_CMP; end
            else pstate <= P_BYTE;
        end
        P_CMP: begin
            // rbyte lags rd_adr by a clock: compare the byte for cmp_i-1
            if (cmp_i != 3'd0 && rbyte != magic(cmp_i - 3'd1)) is_hdr <= 1'b0;
            if (cmp_i == 3'd7) begin
                pstate <= P_NEXT;   // one more clock for byte 7
            end
            cmp_i <= cmp_i + 3'd1;
        end
        P_NEXT: begin
            // the byte for cmp_i == 7 (cmp_i has wrapped to 0)
            if (is_hdr && rbyte == magic(3'd7)) begin
                pos    <= pos + 24'd8;
                hdr_n  <= short_header ? 13'd200 : 13'd1000;
                tape_bit <= 1'b0;
                half_c <= HALF_1200 + HALF_1200;
                pstate <= P_SILENCE;
            end else
                pstate <= P_BYTE;
        end
        P_SILENCE: begin
            // hdr_n bit-times of nothing, then the header tone
            if (half_c != 16'd0) half_c <= half_c - 16'd1;
            else if (hdr_n != 13'd0) begin hdr_n <= hdr_n - 13'd1; half_c <= HALF_1200 + HALF_1200; end
            else begin
                hdr_n  <= short_header ? 13'd1500 : 13'd4000;
                start_bit(1'b1);
                pstate <= P_HEADER;
            end
        end
        P_HEADER: begin
            // hdr_n bit-times of 1
            if (half_c != 16'd0) half_c <= half_c - 16'd1;
            else if (half_n != 3'd1) begin tape_bit <= ~tape_bit; half_n <= half_n - 3'd1; half_c <= HALF_2400; end
            else if (hdr_n != 13'd0) begin tape_bit <= ~tape_bit; hdr_n <= hdr_n - 13'd1; start_bit(1'b1); end
            else pstate <= P_LOOK;
        end
        P_BYTE: begin
            // rbyte holds buf[pos] (the address has been pos for a clock)
            cur   <= rbyte;
            bit_n <= 4'd0;
            start_bit(1'b0);
            pstate <= P_BIT;
        end
        P_BIT: begin
            if (half_c != 16'd0) half_c <= half_c - 16'd1;
            else if (half_n != 3'd1) begin
                tape_bit <= ~tape_bit;
                half_n   <= half_n - 3'd1;
                half_c   <= bit_v ? HALF_2400 : HALF_1200;
            end else begin
                tape_bit <= ~tape_bit;
                if (bit_n == 4'd10) begin
                    pos    <= pos + 24'd1;
                    pstate <= P_LOOK;
                end else begin
                    bit_n <= bit_n + 4'd1;
                    start_bit((bit_n >= 4'd8) ? 1'b1 : cur[bit_n[2:0]]);
                end
            end
        end
        default: pstate <= P_IDLE;
    endcase
end

endmodule
