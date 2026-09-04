# PK8000 Nano - how to

The short form.  `README.md` has the wiring and the flashing; the long
form of everything is under `.claude/docs/`.

## 1. What you get

A ПК8000 "Сура" that starts into BASIC 1.2 with 46873 bytes free, on
HDMI at 768x576 (the machine's 50.73 Hz), with a USB keyboard and up to
two USB joysticks on the BL616, and the beeper over HDMI and the dock's
I2S output.  No tape, no floppy yet - the ways of getting software in
are what comes next (`.claude/docs/progress.md`).

## 2. The keyboard

The machine's keyboard is a 10x8 matrix and the USB keyboard is mapped
onto it by position.  Letters and digits are where they say; the rest:

| PC key | ПК8000 key |
|---|---|
| `=` | `^` |
| `'` | `:` |
| `` ` `` | `@` |
| F6 | `_` |
| F7, Pause | СТОП |
| F8, Caps Lock | ФИКС |
| F9, right Alt | АЛФ (Cyrillic/Latin) |
| F10, left Alt | ГРФ |
| F11 | СЕЛ |
| Home / End | home / end (row 9) |
| PgUp / PgDn | page home / page end |
| keypad 7 3 5 4 6 | the row-9 cursor keys |
| keypad `*` `/` `-` | ВСТ УДЛ СТРН |
| Insert, Delete, Backspace, Tab, Esc, Enter, Space, cursors | themselves |
| F12 | the menu (never reaches the machine) |

Shift and Ctrl are РГ and УПР.  Letters are lower case unshifted
(Caps Lock is ФИКС).  What the digit keys type with Shift is the
machine's own layout, not the PC's, and is not yet documented here -
try it; a firmware layer that maps PC digits and symbols onto it is on
the list once it is known.

## 3. The menu

F12.  Cursor keys move, left/right step a value, Space or Enter selects,
Esc closes.

- **Reset** - the machine restarts.
- **Hardware** - Volume (Mute / 33% / 66% / 100%); Beeper (Mute / On);
  CPU waits (Off / On: On is the real machine's speed, with the video
  controller's stalls; Off is about a third faster); Joysticks (Normal /
  Swapped).
- **About**.
- **Save settings** - writes `/pk8000.ini` on the card; loaded at power-up.

## 4. If it does not start

- No picture at all: the monitor may not take 768x576 at 50.73 Hz -
  try another; and check the seven wires (`README.md`).
- A cyan screen for ever: the ROM's RAM test is failing - the SDRAM.
  This is the one thing simulation cannot vouch for.
- The picture but no keys: the BL616 is not talking - its firmware, the
  wires, or the card missing (the firmware still runs without one).
- Flashing: replug, flash, power-cycle, in that order
  (`.claude/docs/build.md`).
