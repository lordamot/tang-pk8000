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
running it on a board, and as of 4 Sep 2026 no bitstream of this design
has been on one.**  So "it builds", "it lints", "it boots in
simulation" and "it meets timing" are four different claims, none of
them is "it works", and you should say which one you are making.

The machine, as implemented: vm80a (1801BM1's gate-level КР580ВМ80А)
on a 30 MHz clock with the two phases as enables, a T-state of twelve
clocks; 64 KB in the SDRAM with a fixed slot for the CPU and one for
the video in every T-state; the 16 KB BASIC 1.2 ROM in BSRAM; the two
ВВ55s, the video registers, the colour RAM, the keyboard matrix and the
joysticks in `ports.v`; the display rendered line by line into a
buffer and read out as 768x576 at the machine's own 50.73 Hz over
HDMI, with the beeper as the sound; the video controller's cost to the
CPU paid as wait states from Emu80's measured tables.  No tape, no
floppy yet.

```
Logic 17%   Register 10%   BSRAM 24%   PLL 2/2 (100%)  [4 Sep 2026 PnR, v0.1.0; clk30 makes 66.6 MHz, 0 violations]
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
  with "0 wrong" is only evidence if the data was not zero.
- **The ROM's first act is a RAM test of F000h-FFFFh that retries for
  ever if a byte does not read back** (2942h: `XRA A / MOV M,A / CMP M
  / JZ / INX B ... JNZ 293C`).  A machine "stuck at boot with a cyan
  border" (port 88h = 77h is set just before) is the memory, not the
  video.  Then it copies two routines to F800h/F8F0h and calls into
  them; a RET to 0000h from 0066h is the stack (F7FDh down) reading
  wrong.
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
  seen; keys typed faster come out in row order ("PRINT 1+1" as
  "1+INPRT"); and at 30 and 60 ms holds the Shift state the ROM paired
  with a digit still differed between runs.  The testbench's `+TYPE` is
  therefore not yet evidence about the digit row's layout, only about
  the path; a USB keyboard's human is slower than any of this.
- **`hid.v`'s keyboard byte has a strobe now.**  UKNC Nano's took a
  change of the byte and lost the second of two equal events; here
  `ports.v` acts on `kbd_stb`.  The code is `row*8+col+1` with bit 7
  for release, 0 for no key - the firmware's `pk8000.h` and `ports.v`
  agree and must keep agreeing.
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
- **`prompts/` is a transcript, not context.**  Never read it at the
  start of a session; append every exchange as it finishes, in the form
  `.claude/rules/guideline.md` gives.
