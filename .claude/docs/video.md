# The display generator: `tang/src/pk8000/video.v`

One module does three jobs: it fetches what the ПК8000's video
controller would fetch, it renders each machine line into a line buffer
as the beam would have drawn it, and it reads that buffer back as an
HDMI raster.  All three run on the one 30 MHz clock and on the counters
`top.v` keeps: `hcnt` 0..1919 (the machine's line, 64 us), `vcnt`
0..307 (the frame), `tphase` 0..11 (the CPU's T-state, of which the
line is 160).

## The machine's raster

320 pixel slots of six clocks.  Where the picture is, by mode:

| mode | picture slots | clocks (x0..x1) | tile | clocks a tile |
|---|---|---|---|---|
| 0 (text 40) | 40..279, 240 px | 240..1679 | 6 px | 36 = 3 T-states |
| 1, 2 | 32..287, 256 px | 192..1727 | 8 px | 48 = 4 T-states |
| 3 | none | - | - | - |

Lines 71..262 are the picture, the rest border.  Both windows start on
a T-state boundary (240 = 20 x 12, 192 = 16 x 12) - that is what lets
the fetch be scheduled in T-states.  `stall_wide`, for the CPU's wait
model, is "a 40-column mode and inside x0..x1"; `frame_irq` is one clock
at line 263, slot 0.

Emu80 puts the mode-0 picture 14 slots to the right of the mode-1
picture and 16 narrower; this design centres both (8 slots of border
each side of a 40-column picture, within the 256-wide window the HDMI
side shows).  Nothing known depends on the horizontal position, and a
monitor's own centring moves it anyway.

## The fetch, one tile ahead

The SDRAM controller gives the video one six-clock slot in every
T-state, at phases 1..6, with the byte back at phase 6
(`.claude/docs/fpga.md`, the timetable).  A tile's data is two
dependent reads (name, then the pattern row) or three (name, pattern,
colour), one a T-state, so a tile's fetch fits in its own period with a
T-state to spare - and that spare one is where the SDRAM refreshes.

The fetch runs one tile ahead of the display: the fetch window is
`x0 - w6 .. x1 - w6`, so tile k is fetched during the display of tile
k-1 and the first tile during the border before the picture.  `ftst`
counts T-states within the tile period (0 name, 1 pattern, 2 colour in
mode 2), `ftile` the tile.  The result goes into `n_pat`/`n_fg`/`n_bg`
on the period's last clock and the display takes it at its next tile
boundary (`d_pat`, `d_fg`, `d_bg`).  In mode 1 the colours come from
the colour RAM by `name >> 3` at that moment; in mode 2 from the
fetched colour byte; in mode 0 from port 88h at every pixel.

Addresses (`a_name`, `a_pat`, `a_col`), with `scr = bank << 14`,
`row = line >> 3`, `lrow = line & 7`, `part = line >> 6`,
`row8 = (line >> 3) & 7`:

```
mode 0:  name = scr + ((txt & 0Eh) << 10) + row*64 + tile
         pat  = scr + ((sg  & 0Eh) << 10) + name*8 + lrow
mode 1:  name = scr + ( txt         << 10) + row*32 + tile
         pat  = scr + ((sg  & 0Eh) << 10) + name*8 + lrow
mode 2:  name = scr + ((sg  & 0Eh) << 10) + part*256 + row8*32 + tile
         pat  = scr + (gr_base << 13) + part*800h + name*8 + lrow
         col  = scr + (col_base << 13) + part*800h + name*8 + lrow
```

These are Emu80's `renderLine` written as addresses; MAME's
`video_update` agrees.  `gr_base` and `col_base` are the INVERTED bit 3
of ports 92h and 93h (`ports.v`).

## The render

At every clock `pix` is the colour of the current slot from what is
live now - `d_pat[7]` (the pattern shifts left once a slot), the tile's
colours, port 88h, DSCR, the mode, and whether the slot is inside the
picture - and on the slot's last clock it is written to `lbuf[wline,
slot]`.  Two lines of 320 x 4 bits; `wline` follows `vcnt[0]`.  Mode 1
with DSCR low gives white in the picture area (Emu80's `BS_BLANK`), the
other modes ignore DSCR - which is Emu80's model, not MAME's (which
blanks to black).  The eight-pixel background stripe Emu80 draws around
a colour RAM write while blanked (`BS_WRITE`) is not reproduced.

## The HDMI raster

Every machine line is read back twice as two output lines of 32 us:
960 clocks, three a slot, so `out_h = hcnt mod 960` and `out_v = 2*vcnt
+ (hcnt >= 960)`.  The picture is read from the OTHER line buffer, the
one the render finished on the previous machine line, through `oslot`
(a counter, not a divide) and a registered read, with the syncs
registered once alongside.

```
out_h: DE 96..863 (768 = slots 32..287), front porch 864..879,
       HSYNC 880..911 (active high), back porch 912..959 + 0..95 = 144
out_v: VSYNC 4..9 (active high), DE 38..613 (576 = machine lines 19..306)
```

768 x 576 in 960 x 616 at 30 MHz: 31.25 kHz lines, 50.73 Hz frames -
the machine's own rate, and not a CEA mode.  UKNC Nano's 51 Hz was
taken by the operator's television; this is the same kind of claim
and, as of 4 Sep 2026, untested.  The back porch is the data island's
home in `hdmi_tx.v` and 144 clocks fit three packets an island, not
UKNC Nano's four - `hdmi_tx.v` says what changed.

Colours: `{R, B, G, I}` to 8-bit components 00h / 0A8h / 0FFh in
`video.v`, then the OSD takes six bits of each and the encoder eight.

## What the simulation checks

`sim/tb/tb_top.v` decodes the TMDS words back into a frame and, with
`+VIDEO_PPM`, writes `sim/out/frame_NNNN.ppm` at 768 x 576 - the only
way to see the screen without a board, and a statement about
`hdmi_tx.v` as well as this module.  The end-of-run lines say the
frame size, the guard bands, the packet counts and their ECC.  The
render's correctness against the machine is a comparison of those
frames with Emu80's screen of the same ROM, by eye; there is no
automatic one.
