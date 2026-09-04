# The BL616 firmware: `mnano/`

MiSTeryNano's firmware (Till Harbaum), as UKNC Nano carried it, with the
UKNC's additions taken out and the ПК8000's put in.  The MCU does what
the FPGA cannot: USB host (keyboard, mouse, joysticks), the SD card's
file system, the on-screen menu, and it hands the FPGA its settings
over SPI.  The FPGA side of every one of these is under
`tang/src/mister/`.

Built by `make fw` (`.claude/docs/build.md`); flashed by `make flash-mcu
COMX=/dev/ttyACM0`; the shipped binary is `bin/bl616.bin`.

## The core id

`sysctrl.v` answers CMD 0 with `5c 42 07`; 07 is `CORE_ID_PK8000` in
`sysctrl.h`, index 7 of every table the firmware selects by core:
`core_names[]` (sysctrl.c), `keymap[]` and `modifier[]` (usb_host.c),
`settings_file[]` (menu.c: `/sd/pk8000.ini`), the forms and variables
(menu.c).  The other MiSTeryNano cores' tables are still there; the
UKNC's (index 5) are `NULL` now.

## The keyboard

`mnano/pk8000.h`: `keymap_pk8000[]` indexed by USB HID usage,
`modifier_pk8000[8]` by modifier bit.  A code is `PK(row, col) =
row*8 + col + 1`, 1..80; 0 is `MISS`, a key the machine does not have
(F12 among them - it is the OSD's).  The generic path in `usb_host.c`
sends a press as the code and a release as `0x80 | code` through HID
CMD 1; `hid.v` hands the byte to `ports.v` with a strobe, and the
matrix lives there.  No row tracking, no pacing: the ПК8000 keyboard is
a plain matrix and the ROM scans it, so two keys down in one row are
simply two bits.

The mapping is by key position, `.claude/docs/platform.md` has the
matrix.  Unshifted letters are lower case (ФИКС/Caps Lock for
capitals; BASIC takes either).  What the digit row types with and
without Shift is NOT pinned down yet: three simulation runs of the
typing test gave three answers (`.claude/docs/progress.md`), because
the ROM debounces across its once-a-frame scans and the test's key
timing was not yet aligned to that.  Emu80's "smart" layout inverts
Shift for the digit row, which suggests the machine types symbols
unshifted; settle it on a board or with a scan-aligned test before
building the firmware layer that would turn it round.  Choices worth
knowing: `=` is the `^` key, `'` is `:`,
`` ` `` is `@`, F6 is `_`, F7 and Pause are СТОП, F8 ФИКС, F9 АЛФ
(Cyrillic/Latin), F10 ГРФ, F11 СЕЛ, right Alt АЛФ, left Alt ГРФ; the
keypad's 7/3/5/4/6 are row 9's cursor-home keys, `*` and `/` are ВСТ
and УДЛ, `-` is СТРН.

## The menu

```
PK8000 Nano                  Hardware
  Tape:        <file>          Expansion:  None|Floppy|IDE|ROM disk  (x)
  Floppy A:    <file>          ROM disk:   <file>
  Floppy B:    <file>          Tape:       Stop|Play                  (T)
  Hard disk:   <file>          Rewind tape                            (e, a button)
  Run .bas:    <file>          AY card:    Off|On                     (y)
  Reset               (R)
  Hardware  >                  Volume:     Mute|33%|66%|100%          (A)
  About     >                  Beeper:     Mute|On                    (b)
  Save settings                CPU waits:  Off|On                     (w)
                               Joysticks:  Normal|Swapped             (j)
                               Floppy A prot.: Off|On                 (p)
                               Floppy B prot.: Off|On                 (q)
                               HDD prot.:  Off|On                     (K)
```

The file entries are `sdc_image_open` slots: 0 tape (`.cas`), 1 and 2
floppies (`.fdd`), 3 hard disk (`.img`, `.hdd`), 4 ROM disk (`.bin`,
`.rom`); `sd_card.v`'s `image_mounted` index is the same number.
"Run .bas" is drive 5 in the file selector but not a slot: choosing a
file there calls `bas_run()` (`bas.c`), which resets the machine, waits
three seconds for BASIC's prompt, tokenises the text line by line with
the ROM's own table (`pk8000_tokens.h`, generated from the ROM by
`tools/mkcas.py --header`) and sends each line to its address at 4001h
through the SYS target's command 6 (`sysctrl.v`, `poke.v`: an address,
then bytes), then the three end-of-program pointers at F930h, then
"run" and Enter through the keyboard path.  `make bas-test` runs the
tokeniser on the host against `tools/mkcas.py`; the settings file does
not re-run the last `.bas` at power-up.  The
letters are `sysctrl.v`'s CMD 4 ids, and a value needs three edits:
the letter in the form string, an entry in `variables_pk8000[]` (the
default), and a case in `sysctrl.v`.  A button other than Reset and
Save sends its letter as 1 then 0 and leaves the OSD open.  "Save
settings" writes `/pk8000.ini` on the card; at start every variable is
sent once (A b w j x T y p q K, then R 3 and R 0).  The Hardware form
scrolls; its return to the main form is by form number.  The version
at the right of the main form's caption is the first line of
`VERSION`, read by `CMakeLists.txt` into `CORE_VERSION`.

"About" is a page of text (`about_pk8000[]`, menu.c) wrapped to the
OSD's width; its Cyrillic needs glyphs the u8g2 checkout lacks, so
`font_helvR08_te.c` was regenerated with the Cyrillic block added
(from u8g2's 6x10.bdf), ASCII unchanged.

`make menu-test` walks all of this on the host (`menu_test.c`) and
leaves each screen under `build/menu/` as text and PNG.  It is the only
way to see whether a label and its value fit the 128 pixels.

## The SD card

The card is in the Tang's slot and `sd_card.v` reads it; the firmware's
FatFs goes through that module over SPI, and the machine's images go
the other way: a request from the FPGA is an interrupt, the MCU reads
which slot and which sector, translates it through the file's cluster
map and drives the card, and the bytes land in the FPGA
(`.claude/docs/fpga.md`, the SD path).  Write protection is the
FPGA's: the letters p, q, K reach `fdc.v` and `ide.v`.

## The SPI link

Mode 1, 20 MHz, four targets by the first byte (0 SYS, 1 HID, 2 OSD, 3
SDC); `mcu_spi.v` takes it through a handshake into the 30 MHz domain.
`-DM0S_DOCK=1` picks the pinout in `spi.c` that matches the seven wires
in `README.md`.  UKNC Nano's `.claude/docs/mcu.md` has the byte-level
protocol of each target and it has not changed.

## What was removed from UKNC Nano's firmware (Sep 2026)

`uknc.h`, `rt11sav.c/h` ("Run SAV"), the UKNC forms and variables, the
RTC form and `sys_get_rtc` (CMD 6), the HDD geometry sends in `sdc.c`,
the Kakave+ mouse report ('M'), `kbd_tx_uknc` and its row tracking.
`git log --all` of `../tang-uknc` has them all.
