# soft/ - software for the machine

What is here, where it came from, and what has been seen of it - in
simulation only, as of 4 September 2026; nothing has run on a board.

| file | what | seen |
|---|---|---|
| `cf.img` | the 2 MB IDE/CF card image Emu80 ships: P/M 2.2 and "most of the programs written for the ПК8000 except BASIC ones", among them STCPL.COM (the AY player) and DEMOAY.COM | boots to the P/M prompt with the IDE adapter in the expansion slot |
| `ayplayer.fdd` | a system floppy (DISK1 of the 2009 set of eighteen, P/M with its file-manager shell) with `STCPL.COM` 1.2 (MrDemonid's STC player, from github.com/MrDemonid/AY-Player) and `DEMOAY.COM` (from `cf.img`) added by `tools/mkfdd.py` | boots to the shell's A> prompt; `demoay` plays the AY card |
| `demo.bas` | the screen modes - text 40, text 32, graphics twice - plain text, a BASIC program as one types it (SCREEN 3 is border only on this machine and a syntax error in this BASIC) | loads through the OSD's "Run .bas" path in simulation (`+BAS=`); its frames found the mode-2 decode defect |
| `demo.cas` | the same as a cassette image (`tools/mkcas.py soft/demo.cas soft/demo.bas`) | |
| `hello.cas` | two lines that print TAPE OK, the tape test's file (`tools/mkcas.py soft/hello.cas`) | `cload"TEST` loads it, `run` prints TAPE OK |

The floppy has no STC tunes on it: none were to hand.  `STCPL.COM` reads
`.STC` files (the ZX Spectrum's Sound Tracker format) from the current
disk; put some on with `tools/mkfdd.py`.

The `.bas` form: a line number, a space, the text; keywords in either
case; strings and REM text as they are.  `tools/mkcas.py` and the
firmware's `mnano/bas.c` tokenise it the same way (`make bas-test`
checks that), with the ROM's own token table.
