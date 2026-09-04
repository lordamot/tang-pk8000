# Tools and ROM data

The toolchain is fetched into `tools/` and driven from the `Makefile`;
`.claude/docs/build.md` says what builds here.  Beside it there is a
handful of small scripts, all committed (force-added past the `/tools/`
ignore line), and the ROM data under `tang/rom/`.

## `tools/`

| script | what |
|---|---|
| `fetch.sh` | fetches the toolchain (oss-cad-suite, CMake, Ninja, the RISC-V GCC, the Bouffalo SDK, Gowin EDA Education, gh), patches the SDK's host-tool selection, shadows Gowin's stale bundled libraries.  UKNC Nano's; it still clones macro11, which this project does not use |
| `env.sh` | puts the same set on `PATH` for use by hand |
| `srcs.py` | prints the design's source list out of `tang/pk8000.gprj`; `--ip` the stubbed files, `--cst`, `--sdc` |
| `gowin_tcl.py` | emits `tang/build.tcl` for `gw_sh`, from the same `.gprj` and the IDE's process config |
| `timing_check.py` | the timing gate (`.claude/rules/timing.md`) |
| `bin2prom.py` | a flat binary -> a Verilog module of Gowin pROM primitives (1024 x 16 each), registered output; `make rom` runs it for the BASIC ROM |
| `waits_rom.py` | the four wait-state tables (from Emu80's Pk8000CpuWaits) -> `waits_rom.v`, a combinational lookup; `make waits` |
| `mif.py` | flat binary <-> `.mif` <-> `$readmemh` hex; `binhex` makes the sim model's ROM image |
| `osd_png.py` | the OSD test's text dumps -> PNG |
| `sdk-host-tools.patch` | the Bouffalo SDK's `cmake/bflb_flash.cmake` fix, applied at fetch |

`bin2prom.py` packs little-endian 16-bit words, so byte 2n is the low
half of word n and `top.v` picks the byte by `adr[0]`; the sim model
(`pk8000_rom` in `sim/stubs/gowin_ip_sim.v`) reads `mif.py binhex`'s
hex, which is the same layout.

## `tang/rom/`

| file | what |
|---|---|
| `pk8000_v12.rom` | 16384 bytes: ПК8000 BASIC 1.2, the ROM of the Сура and the Хобби (CRC32 a25b4b2c, MAME's `hobby.rom`).  From Emu80's distribution.  The one the design runs |
| `pk8000_fdc.rom` | 8192 bytes: the НГМД controller's ROM (expansion page 1, 0000h-1FFFh).  Not used yet |
| `pk8000_hdd.rom` | 9322 bytes: the community IDE/CF adapter's ROM.  Not used yet |
| `schematic_px3.099.001_lower_board.pdf` | the CPU board, redrawn by Mick (micklab.ru) from a Веста; 3 sheets |
| `schematic_px3.099.006_upper_board.pdf` | the video/memory board, the same |

micklab.ru also has BASIC 1.0 (Сура only), 1.1 (Сура and Веста), 1.2,
and the two 556РТ2 PLM dumps of the upper board (`d16firmware.JED`,
`d17firmware.JED`) - all in RAR5 archives, which `7z` on this host
reports as "Unsupported Method".  The PLM dumps are the one document
of the video controller's decode that exists; opening them needs
`unrar`, which is not installed (ask before adding it, or build it
into `tools/`).

## What is missing and would be worth having

- The PLM dumps read into equations, to check the wait model against
  the hardware rather than against Emu80's measurements.
- A `.cas` reader/player and `.fdd` support in `tools/` and the FPGA
  (`.claude/docs/progress.md`).
