# The machine: ПК8000 "Сура"

The ПК8000 is a Soviet home computer of 1987 from the ВЭМ works in
Penza (Сура), built again in Stavropol (Веста) and Orenburg (Хобби).
It was meant to be an MSX-1 and could not be: no Z80, no TMS9918, no
AY-3-8910 in the national catalogue, so it is a КР580ВМ80А (8080A) at
2.5 MHz with a video controller of discrete logic and two 556РТ2 PLMs
that imitates the TMS9918's screen modes from the outside - the same
name/pattern/colour tables, at different ports, without sprites.  64 KB
of DRAM, 16 KB of ROM holding an MSX-derived BASIC, an 80-key reed
matrix, a beeper, a cassette interface, two joystick ports, a printer
port.  Later: a floppy controller (НГМД) with its own ROM in an
expansion page, and from the community an IDE/CF adapter, a ROM disk
cartridge and an AY sound card at the Вектор's ports.

The designer's own account (Андрей Малышкин, interviewed in 2009,
quoted on micklab.ru) is worth two paragraphs: the machine was to be a
full MSX-1 clone; the ministry refused a Zilog licence and custom
logic; a discrete TMS9918 needed a multilayer board they could not
afford; so "we will make a first try with weak abilities and then
quickly do the full clone", and the country ended before the second
step.  The PLMs were chosen partly so the design could not be copied
by other works - and their contents were kept from the factory floor.
That is why there is no register-level document of the video
controller and why Emu80's measured model is what this design follows.

## What this design is built against

| source | what it is authority for |
|---|---|
| `tang/rom/schematic_px3.099.001_lower_board.pdf` | the CPU board: port decode (DD21), the ВВ55 pins, ROM select (DD40/DD35), the joystick mux (DD2/DD3), the 8228-equivalent status latch (DD8) |
| `tang/rom/schematic_px3.099.006_upper_board.pdf` | the video/memory board: the colour RAM (DD23-26, 155РУ2), the colour output registers (DD28-31), the bank mux (DD34) |
| Emu80, `src/Pk8000.cpp` (Viktor Pykhonin) | raster timing, screen modes, register semantics, colour RAM blanking rule, the wait-state tables, palette |
| MAME, `src/mame/ussr/pk8000.cpp`, `shared/pk8000_v.cpp` | a second reading of the same, the keyboard matrix names |
| `tang/rom/pk8000_v12.rom` | BASIC 1.2, the ROM of the Сура and the Хобби; CRC32 a25b4b2c, MAME's `hobby.rom`.  Emu80's copy; micklab.ru's 1.0/1.1/1.2 dumps are in RAR5 archives this host cannot open |

## CPU and memory

**КР580ВМ80А at 2.5 MHz.**  The clock phases come off a divider on the
CPU board; the design makes them as enables at phases 0 and 6 of a
twelve-clock T-state on 30 MHz (`cpu8080.v`).  The status byte on the
data bus during SYNC is latched by a 4-bit register (DD8) into IORD/,
RDR/ (memory read), IOWR/, WRRAM/ and INTA/; the design decodes the
same bits.

**Memory map**, four 16 KB quarters, each with a two-bit page in the
bank register (ВВ55 #1 port A, port 80h; bits 1:0 quarter 0 ... 7:6
quarter 3):

| page | read | write |
|---|---|---|
| 0 | the ROM (16 KB, at every quarter's own offset) | RAM |
| 1 | expansion slot 1 (CSX1/): the НГМД controller's 8 KB ROM at 0000h-1FFFh and its registers at 3FF7h-3FFFh, or the IDE adapter's ROM; nothing here yet, reads 0FFh | RAM |
| 2 | expansion slot 2 (CSX2/): nothing here, reads 0FFh | RAM |
| 3 | RAM | RAM |

Writes always land in the RAM behind the page - the schematic's WRRAM/
does not consult the bank register - which is how the ROM copies itself
or a loader puts code under it.  The reset value is 0: all ROM.  The
BASIC ROM's first instructions set port 80h to the layout it wants
(0FCh: quarter 0 ROM, the rest RAM) and test F000h-FFFFh with a
`XRA A / MOV M,A / CMP M / JZ / INX H` loop - about 110 ms, and it
retries for ever on a failure.

Emu80 tags RAM pages with 1 and everything else with 0, and the wait
tables are indexed by that tag; `top.v`'s `rom_now` is `page != 3`.

## I/O ports

The lower board's DD21 decodes A7 = 1, A6 = 0, A5 = 0 into blocks by
A4..A2; A7 = 1, A6 = 0, A5 = 1 is the colour RAM.  Nothing else on the
board answers an I/O address; the community's AY card sits at 14h/15h
(the Вектор-06Ц's, because MSX's A0h-A2h are under the colour RAM).

| port | r/w | what |
|---|---|---|
| 80h | w (r) | ВВ55 #1 A: the bank register |
| 81h | r | ВВ55 #1 B: the keyboard's eight data lines for the selected row, a pressed key low |
| 82h | w (r) | ВВ55 #1 C: [3:0] keyboard row select (0..9; 10..15 read 0FFh), [4] tape motor, [6] tape output, [7] the beeper |
| 83h | w | ВВ55 #1 control: bit 7 set = mode word (ports cleared), clear = bit set/reset on port C ({bit 3:1, value 0}) |
| 84h | w (r) | ВВ55 #2 A: [4] graphics, [5] 40 columns, [7:6] the screen's quarter.  Mode = {bit 4, ~bit 5}: 00 text 40, 01 text 32, 10 graphics, 11 border only |
| 85h | w (r) | ВВ55 #2 B: printer data |
| 86h | w / r | ВВ55 #2 C: [4] display enable (DSCR; 0 = "blanking"), [7] printer strobe.  A read answers 0FBh - printer not busy - as Emu80 answers it |
| 87h | w | ВВ55 #2 control, as 83h |
| 88h | w (r) | colour: [3:0] foreground (text modes), [7:4] background and border |
| 8Ch | r | joystick 1: [0] up [1] down [2] left [3] right [4] button 1 [5] button 2, active high; [6] 0; [7] 0 |
| 8Dh | r | joystick 2 the same; [7] the tape input |
| 90h | w (r) | text base: name table at [3:0] << 10 (mode 0 ignores bit 0) |
| 91h | w (r) | symbol generator base: patterns at [3:1] << 10; in graphics mode the NAME table |
| 92h | w (r) | graphics pattern base: ~[3] << 13 |
| 93h | w (r) | graphics colour base: ~[3] << 13 |
| A0h-BFh | w / r | the colour RAM of mode 1: 32 bytes, {background [7:4], foreground [3:0]} for names 0-7, 8-15, ...  Writes take only while DSCR is low (the display owns the RAM otherwise); reads work any time |

"(r)" means the machine's bus floats - WR88/ and WR90/ are write
strobes only - and the design, like both emulators, answers with the
value last written.  Emu80's source names its port 92h class
`ColBufSelector` and 93h `GrBufSelector` but wires them the other way
in `pk8000.conf`, agreeing with MAME; the table above is the wiring.

The 8080's `IN`/`OUT` put the port number on A7..A0 and A15..A8 alike;
the decode uses A7..A0.

## The display

Emu80's model, which this design reproduces (`video.v`; the account of
the implementation is `.claude/docs/video.md`):

- **Pixel clock 5 MHz**, 320 pixel slots a line = 64 us, **308 lines** a
  frame = **50.73 Hz**.  Lines 71..262 carry the picture (192 lines);
  the rest is border.  The frame interrupt is raised at the start of
  line 263.
- **Mode 0** (text, 40 columns): the name table is 64 bytes a row
  (columns 0..39 used), characters 6 pixels wide from bits 7..2 of the
  pattern byte, 240 pixels of picture with 40 slots of border each
  side.  Foreground and background from port 88h, live.
- **Mode 1** (text, 32 columns): 32 bytes a row, 8-pixel characters,
  256 pixels of picture with 32 slots of border each side.  Colours from
  the colour RAM by name >> 3.  With DSCR low the picture area shows
  colour 15 (white) - the display reads a disconnected colour RAM -
  which is Emu80's `BS_BLANK`; the eight-pixel `BS_WRITE` stripe it
  draws around each colour RAM write is not reproduced.
- **Mode 2** (graphics, 256 x 192): TMS9918 graphics II.  Three thirds
  of 64 lines; the name table (port 91h's base) is 768 bytes, 256 a
  third; the pattern table (port 92h) and the colour table (port 93h)
  are 2 KB a third, 8 bytes a name; colour byte = {background,
  foreground} per pixel row.  32 slots of border each side.
- **Mode 3**: border only.
- **Palette**: four bits {R, B, G, I}; a component is 0A8h with I clear,
  0FFh with I set, 0 without its bit.  So 0 and 1 are black, 2 dark
  green, 3 green, 4 dark blue, 5 blue, 6/7 cyan, 8/9 red, A/B yellow,
  C/D magenta, E grey, F white.

The border colour, the text foreground and DSCR are read at every
pixel, so a program that changes port 88h mid-line gets the stripe the
machine draws.  Bank and base changes take effect at the next tile
fetch (Emu80 defers them to the next line unless early in the line;
nothing known depends on the difference).

## The video controller's cost to the CPU

The video controller reads the DRAM on its own and holds the CPU's
READY off while it does, and how much of an instruction that eats
depends on the opcode, on whether it came from ROM or RAM (the ROM is
on the CPU board, the DRAM behind the controller), and on whether a
40-column mode is in the active part of a line - where the 6-pixel
cadence leaves the CPU more slots.  The exact logic is in the PLMs;
what exists is Emu80's four tables of MEASURED extra clocks per opcode
(`Pk8000CpuWaits`), which `tools/waits_rom.py` reproduces, with the
conditional return and call rows depending on whether the branch was
taken: Rxx from RAM costs 3/5 not taken/taken (1/7 in the 40-column
active area), from ROM 1/3; Cxx from RAM 5/15 (7/13), from ROM 14/11 (9
in the active area).  An interrupt costs 7 more clocks in a 40-column
mode and 5 otherwise.  `cpu8080.v` pays each instruction's clocks as
wait states in the next instruction's M1.  The OSD's "CPU waits: Off"
removes them, which makes the machine roughly a third faster than a
real one - useful for a stubborn loader, wrong for a game.

Only the totals are known.  Where within an instruction the machine
stalls is not, and a program that races the beam to the pixel could
tell the difference; none is known to.

## Interrupt

One source: the frame, at line 263, into a flip-flop (the schematic's
ПРЕР into the CPU's INT, cleared by СБР.ПРЕР = INTA/).  During the
acknowledge cycle nothing drives the data bus, the pull-ups read 0FFh,
and the CPU executes RST 7 - the ROM's handler at 38h.  The design
holds the request until the acknowledge, so an interrupt raised while
interrupts are disabled is taken at the next EI.

## Keyboard

A 10 x 8 reed matrix scanned by the ROM: row on port 82h[3:0], data on
port 81h, pressed = 0.  Rows, as Emu80 and MAME have them (columns 0..7):

```
0: 0 1 2 3 4 5 6 7
1: 8 9 , - . : ; /
2: [ \ ] ^ _ @ A B
3: C D E F G H I J
4: K L M N O P Q R
5: S T U V W X Y Z
6: РГ(Shift) УПР(Ctrl) ГРФ(Graph) АЛФ(Lang) ФИКС(Caps) F1 F2 F3
7: F4 F5 ESC TAB СТОП ЗБ(Backspace) СЕЛ ВВОД(Enter)
8: ПРОБЕЛ СТРН(Clear) ВСТ(Ins) УДЛ(Del) Left Up Down Right
9: home-up-left(KP7) end-down-right(KP3) МЕНЮ(KP5) home(KP4) end(KP6) page-end(PgDn) page-home(PgUp) -
```

The MCU translates USB HID usages into `row*8 + col + 1` (0 = no key)
and sends a press as the code and a release as the code with bit 7 set
(`mnano/pk8000.h`); `ports.v` keeps the matrix.  Two keys down in one
row are two low bits, as on the machine.  The machine's own keycaps
carry Cyrillic on the letter keys and symbols on the digit row that
the ROM decides by АЛФ and Shift; the translation is by key position,
not by character.  As the ROM has it (seen in simulation): unshifted
letters are lower case, and Shift changes the function-key bar's
labels as on an MSX.  What the digit row types with and without Shift
is not settled - the three typing runs of 4 Sep 2026 disagreed
(`progress.md`); Emu80's "smart" layout inverts Shift for digits,
which suggests symbols unshifted.

## Joysticks

Two DB9 ports (Atari pinout, reversed sense: a contact reads 1),
through DD2/DD3 onto ports 8Ch/8Dh as above.  The design takes
MiSTeryNano's USB joystick bytes ({-, -, b2, b1, up, down, left,
right}) and reorders them.  The OSD's "Joysticks: Swapped" exchanges
the two ports.

## Tape

Output on port 82h bit 6, the motor relay on bit 4, input on port 8Dh
bit 7.  MSX format at 1200 baud: a 1 is two cycles of 2400 Hz, a 0 one
of 1200 Hz, a byte is a start bit, eight data bits LSB first, two
stop bits, and a file begins with a run of 1s (the "header") and the
eight bytes 1F A6 DE BA CC 13 7D 74 ... - Emu80's `MsxTapeHooks` and
`.cas` files are the reference.  Nothing here drives it yet; the tape
input reads 0 and the output goes into the sound mix at a low level.
A tape player reading `.cas` from the SD card is the next thing worth
building - it is how a Сура without a drive gets its software.

## Sound

One bit, port 82h bit 7, into a piezo (HA1 on the CPU board).  The
design mixes it at a quarter of full scale with the tape output at a
sixteenth and sends the sum to I2S and to HDMI.

## Floppy and the rest (not built)

The Сура НГМД: a КР1818ВГ93 (WD1793) in expansion page 1 with an 8 KB
ROM (`tang/rom/pk8000_fdc.rom`) at 0000h-1FFFh and registers at
3FF7h-3FFFh - 3FF7h the drive/side/reset control (bit 7 reset, bit 6
drive, bit 4 side), 3FF8h-3FFBh the ВГ93, 3FFCh-3FFFh a status byte
selected by {DRQ, IRQ}.  `.fdd` images are 80 tracks x 2 sides x 5
sectors x 1024 bytes.  Emu80's `pk8000_fdc.conf` is the map.  The IDE
adapter is a ВВ55 at 50h-53h with `pk8000_hdd.rom` (9322 bytes) in
expansion page 1.  The ROM disk cartridge selects a 16 KB page by port
77h.  The AY card: register at 14h, data at 15h, 1.75 MHz.
