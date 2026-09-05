//========================================================================
// Top-level testbench: the whole machine, with the SDRAM modelled and a
// minimal stand-in for the BL616.
//========================================================================
// Plusargs:
//   +VCD          dump sim/out/tb_top.vcd (large)
//   +VIDEO_PPM    write each decoded frame as a .ppm
//   +RUN_MS=<n>   how long to run, in simulated milliseconds (default 40)
//   +NOFASTBOOT   do not shortcut the 280 ms power-on reset counter
//   +CPUTRACE     every opcode fetch: address and opcode
//   +IOTRACE      every IN and OUT
//   +MEMTRACE     every SDRAM request of the CPU and every ROM read
//   +DQTRACE      the SDRAM data bus on every clock of a CPU read
//   +TRACE_MS=<n> hold the traces off until n ms
//   +SPITRACE     every byte the MCU stand-in gets into sysctrl
//   +PPM_MAX=<n>  cap how many .ppm frames are written (default 4)
//   +PPM_EVERY=<n>  write every n-th frame only (default 1; 50 is about a second)
//   +PPM_FROM=<n> skip the frames before n ms
//   +NOMEMCHECK   turn off the read-after-write check on the SDRAM port
//   +HDMIDBG      print every data island packet the decoder sees
//   +TYPE         type a BASIC line through the HID path (at +TYPE_MS=<n>, default 2200)
//   +TYPE_SHIFTTEST  "ab", Shift tap, "ab", Shift tap, "ab", Enter at +TYPE_MS
//   +TYPE_LINE    10 print "tape ok" and Enter at +TYPE_MS (with +RAMDUMP: the tokens)
//   +TYPE_STR=<text>  type the text ('_' for a space) and Enter at +TYPE_MS
//   +BAS=<file.tok>  poke a tokenised program into 4001h at +TYPE_MS and run it
//   +TYPE_CLOAD   type cload"TEST and Enter at +TYPE_MS, then "run" and Enter
//                 +RUN_MS-300 later (with +TAPE=<file>, see sd_card_sim.v;
//                 +CLOAD_VAR=<n> for the other spellings, none of which load);
//                 $test$plusargs matches prefixes, so +TYPE_CLOAD and
//                 +TYPE_MS= would both read as +TYPE without the guard below
//   +EXP=<n>      the OSD's expansion switches: 1 floppy, 2 IDE, 3 ROM disk (one
//                 on); +EXP_FDD +EXP_IDE +EXP_ROM turn each on as well
//   +NOWAITS      run with the video controller's cost turned off ('w' 0)
//   +TAPE= +FDDA= +FDDB= +HDD= +ROMDISK=<file>   images (sim/stubs/sd_card_sim.v)
//   +SDFAST       the card answers in microseconds, not a millisecond
//   +LONG_HEADER  the tape's header tones at the machine's length (4000
//                 bit-times, 3.3 s each) instead of the testbench's short ones
//
// Every delay in milliseconds is `ms * 64'd1000000`: a 32-bit product
// wraps past 4294 ms, and +PPM_FROM=6300 once wrote its frames at 2.0 s.
//
// The SPI master, the HDMI decoder and the .ppm writer are UKNC Nano's
// (sim/tb/tb_top.v there), the checks around them are this machine's.
//========================================================================
`timescale 1ns / 1ps

module tb_top;

    //--------------------------------------------------------------------
    // Clock and board inputs
    //--------------------------------------------------------------------
    reg clk27 = 1'b0;
    always #18.518 clk27 = ~clk27;      // 27 MHz

    reg  [1:0] buts = 2'b00;
    wire [5:0] leds;

    wire uart_tx;
    reg  uart_rx = 1'b1;

    wire sdclk;
    wire sdcmd, sddat0, sddat1, sddat2, sddat3;
    pullup (sdcmd); pullup (sddat0); pullup (sddat1);
    pullup (sddat2); pullup (sddat3);

    wire       O_tmds_clk_p, O_tmds_clk_n;
    wire [2:0] O_tmds_data_p, O_tmds_data_n;

    wire HP_BCK, HP_WS, HP_DIN, PA_EN;

    wire        O_sdram_clk, O_sdram_cke, O_sdram_cs_n;
    wire        O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [3:0]  O_sdram_dqm;
    wire [10:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba;
    wire [31:0] IO_sdram_dq;

    reg  spi_io_ss  = 1'b1;
    reg  spi_io_clk = 1'b0;
    reg  spi_io_din = 1'b0;

    wire [4:0] m0s;
    assign m0s[1] = spi_io_din ;
    assign m0s[2] = spi_io_ss  ;
    assign m0s[3] = spi_io_clk ;
    wire spi_io_dout = m0s[0];
    wire mcu_intn    = m0s[4];

    //--------------------------------------------------------------------
    // The design
    //--------------------------------------------------------------------
    top uut (
        .clk27(clk27), .buts(buts), .leds(leds),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .sdclk(sdclk), .sdcmd(sdcmd),
        .sddat0(sddat0), .sddat1(sddat1), .sddat2(sddat2), .sddat3(sddat3),
        .O_tmds_clk_p(O_tmds_clk_p),   .O_tmds_clk_n(O_tmds_clk_n),
        .O_tmds_data_p(O_tmds_data_p), .O_tmds_data_n(O_tmds_data_n),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN), .PA_EN(PA_EN),
        .O_sdram_clk(O_sdram_clk),     .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),   .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_dqm(O_sdram_dqm),     .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),       .IO_sdram_dq(IO_sdram_dq),
        .m0s(m0s)
    );

    //--------------------------------------------------------------------
    // Memory.  sdram.v uses single-word reads (BL1), CAS 2.
    //--------------------------------------------------------------------
    sdram_model #(.BURST(1)) ram (
        .clk(O_sdram_clk), .cke(O_sdram_cke),
        .cs_n(O_sdram_cs_n), .ras_n(O_sdram_ras_n),
        .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n),
        .ba(O_sdram_ba), .a(O_sdram_addr),
        .dqm_l(O_sdram_dqm[0]), .dqm_h(O_sdram_dqm[1]),
        .dq(IO_sdram_dq[15:0])
    );

    //--------------------------------------------------------------------
    // A minimal BL616: SPI master, mode 1, MSB first.
    //--------------------------------------------------------------------
    localparam SPI_HALF = 25;           // ns; 20 MHz like the real firmware
    // Hold time on MOSI after the falling edge: mcu_spi.v samples din on
    // the falling edge, and without this the next bit lands at the same
    // timestamp - a delta-cycle race the slave loses (UKNC Nano found it).
    localparam SPI_HOLD = 5;

    reg [7:0] spi_rx;

    task spi_byte(input [7:0] tx);
        integer b;
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                spi_io_din  = tx[b];
                #SPI_HALF spi_io_clk = 1'b1;
                #SPI_HALF spi_io_clk = 1'b0;
                #SPI_HOLD;
                spi_rx = {spi_rx[6:0], spi_io_dout};
            end
            // sysctrl.v answers one strobe behind: an inter-byte gap is
            // NOT optional (the real firmware gets it for free)
            #(SPI_HALF * 20);
        end
    endtask

    task spi_begin; begin spi_io_ss = 1'b0; #SPI_HALF; end endtask
    task spi_end;   begin #SPI_HALF spi_io_ss = 1'b1; #(SPI_HALF*4); end endtask

    // SYS command 4: set a configuration value
    task sys_set_val(input [7:0] id, input [7:0] val);
        begin
            spi_begin;
            spi_byte(8'd0);     // target SYS
            spi_byte(8'd4);     // command "set value"
            spi_byte(id);
            spi_byte(val);
            spi_end;
        end
    endtask

    // SYS command 6: bytes into the machine's RAM (sysctrl.v, poke.v), as
    // mnano/bas.c sends them: the address, then the bytes of a file
    task sys_poke_file(input [15:0] adr, input [1023:0] fname);
        integer fd, c, n;
        begin
            fd = $fopen(fname, "rb");
            if (fd == 0) $display("[tb] cannot open %0s", fname);
            else begin
                spi_begin;
                spi_byte(8'd0);     // target SYS
                spi_byte(8'd6);     // command "poke"
                spi_byte(adr[15:8]);
                spi_byte(adr[7:0]);
                n = 0;
                c = $fgetc(fd);
                while (c != -1) begin
                    spi_byte(c[7:0]);
                    n = n + 1;
                    c = $fgetc(fd);
                end
                spi_end;
                $fclose(fd);
                $display("[tb] %0t poked %0d bytes at %04x", $time, n, adr);
                poke_len = n;
            end
        end
    endtask

    task sys_poke_word(input [15:0] adr, input [15:0] val);
        begin
            spi_begin;
            spi_byte(8'd0);
            spi_byte(8'd6);
            spi_byte(adr[15:8]);
            spi_byte(adr[7:0]);
            spi_byte(val[7:0]);
            spi_byte(val[15:8]);
            spi_end;
        end
    endtask
    integer poke_len = 0;

    // HID command 1: one keyboard byte, as usb_host.c's kbd_tx sends it
    task hid_key(input [7:0] code);
        begin
            spi_begin;
            spi_byte(8'd1);     // target HID
            spi_byte(8'd1);     // keyboard
            spi_byte(code);
            spi_end;
        end
    endtask

    // press and release a matrix key: row, column.  The ROM scans the
    // matrix once a frame, in its interrupt, so a key has to be down for
    // more than 19.7 ms to be seen and up for as long to be seen released
    // - typed faster, "PRINT 1+1" came out as "1+INPRT", the rows in the
    // order the scan visits them.
    localparam KEY_HOLD = 60000000;   // 60 ms: three scans, so Shift and the key are seen together
    task key(input [3:0] row, input [2:0] col);
        reg [7:0] code;
        begin
            code = {1'b0, row, col} + 8'd1;
            hid_key(code);
            #KEY_HOLD;
            hid_key(8'h80 | code);
            #KEY_HOLD;
        end
    endtask

    // РГ (Shift) is row 6, column 0
    task shift_down; begin hid_key({1'b0, 4'd6, 3'd0} + 8'd1); #KEY_HOLD; end endtask
    task shift_up;   begin hid_key(8'h80 | ({1'b0, 4'd6, 3'd0} + 8'd1)); #KEY_HOLD; end endtask

    // A character as the ROM makes it (platform.md, the keyboard): letters
    // lower case unshifted and capitals with Shift; the digit row gives the
    // digit WITH Shift and the symbol without; the rest of the symbols on
    // the MSX keycaps' positions, Shift for the upper one.  Unknown
    // characters are skipped with a message.
    task type_char(input [7:0] ch);
        reg [3:0] row; reg [2:0] col; reg sh; reg ok;
        begin
            ok = 1'b1; sh = 1'b0; row = 4'd0; col = 3'd0;
            if (ch >= "a" && ch <= "z") begin ch = ch - 8'h20; sh = 1'b0; end
            else if (ch >= "A" && ch <= "Z") sh = 1'b1;
            if (ch >= "A" && ch <= "Z") begin
                // row 2 has A B at 6, 7; rows 3, 4, 5 the rest, eight a row
                ch = ch - "A" + 8'd22;      // A = 22 = row 2 col 6
                row = ch[6:3] + 4'd0; col = ch[2:0];
                row = (ch >> 3); col = ch[2:0];
            end
            else if (ch >= "0" && ch <= "9") begin
                sh = 1'b1;
                if (ch <= "7") begin row = 4'd0; col = ch - "0"; end
                else begin row = 4'd1; col = ch - "8"; end
            end
            else case (ch)
                "!": begin row = 4'd0; col = 3'd1; end
                "\"": begin row = 4'd0; col = 3'd2; end
                "#": begin row = 4'd0; col = 3'd3; end
                "$": begin row = 4'd0; col = 3'd4; end
                "%": begin row = 4'd0; col = 3'd5; end
                "&": begin row = 4'd0; col = 3'd6; end
                "'": begin row = 4'd0; col = 3'd7; end
                "(": begin row = 4'd1; col = 3'd0; end
                ")": begin row = 4'd1; col = 3'd1; end
                ",": begin row = 4'd1; col = 3'd2; end
                "-": begin row = 4'd1; col = 3'd3; end
                ".": begin row = 4'd1; col = 3'd4; end
                ":": begin row = 4'd1; col = 3'd5; end
                ";": begin row = 4'd1; col = 3'd6; end
                "?": begin row = 4'd1; col = 3'd7; end     // the / key unshifted is ? (BASIC's PRINT)
                "<": begin row = 4'd1; col = 3'd2; sh = 1'b1; end
                "=": begin row = 4'd1; col = 3'd3; sh = 1'b1; end
                ">": begin row = 4'd1; col = 3'd4; sh = 1'b1; end
                "*": begin row = 4'd1; col = 3'd5; sh = 1'b1; end
                "+": begin row = 4'd1; col = 3'd6; sh = 1'b1; end
                "/": begin row = 4'd1; col = 3'd7; sh = 1'b1; end
                "@": begin row = 4'd2; col = 3'd5; end
                "_": begin row = 4'd8; col = 3'd0; end     // a space
                " ": begin row = 4'd8; col = 3'd0; end
                default: begin ok = 1'b0; $display("[tb] type_char: no key for %c (%02x)", ch, ch); end
            endcase
            if (ok) begin
                if (sh) shift_down;
                key(row, col);
                if (sh) shift_up;
            end
        end
    endtask

    task type_string(input [8*255:1] str);
        integer n, i;
        reg [7:0] c;
        begin
            // the string is right-aligned in the vector: find its length
            n = 0;
            for (i = 0; i < 255; i = i + 1) if (str[8*(i+1) -: 8] != 8'd0) n = i + 1;
            for (i = n - 1; i >= 0; i = i - 1) begin
                c = str[8*(i+1) -: 8];
                type_char(c);
            end
        end
    endtask

    reg [7:0] st0, st1, st2, st3;

    // Exactly what sys_status_is_valid() in mnano/sysctrl.c does.
    task sys_status;
        begin
            spi_begin;
            spi_byte(8'd0);     // target SYS
            spi_byte(8'd0);     // command "status"
            spi_byte(8'h00);                    // dummy
            spi_byte(8'h00);  st0 = spi_rx;     // expect 5c
            spi_byte(8'h00);  st1 = spi_rx;     // expect 42
            spi_byte(8'h00);  st2 = spi_rx;     // core id
            spi_byte(8'h00);  st3 = spi_rx;     // coldboot status
            spi_end;
        end
    endtask

    // SYS command 7: the debug window, as sys_get_debug() in
    // mnano/sysctrl.c reads it - an offset, then eight bytes
    reg [7:0] dbgb [0:31];
    integer dbg_i, dbg_o;
    task sys_debug;
        begin
            for (dbg_o = 0; dbg_o < 32; dbg_o = dbg_o + 8) begin
                spi_begin;
                spi_byte(8'd0);             // target SYS
                spi_byte(8'd7);             // command "debug"
                spi_byte(dbg_o[7:0]);       // the offset
                for (dbg_i = 0; dbg_i < 8; dbg_i = dbg_i + 1) begin
                    spi_byte(8'h00);
                    dbgb[dbg_o + dbg_i] = spi_rx;
                end
                spi_end;
            end
        end
    endtask

    //--------------------------------------------------------------------
    // Run
    //--------------------------------------------------------------------
    integer run_ms, type_ms, exp_n, cload_var;
    reg [8*255:1] type_str;
    reg [1023:0]  bas_file;
    integer tries;
    reg     fastboot;
    integer cfg_errs = 0;

    initial begin
        if (!$value$plusargs("RUN_MS=%d", run_ms)) run_ms = 40;
        fastboot = !$test$plusargs("NOFASTBOOT");

        if ($test$plusargs("VCD")) begin
            $dumpfile("sim/out/tb_top.vcd");
            $dumpvars(0, tb_top);
        end

        // Skip the 280 ms power-on reset counter unless told not to.  It
        // is held at zero until the SDRAM reports init, so wait for that.
        if (fastboot) begin
            wait (uut.init);
            #20000;
            force uut.count_rst = 24'h7FFFF0;
            #20000;
            release uut.count_rst;
            $display("[tb] %0t fastboot: count_rst forced", $time);
        end

        // Wait for the core to answer, the way main.c does.
        tries = 0;
        st0 = 0; st1 = 0; st2 = 0;
        while (tries < 200 && !(st0 == 8'h5c && st1 == 8'h42)) begin
            #100000;
            sys_status;
            tries = tries + 1;
        end

        if (st0 == 8'h5c && st1 == 8'h42)
            $display("[tb] %0t FPGA ready, core id 0x%02x (expect 07 = PK8000)",
                     $time, st2);
        else begin
            $display("[tb] %0t FPGA never answered (got %02x %02x %02x)",
                     $time, st0, st1, st2);
            cfg_errs = cfg_errs + 1;
        end
        if (st2 !== 8'h07) cfg_errs = cfg_errs + 1;

        sys_set_val("R", 8'd3);     // cold boot, as main.c does
        #50000;
        // the OSD's defaults (mnano/menu.c, variables_pk8000)
        sys_set_val("A", 8'd1);
        sys_set_val("b", 8'd1);
        sys_set_val("w", $test$plusargs("NOWAITS") ? 8'd0 : 8'd1);
        sys_set_val("j", 8'd0);
        if (!$value$plusargs("EXP=%d", exp_n)) exp_n = 0;
        sys_set_val("f", {7'd0, (exp_n == 1) || $test$plusargs("EXP_FDD")});
        sys_set_val("i", {7'd0, (exp_n == 2) || $test$plusargs("EXP_IDE")});
        sys_set_val("r", {7'd0, (exp_n == 3) || $test$plusargs("EXP_ROM")});
        sys_set_val("T", 8'd1);
        sys_set_val("y", 8'd1);
        sys_set_val("p", 8'd0); sys_set_val("q", 8'd0); sys_set_val("K", 8'd0);
        // the tape's header tone is 4000 bit-times on the machine, which is
        // three seconds of simulation; the ROM locks on far fewer
        if (!$test$plusargs("LONG_HEADER")) force uut.tp.short_header = 1'b1;
        sys_set_val("R", 8'd0);     // and run
        $display("[tb] %0t released reset", $time);
        #2000;
        if (uut.system_volume !== 2'd1 || uut.system_beeper !== 1'b1 ||
            uut.system_joyswap !== 1'b0) begin
            $display("[tb] *** OSD VALUES WRONG after the defaults");
            cfg_errs = cfg_errs + 1;
        end

        // +TYPE: a line of BASIC through the keyboard path, once the ROM
        // is at its prompt: "print 1+1" and Enter, so the screen shows
        // " 2" - see the frames.  Unshifted letters are lower case.
        if ($test$plusargs("TYPE") && !$test$plusargs("TYPE_CLOAD") && !$test$plusargs("TYPE_SHIFTTEST")
                                   && !$test$plusargs("TYPE_LINE") && !$test$plusargs("TYPE_STR")
                                   && !$test$plusargs("BAS")) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2200;
            #(type_ms * 64'd1000000);
            $display("[tb] %0t typing PRINT 1+1", $time);
            key(4, 5); key(4, 7); key(3, 6); key(4, 3); key(5, 1);   // P R I N T
            key(8, 0);                                              // space
            // the digit keys type their symbols unshifted on this ROM
            // ('!' for the 1 key) and digits with Shift; ';' shifted is '+'
            hid_key({1'b0, 4'd6, 3'd0} + 8'd1); #KEY_HOLD;           // Shift down
            key(0, 1); key(1, 6); key(0, 1);                        // 1 + 1
            hid_key(8'h80 | ({1'b0, 4'd6, 3'd0} + 8'd1)); #KEY_HOLD; // Shift up
            key(7, 7);                                              // Enter
        end

        // +BAS=<file.tok>: a tokenised program (tools/mkcas.py --tok) into
        // the RAM at 4001h at +TYPE_MS, the ROM's pointers after it, then
        // "run" - the OSD's "Run .bas" as mnano/bas.c does it
        if ($value$plusargs("BAS=%s", bas_file)) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2200;
            #(type_ms * 64'd1000000);
            sys_poke_file(16'h4001, bas_file);
            sys_poke_word(16'hF930, 16'h4001 + poke_len[15:0]);   // VARTAB
            sys_poke_word(16'hF932, 16'h4001 + poke_len[15:0]);   // ARYTAB
            sys_poke_word(16'hF934, 16'h4001 + poke_len[15:0]);   // STREND
            #(20 * 64'd1000000);
            $display("[tb] %0t typing run", $time);
            key(4, 7); key(5, 2); key(4, 3);                        // r u n
            key(7, 7);
        end

        // +TYPE_STR=<text>: type the text and Enter at +TYPE_MS, through
        // type_str below (letters, digits, the symbols a BASIC line needs;
        // '_' for a space, since a plusarg cannot carry one)
        if ($value$plusargs("TYPE_STR=%s", type_str)) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2200;
            #(type_ms * 64'd1000000);
            $display("[tb] %0t typing %0s", $time, type_str);
            type_string(type_str);
            key(7, 7);                                              // Enter
        end

        // +TYPE_LINE: type 10 print "tape ok" and Enter at +TYPE_MS - the
        // line mkcas.py puts on the tape, for a RAM dump of the ROM's own
        // tokens (+RAMDUMP; the program is at 4001h)
        if ($test$plusargs("TYPE_LINE")) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2200;
            #(type_ms * 64'd1000000);
            $display("[tb] %0t typing 10 print \"tape ok\"", $time);
            shift_down; key(0, 1); key(0, 0); shift_up;             // 1 0 (digits are shifted)
            key(8, 0);                                              // space
            key(4, 5); key(4, 7); key(3, 6); key(4, 3); key(5, 1);   // p r i n t
            key(8, 0);                                              // space
            key(0, 2);                                              // "
            key(5, 1); key(2, 6); key(4, 5); key(3, 2);             // t a p e
            key(8, 0);                                              // space
            key(4, 4); key(4, 0);                                   // o k
            key(0, 2);                                              // "
            key(7, 7);                                              // Enter
        end

        // +TYPE_SHIFTTEST: "ab", a Shift tap, "ab", a Shift tap, "ab", Enter -
        // what a Shift press does to the case of what follows
        if ($test$plusargs("TYPE_SHIFTTEST")) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2200;
            #(type_ms * 64'd1000000);
            $display("[tb] %0t shift test; matrix row 6 = %b", $time, uut.io.keys[6]);
            key(2, 6); key(2, 7);                                   // a b
            shift_down; shift_up;
            $display("[tb] %0t after a Shift tap: matrix row 6 = %b", $time, uut.io.keys[6]);
            key(2, 6); key(2, 7);                                   // a b
            shift_down; shift_up;
            $display("[tb] %0t after a Shift tap: matrix row 6 = %b", $time, uut.io.keys[6]);
            key(2, 6); key(2, 7);                                   // a b
            key(7, 7);                                              // Enter
        end

        // +TYPE_CLOAD: cload"TEST Enter, then "run" Enter 300 ms before the end.
        // +CLOAD_VAR=<n> picks the spelling; 2 (the default) is cload"TEST
        // with Shift held from the quote to the end of the name.  Measured
        // 4 Sep 2026 (with the matrix polarity of ports.v still wrong):
        // 0 CLOAD with Shift held and 3 lowercase cload both get
        // "? 2 Error" (a syntax error: this ROM's CLOAD wants its string),
        // 1 the Shift+F2 macro types nothing the ROM takes; 4 is 2 with
        // Shift tapped around each letter of the name.
        if ($test$plusargs("TYPE_CLOAD")) begin
            if (!$value$plusargs("TYPE_MS=%d", type_ms)) type_ms = 2200;
            if (!$value$plusargs("CLOAD_VAR=%d", cload_var)) cload_var = 2;
            #(type_ms * 64'd1000000);
            $display("[tb] %0t typing cload (variant %0d)", $time, cload_var);
            case (cload_var)
                0: begin
                    shift_down;
                    key(3, 0); key(4, 1); key(4, 4); key(2, 6); key(3, 1);   // C L O A D
                    shift_up;
                end
                1: begin
                    shift_down; key(6, 6); shift_up;                        // Shift+F2
                end
                2: begin
                    key(3, 0); key(4, 1); key(4, 4); key(2, 6); key(3, 1);   // c l o a d
                    key(0, 2);                                              // " (the 2 key unshifted: symbols are unshifted on this ROM)
                    shift_down;
                    key(5, 1); key(3, 2); key(5, 0); key(5, 1);             // T E S T, mkcas.py's name
                    shift_up;
                end
                4: begin
                    key(3, 0); key(4, 1); key(4, 4); key(2, 6); key(3, 1);   // c l o a d
                    shift_down; key(0, 2); shift_up;                        // "
                    shift_down; key(5, 1); shift_up;                        // T E S T, Shift around each
                    shift_down; key(3, 2); shift_up;
                    shift_down; key(5, 0); shift_up;
                    shift_down; key(5, 1); shift_up;
                end
                default: begin
                    key(3, 0); key(4, 1); key(4, 4); key(2, 6); key(3, 1);   // c l o a d
                end
            endcase
            key(7, 7);                                              // Enter
            #((run_ms - type_ms - 300) * 64'd1000000);
            $display("[tb] %0t typing run (tape position %0d)", $time, uut.tp.position);
            key(4, 7); key(5, 2); key(4, 3);                        // r u n
            key(7, 7);
            #(300 * 64'd1000000);
        end else
        #(run_ms * 64'd1000000);
        $display("[tb] %0t done: %0d video frames, leds=%b", $time, rx_frames, leds);
        $display("[tb] tape: position %0d, running %b; sd transfers %0d", uut.tp.position, uut.tape_running, sd_xfers);
        $display("[tb] config checks: %0d wrong", cfg_errs);
        $display("[tb] cpu: %0d opcode fetches, %0d I/O cycles, %0d interrupts taken of %0d raised, %0d wait states",
                 m1_count, io_count, inta_count, irq_count, wait_count);
        if (!$test$plusargs("NOMEMCHECK"))
            $display("[tb] read-after-write: %0d checked, %0d wrong", mem_checks, mem_errs);
        $display("[tb] sdram self-test: done %b, fail %b, late capture %b  (expect 1 0 0 against the model)",
                 uut.bist_done, uut.bist_fail, uut.cap_late);
        $display("[tb] address stability at the strobe: %0d cycles, %0d moved", adr_checks, adr_errs);
        sys_debug;
        $display("[tb] memcheck (CMD 7): %0d reads checked, %0d writes shadowed, %0d wrong; first %02x at %02x%02x got %02x pc %02x%02x; last %02x at %02x%02x got %02x pc %02x%02x",
                 {dbgb[20], dbgb[19]}, {dbgb[22], dbgb[21]}, dbgb[2],
                 dbgb[5], dbgb[4], dbgb[3], dbgb[6], dbgb[8], dbgb[7],
                 dbgb[11], dbgb[10], dbgb[9], dbgb[12], dbgb[14], dbgb[13]);
        $display("[tb] memcheck: flags %02x, %0d cpu resets, %0d fetches at 0000 (last from %02x%02x), last OUT %02x=%02x, pc %02x%02x",
                 dbgb[0], dbgb[15], dbgb[16], dbgb[18], dbgb[17], dbgb[23], dbgb[24], dbgb[26], dbgb[25]);
        $display("[tb] video: %0d tile fetches, mode %0d, screen bank %0d, text base %0d, sg base %0d",
                 vid_fetches, uut.vmode, uut.vbank, uut.txt_base, uut.sg_base);
        $display("[tb] i2s: %0d frames, %0d with sound", i2s_frames, i2s_nonzero);
        $display("[tb] hdmi: %0d packets, %0d ecc errors  (acr %0d, avi %0d, ai %0d, gcp %0d, audio %0d, null %0d)",
                 rx_packets, rx_ecc_errs, rx_acr, rx_avi, rx_ai, rx_gcp, rx_audio, rx_null);
        $display("[tb] hdmi frame: %0d x %0d, %0d bad guard bands", rx_w, rx_h_last, rx_bad_gb);
        $finish;
    end

    //--------------------------------------------------------------------
    // Watching the processor
    //--------------------------------------------------------------------
    integer trace_ms;
    reg     tracing = 1'b0;
    initial begin
        if (!$value$plusargs("TRACE_MS=%d", trace_ms)) trace_ms = 0;
        if (trace_ms > 0) #(trace_ms * 64'd1000000);
        tracing = 1'b1;
    end

    integer m1_count = 0, io_count = 0, inta_count = 0, wait_count = 0, irq_count = 0;
    reg     first_seen = 1'b0;

    // opcode fetches: the address at the strobe, the opcode when it lands
    reg [15:0] m1_adr;
    always @(posedge uut.clk) begin
        if (uut.mem_rd && uut.cpu.st_m1) begin
            m1_count = m1_count + 1;
            m1_adr   = uut.cpu_a_now;
            if (!first_seen) begin
                first_seen = 1'b1;
                $display("[tb] %0t CPU first fetch at %04x", $time, uut.cpu_a_now);
            end
        end
        if (uut.cpu.m1_pending && uut.tphase == 4'd3 && $test$plusargs("CPUTRACE") && tracing)
            $display("[cpu] %0t %04x: %02x", $time, m1_adr, uut.cpu_din);
        if (uut.inta_stb) begin
            inta_count = inta_count + 1;
            if (inta_count <= 6) $display("[tb] %0t interrupt acknowledged (%0d), inte=%b", $time, inta_count, uut.cpu_inte);
        end
        if (uut.frame_irq) irq_count = irq_count + 1;
        if (uut.io_rd && $test$plusargs("IOTRACE") && tracing)
            $display("[io]  %0t IN  %02x", $time, uut.cpu_a_now[7:0]);
        if (uut.io_wr && $test$plusargs("IOTRACE") && tracing)
            $display("[io]  %0t OUT %02x <= %02x", $time, uut.cpu_adr[7:0], uut.cpu_d_now);
        if (uut.io_rd || uut.io_wr) io_count = io_count + 1;
        if (uut.cpu.f2 && uut.cpu.wcnt != 5'd0) wait_count = wait_count + 1;
    end

    // The first-interrupt and the first-OUT to the video registers, as
    // milestones of the boot.
    initial begin
        @(posedge uut.inta_stb);
        $display("[tb] %0t first interrupt acknowledged", $time);
    end
    reg seen_mode = 1'b0;
    always @(posedge uut.clk)
        if (uut.io_wr && uut.cpu_adr[7:0] == 8'h84 && !seen_mode) begin
            seen_mode = 1'b1;
            $display("[tb] %0t first OUT 84h: %02x (video mode/bank)", $time, uut.cpu_d_now);
        end

    // Is the core's address bus already valid when SYNC is first seen?
    // cpu8080.v takes it at phase 7; if vm80a moved it later, this counts.
    integer adr_checks = 0, adr_errs = 0;
    reg [15:0] adr_at7;
    always @(posedge uut.clk) begin
        if (uut.cpu.cyc_start) adr_at7 = uut.cpu_a_now;
        if (uut.tphase == 4'd11 && uut.cpu.pin_sync) begin
            adr_checks = adr_checks + 1;
            if (adr_at7 !== uut.cpu_a_now) begin
                adr_errs = adr_errs + 1;
                if (adr_errs <= 5)
                    $display("[tb] *** address moved after the strobe: %04x -> %04x at %0t",
                             adr_at7, uut.cpu_a_now, $time);
            end
        end
    end

    // +SPITRACE
    always @(posedge uut.clk)
        if ($test$plusargs("SPITRACE") && uut.mcu_sys_strobe)
            $display("[spi] %0t sys byte %02x start=%b state=%0d cmd=%02x id=%02x",
                     $time, uut.mcu_dout, uut.mcu_start,
                     uut.sctl1.state, uut.sctl1.command, uut.sctl1.id);

    //--------------------------------------------------------------------
    // Read-after-write check on the SDRAM's CPU port: a shadow of every
    // byte written, compared against what is read back.
    //--------------------------------------------------------------------
    reg [7:0]  shadow  [0:65535];
    reg        known   [0:65535];
    integer    mem_errs = 0, mem_checks = 0;
    integer    si;
    initial for (si = 0; si < 65536; si = si + 1) known[si] = 1'b0;

    reg        rd_pend = 1'b0;
    reg [15:0] rd_adr;
    integer    rd_wait = 0;
    always @(posedge uut.clk) begin
        if (uut.mem.cpu_req && uut.tphase == 4'd7) begin
            if (uut.mem.cpu_we) begin
                shadow[uut.mem.cpu_adr] = uut.mem.cpu_wdata;
                known[uut.mem.cpu_adr]  = 1'b1;
            end else begin
                rd_pend = 1'b1; rd_adr = uut.mem.cpu_adr; rd_wait = 0;
            end
        end else if (rd_pend) begin
            rd_wait = rd_wait + 1;
            if (rd_wait == 6) begin
                rd_pend = 1'b0;
                if (known[rd_adr] && !$test$plusargs("NOMEMCHECK")) begin
                    mem_checks = mem_checks + 1;
                    if (uut.ram_rdata !== shadow[rd_adr]) begin
                        mem_errs = mem_errs + 1;
                        if (mem_errs <= 10)
                            $display("[mem] %0t read %02x at %04x, wrote %02x",
                                     $time, uut.ram_rdata, rd_adr, shadow[rd_adr]);
                    end
                end
            end
        end
    end

    // +MEMTRACE: every request on the SDRAM's CPU port, and every ROM read
    always @(posedge uut.clk)
        if ($test$plusargs("MEMTRACE") && tracing) begin
            if (uut.mem.cpu_req && uut.tphase == 4'd7)
                $display("[ram] %0t %s %04x %s %02x", $time, uut.mem.cpu_we ? "wr" : "rd",
                         uut.mem.cpu_adr, uut.mem.cpu_we ? "<=" : "", uut.mem.cpu_wdata);
            if (uut.mem_rd && uut.page_now != 2'd3)
                $display("[rom] %0t rd %04x page %0d", $time, uut.cpu_a_now, uut.page_now);
        end

    // +DQTRACE: the SDRAM data bus on every clock of a CPU read in flight,
    // with the controller's slot clock beside it - which clock the word is
    // really on the bus is not a thing to take on trust in Verilator
    always @(posedge uut.clk)
        if ($test$plusargs("DQTRACE") && tracing && uut.mem.act && !uut.mem.act_we && !uut.mem.act_vid)
            $display("[dq] %0t sc=%0d tphase=%0d adr=%04x dq=%04x oe=%b rdata=%02x", $time, uut.mem.sc, uut.tphase,
                     uut.mem.act_adr, IO_sdram_dq[15:0], ram.dq_oe, uut.ram_rdata);

    integer vid_lines = 0;
    // +VIDTRACE: the video's first 400 requests and answers after the trace starts,
    // and the display's tile hand-overs there; +RAMDUMP writes the SDRAM
    // model's contents to sim/out/ram.hex at the end (word n = bytes 2n, 2n+1)
    always @(posedge uut.clk) begin
        if ($test$plusargs("VIDTRACE") && tracing && vid_lines < 400 && uut.vcnt == 9'd72) begin
            if (uut.vid.px6 == 3'd5 && uut.vid.slot >= 9'd40 && uut.vid.slot < 9'd64)
                $display("[pix] %0t slot=%0d pix=%x d_pat=%02x d_px=%0d fg=%x bg=%x", $time, uut.vid.slot, uut.vid.pix, uut.vid.d_pat, uut.vid.d_px, uut.color88[3:0], uut.color88[7:4]);
            if (uut.vid_req) begin vid_lines = vid_lines + 1;
                $display("[vid] %0t v=%0d h=%0d req %04x ftst=%0d ftile=%0d mode=%0d", $time, uut.vcnt, uut.hcnt, uut.vid_adr, uut.vid.ftst, uut.vid.ftile, uut.vmode); end
            if (uut.vid_ack) $display("[vid] %0t h=%0d ack %02x", $time, uut.hcnt, uut.vid_rdata);
            if (uut.vid.hand_over) $display("[vid] %0t h=%0d hand_over pat=%02x name=%02x", $time, uut.hcnt, uut.vid.f_pat, uut.vid.f_name);
        end
        if ($test$plusargs("IRQTRACE") && tracing) begin
            if (uut.frame_irq) $display("[irq] %0t frame_irq (int_ff=%b inte=%b)", $time, uut.int_ff, uut.cpu_inte);
            if (uut.inta_stb)  $display("[irq] %0t inta_stb", $time);
        end
    end
    final if ($test$plusargs("RAMDUMP")) $writememh("sim/out/ram.hex", ram.mem, 0, 32767);

    integer sd_xfers = 0;
    always @(posedge uut.clk) if (uut.sd_rdone) sd_xfers = sd_xfers + 1;

    // the tape motor (port 82h bit 4), with the player's position: where
    // the ROM's loader started and stopped
    reg motor_d = 1'b0;
    always @(posedge uut.clk) begin
        motor_d <= uut.tape_motor;
        if (uut.tape_motor != motor_d)
            $display("[tb] %0t tape motor %s at position %0d", $time, uut.tape_motor ? "on" : "off", uut.tp.position);
    end

    integer vid_fetches = 0;
    always @(posedge uut.clk) if (uut.vid_req) vid_fetches = vid_fetches + 1;

    //--------------------------------------------------------------------
    // I2S monitor
    //--------------------------------------------------------------------
    reg [15:0] i2s_sr = 16'd0;
    reg [15:0] i2s_l  = 16'd0;
    reg        ws_d   = 1'b0;
    integer    i2s_frames = 0, i2s_nonzero = 0;
    always @(posedge HP_BCK) begin
        i2s_sr <= {i2s_sr[14:0], HP_DIN};
        ws_d   <= HP_WS;
        if (HP_WS && !ws_d) i2s_l <= i2s_sr;
        if (!HP_WS && ws_d) begin
            i2s_frames = i2s_frames + 1;
            if (i2s_l !== 16'd0 || i2s_sr !== 16'd0) i2s_nonzero = i2s_nonzero + 1;
        end
    end

    //--------------------------------------------------------------------
    // The HDMI receiver: hdmi_serdes is stubbed, so what leaves the
    // design is three ten-bit TMDS words a pixel clock.  This decodes
    // them as a sink does and rebuilds the picture for `make frames`.
    //--------------------------------------------------------------------
    wire        px_clk = uut.clk;
    wire [9:0]  t0 = uut.tmds_ch0;
    wire [9:0]  t1 = uut.tmds_ch1;
    wire [9:0]  t2 = uut.tmds_ch2;

    localparam [9:0] CTL00 = 10'b1101010100, CTL01 = 10'b0010101011,
                     CTL10 = 10'b0101010100, CTL11 = 10'b1010101011;
    localparam [9:0] VGB_02 = 10'b1011001100, VGB_1 = 10'b0100110011;

    function is_ctl(input [9:0] w);
        is_ctl = (w == CTL00) || (w == CTL01) || (w == CTL10) || (w == CTL11);
    endfunction

    function [1:0] ctl_of(input [9:0] w);
        ctl_of = (w == CTL00) ? 2'b00 : (w == CTL01) ? 2'b01 :
                 (w == CTL10) ? 2'b10 : 2'b11;
    endfunction

    function [7:0] tmds_dec(input [9:0] w);
        reg [7:0] qm, d;
        integer   i;
        begin
            qm = w[9] ? ~w[7:0] : w[7:0];
            d[0] = qm[0];
            for (i = 1; i < 8; i = i + 1)
                d[i] = w[8] ? (qm[i] ^ qm[i-1]) : (qm[i] ~^ qm[i-1]);
            tmds_dec = d;
        end
    endfunction

    function [4:0] terc4_dec(input [9:0] w);   // bit 4 set = not a TERC4 word
        case (w)
            10'b1010011100: terc4_dec = 5'h00;
            10'b1001100011: terc4_dec = 5'h01;
            10'b1011100100: terc4_dec = 5'h02;
            10'b1011100010: terc4_dec = 5'h03;
            10'b0101110001: terc4_dec = 5'h04;
            10'b0100011110: terc4_dec = 5'h05;
            10'b0110001110: terc4_dec = 5'h06;
            10'b0100111100: terc4_dec = 5'h07;
            10'b1011001100: terc4_dec = 5'h08;
            10'b0100111001: terc4_dec = 5'h09;
            10'b0110011100: terc4_dec = 5'h0a;
            10'b1011000110: terc4_dec = 5'h0b;
            10'b1010001110: terc4_dec = 5'h0c;
            10'b1001110001: terc4_dec = 5'h0d;
            10'b0101100011: terc4_dec = 5'h0e;
            10'b1011000011: terc4_dec = 5'h0f;
            default:        terc4_dec = 5'h10;
        endcase
    endfunction

    function [7:0] ecc_step(input [7:0] ecc, input b);
        ecc_step = (ecc >> 1) ^ ((ecc[0] ^ b) ? 8'b10000011 : 8'd0);
    endfunction

    localparam RX_CTL = 0, RX_VGB = 1, RX_VID = 2,
               RX_DGB = 3, RX_DI  = 4, RX_DGBT = 5;

    integer rx_state   = RX_CTL;
    integer rx_gb      = 0;
    integer rx_frames  = 0;
    integer rx_packets = 0, rx_ecc_errs = 0;
    integer rx_acr = 0, rx_avi = 0, rx_ai = 0, rx_audio = 0, rx_null = 0, rx_gcp = 0;
    integer rx_bad_gb = 0;

    reg        rx_vs = 1'b0, rx_vs_d = 1'b0;
    integer    rx_x = 0, rx_y = 0, rx_w = 0, rx_h_last = 0;

    parameter MAXW = 1024;
    parameter MAXH = 640;
    reg [23:0] fb [0:MAXW*MAXH-1];

    reg [4:0]  pk_cnt = 5'd0;
    reg [23:0] pk_hdr;
    reg [55:0] pk_sub [0:3];
    reg [7:0]  pk_par [0:4];
    reg [7:0]  pk_ecc [0:4];
    integer    gi;

    integer fh, fi, fj, fh_h;
    integer written = 0, ppm_max;
    reg     want_ppm = 0;
    reg [255:0] fname;
    integer ppm_from, ppm_every;
    reg     ppm_armed = 1'b0;
    initial begin
        want_ppm = $test$plusargs("VIDEO_PPM");
        if (!$value$plusargs("PPM_MAX=%d", ppm_max)) ppm_max = 4;
        if (!$value$plusargs("PPM_FROM=%d", ppm_from)) ppm_from = 0;
        if (!$value$plusargs("PPM_EVERY=%d", ppm_every)) ppm_every = 1;
        if (ppm_from > 0) #(ppm_from * 64'd1000000);
        ppm_armed = 1'b1;
    end

    task write_ppm;
        begin
            written = written + 1;
            fh_h = (rx_y > MAXH) ? MAXH : rx_y;
            $sformat(fname, "sim/out/frame_%04d.ppm", rx_frames);
            fh = $fopen(fname, "wb");
            if (fh) begin
                $fwrite(fh, "P6\n%0d %0d\n255\n", rx_w, fh_h);
                for (fj = 0; fj < fh_h; fj = fj + 1)
                    for (fi = 0; fi < rx_w; fi = fi + 1)
                        $fwrite(fh, "%c%c%c",
                                fb[fj*MAXW+fi][23:16],
                                fb[fj*MAXW+fi][15:8],
                                fb[fj*MAXW+fi][7:0]);
                $fclose(fh);
                $display("[hdmi] %0t wrote %0s (%0dx%0d)", $time, fname, rx_w, fh_h);
            end
        end
    endtask

    task finish_packet;
        reg [7:0] ptype;
        begin
            rx_packets = rx_packets + 1;
            for (gi = 0; gi < 5; gi = gi + 1)
                if (pk_par[gi] !== pk_ecc[gi]) rx_ecc_errs = rx_ecc_errs + 1;
            ptype = pk_hdr[7:0];
            case (ptype)
                8'h00: rx_null  = rx_null  + 1;
                8'h01: rx_acr   = rx_acr   + 1;
                8'h02: rx_audio = rx_audio + 1;
                8'h03: rx_gcp   = rx_gcp   + 1;
                8'h82: rx_avi   = rx_avi   + 1;
                8'h84: rx_ai    = rx_ai    + 1;
                default: ;
            endcase
            if ($test$plusargs("HDMIDBG"))
                $display("[hdmi] %0t packet type %02x hdr %06x sub0 %014x",
                         $time, ptype, pk_hdr, pk_sub[0]);
        end
    endtask

    always @(posedge px_clk) begin : rx
        reg [1:0] c0, c1, c2;
        reg [4:0] n0, n1, n2;
        reg [7:0] dr, dg, db;
        c0 = ctl_of(t0); c1 = ctl_of(t1); c2 = ctl_of(t2);

        case (rx_state)
        RX_CTL: begin
            if (is_ctl(t0)) begin
                rx_vs_d = rx_vs;
                rx_vs   = c0[1];
                if (rx_vs && !rx_vs_d) begin      // a frame just ended
                    if (rx_frames > 0 && want_ppm && ppm_armed &&
                        written < ppm_max && (rx_frames % ppm_every) == 0) write_ppm;
                    rx_frames = rx_frames + 1;
                    rx_h_last = rx_y;
                    rx_x = 0; rx_y = 0;
                end
            end
            if (is_ctl(t1) && c1 == 2'b01) begin
                if (is_ctl(t2) && c2 == 2'b01) rx_state = RX_DGB;
                else                           rx_state = RX_VGB;
                rx_gb = 0;
            end
        end

        RX_VGB: begin
            if (is_ctl(t1) && ctl_of(t1) == 2'b01) begin
            end else begin
                if (t0 !== VGB_02 || t1 !== VGB_1 || t2 !== VGB_02)
                    rx_bad_gb = rx_bad_gb + 1;
                rx_gb = rx_gb + 1;
                if (rx_gb == 2) begin rx_state = RX_VID; rx_x = 0; end
            end
        end

        RX_VID: begin
            if (is_ctl(t0)) begin
                if (rx_x > rx_w) rx_w = rx_x;
                rx_x = 0;
                rx_y = rx_y + 1;
                rx_state = RX_CTL;
            end else begin
                db = tmds_dec(t0); dg = tmds_dec(t1); dr = tmds_dec(t2);
                if (rx_x < MAXW && rx_y < MAXH)
                    fb[rx_y*MAXW+rx_x] = {dr, dg, db};
                rx_x = rx_x + 1;
            end
        end

        RX_DGB: begin
            if (is_ctl(t1) && ctl_of(t1) == 2'b01 &&
                is_ctl(t2) && ctl_of(t2) == 2'b01) begin
            end else begin
                if (t1 !== VGB_1 || t2 !== VGB_1) rx_bad_gb = rx_bad_gb + 1;
                rx_gb = rx_gb + 1;
                if (rx_gb == 2) begin
                    rx_state = RX_DI;
                    pk_cnt = 5'd0;
                    for (gi = 0; gi < 5; gi = gi + 1) pk_par[gi] = 8'd0;
                end
            end
        end

        RX_DI: begin
            n0 = terc4_dec(t0); n1 = terc4_dec(t1); n2 = terc4_dec(t2);
            if (n0[4] || n1[4] || n2[4]) begin
                rx_gb = 0;
                rx_state = RX_DGBT;
            end else begin
                if (pk_cnt < 5'd24) pk_hdr[pk_cnt] = n0[2];
                for (gi = 0; gi < 4; gi = gi + 1) begin
                    pk_sub[gi][{pk_cnt, 1'b0}] = n1[gi];
                    pk_sub[gi][{pk_cnt, 1'b1}] = n2[gi];
                end
                if (pk_cnt >= 5'd28) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        pk_ecc[gi][{pk_cnt[1:0], 1'b0}] = n1[gi];
                        pk_ecc[gi][{pk_cnt[1:0], 1'b1}] = n2[gi];
                    end
                end
                if (pk_cnt >= 5'd24) pk_ecc[4][pk_cnt[2:0]] = n0[2];
                if (pk_cnt < 5'd28) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        pk_par[gi] = ecc_step(pk_par[gi], n1[gi]);
                        pk_par[gi] = ecc_step(pk_par[gi], n2[gi]);
                    end
                    if (pk_cnt < 5'd24)
                        pk_par[4] = ecc_step(pk_par[4], n0[2]);
                end
                if (pk_cnt == 5'd31) begin
                    finish_packet;
                    for (gi = 0; gi < 5; gi = gi + 1) pk_par[gi] = 8'd0;
                end
                pk_cnt = pk_cnt + 5'd1;
            end
        end

        RX_DGBT: begin
            rx_gb = rx_gb + 1;
            if (rx_gb == 2) rx_state = RX_CTL;
        end
        endcase
    end

endmodule
