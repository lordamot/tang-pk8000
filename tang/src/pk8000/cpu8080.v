`timescale 1ns / 1ps
//========================================================================
// cpu8080.v - the КР580ВМ80А and its bus, as the ПК8000 sees them.
//
// The core is vm80a (tang/src/pk8000/vm80a.v, 1801BM1, CC-BY 3.0): a
// gate-level replica of the real die that runs on a fast clock with the
// two 8080 clock phases fed in as one-clock enables.  Here the system
// clock is 30 MHz and a T-state is twelve of them, so F1 is the enable at
// phase 0 and F2 the one at phase 6 - 2.5 MHz, the machine's own rate.
// Everything else on the board counts the same phase (`tphase`, made in
// top.v), which is what lets the SDRAM controller give the CPU a fixed
// slot in every T-state and never insert a wait of its own.
//
// What this wrapper adds around the core:
//
//  * the 8228's job - the status byte the core puts on its data bus
//    while SYNC is up is latched, and from it the cycle is classed as
//    memory or I/O, read or write, M1, INTA;
//  * one request pulse per machine cycle for the memory system: `rd_stb`
//    at phase 7 of the T-state SYNC is seen in (address valid), `wr_stb`
//    at the first phase 7 after WR/ falls (data valid);
//  * the interrupt: a level on `int_req`, RST 7 supplied on the bus
//    during the acknowledge cycle (the real machine has nothing driving
//    the bus then and the pull-ups read as 0FFh), `inta_stb` for whoever
//    holds the request flop;
//  * the video controller's cost.  On the real machine the display
//    holds READY off while it owns the DRAM, and how much of each
//    instruction that eats was measured rather than derived: the tables
//    in waits_rom.v (from Emu80's Pk8000CpuWaits) give the extra clocks
//    per opcode, by whether it was fetched from ROM or RAM and by whether
//    a 40-column mode is in the active part of a line.  Those clocks are
//    paid here as wait states inserted into the NEXT instruction's M1 -
//    the total is the same and the instruction after it starts at the
//    same time as on the machine.  `waits_en` turns it off, which makes
//    the CPU about a third faster than a real ПК8000.
//========================================================================
module cpu8080 (
    input             clk,
    input             reset,        // active high; hold it a few T-states
    input      [3:0]  tphase,       // 0..11, the T-state phase (top.v)

    // the bus, one request a machine cycle
    output reg [15:0] adr,          // valid from rd_stb / wr_stb to the next
    output reg [7:0]  dout,         // write data, valid with wr_stb
    input      [7:0]  din,          // read data: valid by phase 5 of T3 (T2 is enough)
    output     [15:0] a_now,        // the core's address bus as it stands (for the strobes' clock)
    output     [7:0]  d_now,        // the core's data bus as it stands
    output reg        cyc_io,       // the cycle is IN or OUT
    output reg        cyc_m1,       // the cycle is an opcode fetch
    output reg        cyc_inta,     // the cycle is an interrupt acknowledge
    output            mem_rd,       // phase 7 of the SYNC T-state: a memory read wants din; a_now is the address
    output            io_rd,        // the same for an IN
    output            mem_wr,       // phase 7 after WR/ fell: write d_now to adr
    output            io_wr,        // the same for an OUT
    output            inta_stb,     // an INTA cycle has started

    // interrupt
    input             int_req,      // level; cleared by whoever sees inta_stb
    output            inte,

    // the video controller's cost
    input             waits_en,
    input             stall_wide,   // a 40-column mode, active part of the line
    input             border_wide,  // a 40-column mode at all (modes 0 and 3)
    input             fetch_rom,    // adr (at M1) is not a RAM page: top.v's map

    // for the testbench
    output     [7:0]  dbg_opcode,
    output            dbg_sync,
    output            dbg_wr_n,
    output            dbg_dbin
);

//------------------------------------------------------------------------
// The two phases, one clock each, twelve apart.
//------------------------------------------------------------------------
wire f1 = (tphase == 4'd0);
wire f2 = (tphase == 4'd6);

wire [15:0] pin_a;
wire [7:0]  pin_dout;
wire        pin_sync, pin_dbin, pin_wr_n, pin_inte, pin_wait;
wire        pin_ready;
reg  [7:0]  pin_din;

vm80a_core core (
    .pin_clk   (clk      ),
    .pin_f1    (f1       ),
    .pin_f2    (f2       ),
    .pin_reset (reset    ),
    .pin_a     (pin_a    ),
    .pin_dout  (pin_dout ),
    .pin_din   (pin_din  ),
    .pin_aena  (         ),
    .pin_dena  (         ),
    .pin_hold  (1'b0     ),
    .pin_hlda  (         ),
    .pin_ready (pin_ready),
    .pin_wait  (pin_wait ),
    .pin_int   (int_req  ),
    .pin_inte  (pin_inte ),
    .pin_sync  (pin_sync ),
    .pin_dbin  (pin_dbin ),
    .pin_wr_n  (pin_wr_n )
);

assign inte     = pin_inte;
assign a_now    = pin_a;
assign d_now    = pin_dout;
assign dbg_sync = pin_sync;
assign dbg_wr_n = pin_wr_n;
assign dbg_dbin = pin_dbin;

//------------------------------------------------------------------------
// The status byte.  vm80a raises SYNC and puts the status on its data
// bus on the same F2 edge, so both are there at phase 7 of that T-state,
// and SYNC is exactly one T-state long: (tphase == 7 && sync) is once a
// machine cycle.  Status bits, as the 8080 defines them:
//   D0 INTA  D1 WO/  D2 STACK  D3 HLTA  D4 OUT  D5 M1  D6 INP  D7 MEMR
//------------------------------------------------------------------------
wire cyc_start = (tphase == 4'd7) && pin_sync;

wire st_inta = pin_dout[0];
wire st_wo_n = pin_dout[1];
wire st_out  = pin_dout[4];
wire st_m1   = pin_dout[5];
wire st_inp  = pin_dout[6];

reg  cyc_wr   = 1'b0;      // this cycle writes (WO/ low)
reg  wr_done  = 1'b0;
reg  wr_n_d   = 1'b1;

always @(posedge clk) begin
    wr_n_d <= pin_wr_n;
    if (cyc_start) begin
        adr      <= pin_a;
        cyc_io   <= st_inp | st_out;
        cyc_m1   <= st_m1;
        cyc_inta <= st_inta;
        cyc_wr   <= ~st_wo_n;
        wr_done  <= 1'b0;
    end
    if (wr_stb) begin
        wr_done <= 1'b1;
        dout    <= pin_dout;
    end
end

// A read cycle asks for its data as soon as the address is known.  A
// write is done at the first phase 7 with WR/ low: vm80a drops WR/ on
// F1 of T3, and the data has been on pin_dout since F2 of T2.
wire   rd_stb   = cyc_start && st_wo_n && !st_inta;
wire   wr_stb   = (tphase == 4'd7) && cyc_wr && !pin_wr_n && !wr_done && !pin_sync;
assign mem_rd   = rd_stb && !(st_inp | st_out);
assign io_rd    = rd_stb &&  st_inp;
assign mem_wr   = wr_stb && !cyc_io;
assign io_wr    = wr_stb &&  cyc_io;
assign inta_stb = cyc_start && st_inta;

// The bus the core reads: 0FFh (RST 7) in an acknowledge cycle, the
// memory system's byte otherwise.  vm80a samples it on every clock DBIN
// is up, so it has to be steady by the end of T3.
always @(*) pin_din = cyc_inta ? 8'hFF : din;

//------------------------------------------------------------------------
// The video controller's cost, paid as wait states.
//
// At every M1 the previous instruction is known - its opcode, how many
// machine cycles it took (which says whether a conditional branch was
// taken), and whether it came from ROM - and the table gives the clocks
// the display would have cost it.  That many TW states go into this M1:
// vm80a samples READY on F2 of T2 and of every TW, so holding READY off
// for N of those samples is exactly N wait states.
//------------------------------------------------------------------------
reg  [7:0] opcode      = 8'h00;   // the instruction being executed
reg  [2:0] mcyc        = 3'd0;    // machine cycles of it so far
reg        op_rom      = 1'b0;    // it was fetched from ROM
reg        m1_pending  = 1'b0;    // its opcode is on its way
reg  [4:0] wcnt        = 5'd0;    // wait states still to insert

wire [4:0] tab_waits;
waits_rom wr0 (.idx({op_rom, stall_wide, opcode}), .waits(tab_waits));

// Rxx (conditional return) is one machine cycle if not taken, three if
// taken; Cxx (conditional call) three or five.  Emu80 has these rows
// depend on the outcome rather than on the table, and so does this.
wire is_rxx = (opcode & 8'hC7) == 8'hC0;
wire is_cxx = (opcode & 8'hC7) == 8'hC4;
wire taken  = is_rxx ? (mcyc != 3'd1) : (mcyc != 3'd3);

reg [4:0] prev_waits;
always @(*) begin
    if (is_rxx)
        prev_waits = op_rom ? (taken ? 5'd3 : 5'd1)
                            : (taken ? (stall_wide ? 5'd7 : 5'd5)
                                     : (stall_wide ? 5'd1 : 5'd3));
    else if (is_cxx)
        prev_waits = op_rom ? (taken ? (stall_wide ? 5'd9 : 5'd11) : 5'd14)
                            : (taken ? (stall_wide ? 5'd13 : 5'd15)
                                     : (stall_wide ? 5'd7 : 5'd5));
    else
        prev_waits = tab_waits;
end

// An interrupt costs a few clocks more on top - Emu80's "hrq" at the
// RST, seven in a 40-column mode and five otherwise.
wire [4:0] irq_waits = border_wide ? 5'd7 : 5'd5;
wire [5:0] m1_waits  = {1'b0, prev_waits} + (st_inta ? {1'b0, irq_waits} : 6'd0);

always @(posedge clk) begin
    if (reset) begin
        wcnt       <= 5'd0;
        mcyc       <= 3'd0;
        opcode     <= 8'h00;
        m1_pending <= 1'b0;
        op_rom     <= 1'b0;
    end else begin
        if (cyc_start) begin
            if (st_m1) begin
                if (waits_en) wcnt <= (m1_waits > 6'd31) ? 5'd31 : m1_waits[4:0];
                mcyc       <= 3'd1;
                op_rom     <= fetch_rom;
                m1_pending <= 1'b1;
            end else if (mcyc != 3'd7)
                mcyc <= mcyc + 3'd1;
        end
        // the opcode: din is settled by phase 3 of the T-state after the
        // request (SDRAM 4 clocks, ROM 1); an acknowledge reads RST 7
        if (m1_pending && tphase == 4'd3) begin
            opcode     <= pin_din;
            m1_pending <= 1'b0;
        end
        // one wait state per F2 sample while the count lasts
        if (f2 && wcnt != 5'd0) wcnt <= wcnt - 5'd1;
    end
end

assign pin_ready = (wcnt == 5'd0);
assign dbg_opcode = opcode;

endmodule
