//========================================================================
// memcheck.v - a shadow of F000h-FFFFh, and what the CPU is doing.
//
// The instrument for a board nobody can watch (4 Sep 2026, the second
// flash: the SDRAM's four-byte self-test passed and the ROM still
// restarted after its RAM test).  Every write into the SDRAM's CPU port
// that lands in F000h-FFFFh is copied into a 4 K x 9 BSRAM (the byte and
// a "written" bit); every read from there is compared with the copy
// when the word comes back, and the first and the last mismatch are
// kept with the address, both values and the address of the last
// opcode fetch before them.  Beside that, counts: reads checked, writes
// shadowed, CPU resets, opcode fetches at 0000h (the ROM restarting)
// with the fetch before the last one, and the last OUT.  All of it is
// 32 bytes on `dbg`, read by the MCU through sysctrl.v's CMD 7 and shown
// on the OSD's "Debug" page (mnano/menu.c).
//
// Nothing here touches the machine: it listens on the request the SDRAM
// takes at phase 7 and on cpu_rdata at phase 0 of the next T-state, when
// the word is there whichever slot clock captured it (sdram.v).  The
// BSRAM is written on one clock and read on another (both at phase 7,
// never both: a request is a read or a write), which is the only kind of
// inferred RAM Gowin's place-and-route accepts (CLAUDE.md, PA2122).
//========================================================================
module memcheck (
    input             clk,
    input      [3:0]  tphase,

    // the SDRAM's CPU port as top.v drives it, and the answer
    input             req,          // ram_req, at phase 7
    input             we,
    input      [21:0] adr,          // byte address
    input      [7:0]  wdata,
    input      [7:0]  rdata,        // cpu_rdata: valid from phase 11 to the next request
    input             hold,         // rd_loading: the loader's traffic, not the machine's

    // the CPU
    input             cpu_rst,
    input             mem_rd,       // phase 7: a memory read with cpu_a_now
    input             cyc_m1,       // registered a clock after mem_rd
    input      [15:0] cpu_adr,      // the latched address, valid from the clock after mem_rd
    input             io_wr,
    input      [7:0]  io_data,

    // the memory's own verdicts, for the flags byte
    input             por_done,
    input             init,
    input             bist_done,
    input             bist_fail,
    input             cap_late,

    output    [255:0] dbg
);

wire in_window = (adr[21:12] == 10'h00F);

//------------------------------------------------------------------------
// The shadow
//------------------------------------------------------------------------
reg  [8:0]  shadow [0:4095];       // {written, byte}
reg  [8:0]  shadow_q = 9'd0;
reg         chk_pend = 1'b0;
reg  [11:0] chk_adr  = 12'd0;

wire wr_hit = req &&  we && in_window && !hold;
wire rd_hit = req && !we && in_window && !hold;

always @(posedge clk)
    if (wr_hit) shadow[adr[11:0]] <= {1'b1, wdata};

always @(posedge clk)
    if (rd_hit) shadow_q <= shadow[adr[11:0]];

//------------------------------------------------------------------------
// The records
//------------------------------------------------------------------------
reg  [7:0]  err_cnt   = 8'd0;
reg  [15:0] first_adr = 16'd0, last_adr = 16'd0;
reg  [7:0]  first_exp = 8'd0,  first_got = 8'd0, last_exp = 8'd0, last_got = 8'd0;
reg  [15:0] first_pc  = 16'd0, last_pc  = 16'd0;
reg  [15:0] chk_cnt   = 16'd0, wr_cnt   = 16'd0;
reg  [7:0]  rst_cnt   = 8'd0,  pc0_cnt  = 8'd0;
reg  [15:0] pc_last   = 16'd0, pc_prev  = 16'd0, pc_prev0 = 16'd0;
reg  [7:0]  m1_cnt    = 8'd0;
reg  [7:0]  out_port  = 8'd0,  out_data = 8'd0;
reg         cpu_rst_d = 1'b0;
reg         mem_rd_d  = 1'b0;

always @(posedge clk) begin
    mem_rd_d  <= mem_rd;
    cpu_rst_d <= cpu_rst;

    if (wr_hit && wr_cnt != 16'hFFFF) wr_cnt <= wr_cnt + 16'd1;

    if (rd_hit) begin
        chk_pend <= 1'b1;
        chk_adr  <= adr[11:0];
    end
    if (chk_pend && tphase == 4'd0) begin
        chk_pend <= 1'b0;
        if (shadow_q[8]) begin
            if (chk_cnt != 16'hFFFF) chk_cnt <= chk_cnt + 16'd1;
            if (shadow_q[7:0] != rdata) begin
                if (err_cnt != 8'hFF) err_cnt <= err_cnt + 8'd1;
                if (err_cnt == 8'd0) begin
                    first_adr <= {4'hF, chk_adr};
                    first_exp <= shadow_q[7:0];
                    first_got <= rdata;
                    first_pc  <= pc_last;
                end
                last_adr <= {4'hF, chk_adr};
                last_exp <= shadow_q[7:0];
                last_got <= rdata;
                last_pc  <= pc_last;
            end
        end
    end

    // an opcode fetch: cyc_m1 and cpu_adr are registered at the strobe
    if (mem_rd_d && cyc_m1 && !cpu_rst) begin
        m1_cnt  <= m1_cnt + 8'd1;
        pc_prev <= pc_last;
        pc_last <= cpu_adr;
        if (cpu_adr == 16'h0000) begin
            if (pc0_cnt != 8'hFF) pc0_cnt <= pc0_cnt + 8'd1;
            pc_prev0 <= pc_last;
        end
    end

    if (cpu_rst && !cpu_rst_d && rst_cnt != 8'hFF) rst_cnt <= rst_cnt + 8'd1;

    if (io_wr) begin
        out_port <= cpu_adr[7:0];
        out_data <= io_data;
    end
end

assign dbg = {
    8'd0, 8'd0, 8'd0, 8'd0,                      // 31..28
    m1_cnt,                                      // 27
    pc_last,                                     // 26,25
    out_data, out_port,                          // 24,23
    wr_cnt,                                      // 22,21
    chk_cnt,                                     // 20,19
    pc_prev0,                                    // 18,17
    pc0_cnt, rst_cnt,                            // 16,15
    last_pc,                                     // 14,13
    last_got, last_exp,                          // 12,11
    last_adr,                                    // 10,9
    first_pc,                                    // 8,7
    first_got, first_exp,                        // 6,5
    first_adr,                                   // 4,3
    err_cnt,                                     // 2
    8'd0,                                        // 1 (spare)
    {por_done, init, cpu_rst, bist_done, bist_fail, cap_late, 2'b00}   // 0
};

endmodule
