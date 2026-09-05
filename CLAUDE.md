# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in
this repository.

## Project overview

This is the **ПК8000 "Сура"** - a Soviet home computer of 1987, a
КР580ВМ80А (8080A) at 2.5 MHz with a discrete-logic video controller
that imitates the TMS9918's screen modes - reimplemented on a **Tang
Nano 20K** (Gowin GW2AR-18C), with a **Bouffalo BL616** board alongside
it providing USB HID, the SD card and the on-screen menu.  It is a
sibling of **UKNC Nano** (`../tang-uknc`, Alexey Gurov's hardware,
Sergei Lemeshev's and Claude Code's 2.x line): the MiSTeryNano side,
the HDMI encoder, the toolchain, the Makefile and the method are taken
from there as they are, and the machine itself is new.  Started 4 Sep
2026.

Two halves, two toolchains, and **both build here**:

```
tang/     the FPGA design      - make bitstream  (gw_sh, headless Gowin, ~30 s)
mnano/    the BL616 firmware   - make fw
bin/      the two shipped binaries, both rebuilt from these sources
sim/      testbench, SDRAM model and the stand-ins for the vendor primitives
tools/    the fetched toolchain - make toolchain, ~7 GB, not committed (scripts are)
tang/rom/ the ROM images and the schematics the design was read from
```

`make lint` and `make sim` are the cheap checks; `make bitstream` is the
real one.  `make help` lists the rest.  **What cannot be done here is
running it on a board.  Three bitstreams (the evening of 4 Sep 2026)
did not boot - the ROM's RAM test passed and nothing after it did, the
SDRAM's four-byte self-test passed too - and the fourth (5 Sep, 11:01)
does: the OSD's Debug page (`memcheck.v`) named the fault, a column
word with no A10, and the operator reports the machine working.  See
`.claude/docs/progress.md`, "The first board" through "The fourth
flash".  Anything built since is untested on the board until it says
otherwise there.**  So "it builds", "it
lints", "it boots in simulation" and "it meets timing" are four
different claims, none of them is "it works", and you should say which
one you are making.

The machine, as implemented: vm80a (1801BM1's gate-level КР580ВМ80А)
on a 30 MHz clock with the two phases as enables, a T-state of twelve
clocks; 64 KB in the SDRAM with a fixed slot for the CPU and one for
the video in every T-state; the 16 KB BASIC 1.2 ROM in BSRAM; the two
ВВ55s, the video registers, the colour RAM, the keyboard matrix and the
joysticks in `ports.v`; the display rendered line by line into a
buffer and read out as 768x576 at the machine's own 50.73 Hz over
HDMI, with the beeper and the AY card as the sound; the video
controller's cost to the CPU paid as wait states from Emu80's measured
tables.  Around it the peripherals of 0.2.0: a `.cas` tape player, the
НГМД (MiSTer's wd1793) with its ROM, the IDE/CF adapter with its ROM,
the ROM disk cartridge in the SDRAM, the AY card - all of them fed from
the SD card's image slots through `sd_arbiter.v`, and the three
expansion-page devices each on an OSD switch (f, i, r), the first on
owning page 1.

```
Logic 33%   Register 18%   BSRAM 28/46 (61%)   PLL 2/2 (100%)  [5 Sep 2026 PnR, v0.2.0 + memcheck.v + A10; clk30 makes 65.8 MHz, 0 violations]
```

Key documentation: `.claude/docs/platform.md` (the machine: memory
map, ports, the display, the keyboard, what the waits are and where the
facts come from), `.claude/docs/fpga.md` (the implementation: the
clock, the timetable, the CPU bus, the files), `.claude/docs/video.md`
(the display generator), `.claude/docs/mcu.md` (the firmware, the
keymap, the menu letters), `.claude/docs/build.md` (both toolchains,
the Makefile, what lint and simulation do and do not cover, flashing),
`.claude/docs/tools.md` (`tools/` and the ROM data),
`.claude/docs/progress.md` (state, defects, what is next).  Follow
`.claude/rules/guideline.md`, `.claude/rules/git.md` and
`.claude/rules/timing.md`.

## Traps worth remembering

- **`tang/pk8000.gprj` is the source of truth for what gets built.**
  Every file under `tang/src/` is in it and every module in it is
  instantiated; keep it that way.  `tools/srcs.py` reads it for lint
  and sim, `tools/gowin_tcl.py` for the bitstream.
- **There is one clock, and everything is a phase of it.**  `clk` is
  30 MHz; `tphase` (0..11) is the CPU's T-state, `hcnt`/`vcnt` the
  machine's raster, and they run from PLL lock.  The SDRAM controller
  gives the CPU phases 7..12 and the video phases 1..6 of every
  T-state and nobody ever waits for memory.  Do not add a clock, a
  divided clock, or a flop clocked by a data signal - a slower thing is
  an enable - and do not touch memory outside a slot.  This is why
  `pk8000.sdc` is three lines and why the first layout had 0
  violations; `.claude/rules/timing.md` keeps it so.
- **`hcnt`/`tphase` used to be held until `init`, and the SDRAM's
  initialisation steps run in the video slot, which is a phase of
  `tphase`: the two waited for each other for ever and the first
  simulation printed nothing.**  The counters run from `locked` now.
  Anything new that gates on `init` must not be something `init` needs.
- **The SDRAM word is on the bus one slot clock EARLIER than the CAS
  latency suggests, because the chip is clocked 90 degrees behind.**
  The first `sdram.v` captured a clock late and every read came back
  zero - which the read-after-write check did not catch for a whole
  run, because the ROM's RAM test writes zeros and the 84 non-zero
  bytes were the only ones that failed.  The capture is at slot clock
  3 (`sdram.v`'s header has the arithmetic); `+DQTRACE` in the
  testbench shows the bus clock by clock; and a read-after-write count
  with "0 wrong" is only evidence if the data was not zero.  On the
  board the self-test passes at clock 3 and the ROM still restarts
  (second flash), so "the memory answers the controller" and "the
  memory answers the CPU" are also two claims.
- **The SDRAM model runs a controller that never precharges, and the
  board does not.**  `sdram.v`'s column word was `{2'b0, 1'b1, col}` -
  UKNC Nano's `{5'b00100, col}` repacked from 13 bits to 11, the 1
  landing on A8 instead of A10 - so no access auto-precharged and every
  ACTIVE hit a bank with a row still open.  The model opened the new
  row anyway and BASIC booted for a whole day; the chip aliased all
  64 KB into one row: zeros read back, the four-byte self-test passed
  (one row, nothing between write and read), and the stack came back
  as the zeros a later fill wrote (the third flash's Debug page, 5 Sep
  2026).  The model now honours auto-precharge, refuses an ACTIVE on an
  open bank and prints the count at the end ("must be 0"); a change to
  the command sequence reads that line - the first fix, `{2'b01, 1'b0,
  col}`, put the 1 on A9 and that line said so.  Write a single bit of
  an address word at its own position (`{1'b1, 2'b00, col}`), never
  inside a wider literal.  And a self-test that passes proves what it
  exercised: the pads and the capture clock, not the row handling.
- **The board's only readouts are six active-low LEDs, the border
  colour and the OSD's Debug page.**  `leds[n] = ~signal`, so a lit
  LED is the signal TRUE: LED0 lit is the power-on reset finished and
  LED5 lit is the SDRAM initialised (the first table said the
  opposite).  The Debug page (`memcheck.v`, `sysctrl.v` CMD 7,
  `menu_debug_open`) is a shadow of F000h-FFFFh checked against every
  read plus the CPU's counters; `build.md`, "Reading the board", says
  how to read it.  Adding a byte to it is `memcheck.v`'s `dbg` map,
  the testbench's `sys_debug` print, and the page's `snprintf`.  **The
  third flash opened About for it**: `menu_get_str` returns the rest
  of the form string, not one field, so a label is compared as a
  prefix up to its comma; `menu_test.c` reads the open page through
  `menu_text_line()` and checks which page it is.
- **The ROM's first act is a RAM test of F000h-FFFFh that retries for
  ever if a byte does not read back** (2942h: `XRA A / MOV M,A / CMP M
  / JZ / INX B ... JNZ 293C`).  A machine "stuck at boot with a cyan
  border" (port 88h = 77h is set just before) is the memory, not the
  video.  **The moment the test passes the ROM writes 88h = 0FFh - a
  white border** (295Ch, `CMA` of the loop's zero) - then copies two
  routines to F800h/F8F0h and calls into them; a RET to 0000h from
  0066h is the stack (F7FDh down) reading wrong, and the ROM starts
  over.  So a white border blinking cyan is "zeros read back, other
  bytes do not": defect 2's picture, and what the first board showed
  on 4 Sep 2026.  The test only ever writes zeros; it proves nothing
  about the data path.  `sdram.v` now tests four non-zero bytes itself
  at init and reports on LEDs 2 and 3 (`.claude/docs/build.md`).
- **`vm80a`'s SYNC and status byte appear on the F2 edge and the
  address is valid then** - the testbench checks it stays put through
  the T-state ("address stability at the strobe: 0 moved").  `cpu8080.v`
  therefore latches the cycle at phase 7 and `top.v` uses the core's
  live address (`a_now`) for the request and the latched one (`adr`)
  for the ROM and for writes.  Do not use `adr` at the strobe's own
  clock; it is a clock old.
- **The wait tables are Emu80's measurements, and they are per
  instruction, not per access.**  `cpu8080.v` pays an instruction's
  clocks in the NEXT instruction's M1.  The totals are right; where
  within an instruction the real machine stalls is unknown.  The OSD's
  "CPU waits: Off" removes them, and a program that runs with them off
  but not on is a program that is timing-sensitive, not a wait-model
  bug - until measured otherwise.
- **The wait model needs `stall_wide` from the video and `fetch_rom`
  from the memory map at the M1 strobe**, both live.  A mode-0 program
  gets different waits inside the picture; a program under a ROM page
  gets the ROM tables.
- **A request into the SDRAM's timetable must be UP on the slot's
  first clock, so a registered request is raised the clock before.**
  `video.v` raised `vid_req` on phase 1 - the slot's first clock - and
  so it was up on phase 2; `sdram.v` never took one, the picture was
  black over a correct name table, and the run's "3.7 M tile fetches"
  counted requests nobody answered.  It is raised on phase 0 now.  The
  CPU's requests are combinational at phase 7 and never had this.
  Count acks, not requests.
- **The ROM scans the keyboard once a frame, in its interrupt, and
  debounces across scans.**  A key down for less than 19.7 ms is not
  seen.  With the matrix polarity right (above) the testbench's 60 ms
  holds type cleanly: `+TYPE` gets "print 1+1" answered "2", and
  `+TYPE_CLOAD` loads and runs a program off the tape.
- **`hid.v`'s keyboard byte has a strobe now.**  UKNC Nano's took a
  change of the byte and lost the second of two equal events; here
  `ports.v` acts on `kbd_stb`.  The code is `row*8+col+1` with bit 7
  for release, 0 for no key - the firmware's `pk8000.h` and `ports.v`
  agree and must keep agreeing.  **Bit 7 is the matrix level itself**
  (pressed reads low): `ports.v` wrote its inverse for the whole of
  0.1.0, so every key went down at its release and stayed down, the ROM
  typed it once at that edge, and Shift was held for ever after its
  first use.  "1+INPRT", the three differing typing runs, `cload"TEST`
  coming out in capitals - all that one bit.  A typing test that gives
  odd case or order is the matrix before it is the ROM.
- **Port 88h's border colour, the text foreground and DSCR are read at
  every pixel; the bases and the bank at every tile fetch.**  That is
  Emu80's model and it makes mid-line register writes visible.  The
  line buffer is `lbuf[{wline, slot}]` - 512 entries a line, 1024 in
  all; it was 640 once and slots past 127 of every other line went
  nowhere, which looked like a striped border.
- **`hdmi_tx.v` sends THREE packets an island here, not four.**  The
  back porch is 144 clocks at 30 MHz and four do not fit; the audio
  still has two slots a line.  `ACR_CTS` is 30000 for exactly 48 kHz.
  Changing the raster's blanking means checking `DI_PKTS` against it.
- **The frame is 768x576 in 960x616 at 50.73 Hz, not a CEA mode.**
  UKNC Nano's television took 51 Hz; whether a given sink takes this
  is a board question, and a black screen on a board is that before it
  is anything else.  The OSD centres itself on the syncs and needs no
  change.
- **The firmware's core id is 7** (`CORE_ID_PK8000`), and every table
  the firmware selects by core is indexed by it - `settings_file[]`,
  `keymap[]`, `modifier[]`, `core_names[]`.  The UKNC's entries at 5
  are `NULL`.  A menu value is three edits: the letter in the form
  string, `variables_pk8000[]`, and `sysctrl.v`.
- **`tools/` on this host is hard links into `../tang-uknc/tools/`.**
  Same files, same inodes; an in-place edit to one is an edit to both.
  Nothing in `tools/` is edited in place - a new toolchain version is a
  fresh fetch.
- **Flashing the FPGA is replug, flash, power-cycle - in that order**,
  and the BL616 must be in boot mode (hold BOOT, tap RESET, release
  BOOT).  `.claude/docs/build.md`; UKNC Nano learned both the hard way.
- **Gowin's synthesis will not read a file that says `` `default_nettype
  none``** - every port of it and of every file after it fails EX3094 -
  and its place-and-route refuses an inferred dual-port RAM that reads
  the old data on a write (PA2122, "WRITE_MODE0 = 2'b10").  Verilator
  minds neither, so `make lint` clean is not `make bitstream` clean;
  `wd1793.sv` lost the directive and its buffer became write-through
  (Altera's same-port behaviour anyway).  An inferred RAM here is
  read-only-or-write on a port, never both in one clock.
- **The SD request must stay up until the card is busy on it.**  The
  MCU polls `rstart`/`wstart` as levels and takes the direction from them
  when it starts the transfer, milliseconds later; every client drops its
  `rd` the clock after `ack`, and the first `sd_arbiter.v` followed the
  client and dropped the request after one clock - the card model read
  it as a write and every peripheral hung.  The arbiter latches the
  direction and the sector at the grant; the model checks the request is
  still up when it takes it and says so if not.
- **The firmware mounts the images while it holds the machine in reset**
  (`menu.c`: the files, then R=3, R=0), so a peripheral that keeps its
  "image present" under the CPU reset loses the mount: the IDE BIOS sat
  at "Reset..." waiting for a drive.  `mounted`/`image_size` bookkeeping
  is never under `cpu_rst`; `top.v`'s `mounted[]`, `ide.v` and `tape.v`
  keep it in a block of their own.
- **This BASIC's tokens are not MSX's, and its numbers are not
  encoded.**  PRINT is 95h (MSX: 91h), END is ECh, CLS is 80h; the
  table is at 3170h in the ROM and `tools/mkcas.py` reads it from there
  (`make tokens` writes `mnano/pk8000_tokens.h` for the firmware).  A
  number stays as its digits - no 0Fh/1Ch/11h prefixes - so a line in
  memory is the text with keywords and operators as bytes and the
  letters in capitals, nothing more.  A program written with MSX
  tokens loads and then fails with "? 13 Error in 10".  The loader
  reads eight bytes past the program's final 00 00, so a `.cas` needs
  a zero trailer longer than MSX's seven, or it is "Device I/O error"
  with the program already in memory.  `make bas-test` keeps `bas.c`
  and `mkcas.py` agreeing.
- **A register decode is not verified until software has used it.**
  Port 84h's mode bits were read from Emu80 into a table in
  `platform.md` and decoded in `ports.v` with the graphics half
  inverted; the ROM's prompt and P/M's shell use the two text modes
  and never touched it, and SCREEN 2 was black until `soft/demo.bas`
  ran.  The cheap instrument is `+BAS=` with a two-line program and
  `+IOTRACE`: what the ROM writes to a port is the fact.
- **The "Run .bas" path is a poke, not typing.**  `sysctrl.v` CMD 6 and
  `poke.v` write bytes into the SDRAM in T-states the CPU leaves free;
  `bas.c` resets, waits 3 s for the prompt, sends the lines to 4001h
  and the three pointers to F930h, then types "run".  If BASIC is not
  at its prompt when the bytes land (a program running, the machine
  mid-boot), what happens is the ROM's business, not ours.
- **The testbench's millisecond delays are `ms * 64'd1000000`**: a
  32-bit product wraps past 4294 ms, and `+PPM_FROM=6300` wrote its
  frames at 2.0 s.  And `$test$plusargs("TYPE")` matches `+TYPE_CLOAD`
  and `+TYPE_MS=` too - a prefix, not a name - so the `+TYPE` block is
  guarded.
- **`prompts/` is a transcript, not context.**  Never read it at the
  start of a session; append every exchange as it finishes, in the form
  `.claude/rules/guideline.md` gives.
