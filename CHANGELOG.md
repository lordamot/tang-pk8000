# Changelog

## 0.2.0 alpha - 4 September 2026

The peripherals.  Not yet run on a board.

### The machine
- A cassette player: `.cas` files from the SD card into the tape input,
  Play/Stop and Rewind in the menu, the motor bit honoured.
- The НГМД floppy controller: a ВГ93 (MiSTer's wd1793) with its ROM in
  expansion page 1, two drives from `.fdd` images, write protection.
- The community IDE/CF adapter with its ROM: an `.img` in the menu, LBA,
  8- and 16-bit data, write protection; `soft/cf.img` from Emu80.
- The ROM disk cartridge: a `.bin` copied into the SDRAM at mount, port 77h.
- The AY-3-8910 card at 14h/15h.
- The expansion slot as a menu choice: None, Floppy, IDE, ROM disk.
- "Run .bas": a plain-text BASIC program from the card, tokenised by the
  firmware with the ROM's own table and written straight into the
  machine's memory (`poke.v`, SPI command 6), then run - seconds, not
  minutes of tape.
- `soft/`: Emu80's CF image, a P/M system floppy with the AY player
  (`ayplayer.fdd`, made with `tools/mkfdd.py`), a four-mode graphics
  demo as `.bas` and `.cas`.

### For builders
- One owner at a time on the SD path (`sd_arbiter.v`); the SDRAM addressed
  to 4 MB.
- A simulation model of the SD card that serves host files (`+TAPE=`,
  `+FDDA=`, `+HDD=`, ...), a `.cas` writer (`tools/mkcas.py`), a CLOAD test
  in the testbench; the IDE boot and the floppy boot are runs of it.
- Simulated: the CF image boots to its P/M 2.2 prompt, the НГМД ROM reads
  a blank disk's boot sector and falls to BASIC, `cload"TEST` loads
  `soft/hello.cas` and "run" prints "TAPE OK".  `tools/mkcas.py` writes
  this ROM's tokens (read from the ROM; they are not MSX's) and the zero
  trailer its loader reads.
- Port 84h's graphics mode was decoded as "border only" (`ports.v`), so
  SCREEN 2 showed nothing; found by `soft/demo.bas`, fixed from Emu80.
- The keyboard matrix took a key's release as its press (`ports.v`), so a
  key stayed down from its release and Shift stayed down for ever after
  its first use; found through the tape test, and the cause of 0.1.0's
  garbled typing.  "print 1+1" answers "2" in simulation now.
- Simulated too: DISK1 of the 2009 floppy set boots P/M's shell,
  `demoay` from `soft/ayplayer.fdd` plays the AY card (sound on the I2S
  stream), a program poked in through `+BAS=` runs.
- Built and timed: Logic 30%, Register 17%, BSRAM 25/46, clk30 70.3 MHz,
  0 violations.  `wd1793.sv` without `default_nettype none` and with a
  write-through buffer, both for Gowin; the arbiter holds a request until
  the card is busy on it; an image mounted during reset is not lost.

## 0.1.0 alpha - 4 September 2026

The first cut, built in one day from UKNC Nano's framework.  Authors:
Sergei Lemeshev and Claude Code.  Not yet run on a board.

### The machine
- The КР580ВМ80А (vm80a, 1801BM1) at 2.5 MHz on a single 30 MHz clock,
  with the video controller's stalls as wait states from Emu80's tables.
- 64 KB RAM in the SDRAM on a fixed timetable, the BASIC 1.2 ROM in BSRAM,
  the bank register and the ROM/RAM/expansion pages.
- The two ВВ55s, ports 88h and 90h-93h, the mode-1 colour RAM, the
  frame interrupt.
- The display: modes 0, 1, 2 and 3, the border, live colour and
  blanking; 768x576 over HDMI at 50.73 Hz.
- The keyboard matrix from USB, two USB joysticks, the beeper over HDMI
  and I²S.

### The on-screen menu
- Reset, Volume, Beeper, CPU waits, Joysticks, About, Save settings;
  settings in `/pk8000.ini`; the core id 7.

### For builders
- `make lint`, `make sim` (the ROM to its prompt, frames as `.ppm`, a
  typed line of BASIC), `make bitstream` with the timing gate, `make fw`,
  `make menu-test`; the documentation under `.claude/`.
