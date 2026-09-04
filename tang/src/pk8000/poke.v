`timescale 1ns / 1ps
//========================================================================
// poke.v - the MCU's way into the machine's RAM while it runs.
//
// sysctrl.v's CMD 6 carries an address and then any number of bytes;
// each arrives here as a one-clock strobe.  They are queued and written
// into the SDRAM through the CPU's slot of the timetable in T-states
// where the CPU itself makes no request - an 8080 touches memory in at
// most one T-state of every machine cycle of three or more, so a byte
// waits a T-state or two, and the SPI link delivers one in a
// microsecond at best.  The queue is for the difference.
//
// The firmware uses it to put a BASIC program into memory as if it had
// been typed: the tokenised lines at 4001h and the ROM's four pointers
// at F92Eh (TXTTAB, VARTAB, ARYTAB, STREND), then "run" through the
// keyboard path (mnano/bas.c).  Nothing here knows any of that: it is
// a byte to an address.
//========================================================================
module poke (
    input             clk,
    input             reset,

    input             stb,          // a byte from sysctrl.v
    input      [15:0] adr,
    input      [7:0]  data,

    input      [3:0]  tphase,
    input             cpu_busy,     // the CPU requests the SDRAM this T-state (at phase 7)
    input             hold,         // somebody else owns the CPU port (the ROM disk loader)

    output            req,          // one clock at phase 7: write req_data to req_adr
    output     [15:0] req_adr,
    output     [7:0]  req_data,
    output            pending       // bytes queued
);

reg [23:0] fifo [0:15];
reg [4:0]  wp = 5'd0, rp = 5'd0;

wire empty = (wp == rp);
wire full  = (wp[3:0] == rp[3:0]) && (wp[4] != rp[4]);

assign pending  = !empty;
assign req      = !empty && !hold && !cpu_busy && (tphase == 4'd7);
assign req_adr  = fifo[rp[3:0]][23:8];
assign req_data = fifo[rp[3:0]][7:0];

always @(posedge clk) begin
    if (reset) begin
        wp <= 5'd0; rp <= 5'd0;
    end else begin
        if (stb && !full) begin
            fifo[wp[3:0]] <= {adr, data};
            wp <= wp + 5'd1;
        end
        if (req) rp <= rp + 5'd1;
    end
end

endmodule
