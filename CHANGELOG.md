# Changelog

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
