# State of the port

Last updated: 4 September 2026, v0.1.0 alpha, the first day.

## What there is

Built, linted, simulated to the BASIC prompt, timed - not run on a
board.  In one day, on UKNC Nano's framework:

- the КР580ВМ80А (vm80a) at 2.5 MHz on a 30 MHz clock, the SDRAM on a
  fixed timetable, the BASIC 1.2 ROM, the bank register;
- the two ВВ55s, the video registers, the colour RAM, the frame
  interrupt, the keyboard matrix from USB, two USB joysticks, the beeper;
- the display in all four modes, rendered as the beam draws it and shown
  as 768x576 at 50.73 Hz over HDMI with UKNC Nano's encoder;
- the video controller's cost to the CPU, from Emu80's measured tables;
- the firmware: core id 7, the keymap, a four-value menu, settings on
  the card;
- lint, a full-machine simulation with checks and frames, a host walk
  of the menu, the bitstream with the timing gate.

```
Logic 17%   Register 10%   BSRAM 24%   PLL 2/2   clk30 66.6 MHz   0 violations   [4 Sep 2026]
```

## What the simulation showed on 4 September 2026

`make frames RUN_MS=2700 PPM_FROM=2350 SIMARGS="+TYPE +TYPE_MS=2200"`,
about four minutes of wall time:

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
  Bytes free" - the RAM dump at 700 ms has both, and the font at 0800h.
- Every byte written to RAM read back as written (490175 checks);
  vm80a's address never moved after the strobe (2.5 M cycles); the HDMI
  stream decoded as 768x576 with 0 ECC errors and no bad guard band.
- The frames at 2.35 s show the screen as the machine draws it: the
  banner, "46873 Bytes free", "Ok", the cursor, and the function-key
  bar "color 1 cload" cont list run" along the bottom - white 6x8
  text on black, 40 columns, the border around it.  A line typed
  through the HID path (`+TYPE`) is echoed by BASIC, and a held Shift
  changes the function-key bar to "color auto goto list run" as on an
  MSX: the keyboard path works.  The typing test itself is not yet a
  reliable instrument: three runs typed "1+INPRT" (keys held 60 us,
  faster than the once-a-frame scan), "print !+" and "print !;!" (keys
  held 30 and 60 ms, Shift held for the digits in the last two), so
  what the digit row types under Shift, and why Enter was not taken in
  the last run, are open.  The ROM debounces across scans; a test that
  holds keys for whole frames and changes them right after the scan is
  the next step.
- Each of the first four long runs found a defect of its own, listed
  below; the frames were the evidence every time and the counters in
  the end-of-run lines were not - "3.7 M tile fetches" counted requests
  nobody answered.

## Defects, in the order found

1. **Fixed** - `hcnt`/`tphase` held until `init` while the SDRAM's
   initialisation ran in a phase of them: a deadlock that printed
   nothing.  The counters run from PLL lock.
2. **Fixed** - the SDRAM word captured one slot clock late; every read
   was zero and the ROM's RAM test (which writes zeros) hid it from the
   read-after-write check for a whole run.  Captured at slot clock 3;
   `sdram.v`'s header has the arithmetic; `+DQTRACE` shows it.
3. **Fixed** - the line buffer was 640 entries for a {line, slot} index
   that needs 1024; slots past 127 of every other line went nowhere.
4. **Fixed** - the display's tile hand-over and the fetch's were on the
   same clock, so a tile showed its predecessor's pattern.  The fetch
   hands over a clock earlier.
5. **Fixed** - the video's SDRAM request was registered on phase 1 and
   so was up on phase 2, a clock after the slot's first; `sdram.v`
   never took one and the picture was black over a correct name table.
   Raised on phase 0.
6. **Open** - whether a sink takes 768x576 at 50.73 Hz with a 144-clock
   back porch.  UKNC Nano's television took its 51 Hz; a board will
   say.
7. **Not a defect** - the interrupt count looked like two a frame on
   the first long run; counted properly (2.7 s: 252 frames raised, 224
   taken, interrupts enabled at 556 ms) it is one a frame from the
   moment BASIC enables them.  `+IRQTRACE` prints both.

## What is not built, in the order worth building

1. **A tape player.**  `.cas` files from the SD card, through the
   `sd_card.v` sector interface, generating the MSX FSK on port 8Dh
   bit 7 with the motor on port 82h bit 4 - the way a Сура without a
   drive loads anything, and the way most of the surviving software
   is kept.  Emu80's `MsxTapeHooks` and the format note in
   `platform.md` are the reference; the OSD needs a file selector ('F'
   entry, slot 0) and a "Play" control.
2. **The НГМД floppy controller**: a ВГ93 (WD1793) in expansion page 1
   with `tang/rom/pk8000_fdc.rom`, `.fdd` images of 80x2x5x1024.
   UKNC Nano's `fdd4.v` is the sector-over-SD pattern; the controller
   itself is the classic MiST `wd1793`.
3. **The IDE/CF adapter** (ВВ55 at 50h-53h, `pk8000_hdd.rom`): the
   community's 2 MB card image of nearly all the software.
4. **The AY card** at 14h/15h (UKNC Nano's `ym2149.sv`), the ROM disk
   cartridge (port 77h), the printer.
   Also in the firmware: a "smart" digit row (Emu80's), sending Shift
   with a PC digit and dropping it for a PC symbol - once what the ROM
   types with and without Shift is settled (above).
5. **The wait model against the machine**: the two PLM dumps on
   micklab.ru (RAR5; needs `unrar`), read into equations, would say
   where in an instruction the stall really falls.

## Open questions

- Does the real ROM 1.2 need anything on port 8Dh bit 7 or the joystick
  ports at boot?  In simulation it does not.
- `cpu8080.v` classes an INTA cycle's opcode as 0FFh in the wait table
  (RST 7's row) and adds the interrupt's 7/5; Emu80 adds only the 7/5.
  One or two clocks a frame either way.
- The OSD's "CPU waits: Off" is the only knob on speed; a "turbo" that
  also shortens the SDRAM slots is not needed, since the SDRAM never
  waits the CPU anyway.
