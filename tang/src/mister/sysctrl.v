/*
    sysctrl.v

    The system control target of the MCU link: the status the firmware
    checks at start (CMD 0, with the core id), the LEDs and colour it may
    set (1, 2), the buttons (3), the OSD's values (4), the interrupt
    control (5).  MiSTeryNano's, with this core's letters in CMD 4.

    The letters are the OSD's (mnano/menu.c, variables_pk8000), and a
    menu value needs three edits: the letter in the form string, an entry
    in variables_pk8000[], and a line here.

    CMD 6 is this core's: a write into the machine's RAM.  Address high,
    address low, then any number of data bytes, each a strobe on
    poke_stb with poke_adr and poke_data, the address counting up
    (poke.v takes them into the SDRAM; mnano/bas.c sends a BASIC
    program that way).
*/

module sysctrl (
  input             clk,
  input             reset,

  input             data_in_strobe,
  input             data_in_start,
  input [7:0]       data_in,
  output reg [7:0]  data_out,

  // interrupt interface
  output            int_out_n,
  input [7:0]       int_in,
  output reg [7:0]  int_ack,

  input [1:0]       buttons, // S0 and S1 buttons on Tang Nano 20k

  output reg [1:0]  leds, // two leds can be controlled from the MCU
  output reg [23:0] color, // a 24bit color to e.g. be used to drive the ws2812

  // values that can be configured by the user
  output reg [1:0]  system_reset,     // 'R' coldboot(3), reset(1), run(0)
  output reg [1:0]  system_volume,    // 'A' mute(0), 33%(1), 66%(2), 100%(3)
  output reg        system_beeper,    // 'b' 0 mute, 1 on: the beeper in the mix
  output reg        system_waits,     // 'w' 1 = the video controller's cost paid by the CPU (cpu8080.v)
  output reg        system_joyswap,   // 'j' 1 = joystick ports exchanged
  output reg [1:0]  system_exp,       // 'x' expansion page 1: 0 none, 1 floppy, 2 IDE, 3 ROM disk
  output reg        system_tape,      // 'T' 0 stop, 1 play (with the motor)
  output reg        system_rewind,    // 'e' a level while the OSD button is down
  output reg        system_ay,        // 'y' the AY card at 14h/15h
  output reg [1:0]  system_fdd_wprot, // 'p' 'q' floppy A, B write-protected
  output reg        system_hdd_wprot, // 'K' the hard disk write-protected

  // CMD 6: a byte into the machine's RAM
  output reg        poke_stb,
  output reg [15:0] poke_adr,
  output reg [7:0]  poke_data
);

reg [3:0] state;
reg [7:0] command;
reg [7:0] id;

// reverse data byte for rgb
wire [7:0] data_in_rev = { data_in[0], data_in[1], data_in[2], data_in[3],
                           data_in[4], data_in[5], data_in[6], data_in[7] };

reg coldboot = 1'b1;

assign int_out_n = (int_in != 8'h00 || coldboot)?1'b0:1'b1;

always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;
      leds <= 2'b00;        // after reset leds are off
      color <= 24'h000000;  // color black -> rgb led off

      int_ack <= 8'h00;
      coldboot = 1'b1;      // reset is actually the power-on-reset

      // the OSD's defaults (menu.c, variables_pk8000), until the MCU says
      system_reset  <= 2'b00;
      system_volume <= 2'b01;
      system_beeper <= 1'b1;
      system_waits  <= 1'b1;
      system_joyswap <= 1'b0;
      system_exp    <= 2'd0;
      system_tape   <= 1'b1;
      system_rewind <= 1'b0;
      system_ay     <= 1'b1;
      system_fdd_wprot <= 2'b00;
      system_hdd_wprot <= 1'b0;
      poke_stb <= 1'b0;
      poke_adr <= 16'd0;
   end else begin
      int_ack <= 8'h00;
      poke_stb <= 1'b0;
      if(poke_stb) poke_adr <= poke_adr + 16'd1;   // the clock after a byte

      // iack bit 0 acknowledges the coldboot notification
      if(int_ack[0]) coldboot <= 1'b0;

      if(data_in_strobe) begin
        if(data_in_start) begin
            state <= 4'd1;
            command <= data_in;
        end else if(state != 4'd0) begin
            if(state != 4'd15) state <= state + 4'd1;

            // CMD 0: status data
            if(command == 8'd0) begin
                if(state == 4'd1) data_out <= 8'h5c;
                if(state == 4'd2) data_out <= 8'h42;
                if(state == 4'd3) data_out <= 8'h07;   // core id 7 = PK8000 (mnano/sysctrl.h)
            end

            // CMD 1: there are two MCU controlled LEDs
            if(command == 8'd1) begin
                if(state == 4'd1) leds <= data_in[1:0];
            end

            // CMD 2: a 24 color value to be mapped e.g. onto the ws2812
            if(command == 8'd2) begin
                if(state == 4'd1) color[15: 8] <= data_in_rev;
                if(state == 4'd2) color[ 7: 0] <= data_in_rev;
                if(state == 4'd3) color[23:16] <= data_in_rev;
            end

            // CMD 3: return button state
            if(command == 8'd3) begin
                data_out <= { 6'b000000, buttons };
            end

            // CMD 4: config values (e.g. set by user via OSD)
            if(command == 8'd4) begin
                if(state == 4'd1) id <= data_in;

                if(state == 4'd2) begin
                    if(id == "R") system_reset   <= data_in[1:0];
                    if(id == "A") system_volume  <= data_in[1:0];
                    if(id == "b") system_beeper  <= data_in[0];
                    if(id == "w") system_waits   <= data_in[0];
                    if(id == "j") system_joyswap <= data_in[0];
                    if(id == "x") system_exp     <= data_in[1:0];
                    if(id == "T") system_tape    <= data_in[0];
                    if(id == "e") system_rewind  <= data_in[0];
                    if(id == "y") system_ay      <= data_in[0];
                    if(id == "p") system_fdd_wprot[0] <= data_in[0];
                    if(id == "q") system_fdd_wprot[1] <= data_in[0];
                    if(id == "K") system_hdd_wprot <= data_in[0];
                end
            end

            // CMD 6: a write into RAM - address, then the bytes
            if(command == 8'd6) begin
                if(state == 4'd1) poke_adr[15:8] <= data_in;
                if(state == 4'd2) poke_adr[7:0]  <= data_in;
                if(state >= 4'd3) begin poke_data <= data_in; poke_stb <= 1'b1; end
            end

            // CMD 5: interrupt control
            if(command == 8'd5) begin
                if(state == 4'd1) int_ack <= data_in;
                data_out <= { int_in[7:1], coldboot };
            end
         end
      end
   end
end

endmodule
