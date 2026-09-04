# State of the port

Last updated: 4 September 2026, v0.2.0 alpha, still the first day.

## What there is

Built, linted, simulated, timed - not run on a board.  **No bitstream
of this design has been on a board yet.**  On UKNC Nano's framework:

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
Logic 29%   Register 17%   BSRAM 25/46 (55%)   PLL 2/2   clk30 62.8 MHz   0 violations   [4 Sep 2026, v0.2.0]
Logic 17%   Register 10%   BSRAM 11/46 (24%)   PLL 2/2   clk30 66.6 MHz   0 violations   [4 Sep 2026, v0.1.0]
```

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
6. **Open** - whether a sink takes 768x576 at 50.73 Hz with a 144-clock
   back porch.  UKNC Nano's television took its 51 Hz; a board will say.
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
