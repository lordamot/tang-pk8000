# PK8000 Nano

**ПК8000 «Сура»** - советский домашний компьютер 1987 года на
КР580ВМ80А с видеоконтроллером «под MSX» - на **Tang Nano 20K** с платой
**BL616** (M0S Dock) рядом.  Сделано по образцу и на основе
[UKNC Nano](https://github.com/lordamot/tang-uknc) (аппаратная часть -
Алексей Гуров, линия 2.x - Сергей Лемешев и Claude Code): оттуда взяты
связь с BL616, HDMI-кодер со звуком, инструменты и метод.  Процессор -
vm80a (1801BM1/Vslav, CC-BY 3.0), точная копия кристалла 580ВМ80А.
Версия - в файле `VERSION`, история - в `CHANGELOG.md`, лицензия - MIT
(`LICENCE.md`).  *English below.*

**Состояние (4 сентября 2026): собирается, проходит временной анализ,
в симуляции загружает Бейсик до приглашения.  На плате ещё не
запускалось.**

## Что умеет

- КР580ВМ80А на 2,5 МГц, с задержками, которые вносит видеоконтроллер
  (по измеренным таблицам Emu80; отключаются в меню).
- Все три экранных режима: текст 40 и 32 колонки, графика 256×192,
  16 цветов; экран по HDMI 768×576 при родных 50,73 Гц.
- ПЗУ Бейсика 1.2 («Сура»/«Хобби»), 64 КБ ОЗУ.
- Клавиатура USB, переведённая в матрицу 10×8; два USB-джойстика.
- Магнитофон: файлы `.cas` с карты воспроизводятся на вход магнитофона
  (`CLOAD`, `LOAD`, `BLOAD`); записи пока нет.
- Дисковод НГМД (КР1818ВГ93 с его ПЗУ) - два дисковода из файлов `.fdd`.
- IDE/CF-адаптер сообщества с его ПЗУ - образ `.img` на карте; в
  `soft/cf.img` - 2 МБ образ из поставки Emu80 с большинством программ.
- ROM-диск (картридж, порт 77h) - файл `.bin` загружается в SDRAM.
- Звуковая карта AY-3-8910 на портах 14h/15h.
- Бипер и AY по HDMI и I²S.
- Меню по **F12**: образы, «Run .bas» (текстовая программа на Бейсике с
  карты - сразу в память машины, как будто набрана), три переключателя
  расширения (дисковод, IDE, ROM-диск - каждый отдельно; если включено
  несколько, страницу 1 занимает первый из них в этом порядке),
  магнитофон, AY, громкость, бипер, задержки процессора, джойстики,
  защита записи, «About», сохранение настроек на карту.
- В `soft/`: образ CF из Emu80, системная дискета с AY-плеером, демо
  четырёх экранных режимов (`.bas` и `.cas`).

Чего пока нет: записи на магнитофон, принтера.  Состояние и порядок - в
`.claude/docs/progress.md`.

## Что нужно

- Tang Nano 20K, плата BL616 (M0S Dock), SD-карта FAT32, USB-клавиатура.
- Семь проводов между платами - распиновка **как в исходном MiSTeryNano**
  и в UKNC Nano:

```
Tang Nano 20K   BL616
42              io10   MISO
41              io11   MOSI
56              io12   CSN
54              io13   SCK
51              io14   IRQ
GND             GND
+5              +5
```

Звук I²S - на выводах 71 (BCK), 72 (WS), 73 (DIN), 74 (разрешение
усилителя); по HDMI звук идёт сам.

## Как прошить

**BL616** - через его загрузчик: удерживая **BOOT**, подключить USB (или
нажать **RST**), отпустить BOOT; плата появится как последовательный
порт.  Дальше либо BLDevCube (чип BL616/BL618, вкладка MCU, файл
`bin/bl616.bin`, адрес `0x00000000`, скорость 2000000, Create & Download),
либо из этого репозитория:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

После прошивки нажать RST.

**Tang Nano 20K** - через openFPGALoader (или Gowin Programmer):

```sh
openFPGALoader -b tangnano20k -f bin/tang.fs     # во флеш
make flash-fpga-flash                            # то же из репозитория
```

и **выключить-включить питание**: после записи во флеш плата продолжает
работать со старой прошивкой, пока её не перезапустить.

## Как пользоваться

Включить - и через секунды две Бейсик выведет приглашение.  **F12**
открывает меню; курсор - по пунктам, влево/вправо - значение, пробел или
Enter - выбрать, ESC - закрыть.  «Save settings» пишет `/pk8000.ini`
на карту.  Раскладка: буквы и цифры - как на клавише; `=` даёт `^`, `'`
даёт `:`, F9 - АЛФ (рус/лат), F10 - ГРФ, F8 - ФИКС, F11 - СЕЛ, F6 - `_`;
подробно - `.claude/docs/mcu.md`.

## Как собрать

```sh
make toolchain    # один раз, ~7 ГБ в tools/
make lint         # Verilator, секунды
make sim          # машина целиком, до приглашения Бейсика (минуты)
make frames       # то же, кадры экрана в sim/out/*.ppm
make bitstream    # прошивка ПЛИС -> bin/tang.fs, с проверкой временных ограничений
make fw           # прошивка BL616 -> build/fw/bl616.bin
```

---

# PK8000 Nano

The **ПК8000 "Сура"**, a Soviet home computer of 1987 - a КР580ВМ80А
(8080A) with an MSX-like video controller of discrete logic - on a
**Tang Nano 20K** with a **BL616** board (M0S Dock) beside it.  Modelled
on and built from [UKNC Nano](https://github.com/lordamot/tang-uknc)
(hardware by Alexey Gurov; the 2.x line by Sergei Lemeshev and Claude
Code): the BL616 link, the HDMI encoder with audio, the tools and the
method are taken from there.  The CPU is vm80a (1801BM1/Vslav, CC-BY
3.0), a gate-level replica of the 580ВМ80А die.  The version is in
`VERSION`, the history in `CHANGELOG.md`, the licence is MIT
(`LICENCE.md`).

**State (4 September 2026): builds, meets timing, boots BASIC to its
prompt in simulation.  Not yet run on a board.**

## Features

- The КР580ВМ80А at 2.5 MHz, with the stalls the video controller costs
  it (Emu80's measured tables; switchable off in the menu).
- All three screen modes - text 40 and 32 columns, 256x192 graphics -
  16 colours, over HDMI as 768x576 at the machine's own 50.73 Hz.
- BASIC 1.2 ROM (Сура/Хобби), 64 KB RAM.
- A USB keyboard translated into the 10x8 matrix; two USB joysticks.
- Tape: `.cas` files from the card play into the tape input (`CLOAD`,
  `LOAD`, `BLOAD`); no recording yet.
- The НГМД floppy (a КР1818ВГ93 with its ROM), two drives from `.fdd` files.
- The community IDE/CF adapter with its ROM, an `.img` on the card;
  `soft/cf.img` is Emu80's 2 MB image with most of the software.
- The ROM disk cartridge (port 77h), a `.bin` loaded into the SDRAM.
- The AY-3-8910 sound card at 14h/15h.
- The beeper and the AY over HDMI and I²S.
- A menu on **F12**: the images, "Run .bas" (a plain-text BASIC program
  from the card straight into the machine's memory, as if typed),
  three expansion switches (floppy, IDE, ROM disk, each on its own;
  with more than one on, the first in that order owns page 1), tape, AY, volume, beeper, CPU waits,
  joysticks, write protection, About, settings saved to the card.
- In `soft/`: Emu80's CF image, a system floppy with the AY player, a
  four-mode graphics demo as `.bas` and `.cas`.

Not yet: recording to tape, the printer.  `.claude/docs/progress.md`
has the state.

## What you need

- A Tang Nano 20K, a BL616 board (M0S Dock), a FAT32 SD card, a USB keyboard.
- Seven wires between the boards - the **stock MiSTeryNano pinout**, as
  UKNC Nano wires it (table above).  I²S audio on pins 71 (BCK), 72
  (WS), 73 (DIN), 74 (amplifier enable); HDMI carries the sound itself.

## How to flash

**BL616**, through its bootloader: hold **BOOT**, plug in USB (or press
**RST**), release BOOT; the board shows up as a serial port.  Then either
BLDevCube (chip BL616/BL618, MCU tab, file `bin/bl616.bin`, address
`0x00000000`, baud 2000000, Create & Download) or, from this repository:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

Press RST afterwards.

**Tang Nano 20K**, with openFPGALoader (or the Gowin Programmer):

```sh
openFPGALoader -b tangnano20k -f bin/tang.fs     # to flash
make flash-fpga-flash                            # the same from the repository
```

then **power-cycle the board**: after a write to flash it keeps running
the old bitstream until it is restarted.

## How to use it

Power on; BASIC prints its prompt after about two seconds.  **F12**
opens the menu; cursor keys move, left and right step a value, Space or
Enter selects, ESC closes.  "Save settings" writes `/pk8000.ini` to the
card.  Keys are by position: `=` is the `^` key, `'` is `:`, F9 is АЛФ
(Cyrillic/Latin), F10 ГРФ, F8 ФИКС, F11 СЕЛ, F6 `_`; the whole table is
in `.claude/docs/mcu.md`.

## How to build

```sh
make toolchain    # once, ~7 GB into tools/
make lint         # Verilator, seconds
make sim          # the whole machine, to the BASIC prompt (minutes)
make frames       # the same, with the screen as sim/out/*.ppm
make bitstream    # the FPGA bitstream -> bin/tang.fs, through the timing gate
make fw           # the BL616 firmware -> build/fw/bl616.bin
```
