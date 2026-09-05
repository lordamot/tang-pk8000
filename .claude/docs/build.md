# Building and flashing

Two binaries, two toolchains.  What ships prebuilt is:

```
bin/tang.fs      the FPGA bitstream   (make bitstream)
bin/bl616.bin    the MCU firmware     (make fw, copied by hand)
```

A user who only wants to run the machine flashes those two and needs no
toolchain at all.  That is the point of committing them.

**Both halves build on this host.**  Everything they need lives under
`tools/`, fetched by `make toolchain` - about 7 GB including Gowin -
nothing is installed on the host and `tools/` is in `.gitignore`.  On
this machine `tools/` was made as hard links into `../tang-uknc/tools/`
(4 Sep 2026), which is the same content at no cost in disk; a clone
elsewhere runs `make toolchain`.

```
make toolchain   fetch the toolchain into tools/  (~7 GB, once)
make lint        Verilator over the whole design - the fast check, seconds
make sim         run the machine to the BASIC prompt (RUN_MS=1200; ~4 ms a second)
make frames      the same, writing video frames as .ppm (PPM_FROM=1000)
make wave        the same, dumping a VCD, then open it (WAVE_MS=2)
make bitstream   build the FPGA bitstream -> bin/tang.fs (about 30 s)
make timing      the timing gate alone, on the last PnR report
make fw          build the BL616 firmware -> build/fw/bl616.bin
make menu-test   the OSD menu on the host: every form walked, screens as PNG
make bas-test    the firmware's BASIC tokeniser on the host against tools/mkcas.py
make tokens      regenerate mnano/pk8000_tokens.h from the ROM
make rom         regenerate tang/src/pk8000/pk8000_rom.v from tang/rom/pk8000_v12.rom
make waits       regenerate tang/src/pk8000/waits_rom.v from tools/waits_rom.py
make mif         the ROM as $readmemh hex for the sim model (build/mif/)
make flash-fpga  openFPGALoader the shipped bitstream to SRAM
make flash-mcu   flash the firmware over UART (COMX=/dev/ttyACM0)
```

`SIMARGS="+CPUTRACE +TRACE_MS=100"` and the like pass plusargs to the
simulator; `sim/tb/tb_top.v`'s header lists them.

## The FPGA half

Toolchain: **Gowin EDA Education edition**, V1.9.11.03, in
`tools/gowin/`.  `make bitstream` drives its headless shell with a Tcl
generated from `tang/pk8000.gprj` and the IDE's own
`tang/impl/pk8000_process_config.json` (`tools/gowin_tcl.py`), so the
command line and an IDE build read the same list and options.  The
build takes about 30 seconds; the result is
`tang/impl/pnr/pk8000.fs`, copied to `bin/tang.fs` when the timing
gate passes.  `gw_sh`'s three quirks - its bundled libraries fight a
current Linux, its option names differ from the IDE's, and
`-use_sspi_as_gpio 1` is not optional - are handled by `tools/fetch.sh`
and the Makefile; UKNC Nano's `.claude/docs/build.md` has the account.

The timing gate (`tools/timing_check.py`, `.claude/rules/timing.md`)
wants `clk27`, `clk30` and `spi_clk` in the report, no violations, no
undeclared or unrelated clock.  First run of this design, 4 Sep 2026:
0 setup, 0 hold, clk30 at 66.6 MHz.

## What lint and simulation cover

`make lint` runs Verilator over exactly the `.gprj`'s list with the
four stubs standing in.  It is clean but for warnings, most of them
the MiSTeryNano sources' and vm80a's (timescale, unused bits); any
error is yours.

`make sim` builds the whole machine into a Verilator binary against a
functional SDRAM model and a stand-in BL616 that speaks the real SPI
protocol, and runs the BASIC ROM.  What it showed on 4 Sep 2026 is in
`.claude/docs/progress.md`.  The testbench's end-of-run lines are the
checks:

```
[tb] config checks: 0 wrong                     the OSD values landed in sysctrl
[tb] cpu: N opcode fetches, ... wait states     the core runs; waits are being paid
[tb] read-after-write: N checked, 0 wrong       every RAM byte read back as written
[tb] address stability at the strobe: 0 moved   vm80a's address is valid when taken
[tb] hdmi: ... 0 ecc errors                     the data islands are well formed
[tb] hdmi frame: 768 x 576                      the raster is what video.md says
```

The SDRAM model is FUNCTIONAL: it tracks rows and serves words, checks
no timing, and drives read data the way the chip does with the
90-degree clock - which is what caught the one-clock-late capture
(sdram.v's header).  Nothing here says anything about the real card,
the real SDRAM pads, the HDMI PHY or a monitor's opinion of a 50.73 Hz
frame.

`make frames` decodes the TMDS words back into `.ppm` frames.  The
BASIC prompt is about two seconds of machine time in; `PPM_FROM=2350`
with `+TYPE` (a line of BASIC typed through the keyboard path at 2.2 s)
is what the screenshots in `progress.md` were made with.

The peripherals are simulated against `sim/stubs/sd_card_sim.v`, which
serves host files as the image slots - `+TAPE=`, `+FDDA=`, `+FDDB=`,
`+HDD=`, `+ROMDISK=` - on `sd_card.v`'s core-side interface, with
`+SDFAST` for a card that answers in microseconds and `+SDTRACE` for
every sector.  `+EXP=<n>` turns one expansion switch on (1 floppy, 2 IDE, 3 ROM disk); `+EXP_FDD`, `+EXP_IDE`, `+EXP_ROM` turn each on as well, for combinations.  The three
runs of 4 Sep 2026 that `progress.md` reports:

```
make frames RUN_MS=6400 PPM_FROM=8200 SIMARGS="+TAPE=soft/hello.cas +TYPE_CLOAD +SDFAST"
make frames RUN_MS=4000 PPM_FROM=3700 SIMARGS="+EXP=2 +HDD=soft/cf.img +SDFAST"
make frames RUN_MS=4000 PPM_FROM=3700 SIMARGS="+EXP=1 +FDDA=blank.fdd +SDFAST"
make frames RUN_MS=8000 PPM_FROM=7900 SIMARGS="+EXP=1 +FDDA=soft/ayplayer.fdd +SDFAST +TYPE_STR=demoay +TYPE_MS=5500"
python3 tools/mkcas.py --tok build/demo.tok soft/demo.bas
make frames RUN_MS=14000 PPM_FROM=2400 PPM_EVERY=40 PPM_MAX=16 SIMARGS="+BAS=build/demo.tok"
```

`+TYPE_STR=` types any text at the prompt (`_` for a space; `+RAMDUMP`
then shows what the ROM made of it), `+BAS=` puts a tokenised program
into the RAM through the MCU's poke path and runs it, `+PPM_EVERY=`
thins the frames so one run can sample a demo over time.

(`blank.fdd` is 819200 zero bytes; the repository has no floppy image.
The typing takes real time - 120 ms a key - so "run" lands about
1.1 s after `RUN_MS` and the frame after that; `+RAMDUMP` writes the
RAM to `sim/out/ram.hex`, word n = bytes 2n and 2n+1, the program at
4001h.)
On this host the simulation runs at about 15 ms of machine time a
second, so those are four to nine minutes each, and they are
independent: run them in parallel from separate directories that hold
`build/`, `soft/` and `tang/` as symlinks and an empty `sim/out/`, since
the testbench writes its frames to `sim/out/` relative to where it runs.

## The MCU half

The Bouffalo SDK (`master_legacy`) plus a T-Head RISC-V GCC, both in
`tools/`; `make fw` builds `mnano/` into `build/fw/bl616.bin` and it is
copied on to `bin/` by hand.  The three things UKNC Nano settled to make
that work (the SDK branch, the host-tool patch, the two `-D`s through
`BOARD`) are still in `tools/fetch.sh` and the Makefile and still
needed.  The version in the OSD's caption is the first line of
`VERSION`, read by `mnano/CMakeLists.txt` into `CORE_VERSION`.

## Flashing

**Tang Nano 20K**: `make flash-fpga` (SRAM, gone at power-off) or
`make flash-fpga-flash` (the SPI flash), then **power-cycle the board**
- `openFPGALoader -f -r` writes the flash and reports success but does
not reliably reconfigure the chip.  Once anything has opened
`/dev/ttyUSB*` the next flash fails with `ftdi_usb_reset failed` and
only replugging the cable clears it.  Replug, flash, power-cycle, in
that order.

**BL616**: hold BOOT, tap RESET, release BOOT; the chip enumerates as a
serial port (`/dev/ttyACM0`); `make flash-mcu COMX=/dev/ttyACM0` (needs
`dialout`; `sg dialout -c '...'` works without a relogin).  `BFLB IMG
LOAD HANDSHAKE FAIL` means the port opened and nothing answered: not in
boot mode, or the wrong port.  Press RST afterwards.

## Reading the board

The six LEDs, lit when the thing is true (`top.v`'s last lines; the
board's LEDs are active low and the assignments invert, so a lit LED
is the signal at 1):

```
LED0  the power-on reset has finished (lit 280 ms after the memory is up)
LED1  the beeper is on
LED2  the tape is running - or, at boot, the SDRAM self-test chose the
      late capture (sdram.v: the word was on the bus on slot clock 4, not 3)
LED3  a disk or SD transfer is busy - or, at boot, the SDRAM self-test
      FAILED both captures
LED4  the CPU is held in reset
LED5  the SDRAM is initialised
```

So a healthy start is LED5 then LED0 coming on, LED4 going out, and 2
and 3 dark - which is what the second flash showed (4 Sep 2026, 22:50:
"LED1 and LED6 counted from 1").  What the screen says while the ROM
boots, from its own code (`platform.md`, the boot sequence): a
**cyan** border while the RAM test of F000h-FFFFh runs (about 110 ms),
**white** the moment it passes, black with the BASIC banner once BASIC
has initialised.  A cyan border that stays is the zero test failing; a
white border that stays, or blinks with cyan, is the test passing and
the code after it - which puts non-zero bytes through the stack -
failing back to 0000h: the memory reads zeros right and other values
wrong.  Both boards showed that, and the Debug page of 5 Sep 2026 said
why (`progress.md`, "The Debug page read": the controller never
precharged).  The OSD on F12 says whether the MCU link works, and
needs no memory.

**The Debug page** (main form, below About) is the instrument for
everything after that: `memcheck.v` keeps a shadow of F000h-FFFFh in
BSRAM, compares every read from there with it as the word comes back,
and counts; the MCU reads 32 bytes through `sysctrl.v`'s CMD 7 and
formats them (`menu_debug_open`, menu.c).  Open it while the machine is
doing whatever it does; open it again for a second sample.  The lines:

```
por 1 init 1 rst 0 bist 1 fail 0 late 0     the flags, as the LEDs
F000-FFFF: 4100 rd 4351 wr 0 bad             reads checked, writes shadowed, mismatches
1st F7FC exp 29 got 00 pc 005C               the first mismatch: address, shadow, memory, last opcode fetch
last ....                                    the most recent one
cpu resets 2, M1 at 0000: 2                  resets seen; opcode fetches from 0000h
  last from 292A                             the fetch before the last one at 0000h
last OUT 88=FF pc 24C1 m1 37                 the last port write, the last opcode address, a fetch counter
```

"bad" at 0 with the ROM still restarting means the RAM told the CPU
the truth and the fault is elsewhere; "M1 at 0000" climbing faster
than "cpu resets" is the ROM jumping to 0000h by itself, and "last
from" says from where.  A counter that does not move between two
samples is a machine that has stopped.  The simulation's numbers
(`make sim`, the `[tb] memcheck` lines) are what a working machine
shows.

The first page ever read (5 Sep 2026, the third flash) was `F000-FFFF:
65535 rd 65535 wr 80 bad / 1st F7F9 exp 51 got 00 pc 24C4 / last F7FC
exp 29 got 00 pc 24C5 / cpu resets 3, M1 at 0000: 23, last from 24C5`:
stack bytes pushed by the ROM's fill routine coming back as the zeros
the fill wrote elsewhere.  With the ROM listing beside it that named
the row handling in `sdram.v` within the hour (`progress.md`).  The
"pc" is the last opcode fetch before the read, so a `POP`'s mismatch
carries its own address and a `RET`'s the RET's.

## The SD card

FAT32.  The firmware reads it through the FPGA's `sd_card.v` and keeps
its settings in `/pk8000.ini`.  No disk images are used yet.
