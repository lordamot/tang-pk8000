#!/usr/bin/env python3
"""Write a .cas (fMSX cassette image) of a small tokenised BASIC program.

The ПК8000's BASIC is MSX's, and a CLOAD-able file on tape is: a header
tone, ten bytes of D3h, a six-character name, another header tone, then
the program as it sits in memory - for each line, a two-byte link to the
next line (an ABSOLUTE address, the program starting at 4001h on this
machine, which is what Emu80's Pk8000FileLoader assumes too), a two-byte
line number, the tokenised text, a zero; two zero bytes at the end; and
then a trailer of zero bytes, of which the loader reads eight.
In a .cas each header tone is the eight bytes 1F A6 DE BA CC 13 7D 74 at
an 8-aligned position.

    mkcas.py out.cas            the built-in test program
    mkcas.py out.cas prog.txt   lines of "10 PRINT "..."" - a few keywords only
    mkcas.py --tok out.tok prog.txt   the program alone, as it sits at 4001h
                                (what the firmware's bas.c and the
                                testbench's +BAS= put into the RAM)
    mkcas.py --header mnano/pk8000_tokens.h   the table for the firmware

The tokens are the ROM's own, read out of tang/rom/pk8000_v12.rom: its
reserved-word table (at 3170h, each word's last letter with bit 7 set,
CLS first) is NOT MSX-BASIC's - PRINT is 95h here, 91h there - which a
RAM dump of a line typed at the keyboard showed (4 Sep 2026).  The
first word is token 80h, by that measurement.  Numbers are NOT encoded:
a RAM dump of "pset(10,20),15:a=-3/2+7*8" typed at the keyboard holds
the digits as text, with the operators as tokens (A4h + A5h - A6h *
ACh =) and the letters outside strings in capitals.  That is the whole
of the format: keywords and operators to tokens, the rest as typed, in
capitals, strings and a REM's text verbatim.  mnano/bas.c does the
same in the firmware and mnano/pk8000_tokens.h (--header) is its table.

The text is UTF-8 and the machine's character set is КОИ-8 (the ROM's
banner spells "версия" D7 C5 D2 D3 C9 D1, "ПК" F0 EB - KOI8-R's
letters).  A Cyrillic letter becomes its KOI8-R byte wherever it
stands; Ё/ё (B3h/A3h in KOI8-R, not known to be in the Сура's font) and
every other non-ASCII character become '*', as in bas.c.
"""
import os, struct, sys

# а..я in KOI8-R (the table's own order, not the alphabet's); А..Я is +20h
KOI8_LOWER = [0xC1, 0xC2, 0xD7, 0xC7, 0xC4, 0xC5, 0xD6, 0xDA, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0,
              0xD2, 0xD3, 0xD4, 0xD5, 0xC6, 0xC8, 0xC3, 0xDE, 0xDB, 0xDD, 0xDF, 0xD9, 0xD8, 0xDC, 0xC0, 0xD1]


def koi8(text):
    """The machine's bytes for a string: ASCII as is, Cyrillic KOI-8, else '*'."""
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if cp < 0x80:
            out.append(cp)
        elif 0x430 <= cp <= 0x44F:
            out.append(KOI8_LOWER[cp - 0x430])
        elif 0x410 <= cp <= 0x42F:
            out.append(KOI8_LOWER[cp - 0x410] + 0x20)
        else:
            out.append(ord("*"))
    return bytes(out)

HEADER = bytes([0x1F, 0xA6, 0xDE, 0xBA, 0xCC, 0x13, 0x7D, 0x74])
ROM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tang", "rom", "pk8000_v12.rom")
BASE = 0x4001


def rom_tokens():
    """The reserved words of the ROM, {word: token}, from its table."""
    rom = open(ROM, "rb").read()
    # the ROM has two copies of the start of the list (one at 0088h, 40
    # words long); the whole table is the longer one, at 3170h
    best = []
    i = rom.find(b"CL\xd3FO\xd2NEX\xd4")
    while i >= 0:
        words, cur, j = [], "", i
        while rom[j] != 0:
            cur += chr(rom[j] & 0x7F)
            if rom[j] & 0x80:
                words.append(cur)
                cur = ""
            j += 1
        if len(words) > len(best):
            best = words
        i = rom.find(b"CL\xd3FO\xd2NEX\xd4", i + 1)
    if len(best) < 100:
        sys.exit("mkcas: no keyword table in " + ROM)
    return {w: 0x80 + n for n, w in enumerate(best)}


TOKENS = rom_tokens()

DEFAULT = ['10 PRINT "TAPE OK"', '20 END']


def tokenise(text):
    out = bytearray()
    i = 0
    while i < len(text):
        c = text[i]
        # after REM (or its ') the rest of the line is kept as it is
        if out and out[-1] in (TOKENS["REM"], TOKENS["'"]):
            out += koi8(text[i:])
            break
        if c == '"':
            j = text.find('"', i + 1)
            if j < 0:
                j = len(text) - 1            # an unclosed string runs to the end of the line
            out += koi8(text[i:j + 1])
            i = j + 1
            continue
        if ord(c) >= 0x80:                   # Cyrillic outside a string: as it is
            out += koi8(c)
            i += 1
            continue
        # the longest reserved word here, letters or an operator (the
        # table has + - * / ^ = < > and the ones ending in $ or in "(")
        best = ""
        for w in TOKENS:
            if text[i:i + len(w)].upper() == w and len(w) > len(best):
                best = w
        if best:
            out.append(TOKENS[best])
            i += len(best)
            continue
        out += c.upper().encode("ascii", "replace")
        i += 1
    return bytes(out)


def header(path):
    """mnano/pk8000_tokens.h: the table for the firmware's tokeniser."""
    words = sorted(TOKENS, key=lambda w: (-len(w), w))     # longest first
    with open(path, "w") as f:
        f.write("// pk8000_tokens.h - GENERATED by tools/mkcas.py --header from the\n"
                "// reserved-word table in tang/rom/pk8000_v12.rom (3170h).  Do not edit.\n"
                "// Longest word first, so a tokeniser can take the first match.\n\n"
                "static const struct { const char *word; unsigned char token; } pk8000_tokens[] = {\n")
        for w in words:
            f.write('  { "%s", 0x%02X },\n' % (w.replace("\\", "\\\\").replace('"', '\\"'), TOKENS[w]))
        f.write("  { 0, 0 }\n};\n")
    print(f"{path}: {len(words)} words")


def program(lines):
    body = bytearray()
    addr = BASE
    for line in lines:
        num, _, text = line.strip().partition(" ")
        tok = tokenise(text)
        ln = 2 + 2 + len(tok) + 1
        addr += ln
        body += struct.pack("<H", addr) + struct.pack("<H", int(num)) + tok + b"\0"
    body += b"\0\0"
    return bytes(body)


def pad8(b):
    return b + b"\0" * ((-len(b)) % 8)


def main():
    args = sys.argv[1:]
    tok = False
    if args and args[0] == "--header":
        header(args[1])
        return
    if args and args[0] == "--tok":
        tok = True
        args = args[1:]
    out = args[0]
    lines = open(args[1], encoding="utf-8", errors="replace").read().lstrip("\ufeff").splitlines() if len(args) > 1 else DEFAULT
    lines = [l for l in lines if l.strip()]
    if tok:
        body = program(lines)
        open(out, "wb").write(body)
        print(f"{out}: {len(body)} bytes, {len(lines)} lines")
        return
    # this ROM's CLOAD skips a file whose name is not the string given
    # ("Skip :TEST" for cload" with the name empty, 4 Sep 2026); the
    # testbench types cload"TEST
    name = b"TEST  "
    cas = HEADER + bytes([0xD3] * 10) + name
    # the loader reads on past the program's own 00 00: with a trailer of
    # seven zeros (what MSX's CSAVE writes) it still asked for an eighth
    # byte, and a tape that has stopped is "Device I/O error" with the
    # whole program already in memory; with 32 it stopped by itself at
    # the eighth (measured in simulation, 4 Sep 2026).  Sixteen is safe.
    cas = pad8(cas) + HEADER + program(lines) + b"\0" * 16
    open(out, "wb").write(cas)
    print(f"{out}: {len(cas)} bytes, {len(lines)} lines")


if __name__ == "__main__":
    main()
