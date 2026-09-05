# PK8000 Nano - how to

The short form.  `README.md` has the wiring and the flashing; the long
form of everything is under `.claude/docs/`.

## 1. What you get

A ПК8000 "Сура" that starts into BASIC 1.2 with 46873 bytes free, on
HDMI at 768x576 (the machine's 50.73 Hz), with a USB keyboard and up to
two USB joysticks on the BL616, and the beeper and the AY card over
HDMI and the dock's I2S output.  Software comes in from the SD card: a
`.cas` tape, `.fdd` floppies through the НГМД controller, a CF image
through the IDE adapter, a ROM disk cartridge, or a `.bas` text put
straight into memory.  Boots on a board since 5 Sep 2026.

## 2. The keyboard

The machine's keyboard is a 10x8 matrix and the USB keyboard is mapped
onto it by position (`mnano/pk8000.h`).  The whole layout, row by row
of the matrix, ПК8000 key first:

| ПК8000 key | PC key |
|---|---|
| `0` `1` `2` `3` `4` `5` `6` `7` `8` `9` | the digits |
| `,` `-` `.` `/` | `,` `-` `.` `/` |
| `:` | `'` |
| `;` | `;` |
| `[` `]` `\` | `[` `]` `\` (and the ISO key next to Enter) |
| `^` | `=` |
| `_` | F6 |
| `@` | `` ` `` |
| `A` .. `Z` | the letters |
| РГ (Shift) | Shift |
| УПР (Ctrl) | Ctrl |
| ГРФ (Graph) | left Alt, F10 |
| АЛФ (Cyrillic/Latin) | right Alt, F9 |
| ФИКС (Caps) | Caps Lock, F8 |
| F1 .. F5 | F1 .. F5 |
| ESC, TAB | Esc, Tab |
| СТОП | F7, Pause |
| ЗБ (Backspace) | Backspace |
| СЕЛ | F11 |
| ВВОД (Enter) | Enter, keypad Enter |
| ПРОБЕЛ | Space |
| СТРН (Clear) | keypad `-` |
| ВСТ (Insert) | Insert, keypad `*` |
| УДЛ (Delete) | Delete, keypad `/` |
| ← ↑ ↓ → | the cursor keys; keypad 8 is ↑, keypad 2 is ↓ |
| home-up-left | keypad 7 |
| end-down-right | keypad 3, keypad 9 |
| МЕНЮ | keypad 5 |
| home | Home, keypad 4, keypad 1 |
| end | End, keypad 6 |
| page-home | PgUp |
| page-end | PgDn, keypad 0, keypad `.` |
| (the menu) | F12 - never reaches the machine |

What the keys type is the ROM's business and the machine's own layout,
not the PC's.  Measured in simulation (`.claude/docs/platform.md`):
letters are lower case unshifted and capitals with Shift or under
ФИКС; the digit row is the other way round from a PC - a digit key
alone types the symbol on its cap (the `2` key alone is `"`) and Shift
gives the digit; the `/` key alone is `?` and Shift+`/` is `/`; Shift+`;`
is `+`.  A firmware layer that maps PC digits and symbols onto that is
on the list (`.claude/docs/progress.md`).

## 3. The menu

F12.  Cursor keys move, left/right step a value, Space or Enter selects,
Esc closes.

- **Tape, Floppy A, Floppy B, Hard disk** - the image slots on the card
  (`.cas`, `.fdd`, `.img`/`.hdd`).
- **Run .bas** - a plain-text BASIC program from the card is tokenised
  and put into the machine's memory as if typed, then run.
- **Reset** - the machine restarts.
- **Hardware** - **Floppy**, **IDE**, **ROM disk** (Off / On, each on
  its own: the floppy controller with its ROM, the IDE/CF adapter with
  its ROM, the ROM disk cartridge.  All three share expansion page 1,
  and when more than one is on the first of them in that order owns
  the page; the others keep their ports - the IDE's 50h-53h, the ROM
  disk's 77h - but have no ROM window, so a machine that should boot
  from the CF needs the floppy off); **ROM file** (the ROM disk's
  image); Tape (Stop / Play) and Rewind; AY card; Volume (Mute / 33% /
  66% / 100%); Beeper (Mute / On); CPU waits (Off / On: On is the real
  machine's speed, with the video controller's stalls; Off is about a
  third faster); Joysticks (Normal / Swapped); write protection for
  the two floppies and the hard disk.
- **About**, **Debug** (what the memory gave the CPU - for when it does
  not start, `.claude/docs/build.md`).
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
