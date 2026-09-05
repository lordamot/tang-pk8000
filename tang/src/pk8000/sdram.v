`timescale 1ns / 1ps
//========================================================================
// sdram.v - the machine's 64 KB of DRAM, in the Tang Nano 20K's SDRAM.
//
// One clock, 30 MHz, and a fixed timetable.  A T-state of the CPU is
// twelve clocks (tphase 0..11, from top.v) and it is cut into two
// six-clock slots: phases 1-6 belong to the video controller and to
// refresh, phases 7-12 (7..11 and 0) to the CPU.  Each slot is one
// complete random access - ACTIVE, READ or WRITE with auto-precharge,
// data - and the slots never overlap, so neither side ever waits for
// the other and there is no arbiter to get wrong.
//
//   slot clock  0: ACTIVE     (row)             if a request is up
//               1: READ/WRITE (column, A10=1)   write data driven now
//               2: -                            write data held
//               3: read data captured
//               4: -
//               5: -
//
// Why clock 3: the chip is clocked by the PLL's copy 90 degrees behind
// ours, so it takes the READ a quarter period after we put it out (in
// clock 2) and, with CAS latency 2, has the word on the bus from tAC
// after its next edge - a third of the way into our clock 3 - until
// tOH after the one following, a quarter into our clock 4.  The edge
// ending clock 3 is inside that window with margin both ways; the edge
// ending clock 4 is past it.  The first version captured on clock 4
// and every read came back as zero in simulation, which was hidden for
// a whole run by the ROM's RAM test writing zeros: the read-after-write
// check passed on all the zeros and failed on the 84 bytes that were
// not.  sim/tb/tb_top.v's +DQTRACE shows the word on the bus clock by
// clock; sdram_model.v drives it the way the chip does.
//
// The CPU's request comes at phase 7 - the clock vm80a's SYNC is seen
// on - so its data is in cpu_rdata by phase 11, well before the core
// samples the bus.  The video asks at phase 1 and has its byte at
// phase 6.  Refresh takes a video slot the video is not using; it needs
// one every 7.8 us and the video leaves at least one in four free.
//
// Two banks of 16 bits behind an 8-bit machine: byte address a[21:1] is
// the word ([21:20] the bank, [19:9] the row, [8:1] the column), a[0]
// picks the lane by DQM on a write and by a mux on a read.  The machine's
// 64 KB is the first 64 KB; the ROM disk cartridge's image lives above it
// (romdisk.v, from 10000h).
//
// Initialisation, from sdram2.v's hard-won sequence (UKNC Nano, Sep
// 2026): a JEDEC part wants 100 us of stable clock before its first
// command, and two AUTO REFRESHes between the precharge and the mode
// load.  65536 clocks of NOP after PLL lock (2.2 ms), then the steps,
// one a slot.  `init` says the memory exists; nothing may run before.
//
// The self-test (4 Sep 2026, after the first board).  The first
// bitstream on a board showed the ROM's RAM test passing - it writes
// and reads zeros - and the code after it, which puts non-zero bytes
// through the stack, failing back to 0000h: the picture simulation
// defect 2 had, when the read was captured on the wrong slot clock.
// The clock the word is on the bus is a property of the chip and of the
// pad delays the tool does not analyse, so after `init`, while the CPU
// is still held in reset, this controller writes four non-zero bytes to
// 0FFF0h-0FFF3h through the CPU slot and reads them back.  If they do
// not come back it moves the capture to slot clock 4 (`cap_late`) and
// tries again; if that fails too `bist_fail` goes up and the capture
// goes back to clock 3.  top.v puts both on the LEDs.  The read-back
// order is the write order, so a bus that echoes the last write does not
// pass.  In simulation the model is on time: done, no fail, not late.
// What the self-test proves is the pads and the capture clock - four
// bytes in one row, nothing else touching the chip.  It passed on the
// board (second flash) while the column word below had no A10 and
// nothing precharged; the Debug page of the third flash said which
// bytes came back wrong, and that was the row handling, not the pads.
// A self-test that spans two rows with a third row's access between
// the write and the read would have caught it; this one does not.
//========================================================================
module sdram (
    input             clk,
    input             lock,         // the PLL has locked
    output            init,         // the memory is initialised

    input      [3:0]  tphase,

    // CPU port: cpu_req is a one-clock pulse at tphase 7
    input             cpu_req,
    input             cpu_we,
    input      [21:0] cpu_adr,      // byte address: [21:20] bank, [19:9] row, [8:1] column
    input      [7:0]  cpu_wdata,
    output reg [7:0]  cpu_rdata,

    // video port: vid_req is a one-clock pulse at tphase 1
    input             vid_req,
    input      [21:0] vid_adr,
    output reg [7:0]  vid_rdata,
    output reg        vid_ack,      // one clock, with vid_rdata

    // the self-test's verdict (see the header)
    output reg        bist_done,
    output reg        bist_fail,
    output reg        cap_late,     // reads captured on slot clock 4, not 3

    // the chip
    output reg [10:0] SDRAM_A,
    output reg [1:0]  SDRAM_BA,
    inout      [15:0] SDRAM_DQ,
    output            SDRAM_nCS,
    output            SDRAM_nRAS,
    output            SDRAM_nCAS,
    output            SDRAM_nWE,
    output reg        SDRAM_DQML,
    output reg        SDRAM_DQMH
);

localparam [3:0] CMD_INHIBIT      = 4'b1111;
localparam [3:0] CMD_NOP          = 4'b0111;
localparam [3:0] CMD_ACTIVE       = 4'b0011;
localparam [3:0] CMD_READ         = 4'b0101;
localparam [3:0] CMD_WRITE        = 4'b0100;
localparam [3:0] CMD_PRECHARGE    = 4'b0010;
localparam [3:0] CMD_AUTO_REFRESH = 4'b0001;
localparam [3:0] CMD_LOAD_MODE    = 4'b0000;

// Mode register: CAS latency 2, burst length 1, sequential, single
// writes.  BL1 rather than sdram2.v's BL4 so a read leaves the bus
// quiet for the next slot.
localparam [10:0] MODE = 11'b0_1_00_010_0_000;

reg  [3:0] cmd = CMD_INHIBIT;
assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = cmd;

reg  [15:0] dq_out = 16'd0;
reg         dq_oe  = 1'b0;
assign SDRAM_DQ = dq_oe ? dq_out : 16'hZZZZ;

// The slot clock: 0..5 inside the video slot (phases 1..6) and inside
// the CPU slot (phases 7..11, 0).
wire       cpu_slot = (tphase >= 4'd7) || (tphase == 4'd0);
wire [2:0] sc = (tphase == 4'd0) ? 3'd5 :
                (tphase >= 4'd7) ? tphase[2:0] - 3'd7 : tphase[2:0] - 3'd1;

//------------------------------------------------------------------------
// Power-up
//------------------------------------------------------------------------
reg  [15:0] settle   = 16'd0;
reg  [4:0]  istep    = 5'd0;      // 0 = done
reg         started  = 1'b0;
assign init = started && (istep == 5'd0);

//------------------------------------------------------------------------
// Refresh: one every 7.8 us, 234 clocks, kept as a count of those due
// so a run of busy slots catches up afterwards.
//------------------------------------------------------------------------
reg  [7:0] ref_cnt = 8'd0;
reg  [2:0] ref_due = 3'd0;

//------------------------------------------------------------------------
// The self-test: eight accesses through the CPU slot, one a T-state,
// advanced at phase 1 when the read data of the T-state before is in
// cpu_rdata whichever clock captured it.  The CPU is in reset for
// 280 ms after init (top.v's por_done), so its port is free.
//------------------------------------------------------------------------
reg         bist_run  = 1'b0;     // the test is running
reg         bist_rd   = 1'b0;     // 0 the write pass, 1 the read pass
reg  [1:0]  bist_i    = 2'd0;
reg         bist_bad  = 1'b0;     // a mismatch in this read pass
wire        bist_req  = bist_run;
wire [21:0] bist_adr  = {6'd0, 14'h3FFC, bist_i};       // 0FFF0h..0FFF3h
reg  [7:0]  bist_pat;
always @(*) case (bist_i)
    2'd0: bist_pat = 8'h55;
    2'd1: bist_pat = 8'hAA;
    2'd2: bist_pat = 8'h5A;
    2'd3: bist_pat = 8'hA5;
endcase

//------------------------------------------------------------------------
// The cycle in flight
//------------------------------------------------------------------------
reg         act      = 1'b0;      // this slot has a request
reg         act_we   = 1'b0;
reg         act_vid  = 1'b0;
reg  [21:0] act_adr  = 22'd0;
reg  [7:0]  act_data = 8'd0;

always @(posedge clk) begin
    cmd        <= CMD_NOP;
    dq_oe      <= 1'b0;
    vid_ack    <= 1'b0;
    SDRAM_DQML <= 1'b1;
    SDRAM_DQMH <= 1'b1;

    if (!lock) begin
        settle  <= 16'd0;
        istep   <= 5'd31;
        started <= 1'b0;
        cmd     <= CMD_INHIBIT;
        ref_due <= 3'd0;
        ref_cnt <= 8'd0;
        bist_run  <= 1'b0;  bist_rd  <= 1'b0; bist_i   <= 2'd0; bist_bad <= 1'b0;
        bist_done <= 1'b0;  bist_fail <= 1'b0; cap_late <= 1'b0;
    end else if (!started) begin
        // 2.2 ms of clock before the first command
        if (&settle) begin started <= 1'b1; istep <= 5'd31; end
        else settle <= settle + 16'd1;
        SDRAM_A  <= 11'd0;
        SDRAM_BA <= 2'd0;
    end else if (istep != 5'd0) begin
        // one step a slot, on the slot's first clock
        if (sc == 3'd0 && !cpu_slot) begin
            istep <= istep - 5'd1;
            case (istep)
                5'd20: begin cmd <= CMD_PRECHARGE;    SDRAM_A <= 11'b100_0000_0000; end
                5'd16: cmd <= CMD_AUTO_REFRESH;
                5'd12: cmd <= CMD_AUTO_REFRESH;
                5'd8:  begin cmd <= CMD_LOAD_MODE;    SDRAM_A <= MODE; end
                default: ;
            endcase
        end
    end else begin
        //----------------------------------------------------------------
        // Running.
        //----------------------------------------------------------------
        // the self-test: started once, at a phase 1 so that its first
        // request is taken at the phase 7 after it and its first tick,
        // at the next phase 1, follows that access
        if (!bist_done && !bist_run && tphase == 4'd1) bist_run <= 1'b1;
        if (bist_run && tphase == 4'd1) begin
            if (bist_rd && cpu_rdata != bist_pat) bist_bad <= 1'b1;
            bist_i <= bist_i + 2'd1;
            if (bist_i == 2'd3) begin
                if (!bist_rd)
                    bist_rd <= 1'b1;
                else begin
                    bist_rd <= 1'b0;
                    bist_bad <= 1'b0;
                    if (!(bist_bad || cpu_rdata != bist_pat)) begin
                        bist_run <= 1'b0; bist_done <= 1'b1;        // pass, keep cap_late
                    end else if (!cap_late) begin
                        cap_late <= 1'b1;                          // try the other clock
                    end else begin
                        bist_run <= 1'b0; bist_done <= 1'b1;
                        bist_fail <= 1'b1; cap_late <= 1'b0;
                    end
                end
            end
        end

        if (ref_cnt == 8'd233) begin
            ref_cnt <= 8'd0;
            if (ref_due != 3'd7) ref_due <= ref_due + 3'd1;
        end else
            ref_cnt <= ref_cnt + 8'd1;

        case (sc)
        3'd0: begin
            // a request on the slot's first clock: cpu_req at phase 7,
            // vid_req at phase 1, both with the address beside them
            act <= 1'b0;
            if (cpu_slot && cpu_req) begin
                act      <= 1'b1;
                act_we   <= cpu_we;
                act_vid  <= 1'b0;
                act_adr  <= cpu_adr;
                act_data <= cpu_wdata;
                cmd      <= CMD_ACTIVE;
                SDRAM_BA <= cpu_adr[21:20];
                SDRAM_A  <= cpu_adr[19:9];
            end else if (cpu_slot && bist_req) begin
                act      <= 1'b1;
                act_we   <= ~bist_rd;
                act_vid  <= 1'b0;
                act_adr  <= bist_adr;
                act_data <= bist_pat;
                cmd      <= CMD_ACTIVE;
                SDRAM_BA <= bist_adr[21:20];
                SDRAM_A  <= bist_adr[19:9];
            end else if (!cpu_slot && vid_req) begin
                act      <= 1'b1;
                act_we   <= 1'b0;
                act_vid  <= 1'b1;
                act_adr  <= vid_adr;
                cmd      <= CMD_ACTIVE;
                SDRAM_BA <= vid_adr[21:20];
                SDRAM_A  <= vid_adr[19:9];
            end else if (!cpu_slot && ref_due != 3'd0) begin
                cmd     <= CMD_AUTO_REFRESH;
                ref_due <= ref_due - 3'd1;
            end
        end
        3'd1: if (act) begin
            // column with auto-precharge - A10 SET; the byte lane by DQM.
            // Until 5 Sep 2026 this was {2'b0, 1'b1, col}: UKNC Nano's
            // {5'b00100, col} on a 13-bit bus, repacked into 11 bits with
            // the 1 landing on A8.  Nothing precharged, every ACTIVE hit a
            // bank with a row still open, and on the board all 64 KB
            // aliased into one row: zeros read back, the stack came back
            // zeroed by the ROM's fills (progress.md, "The third flash").
            // The model refuses such an ACTIVE now and counts them - and
            // caught the first fix, {2'b01, 1'b0, col}, which put the 1 on
            // A9.  Bit 10 is the top of this 11-bit vector: write it so.
            SDRAM_A  <= {1'b1, 2'b00, act_adr[8:1]};   // A10=1, A9=A8=0, A[7:0]=column
            SDRAM_BA <= act_adr[21:20];
            if (act_we) begin
                cmd        <= CMD_WRITE;
                dq_out     <= {act_data, act_data};
                dq_oe      <= 1'b1;
                SDRAM_DQML <=  act_adr[0];
                SDRAM_DQMH <= ~act_adr[0];
            end else begin
                cmd        <= CMD_READ;
                SDRAM_DQML <= 1'b0;
                SDRAM_DQMH <= 1'b0;
            end
        end
        3'd2: if (act && act_we) begin
            dq_oe <= 1'b1;             // hold the data a clock past the command
        end
        // the capture: slot clock 3 by the arithmetic in the header, or
        // clock 4 if the self-test found the word there instead
        3'd3: if (act && !act_we && !cap_late) begin
            if (act_vid) begin
                vid_rdata <= act_adr[0] ? SDRAM_DQ[15:8] : SDRAM_DQ[7:0];
                vid_ack   <= 1'b1;
            end else
                cpu_rdata <= act_adr[0] ? SDRAM_DQ[15:8] : SDRAM_DQ[7:0];
        end
        3'd4: if (act && !act_we && cap_late) begin
            if (act_vid) begin
                vid_rdata <= act_adr[0] ? SDRAM_DQ[15:8] : SDRAM_DQ[7:0];
                vid_ack   <= 1'b1;
            end else
                cpu_rdata <= act_adr[0] ? SDRAM_DQ[15:8] : SDRAM_DQ[7:0];
        end
        default: ;
        endcase
    end
end

endmodule
