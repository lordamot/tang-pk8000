# The FPGA implementation

Target: **GW2AR-LV18QN88C8/I7** (GW2AR-18C, QFN88) - the Tang Nano 20K.
Project file `tang/pk8000.gprj`, top module `top` in `tang/src/top.v`,
constraints `tang/src/pk8000.cst` and `pk8000.sdc`.

## What is built

**`tang/pk8000.gprj` is the source of truth.**  Every file under
`tang/src/` is in it and every module is instantiated.  `tools/srcs.py`
reads the list for lint and simulation, `tools/gowin_tcl.py` for the
bitstream.

| role | files |
|---|---|
| top | `top.v` - the clock, the resets, the counters, the memory map, the mix, and every instance |
| the machine | `pk8000/vm80a.v` (the КР580ВМ80А, 1801BM1, verbatim), `pk8000/cpu8080.v` (its bus, the status decode, the interrupt, the wait model), `pk8000/waits_rom.v` (generated: the wait tables), `pk8000/sdram.v` (the 64 KB and the ROM disk above it), `pk8000/pk8000_rom.v` (generated: the BASIC ROM in pROMs), `pk8000/ports.v` (the ВВ55s, video registers, keyboard, joysticks), `pk8000/video.v` (the display) |
| the peripherals | `pk8000/sd_arbiter.v` (one owner on the SD path), `pk8000/tape.v` (the cassette player), `pk8000/fdc.v` + `pk8000/wd1793.sv` (MiSTer's ВГ93) + `pk8000/fdc_rom.v` (generated), `pk8000/ide.v` + `pk8000/hdd_rom.v` (generated), `pk8000/romdisk.v`, `pk8000/ay.v` + `pk8000/ym2149.sv` (UKNC Nano's), `pk8000/poke.v` (the MCU's bytes into the RAM), `pk8000/memcheck.v` (the debug window: a shadow of F000h-FFFFh checked against every read, CPU counters, 32 bytes for `sysctrl.v`'s CMD 7) |
| clock, sound | `sys_pll.v` (rPLL by hand: 27 -> 30 MHz), `i2s_tx.v` |
| MiSTeryNano | `mister/{mcu_spi,sysctrl,hid,osd_u8g2,sd_card,sd_rw,sdcmd_ctrl,sector_dpram}.v` - UKNC Nano's copies; `sysctrl.v` rewritten for this core's letters, `hid.v` given a keyboard strobe |
| HDMI | `hdmi/{hdmi_tx,tmds_channel,hdmi_packet,hdmi_serdes}.v` - UKNC Nano's encoder with audio; `hdmi_tx.v` at 30 MHz with three packets an island, `hdmi_serdes.v` at 150 MHz |

Stubbed in simulation (`tools/srcs.py`'s `STUBBED`): `sys_pll.v`,
`hdmi/hdmi_serdes.v`, the three generated ROMs and `mister/sector_dpram.v`
by `sim/stubs/gowin_ip_sim.v`; and `mister/sd_card.v` with `sd_rw.v` and
`sdcmd_ctrl.v` by `sim/stubs/sd_card_sim.v`, which serves image files
from the host on the same core-side interface (`+TAPE=`, `+FDDA=`,
`+FDDB=`, `+HDD=`, `+ROMDISK=`).

## Resources

```
Logic 33%   Register 18%   BSRAM 28/46 (61%)   PLL 2/2   [4 Sep 2026 PnR, v0.2.0 with memcheck.v]
clk30: needs 30 MHz, makes 55.4 MHz; 0 setup, 0 hold violations
v0.1.0 for comparison: Logic 17%, Register 10%, BSRAM 11/46, clk30 66.6 MHz
```

BSRAM: 17 blocks are pROMs - the BASIC ROM's eight, the НГМД's four,
the IDE adapter's five - and the other eight the line buffer, the OSD,
`sd_card.v`'s sector buffer and the peripherals' own (the tape's two
sectors, the ВГ93's 2 KB, the IDE's and the ROM disk's 512 bytes).  The
machine's 64 KB and the ROM disk are in the SDRAM.  The peripherals
took 12% of the logic and 7% of the registers between them.

## The clocks

```
clk27            27 MHz     the crystal, pin 4
  `- sys_pll (x10 / 9)
      |- clk           30 MHz   CLKOUT: everything
      `- O_sdram_clk   30 MHz   CLKOUTP, 90 degrees behind: the SDRAM pad only
  `- hdmi_ser/pll_hdmi (x5, referenced to clk)
      `- clk_serial   150 MHz   the four OSER10s
m0s[3]           20 MHz     the BL616's SPI clock, asynchronous, into mcu_spi.v
```

That is all of them.  Every flop of the design is on `clk`; the CPU's
T-state, the machine's pixel, the HDMI pixel and the I2S bit clock are
phases or enables of it (`top.v`'s `tphase` and `hcnt`; `i2s_tx.v`'s
counter).  `pk8000.sdc` declares `clk27`, `clk30` (on the PLL pin, which
replaces the tool's own derived clock there) and `spi_clk`, and puts the
SPI clock in an asynchronous group because `mcu_spi.v` crosses it by a
handshake; the serial clock the tool derives itself.  The PLL: IDIV 9
puts the phase detector at 3 MHz, the bottom of the rPLL's range; ODIV
32 puts the VCO at 960 MHz.  `.claude/rules/timing.md` is the rule that
keeps it this way.

## The timetable

The one idea the rest hangs on.  A T-state of the CPU is twelve clocks,
`tphase` 0..11, and it is cut into two six-clock SDRAM slots:

```
tphase   0   1   2   3   4   5   6   7   8   9  10  11
         F1  |---- video slot ----|  F2  |----- CPU slot -----|
             ACT RD/WR -  cap  -   -     ACT RD/WR -  cap  -   -
```

- `F1` (phase 0) and `F2` (phase 6) are the 8080's two clock phases as
  one-clock enables into vm80a.  Its SYNC and the status byte appear
  on the F2 edge, so at phase 7 `cpu8080.v` knows the cycle and the
  address, and that is the CPU slot's first clock: ACTIVE at 7, READ or
  WRITE at 8, the word captured at 10, in `cpu_rdata` for the core by
  phase 11 - long before it samples the bus (READY on F2 of T2, the
  data through T3).  So the SDRAM never makes the CPU wait, and the
  wait states the CPU does see are all the video controller's model.
- The video asks at phase 1 (`vid_req`) and has its byte at phase 6.
  One request a T-state is one byte per 400 ns: a tile of 8 pixels is
  4 T-states and needs 3 bytes (mode 2) or 2, so the fourth slot is
  free and refresh takes it (one every 7.8 us, counted as due and
  taken at the next free video slot).
- Writes are posted; a write and the read after it are in different
  T-states, so order is kept by construction.
- **Every access is ACTIVE, then READ or WRITE with auto-precharge (A10
  set), one row open for two clocks and closed by the chip itself**, so
  the next slot's ACTIVE finds its bank idle whatever row it wants.
  Until 5 Sep 2026 the column word had its 1 on A8, not A10 - UKNC
  Nano's `{5'b00100, col}` repacked into an 11-bit bus - and nothing
  precharged: every ACTIVE after the first was to a bank with a row
  open, which the part does not define.  On the board all 64 KB
  behaved as one 512-byte row (the third flash's Debug page:
  the stack's bytes came back as the zeros a later fill wrote), and the
  simulation model, which just opened the new row, booted BASIC.  The
  model honours A10 and refuses such an ACTIVE now, and reports the
  count at the end of a run.
- **The read is captured on slot clock 3** - the chip is clocked by the
  PLL's copy 90 degrees behind, takes the READ inside our clock 2 and,
  with CAS latency 2, has the word on the bus a third of the way into
  clock 3 until a quarter into clock 4 (`sdram.v`'s header).  The pads
  are not analysed by the tool, so **after `init` the controller tests
  itself**: four non-zero bytes to 0FFF0h-0FFF3h through the CPU slot,
  read back in the same order (a bus that echoes the last write does
  not pass).  If they do not come back it captures on clock 4 instead
  (`cap_late`) and tries again; a second failure raises `bist_fail` and
  puts the capture back.  Both are on the LEDs (`build.md`, reading the
  board) and in the testbench's end-of-run lines; `+SDRAM_LATE` makes the
  model a clock late and shows the move happening.  The CPU is in reset
  for 280 ms after `init`, the test takes 4 us.  Added after the first
  board (4 Sep 2026), which showed the ROM's zero-fill RAM test passing
  and the stack failing - defect 2's picture, on hardware.

No arbiter, no CDC, nothing that depends on placement.  The cost is
that everything that touches memory has to be a phase of `tphase`; a
new bus master takes a slot, it does not ask for one.

## The CPU bus

`cpu8080.v` gives one pulse a machine cycle: `mem_rd`/`io_rd` at phase
7 of the SYNC T-state with the address on `a_now` (the core's own
address bus, which the testbench checks does not move afterwards),
`mem_wr`/`io_wr` at the first phase 7 with WR/ low (F1 of T3) with the
latched address in `adr` and the data on `d_now`.  `top.v` turns the
address into a page through the bank register (`page_of`), sends RAM
reads and every write to the SDRAM, ROM reads to the pROMs (registered,
addressed by the latched `adr[13:1]`, the byte picked by `adr[0]`) and
I/O to `ports.v`, and `rd_src` remembers which of them the read in
flight will answer from: `cpu_din` is that mux and it is steady from
phase 0 of T2 to the end of the cycle.  An acknowledge cycle reads
0FFh.

## The wait model

`cpu8080.v` keeps the opcode of the instruction being executed, how
many machine cycles it took, and whether it came from ROM.  At the next
M1 it looks the instruction up in `waits_rom.v` (index {rom, the video
controller's `stall_wide`, opcode}), overrides the conditional
return/call rows by taken/not taken, adds 7 or 5 for an interrupt, and
loads `wcnt`; READY is `wcnt == 0` and `wcnt` counts down once per F2
sample, so exactly that many TW states go into the M1.  The OSD's 'w'
(`system_waits`) gates the load.  `.claude/docs/platform.md` says what
is known about the machine's own behaviour and what is not.

## Reset

`sdram.v`'s `init` (2.2 ms after PLL lock, then the initialisation
steps taken in video slots) is the root: `hcnt`/`tphase` run from PLL
lock (the SDRAM's steps need the timetable), the MiSTeryNano side
waits 2^23 clocks after `init` (`por_done`, 280 ms, as upstream) and
takes `mist_rst` until then, and the CPU is held by `cpu_rst` while
`mist_rst` or the OSD's 'R' bit 0 or `~init` is up and for 16 T-states
after (vm80a's reset is registered on both phases).  The MCU sends R=3
at start and R=0 when it has sent the settings, so the machine starts
when the OSD's values are in.  S1 (`buts[0]`, reads 1 pressed) resets
everything.

## Pinout

The board as UKNC Nano wires it, unchanged - `README.md` has the table.
The SDRAM is in the package and its pins are the tool's.  The USB-C
serial (pin 69) is driven idle; the ПК8000 has no serial port.

## The SD path

`sd_card.v` (MiSTeryNano's) has one sector interface for the machine:
request levels `rstart[4:0]`/`wstart[4:0]` one-hot by image slot, the
sector within the image, then `rbusy`, the 512 bytes on
`outen/outaddr/outbyte` (or taken from `inbyte` at `outaddr` for a
write), and `rdone`.  The MCU sees the request as an interrupt,
translates the sector through its file system and drives the card.
Five clients share it through `sd_arbiter.v`: slot 0 the tape, 1 and 2
the floppies (one controller; its drive bit picks the slot), 3 the hard
disk, 4 the ROM disk loader.  A client raises `rd`/`wr` with its
sector, gets `ack` as a level while it owns the path, the byte stream
gated to it, and `done`.  Only one request ever reaches `sd_card.v` at
a time, which the MCU's one-hot reading requires.

The expansion page: `top.v` routes a page-1 read to `fdc.v`, the IDE
ROM, or the SDRAM at `romdisk.v`'s address by the OSD's 'x', and a
page-1 write to the RAM under it and, with the floppy in, to `fdc.v`
as well.  `rd_src` grew from four sources to eight (RAM, ROM, ports,
FDC, HDD ROM, AY, IDE, none).

## The MCU's way into the RAM

`sysctrl.v`'s CMD 6 is an address and then any number of bytes; each
byte is a strobe into `poke.v`, a 16-deep queue that writes them
through the SDRAM's CPU port in T-states where the CPU makes no
request of its own - `top.v` ORs `poke_req` into `ram_req` behind
`mem_rd`/`mem_wr` at phase 7, so the CPU never waits and never sees
the write happen.  The ROM disk loader (which holds the CPU) has
priority over it.  The firmware's `bas.c` uses it to put a tokenised
BASIC program at 4001h and the ROM's pointers after it; the testbench's
`+BAS=` does the same from a `.tok` file.

## What is not there yet

Recording to tape, a second thing in the expansion slot at the same
time, the printer (its port is decoded, its data goes nowhere) - and
everything in `.claude/docs/progress.md`.
