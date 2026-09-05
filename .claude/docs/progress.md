# State of the port

Last updated: 5 September 2026 (morning), v0.2.0 alpha, the second day.

## What there is

Built, linted, simulated, timed - and, on the evening of 4 Sep 2026,
**flashed three times**: no bitstream has booted (below, "The first
board", "The second flash", "The third flash").  Nothing of this
design has yet run on hardware past the ROM's RAM test.  The third
flash's Debug page, read on the morning of 5 Sep, named the fault: the
SDRAM controller never precharged (defect 16, its column word had no
A10), the simulation model had not minded, and the chip aliased all
64 KB into one row.  Fixed, reproduced in simulation, rebuilt; the
fourth bitstream waits to be flashed ("The Debug page read", below).
On UKNC Nano's framework:

- the КР580ВМ80А (vm80a) at 2.5 MHz on a 30 MHz clock, the SDRAM on a
  fixed timetable, the BASIC 1.2 ROM, the bank register;
- the two ВВ55s, the video registers, the colour RAM, the frame
  interrupt, the keyboard matrix from USB, two USB joysticks, the beeper;
- the display in all four modes, rendered as the beam draws it and shown
  as 768x576 at 50.73 Hz over HDMI with UKNC Nano's encoder;
- the video controller's cost to the CPU, from Emu80's measured tables;
- **0.2.0, the peripherals**: a `.cas` tape player into the tape input;
  the НГМД (MiSTer's wd1793 with the controller's ROM) with two drives
  from `.fdd` images; the community IDE/CF adapter with its ROM and an
  `.img`; the ROM disk cartridge copied into the SDRAM; the AY card at
  14h/15h; one owner at a time on the SD path (`sd_arbiter.v`); the
  expansion page as a menu choice;
- the firmware: core id 7, the keymap, the image slots and the switches
  in the menu, settings on the card, "Run .bas" (a text program
  tokenised and poked into the RAM through `poke.v`);
- lint, a full-machine simulation with checks and frames, a card model
  that serves host files as the images, a host walk of the menu, the
  bitstream with the timing gate.

```
Logic 30%   Register 17%   BSRAM 25/46 (55%)   PLL 2/2   clk30 70.3 MHz   0 violations   [4 Sep 2026, v0.2.0 + poke.v]
Logic 33%   Register 18%   BSRAM 28/46 (61%)   PLL 2/2   clk30 65.8 MHz   0 violations   [5 Sep 2026, v0.2.0 + memcheck.v + A10 - the fourth bitstream]
Logic 33%   Register 18%   BSRAM 28/46 (61%)   PLL 2/2   clk30 55.4 MHz   0 violations   [4 Sep 2026 night, v0.2.0 + memcheck.v]
Logic 29%   Register 17%   BSRAM 25/46 (55%)   PLL 2/2   clk30 62.8 MHz   0 violations   [4 Sep 2026, v0.2.0]
Logic 17%   Register 10%   BSRAM 11/46 (24%)   PLL 2/2   clk30 66.6 MHz   0 violations   [4 Sep 2026, v0.1.0]
```

## The first board, 4 September 2026 (evening)

The operator flashed v0.2.0's `bin/tang.fs` and `bin/bl616.bin` and
reported: a wide black screen with the upper and lower borders white,
blinking with colours.  Read against the design and the ROM:

- The monitor took the 768x576 at 50.73 Hz frame with its 144-clock
  back porch, and the geometry is the machine's: a 384-line picture
  area with 104 and 88 lines of border above and below.  Both PLLs and
  the HDMI path work (defect 6 closed, on this monitor).
- The border is port 88h's high nibble, live.  The ROM writes 88h = 77h
  (cyan) at 2938h before its RAM test of F000h-FFFFh and 88h = **0FFh**
  (white) at 295Ch the moment the test passes (`CMA` of the zero the
  loop ends on), and BASIC's 0Fh (black) only much later.  A white
  border means the zero-fill test passed; blinking cyan/white means the
  ROM is restarting - the code after the test pushes 0000h, calls the
  copy routine at 005Ch through the stack, and a RET that reads back
  zeros goes to 0000h.  That is exactly defect 2's picture in
  simulation: the memory reads zeros right and other values wrong.
- The picture is black because the machine is still in the ROM's boot
  mode 1 with the colour RAM at zero; BASIC's mode 0 is never reached.

So the memory interface is suspect and the tool cannot say: the SDRAM
pads are unconstrained, and the capture clock in `sdram.v` rests on
the arithmetic in its header (the chip clocked 90 degrees behind, CAS
latency 2, the word on the bus in slot clock 3) which the simulation
model was written to.  UKNC Nano's `sdram2.v` uses the same phase and
latency at 50 MHz and captures two clocks after its READ, which is the
same arithmetic and works; at 30 MHz the margins are wider, not
narrower.  Tried: `set_output_delay`/`set_input_delay` on the SDRAM pads
against a `create_clock` on CLKOUTP with its 90-degree waveform, in a
scratch copy - the tool accepted it with no violation but reported no
path through those pads, so it proved nothing and is not in the SDC.

What was done instead: **the controller tests itself** (defect 16).
After `init`, while the CPU is still held, it writes 55h AAh 5Ah A5h to
0FFF0h-0FFF3h and reads them back in order; on a mismatch it moves the
capture to slot clock 4 and repeats; on a second failure it flags.
LED2 lit at boot = the late capture was chosen, LED3 lit = both
failed (`build.md`, "Reading the board").  Against the model the
verdict is done/no fail/clock 3, and with `+SDRAM_LATE` (the model a
clock late) the controller moves to clock 4 and the boot run's
read-after-write check stays at 0 wrong.  Rebuilt: 0 violations, the
gate green, `bin/tang.fs` replaced.  **Not yet flashed.**  What the
next flash tells, by the LEDs and the border colour:

- LED2 lit, LED3 dark, BASIC's banner: the capture clock was it.
- LED2 and LED3 dark and the same white/cyan blinking: the memory
  passes four bytes in isolation and fails under the ROM - look at
  refresh, at the video slot's reads interleaved with the CPU's, or
  at the byte lanes.
- LED3 lit: the interface is wrong beyond the capture clock - the
  command/address setup at the chip, the PLL phase, or the mode word.
- LED4 lit for ever: the CPU is held - the MCU link (does F12 open the
  OSD?) or `init`.

### The second flash, 22:50

Flashed (both binaries, the BL616 first).  The operator reported: the
OSD works (it did before too); the LEDs lit are the first, next to S1,
and the last - LED0 and LED5 in `top.v`'s numbering, whichever way the
row is read; the border blinks white and cyan.  Read against the code:
`leds[0] = ~por_done` and `leds[5] = ~init` on active-low LEDs are lit
when the reset has FINISHED and the memory IS initialised (the table
in `build.md` had those two the wrong way round; corrected), LED4 dark
is the CPU running, and LED2 and LED3 dark are the self-test passing
on slot clock 3.  That is the second case above: **four non-zero bytes
written and read back through the same controller pass, and the ROM's
traffic still fails** - the memory interface is not simply dead, and
the capture clock was not the bug.

What the ROM does at that point (`platform.md`): `LXI SP,F7FF / LXI
B,0 / PUSH B / CMA / OUT 88h` (white), then `CALL 005Ch` - whose
return address at F7FBh/F7FCh is the first non-zero data the RAM has
to give back.  Whether it does, and if not what came instead, is what
the simulation cannot say and the LEDs cannot show, so the next build
carries an instrument instead of a guess:

**`memcheck.v` and the OSD's Debug page.**  A 4 K x 9 BSRAM shadow of
F000h-FFFFh written beside every write into the SDRAM's CPU port and
compared with every read from there when the word comes back (phase 0
of the next T-state, whichever slot clock captured it); the first and
the last mismatch kept with address, expected, actual and the last
opcode address; counts of reads checked, writes shadowed, CPU resets,
opcode fetches at 0000h (with the fetch before the last one) and the
last OUT.  32 bytes through `sysctrl.v`'s new CMD 7, read by
`sys_get_debug` and shown by "Debug" on the main form (`build.md`,
"Reading the board", has the lines).  Against the model: 4100 reads
checked, 0 wrong, and the counters match the testbench's own.  Built:
Logic 33%, BSRAM 28/46, 0 violations, gate green.  `bin/tang.fs` and
`bin/bl616.bin` replaced, 23:02.  **Not yet flashed.**  What it will
say:

- "bad" > 0: the RAM lies to the CPU; the first line says which
  address, what the CPU wrote, what it got back, and where the CPU
  was.  A "got 00" is a read returning nothing; a "got" that is a
  neighbour's byte is the address or the lane; a "got" that is stale
  is refresh or a lost write.
- "bad" = 0 and "M1 at 0000" climbing with "cpu resets" still: the
  RAM is honest and the ROM restarts anyway - "last from" is the
  address it left, and the fault is in the CPU wrapper, the ROM's
  pROMs, or a port.
- "cpu resets" climbing: something outside the ROM (the MCU, `init`,
  the loader) is resetting the machine.

### The third flash, 23:11

Both binaries flashed (the BL616 first, then the FPGA, erase and write
to 100%).  The operator opened F12, Debug - and it showed the About
text (defect 17).  The firmware's 'T' entry dispatch compared the
label with `strcmp` against "Debug", but `menu_get_str` returns the
rest of the form string ("Debug,;B,Save settings,S;"), so the compare
never matched and every 'T' entry was About; the host test had checked
that a text page opened, not which.  The session's limit was reached
there.  Fixed the next morning: the compare is a prefix up to the
comma, `menu_text_line()` lets the host test read the page, and the
test now checks About begins "PK8000 Nano" and Debug begins "por ".
`make menu-test` 20 screens 0 errors; `make fw` built, `bin/bl616.bin`
replaced 5 Sep 10:19.  **The FPGA bitstream of 23:02 is unchanged and
does not need reflashing**; the BL616 does.  What the machine did on
this flash, by the LEDs and the border, was not reported and is
presumed the same as 22:50.

### The Debug page read, 5 September, 10:40

The BL616 reflashed with the fixed firmware, the FPGA of 23:02 left as
it was.  The operator read the page twice:

```
por 1 init 1 rst 0 bist 1 fail 0 late 0
F000-FFFF: 65535 rd 65535 wr 80 bad          (second sample: 255 bad)
1st F7F9 exp 51 got 00 pc 24C4
last F7FC exp 29 got 00 pc 24C5
cpu resets 3, M1 at 0000: 23                 (second sample: 91)
  last from 24C5
last OUT 88=FF pc 24BE m1 175                (second sample: m1 146)
```

Read against the ROM: 24B9h is its fill routine (`PUSH D`, a `MOV M,A`
loop, `POP D`, `RET`); F7F9h is where that `PUSH D` put E (51h) and
F7FCh the high byte of the return address the `CALL 005Ch` at 2967h
pushed (296Ah).  Both were written, both came back as 00h - the byte
the fill writes - after the fill had run over other addresses; the
`POP` got zeros, the `RET` went to 0000h, "M1 at 0000" climbs with
"cpu resets" still, and the ROM starts over.  So: a byte written to one
row is destroyed by writes to another row.  That is not the capture
clock (the self-test's four bytes are in one row with nothing between
the write and the read) and not the pads.

The cause, in `sdram.v`'s column word: `{2'b0, 1'b1, act_adr[8:1]}` -
UKNC Nano's `{5'b00100, col}` for a 13-bit address bus, repacked into
this design's 11 bits with the 1 on **A8, not A10**.  No access ever
auto-precharged; every ACTIVE after the first was to a bank with a row
still open, which the part does not define.  The chip evidently kept
the old row: the whole 64 KB was one 512-byte row, so zeros read back
as zeros, the four-byte self-test passed, and the stack's columns were
zeroed by the ROM's fills of other rows.  The simulation model simply
opened the new row on every ACTIVE, and BASIC booted on it for a day.

Done about it (5 Sep, morning):
- `sim/stubs/sdram_model.v` refuses an ACTIVE to a bank whose row is
  open - the old row stays - counts them and prints the count at the
  end ("must be 0"), and closes the row on a READ or WRITE with A10
  (it had ignored auto-precharge entirely, so the first run of the
  fixed design tripped the check on every access too).  The unfixed controller against it, 900 ms:
  607541 such ACTIVEs, and `memcheck` says **"first 51 at f7f9 got 00
  pc 24c4; last 29 at f7fc got 00 pc 24c5 ... 3 fetches at 0000 (last
  from 24c5)"** - the board's page, byte for byte.
- `sdram.v`: `{1'b1, 2'b00, act_adr[8:1]}`, A10 set.  The first
  attempt, `{2'b01, 1'b0, col}`, put the 1 on A9 - the same slip
  again - and the strict model caught it: the fixed design's first run
  reported the same 1.76 M refused ACTIVEs and the same stack failure,
  which is what the check is for.  Lint clean.  The boot run, 2600 ms
  against the strict model: **0 refused ACTIVEs**, read-after-write
  250127 checked 0 wrong, memcheck 65535 reads 0 wrong, 2 CPU resets
  and 2 fetches at 0000h (the normal two), the BASIC banner and "Ok"
  in the frame at 2.45 s.
- Rebuilt: Logic 33%, Register 18%, BSRAM 28/46, 0 violations, the gate
  green, `bin/tang.fs` replaced 5 Sep 11:01 (clk30 65.8 MHz).  **Not yet flashed.**
  Firmware unchanged from 10:21.

## What the simulation showed on 4 September 2026

### The machine (v0.1.0 runs, still true of v0.2.0)

`make frames RUN_MS=2700 PPM_FROM=2350 SIMARGS="+TYPE +TYPE_MS=2200"`:

- The ROM starts at 0000h, sets the ports (87h=81, 84h=00, 83h=82,
  80h=FC, 86h=DF, 87h=05, 88h=77), runs its RAM test over F000h-FFFFh
  (about 110 ms of machine time), copies two routines to F800h and
  F8F0h, and goes on into BASIC's initialisation.
- Interrupts are enabled at about 556 ms; from then the frame
  interrupt is serviced once a frame and the keyboard is scanned in it
  (rows 0..9 on port 82h, port 81h read).
- BASIC sets mode 0 (84h=20), the name table at 0000h (90h=00) and the
  patterns at 0800h (91h=02), white on black (88h=0F), and writes its
  banner into the name table: "PK8000 BASIC 1987 ВЕРСИЯ 1.2" and "46873
  Bytes free".
- Every byte written to RAM read back as written; vm80a's address never
  moved after the strobe; the HDMI stream decoded as 768x576 with 0 ECC
  errors and no bad guard band.  Those four lines end every run and were
  clean in every run of the day.
- The frames show the banner, "46873 Bytes free", "Ok", the cursor and
  the function-key bar "color auto goto list run" (MSX's unshifted set;
  with Shift held it reads "color 1 cload" cont list run" - the 0.1.0
  note had the two the other way round).  A line typed through the HID
  path is echoed by BASIC.

### The peripherals (v0.2.0 runs)

The card model `sim/stubs/sd_card_sim.v` serves host files as the image
slots; `build.md` has the three commands.  On this host the simulation
makes about 15 ms of machine time a second.

- **IDE**: `+EXP=2 +HDD=soft/cf.img`.  The IDE BIOS in page 1
  prints "IDE BIOS ПК8000 1.5 / Test ROM ... ok. / Reset...", identifies
  the drive, reads 15 sectors through the arbiter and boots the card's
  P/M 2.2 shell to its ">" prompt by 3.7 s, in green on black in a
  different screen bank.  That is the ВВ55-to-ATA path, the LBA read
  command, 8/16-bit data and the ROM decode all exercised by the
  software the community actually uses.
- **Floppy**: `+EXP=1 +FDDA=blank.fdd` (819200 zero bytes).  The НГМД
  ROM in page 1 seeks and reads the boot sector - two 512-byte blocks
  of drive A at 571 ms, through the ВГ93's SD path - finds no system on
  a blank disk and falls through to BASIC's prompt.  The read path is
  exercised; a real `.fdd` with a system on it is not in the repository,
  so booting one, writing, and drive B are not yet shown.
- **Tape**: `+TAPE=soft/hello.cas +TYPE_CLOAD`.  `cload"TEST` typed
  through the keyboard path turns the motor on at 3.58 s; the ROM
  reads the header tone and the name block off the FSK and prints
  "Found:TEST", reads the second header and the program (byte for byte
  what `tools/mkcas.py` wrote, by a RAM dump at 4001h), turns the motor
  off at 6.81 s, and "run" prints "TAPE OK".  Getting there took
  defects 13 and 14 below and the two ROM facts in `platform.md`: CLOAD
  wants a name, and the loader reads eight bytes past the program.
- **A system floppy**: `+EXP=1 +FDDA=DISK1.FDD` (the 2009 set of
  eighteen images, from the operator's collection) boots P/M with its
  file-manager shell to the A> prompt by 5 s.  `soft/ayplayer.fdd` is
  that disk with STCPL.COM and DEMOAY.COM added by `tools/mkfdd.py`;
  `demoay` typed at the prompt (`+TYPE_STR=demoay +TYPE_MS=5500`) plays
  the AY card - 84381 of 1.36 M I2S frames carried sound - so the
  floppy's file system as written by the script, the shell, and the AY
  card at 14h/15h are all exercised at once.
- **"Run .bas"**: `+BAS=hello.tok` pokes the tokenised program into
  4001h through sysctrl.v's CMD 6 and poke.v while BASIC sits at its
  prompt, sets the three pointers at F930h, types "run", and the
  screen says TAPE OK.  `soft/demo.bas` goes in the same way (636
  bytes, 15 lines) and runs its loop: SCREEN 0 white on blue, SCREEN 1
  yellow on black, SCREEN 2 with fifteen colour bands, the fan of lines,
  the red box with its cross, then fifteen nested boxes and a dot grid -
  eighteen frames at 0.8 s intervals, `build.md` has the command.  It
  found defect 15.  SCREEN 3 is a syntax error in this BASIC (the
  machine's mode 3 is border only), and `LINE ...,B` and `PAINT` are
  "? 2 Error" too, so the demo uses neither.
- **ROM disk**: not exercised by a run; no image in the repository.

### The keyboard and the tokens, measured

`+TYPE_STR=` with `+RAMDUMP` types a line and shows what the ROM made of
it.  Measured: numbers are not encoded (digits as text), operators are
tokens, letters outside strings are upper-cased; the digit row gives
digits under Shift and symbols without; the / key unshifted is `?`.
`platform.md` has the details, `tools/mkcas.py` and `mnano/bas.c`
implement them, `make bas-test` checks the two agree.

## Defects, in the order found

1. **Fixed** (0.1.0) - `hcnt`/`tphase` held until `init` while the
   SDRAM's initialisation ran in a phase of them: a deadlock that
   printed nothing.  The counters run from PLL lock.
2. **Fixed** (0.1.0) - the SDRAM word captured one slot clock late;
   every read was zero and the ROM's RAM test (which writes zeros) hid it
   from the read-after-write check for a whole run.  Captured at slot
   clock 3; `sdram.v`'s header has the arithmetic; `+DQTRACE` shows it.
3. **Fixed** (0.1.0) - the line buffer was 640 entries for a {line,
   slot} index that needs 1024; slots past 127 of every other line went
   nowhere.
4. **Fixed** (0.1.0) - the display's tile hand-over and the fetch's were
   on the same clock, so a tile showed its predecessor's pattern.  The
   fetch hands over a clock earlier.
5. **Fixed** (0.1.0) - the video's SDRAM request was registered on
   phase 1 and so was up on phase 2, a clock after the slot's first;
   `sdram.v` never took one and the picture was black over a correct name
   table.  Raised on phase 0.
6. **Closed** (4 Sep 2026, first board) - a sink takes 768x576 at 50.73
   Hz with a 144-clock back porch: the operator's monitor shows the
   frame with the machine's geometry.
7. **Not a defect** - the interrupt count looked like two a frame on
   the first long run; counted properly it is one a frame from the
   moment BASIC enables them.  `+IRQTRACE` prints both.
8. **Fixed** (0.2.0) - Gowin's synthesis rejected `wd1793.sv`'s
   `` `default_nettype none`` (EX3094 on every port of it and of every
   file read after it), and place-and-route rejected its inferred sector
   buffer for reading the old data on a write (PA2122).  The directive
   is gone and the buffer is write-through, which is what Altera's
   altsyncram did for the original.  Lint had passed both.
9. **Fixed** (0.2.0) - `sd_arbiter.v` dropped the request to the card
   one clock after the grant, because every client drops `rd` on `ack`
   and the arbiter followed it; the card model, sampling the request
   after the MCU's delay, read it as a write, and no peripheral ever got
   a sector.  The arbiter latches the direction and the sector at the
   grant and holds `rstart`/`wstart` until `rbusy`; the model checks the
   request is still up when it takes it.
10. **Fixed** (0.2.0) - `ide.v` kept its "image present" under the CPU
    reset, and the mount pulse arrives while the machine is in reset (in
    the model, and in the firmware's order: files, then R=3, R=0).  The
    IDE BIOS waited at "Reset..." for a drive that never became ready.
    `ide.v` and `tape.v` keep the bookkeeping outside reset, as
    `top.v`'s `mounted[]` did.
11. **Fixed** (0.2.0) - the testbench's `ms * 1000000` delays wrapped at
    4294 ms (frames asked for at 6.3 s came at 2.0 s), and
    `$test$plusargs("TYPE")` matched `+TYPE_CLOAD` and `+TYPE_MS=`, so a
    CLOAD run also typed "PRINT 1+1".  64-bit products and a guard.
12. **Not a defect** - `cload` and `CLOAD` typed without a string get
    "? 2 Error" from this ROM; `cload"NAME` loads.  `platform.md`.
13. **Fixed** (0.2.0) - `ports.v` wrote the keyboard byte's release bit
    inverted into the matrix: a key went down at its release and stayed
    down, the ROM typed it once at that edge, and Shift stayed down for
    ever after its first use.  Found through the tape test - `cload"`
    then `test` came out as `cload"TEST`, and with Shift held around
    each letter as `test` - and it is what 0.1.0's "1+INPRT" and the
    three differing typing runs were.  After the fix `+TYPE`'s
    "print 1+1" answers "2" and "ab", Shift tap, "ab", Shift tap, "ab"
    is "ababab" with the matrix row clean after each tap.
15. **Fixed** (0.2.0) - port 84h's mode decode had the low bit inverted
    for the graphics half: the ROM's SCREEN 2 writes 10h and `ports.v`
    made that "border only", so mode 2 had never been displayable and
    `soft/demo.bas` showed black where its graphics were.  Emu80's
    `setPortA` is the source: bit 4 set, bit 5 clear is graphics.  The
    P/M shell and BASIC's prompt (00h, 20h) were right all along.
14. **Fixed** (0.2.0) - `tools/mkcas.py` wrote MSX-BASIC's tokens and a
    tape that ended with the program.  This ROM's tokens are its own
    (PRINT 95h, END ECh; the table at 3170h, which the script now reads
    from the ROM) - the program loaded and "run" said "? 13 Error in
    10" - and its loader reads eight bytes past the final 00 00: with
    MSX's seven zeros it still asked for an eighth and, the tape having
    stopped, said "Device I/O error" with the program already in memory.
    Sixteen zeros now.

16. **Fixed in the tree, not yet on a board** (found 4 Sep 2026, first
    board; cause found 5 Sep) - the machine does not boot on the board:
    the ROM's zero-fill RAM test passes and the code after it, through
    the stack, restarts the ROM (white border blinking cyan).  The
    self-test of 22:50 passed, so not the capture clock; the Debug page
    of 5 Sep said bytes pushed on the stack came back as the zeros a
    later fill wrote elsewhere.  Cause: `sdram.v`'s column word had its
    1 on A8, not A10 - no auto-precharge, every ACTIVE to a bank with a
    row open, the 64 KB one row on the chip - and the model let it
    pass.  A10 set; the model refuses the illegal ACTIVE and counts it;
    the unfixed design against the strict model reproduces the board's
    page exactly.  Rebuilt 5 Sep 11:01, waiting for the fourth flash.
    See "The Debug page read" above.
17. **Fixed** (5 Sep 2026) - the OSD's Debug entry opened the About
    text: menu.c compared the 'T' entry's label with `strcmp`, and
    `menu_get_str` returns the rest of the form string, not the label
    alone.  A prefix compare now; `menu_test.c` reads the page through
    `menu_text_line()` and checks which one it is.  Firmware only; the
    bitstream of 23:02 stands.

## What is not built, in the order worth building

1. **Recording to tape** (CSAVE into a `.cas`): the output bit on port
   82h bit 6 goes into the sound mix and nowhere else.
2. **A floppy image with a system on it**, to show the НГМД booting and
   writing; then drive B.  The controller's write path
   (`wd1793.sv`'s, through the arbiter's `wr`) has run in no simulation.
3. **A ROM disk image**, to show `romdisk.v`'s load and page select.
4. **The "smart" digit row** in the firmware (Emu80's): a PC digit
   needs Shift on the machine and a PC symbol needs none; measured now
   for the digit row and the / key (`platform.md`), so the firmware's
   keymap can send the Shift itself.  Until then a USB keyboard types
   symbols for digits.
5. **STC tunes on `soft/ayplayer.fdd`**: the player is there, the music
   is not.
6. **The wait model against the machine**: the two PLM dumps on
   micklab.ru (RAR5; needs `unrar`), read into equations.
7. **A self-test that spans rows** in `sdram.v`: the four bytes in one
   row proved the pads and passed over defect 16.  Write a byte in one
   row, access another row, read the first back - and a refresh-length
   wait, to see retention - before the CPU is released.

## Open questions

- **The digit row under Shift**: with the matrix right, the testbench's
  "print 1+1" (Shift held for `1`, `;`, `1`) typed "1+1" and Shift+2
  typed `"` - so Shift+1 is 1 and Shift+; is +, on this ROM with this
  matrix.  The firmware's "smart" digit row (item 5 above) can be
  settled with a run per key now.
- **A green block in SCREEN 1.**  After BASIC's SCREEN 1 with COLOR
  10,1,1 the demo's frames show an 8-character-high green rectangle at
  the right of the top rows of the picture, which the program did not
  draw.  The colour RAM's window, the ROM's SCREEN 1 initialisation, or
  a defect in `video.v`'s mode 1 - not looked into.
- Does the real ROM 1.2 need anything on port 8Dh bit 7 or the joystick
  ports at boot?  In simulation it does not.
- `cpu8080.v` classes an INTA cycle's opcode as 0FFh in the wait table
  (RST 7's row) and adds the interrupt's 7/5; Emu80 adds only the 7/5.
  One or two clocks a frame either way.
- The OSD's "CPU waits: Off" is the only knob on speed; a "turbo" that
  also shortens the SDRAM slots is not needed, since the SDRAM never
  waits the CPU anyway.
