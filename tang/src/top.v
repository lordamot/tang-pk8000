`timescale 1ns / 1ps
//========================================================================
// top.v - PK8000 Nano: the ПК8000 "Сура" on a Tang Nano 20K, with a
// BL616 (M0S Dock) beside it for USB, the SD card and the OSD.
//
// One clock.  sys_pll makes 30 MHz out of the board's 27, and every
// flop in the design runs on it: the CPU's T-state is twelve of them
// (tphase 0..11, counted here), the machine's pixel is six, the HDMI
// pixel is one, and the SDRAM takes the phase-shifted copy on its pad.
// The only other clocks are the HDMI serial clock, made from this one
// inside hdmi_serdes.v, and the MCU's SPI clock, which mcu_spi.v takes
// through a handshake.  There is nothing to cross and nothing to relate
// - pk8000.sdc names the two and the tool has the rest.
//
// The machine (tang/src/pk8000/):
//   cpu8080.v  the КР580ВМ80А (vm80a) with the 8228's status decode,
//              the interrupt and the video controller's wait model
//   sdram.v    the 64 KB, a fixed slot for the CPU and one for the video
//              in every T-state
//   pk8000_rom.v  the 16 KB BASIC ROM (tang/rom/pk8000_v12.rom) in BSRAM
//   ports.v    the two ВВ55s, the video registers, keyboard, joysticks
//   video.v    the display: the machine's raster into a line buffer,
//              read out twice per line as 768x576 at 50.73 Hz
// and around it MiSTeryNano's MCU link (src/mister/), UKNC Nano's HDMI
// encoder with audio (src/hdmi/) and an I2S output (i2s_tx.v).
//========================================================================
module top(
    input         clk27,
    // buts[0] is S1 and forces a reset; buts[1] is S2, read nowhere.
    // They read 0 released and 1 pressed, whatever PULL_MODE=UP suggests.
    input  [ 1:0] buts,
    output [ 5:0] leds,

    output        uart_tx,        // the USB-C serial: idle, the ПК8000 has none
    input         uart_rx,

    output        sdclk,
    inout         sdcmd,          // mosi
    inout         sddat0,         // miso
    inout         sddat1,         // not used
    inout         sddat2,         // not used
    inout         sddat3,         // cs

    output        O_tmds_clk_p,
    output        O_tmds_clk_n,
    output  [2:0] O_tmds_data_p,
    output  [2:0] O_tmds_data_n,

    // I2S to the dock's DAC
    output        HP_BCK,
    output        HP_WS,
    output        HP_DIN,
    output        PA_EN,

    output        O_sdram_clk,
    output        O_sdram_cke,
    output        O_sdram_cs_n,
    output        O_sdram_cas_n,
    output        O_sdram_ras_n,
    output        O_sdram_wen_n,
    output [ 3:0] O_sdram_dqm,
    output [10:0] O_sdram_addr,
    output [ 1:0] O_sdram_ba,
    inout  [31:0] IO_sdram_dq,

    // the MCU link, stock MiSTeryNano wiring: an external BL616 / M0S
    // Dock on 42/41/56/54/51 - 0 miso, 1 mosi, 2 csn, 3 sclk, 4 irqn
    inout  [ 4:0] m0s
);

assign O_sdram_dqm[3:2]   = 2'b11;
assign IO_sdram_dq[31:16] = 16'hZZZZ;
assign O_sdram_cke        = 1'b1;
assign PA_EN              = 1'b1;
assign uart_tx            = 1'b1;

//------------------------------------------------------------------------
// Clock
//------------------------------------------------------------------------
wire clk;          // 30 MHz, everything
wire locked;

sys_pll pll (
    .clkin  (clk27      ),
    .clkout (clk        ),
    .clkoutp(O_sdram_clk),
    .lock   (locked     )
);

//------------------------------------------------------------------------
// Resets.
//
// `init` is the SDRAM's word that the memory exists (2.2 ms after PLL
// lock plus the initialisation sequence); nothing runs before it.  The
// MiSTeryNano side then waits 2^23 clocks - 280 ms - as upstream does,
// for the MCU to come up; that counter is `por_done`, and mist_rst is
// the active-high reset the MiSTeryNano modules take.  The machine
// itself is reset by the OSD's 'R' (the MCU sends 3 at power-up and 0
// when it has sent its settings), by S1, and until the memory is there.
//------------------------------------------------------------------------
wire init;
reg  [23:0] count_rst = 24'd0;
wire        n_all_rst = init & ~buts[0];
wire        por_done  = count_rst[23];
wire        mist_rst  = ~por_done;

always @(posedge clk or negedge n_all_rst)
    count_rst <= !n_all_rst ? 24'd0 : count_rst + {23'd0, !count_rst[23]};

wire [1:0] system_reset;
wire [1:0] system_volume;
wire       system_beeper;
wire       system_waits;
wire       system_joyswap;

//------------------------------------------------------------------------
// The machine's raster and the T-state phase, one counter pair.  The
// line is 1920 clocks (64 us), 160 T-states, so both wrap together.
//------------------------------------------------------------------------
reg  [10:0] hcnt   = 11'd0;
reg  [8:0]  vcnt   = 9'd0;
reg  [3:0]  tphase = 4'd0;

// They run from PLL lock, not from init: the SDRAM controller's
// initialisation steps are taken in the video slot of the timetable,
// which is a phase of this counter - held until init, the two would
// wait for each other for ever (they did, in the first simulation).
always @(posedge clk) begin
    if (!locked) begin
        hcnt <= 11'd0; vcnt <= 9'd0; tphase <= 4'd0;
    end else begin
        tphase <= (tphase == 4'd11) ? 4'd0 : tphase + 4'd1;
        if (hcnt == 11'd1919) begin
            hcnt <= 11'd0;
            vcnt <= (vcnt == 9'd307) ? 9'd0 : vcnt + 9'd1;
        end else
            hcnt <= hcnt + 11'd1;
    end
end

// vm80a takes its reset through two phase-registered stages; hold it
// well past that: 16 T-states after the request goes away.
reg  [7:0] cpu_rst_cnt = 8'hFF;
wire       cpu_rst_req = mist_rst | system_reset[0] | ~init;
always @(posedge clk) begin
    if (cpu_rst_req) cpu_rst_cnt <= 8'd192;
    else if (cpu_rst_cnt != 8'd0 && tphase == 4'd11) cpu_rst_cnt <= cpu_rst_cnt - 8'd1;
end
wire cpu_rst = (cpu_rst_cnt != 8'd0);

//------------------------------------------------------------------------
// The CPU and its memory map.
//
// Port 80h (ports.v, bank_reg) holds two bits a 16 KB quarter: 0 the
// ROM, 1 and 2 the expansion slots (nothing here yet: 0FFh), 3 RAM.  A
// write goes to RAM whatever the quarter shows - the ROM sits in front
// of the RAM for reads only, which is how a program moves itself in
// under the ROM and then switches it out.
//------------------------------------------------------------------------
wire [15:0] cpu_adr, cpu_a_now;
wire [7:0]  cpu_dout, cpu_d_now;
wire        cpu_io, cpu_m1, cpu_inta;
wire        mem_rd, io_rd, mem_wr, io_wr, inta_stb, cpu_inte;
wire [7:0]  bank_reg;

function [1:0] page_of(input [7:0] bank, input [15:0] a);
    case (a[15:14])
        2'd0: page_of = bank[1:0];
        2'd1: page_of = bank[3:2];
        2'd2: page_of = bank[5:4];
        2'd3: page_of = bank[7:6];
    endcase
endfunction

wire [1:0] page_now = page_of(bank_reg, cpu_a_now);   // at the strobe
wire       rom_now  = (page_now != 2'd3);

// what the read in flight will answer with
reg  [1:0] rd_src = 2'd0;    // 0 nothing (0FFh), 1 RAM, 2 ROM, 3 I/O
always @(posedge clk) begin
    if (mem_rd) rd_src <= (page_now == 2'd3) ? 2'd1 : (page_now == 2'd0) ? 2'd2 : 2'd0;
    if (io_rd)  rd_src <= 2'd3;
end

wire [7:0]  ram_rdata, io_rdata;
wire [15:0] rom_word;
wire [7:0]  rom_rdata = cpu_adr[0] ? rom_word[15:8] : rom_word[7:0];
wire [7:0]  cpu_din   = (rd_src == 2'd1) ? ram_rdata :
                        (rd_src == 2'd2) ? rom_rdata :
                        (rd_src == 2'd3) ? io_rdata  : 8'hFF;

wire stall_wide, border_wide, frame_irq;

// The frame interrupt flop: set at the start of line 263, held until
// the acknowledge - the flip-flop the schematic's СБР.ПРЕР clears.
reg int_ff = 1'b0;
always @(posedge clk) begin
    if (cpu_rst)        int_ff <= 1'b0;
    else if (frame_irq) int_ff <= 1'b1;
    else if (inta_stb)  int_ff <= 1'b0;
end

cpu8080 cpu (
    .clk        (clk        ),
    .reset      (cpu_rst    ),
    .tphase     (tphase     ),
    .adr        (cpu_adr    ),
    .dout       (cpu_dout   ),
    .din        (cpu_din    ),
    .a_now      (cpu_a_now  ),
    .d_now      (cpu_d_now  ),
    .cyc_io     (cpu_io     ),
    .cyc_m1     (cpu_m1     ),
    .cyc_inta   (cpu_inta   ),
    .mem_rd     (mem_rd     ),
    .io_rd      (io_rd      ),
    .mem_wr     (mem_wr     ),
    .io_wr      (io_wr      ),
    .inta_stb   (inta_stb   ),
    .int_req    (int_ff     ),
    .inte       (cpu_inte   ),
    .waits_en   (system_waits),
    .stall_wide (stall_wide ),
    .border_wide(border_wide),
    .fetch_rom  (rom_now    ),
    .dbg_opcode (           ),
    .dbg_sync   (           ),
    .dbg_wr_n   (           ),
    .dbg_dbin   (           )
);

// The ROM: a registered pROM, the address from the cycle's latched
// address, so the word is there from the second clock of the cycle.
pk8000_rom rom (
    .dout (rom_word     ),
    .clk  (clk          ),
    .ce   (1'b1         ),
    .reset(1'b0         ),
    .ad   (cpu_adr[13:1])
);

//------------------------------------------------------------------------
// Memory
//------------------------------------------------------------------------
wire        vid_req, vid_ack;
wire [15:0] vid_adr;
wire [7:0]  vid_rdata;

wire        ram_req = (mem_rd && page_now == 2'd3) || mem_wr;
wire [15:0] ram_adr = mem_wr ? cpu_adr : cpu_a_now;

sdram mem (
    .clk       (clk        ),
    .lock      (locked     ),
    .init      (init       ),
    .tphase    (tphase     ),
    .cpu_req   (ram_req    ),
    .cpu_we    (mem_wr     ),
    .cpu_adr   (ram_adr    ),
    .cpu_wdata (cpu_d_now  ),
    .cpu_rdata (ram_rdata  ),
    .vid_req   (vid_req    ),
    .vid_adr   (vid_adr    ),
    .vid_rdata (vid_rdata  ),
    .vid_ack   (vid_ack    ),
    .SDRAM_A   (O_sdram_addr     ),
    .SDRAM_BA  (O_sdram_ba       ),
    .SDRAM_DQ  (IO_sdram_dq[15:0]),
    .SDRAM_nCS (O_sdram_cs_n     ),
    .SDRAM_nRAS(O_sdram_ras_n    ),
    .SDRAM_nCAS(O_sdram_cas_n    ),
    .SDRAM_nWE (O_sdram_wen_n    ),
    .SDRAM_DQML(O_sdram_dqm[0]   ),
    .SDRAM_DQMH(O_sdram_dqm[1]   )
);

//------------------------------------------------------------------------
// I/O and the display
//------------------------------------------------------------------------
wire [1:0]  vmode, vbank;
wire [7:0]  color88;
wire [3:0]  txt_base, sg_base;
wire        gr_base, col_base, blanking, beeper, tape_out, tape_motor;
wire        col_we;
wire [4:0]  col_adr;
wire [7:0]  col_wdata, col_rdata;
wire [7:0]  kbd_byte, joystick0, joystick1;
wire        kbd_stb;

// io_rd comes at the strobe's clock with the address still on the
// core's bus; io_wr comes later, with the cycle's latched address and
// the data on the core's bus.  The two never coincide.
wire [7:0] io_adr = io_wr ? cpu_adr[7:0] : cpu_a_now[7:0];

ports io (
    .clk           (clk       ),
    .reset         (cpu_rst   ),
    .adr           (io_adr    ),
    .io_rd         (io_rd     ),
    .io_wr         (io_wr     ),
    .wdata         (cpu_d_now ),
    .rdata         (io_rdata  ),
    .kbd_byte      (kbd_byte  ),
    .kbd_stb       (kbd_stb   ),
    .joy0          (joystick0 ),
    .joy1          (joystick1 ),
    .joy_swap      (system_joyswap),
    .tape_in       (1'b0      ),
    .bank_reg      (bank_reg  ),
    .vmode         (vmode     ),
    .vbank         (vbank     ),
    .color88       (color88   ),
    .txt_base      (txt_base  ),
    .sg_base       (sg_base   ),
    .gr_base       (gr_base   ),
    .col_base      (col_base  ),
    .blanking      (blanking  ),
    .beeper        (beeper    ),
    .tape_out      (tape_out  ),
    .tape_motor    (tape_motor),
    .printer_data  (          ),
    .printer_strobe(          ),
    .col_we        (col_we    ),
    .col_adr       (col_adr   ),
    .col_wdata     (col_wdata ),
    .col_rdata     (col_rdata )
);

wire        hsync, vsync, visible;
wire [7:0]  red, green, blue;

video vid (
    .clk        (clk        ),
    .reset      (~init      ),
    .hcnt       (hcnt       ),
    .vcnt       (vcnt       ),
    .tphase     (tphase     ),
    .mode       (vmode      ),
    .bank       (vbank      ),
    .txt_base   (txt_base   ),
    .sg_base    (sg_base    ),
    .gr_base    (gr_base    ),
    .col_base   (col_base   ),
    .color88    (color88    ),
    .blanking   (blanking   ),
    .col_we     (col_we     ),
    .col_adr    (col_adr    ),
    .col_wdata  (col_wdata  ),
    .col_rdata  (col_rdata  ),
    .vid_req    (vid_req    ),
    .vid_adr    (vid_adr    ),
    .vid_rdata  (vid_rdata  ),
    .vid_ack    (vid_ack    ),
    .hs         (hsync      ),
    .vs         (vsync      ),
    .de         (visible    ),
    .r          (red        ),
    .g          (green      ),
    .b          (blue       ),
    .stall_wide (stall_wide ),
    .border_wide(border_wide),
    .frame_irq  (frame_irq  )
);

//------------------------------------------------------------------------
// The MCU link (MiSTeryNano): SPI in, four targets out.
//------------------------------------------------------------------------
wire        mcu_sys_strobe, mcu_hid_strobe, mcu_osd_strobe, mcu_sdc_strobe;
wire        mcu_start;
wire  [7:0] mcu_sys_din, mcu_hid_din, mcu_sdc_din;
wire  [7:0] mcu_osd_din = 8'h55;
wire  [7:0] mcu_dout;
wire        hid_int, sdc_int;
wire  [7:0] int_ack;

wire        spi_io_dout;
wire        int_out_n;

assign m0s[4:0] = { int_out_n, 3'bzzz, spi_io_dout };

wire spi_io_din = m0s[1];
wire spi_io_ss  = m0s[2];
wire spi_io_clk = m0s[3];

mcu_spi msp1 (
    .clk           (clk           ),
    .reset         (mist_rst      ),
    .spi_io_ss     (spi_io_ss     ),
    .spi_io_clk    (spi_io_clk    ),
    .spi_io_din    (spi_io_din    ),
    .spi_io_dout   (spi_io_dout   ),
    .mcu_sys_strobe(mcu_sys_strobe),
    .mcu_hid_strobe(mcu_hid_strobe),
    .mcu_osd_strobe(mcu_osd_strobe),
    .mcu_sdc_strobe(mcu_sdc_strobe),
    .mcu_start     (mcu_start     ),
    .mcu_sys_din   (mcu_sys_din   ),
    .mcu_hid_din   (mcu_hid_din   ),
    .mcu_osd_din   (mcu_osd_din   ),
    .mcu_sdc_din   (mcu_sdc_din   ),
    .mcu_dout      (mcu_dout      )
);

sysctrl sctl1 (
    .clk           (clk           ),
    .reset         (mist_rst      ),
    .data_in_strobe(mcu_sys_strobe),
    .data_in_start (mcu_start     ),
    .data_in       (mcu_dout      ),
    .data_out      (mcu_sys_din   ),
    .int_out_n     (int_out_n     ),
    .int_in        ({4'b0000, sdc_int, 1'b0, hid_int, 1'b0}),
    .int_ack       (int_ack       ),
    .buttons       (2'b00         ),
    .leds          (              ),
    .color         (              ),
    .system_reset  (system_reset  ),
    .system_volume (system_volume ),
    .system_beeper (system_beeper ),
    .system_waits  (system_waits  ),
    .system_joyswap(system_joyswap)
);

hid hd1 (
    .clk           (clk           ),
    .reset         (mist_rst      ),
    .data_in_strobe(mcu_hid_strobe),
    .data_in_start (mcu_start     ),
    .data_in       (mcu_dout      ),
    .data_out      (mcu_hid_din   ),
    .db9_port      (6'd0          ),
    .irq           (hid_int       ),
    .iack          (int_ack[1]    ),
    .mouse         (              ),
    .keyboard      (kbd_byte      ),
    .keyboard_stb  (kbd_stb       ),
    .joystick0     (joystick0     ),
    .joystick1     (joystick1     ),
    .mouse_rep_tgl (              ),
    .mouse_rep_dx  (              ),
    .mouse_rep_dy  (              )
);

// The SD card is the MCU's: its FatFs reads the card through this
// module, and the settings file with it.  The machine has no disk yet,
// so nothing here asks for a sector.
wire [31:0] sd_img_size;
wire [ 4:0] sd_img_mounted;

sd_card #(
    .CLK_DIV(3'd1)
) sd_card (
    .rstn         (por_done      ),
    .clk          (clk           ),
    .sdclk        (sdclk         ),
    .sdcmd        (sdcmd         ),
    .sddat        ({sddat3, sddat2, sddat1, sddat0}),
    .data_strobe  (mcu_sdc_strobe),
    .data_start   (mcu_start     ),
    .data_in      (mcu_dout      ),
    .data_out     (mcu_sdc_din   ),
    .image_size   (sd_img_size   ),
    .image_mounted(sd_img_mounted),
    .irq          (sdc_int       ),
    .iack         (int_ack[3]    ),
    .rstart       (5'd0          ),
    .wstart       (5'd0          ),
    .rsector      (32'd0         ),
    .rbusy        (              ),
    .rdone        (              ),
    .inbyte       (8'd0          ),
    .outen        (              ),
    .outaddr      (              ),
    .outbyte      (              )
);

//------------------------------------------------------------------------
// The OSD over the picture, then the encoder.
//------------------------------------------------------------------------
wire [5:0] r_out, g_out, b_out;

osd_u8g2 osd1 (
    .clk           (clk           ),
    .pclk          (clk           ),
    .reset         (mist_rst      ),
    .data_in_strobe(mcu_osd_strobe),
    .data_in_start (mcu_start     ),
    .data_in       (mcu_dout      ),
    .hs            (hsync         ),
    .vs            (vsync         ),
    .r_in          (red[7:2]      ),
    .g_in          (green[7:2]    ),
    .b_in          (blue[7:2]     ),
    .r_out         (r_out         ),
    .g_out         (g_out         ),
    .b_out         (b_out         )
);

reg        I_rgb_vs = 1'b0, I_rgb_hs = 1'b0, I_rgb_de = 1'b0;
reg  [7:0] I_rgb_r = 8'd0, I_rgb_g = 8'd0, I_rgb_b = 8'd0;

always @(posedge clk) begin
    I_rgb_vs <= vsync;
    I_rgb_hs <= hsync;
    I_rgb_de <= visible;
    I_rgb_r  <= {r_out, 2'd0};
    I_rgb_g  <= {g_out, 2'd0};
    I_rgb_b  <= {b_out, 2'd0};
end

wire [9:0]  tmds_ch0, tmds_ch1, tmds_ch2;
wire [15:0] audio_l, audio_r;

hdmi_tx hdmi1 (
    .I_rst_n      (1'b1        ),
    .I_rgb_clk    (clk         ),
    .I_rgb_vs     (I_rgb_vs    ),
    .I_rgb_hs     (I_rgb_hs    ),
    .I_rgb_de     (I_rgb_de    ),
    .I_rgb_r      (I_rgb_r     ),
    .I_rgb_g      (I_rgb_g     ),
    .I_rgb_b      (I_rgb_b     ),
    .I_audio_l    (audio_l     ),
    .I_audio_r    (audio_r     ),
    .O_tmds_ch0   (tmds_ch0    ),
    .O_tmds_ch1   (tmds_ch1    ),
    .O_tmds_ch2   (tmds_ch2    ),
    .O_audio_ovf  (            ),
    .O_audio_dropc(            ),
    .O_audio_pktc (            )
);

hdmi_serdes hdmi_ser (
    .clk_pixel    (clk          ),
    .ref_locked   (locked       ),
    .tmds_ch0     (tmds_ch0     ),
    .tmds_ch1     (tmds_ch1     ),
    .tmds_ch2     (tmds_ch2     ),
    .O_tmds_clk_p (O_tmds_clk_p ),
    .O_tmds_clk_n (O_tmds_clk_n ),
    .O_tmds_data_p(O_tmds_data_p),
    .O_tmds_data_n(O_tmds_data_n)
);

//------------------------------------------------------------------------
// Sound.  The ПК8000 has a one-bit beeper on port 82h bit 7 and the
// tape output on bit 6; both go into one unipolar sum - the beeper at
// a quarter of full scale, the tape output at a sixteenth - and the
// OSD's volume divides it down.  Unipolar on purpose: UKNC Nano's
// notes on hdmi_tx.v say why a DC blocker is not here yet.
//------------------------------------------------------------------------
wire [15:0] mix = {2'd0, beeper & system_beeper, 13'd0} + {4'd0, tape_out, 11'd0};

reg [15:0] volume = 16'd0;
always @(posedge clk)
    case (system_volume)
        2'b00: volume <= 16'd0;
        2'b01: volume <= mix >> 2;
        2'b10: volume <= mix >> 1;
        2'b11: volume <= mix;
    endcase

assign audio_l = volume;
assign audio_r = volume;

i2s_tx i2s (
    .clk     (clk     ),
    .reset   (mist_rst),
    .sample_l(volume  ),
    .sample_r(volume  ),
    .bck     (HP_BCK  ),
    .ws      (HP_WS   ),
    .din     (HP_DIN  )
);

//------------------------------------------------------------------------
// LEDs, active low on the board
//------------------------------------------------------------------------
assign leds[0] = ~por_done;
assign leds[1] = ~beeper;
assign leds[2] = ~int_ff;
assign leds[3] = ~cpu_inte;
assign leds[4] = ~cpu_rst;
assign leds[5] = ~init;

endmodule
