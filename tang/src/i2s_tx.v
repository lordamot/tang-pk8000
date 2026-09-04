`timescale 1ns / 1ps
//========================================================================
// i2s_tx.v - the I2S output to the dock's DAC, on the system clock.
//
// UKNC Nano's audio_drive.v was clocked BY the bit clock, a divided
// signal on general routing - the kind of clock .claude/rules/timing.md
// forbids.  This one runs on the 30 MHz clock with an enable every ten
// clocks: a 1.5 MHz bit clock, 32 bits a frame, 46.875 kHz.  The DAC
// does not mind the rate; the HDMI path resamples on its own and never
// sees this.
//
// I2S: WS low is the left slot, data MSB first, WS changes one bit
// clock ahead of the word.  The sample pair is taken at the frame start.
//========================================================================
module i2s_tx (
    input             clk,
    input             reset,
    input      [15:0] sample_l,
    input      [15:0] sample_r,
    output reg        bck,
    output reg        ws,
    output reg        din
);

reg [2:0]  div  = 3'd0;      // 0..4: half a bit clock every five clocks
reg [4:0]  bit_n = 5'd0;     // 0..31 within the frame
reg [15:0] sr   = 16'd0;
reg [15:0] hold_r = 16'd0;

always @(posedge clk) begin
    if (reset) begin
        div <= 3'd0; bck <= 1'b0; ws <= 1'b0; din <= 1'b0; bit_n <= 5'd0;
    end else begin
        if (div == 3'd4) begin
            div <= 3'd0;
            bck <= ~bck;
            if (bck) begin
                // falling edge: the data changes here, the DAC reads on rising
                bit_n <= bit_n + 5'd1;
                if (bit_n == 5'd31) begin
                    sr     <= sample_l;
                    hold_r <= sample_r;
                end else if (bit_n == 5'd15)
                    sr <= hold_r;
                else
                    sr <= {sr[14:0], 1'b0};
                // WS one bit ahead of the slot it announces
                if (bit_n == 5'd30) ws <= 1'b0;
                if (bit_n == 5'd14) ws <= 1'b1;
            end
        end else
            div <= div + 3'd1;
        din <= sr[15];
    end
end

endmodule
