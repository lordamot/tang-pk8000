#!/usr/bin/env python3
"""Put files onto a ПК8000 floppy image (.fdd), or list one.

The Сура's НГМД disks are 80 tracks x 2 sides x 5 sectors x 1024 bytes
(819200 bytes, track-side-sector order) with a CP/M file system on them,
as read off the images in circulation (4 Sep 2026): the first two
cylinders (20 KB) are the system's, the directory is the two 2 KB blocks
after them (128 entries of 32 bytes), data blocks are 2 KB and numbered
from the directory's first block, allocation numbers are 16-bit, an
extent holds eight of them, and no sector skew was needed to read a
program back in one piece.  The same layout, with the directory at
8600h, is on the IDE/CF image (soft/cf.img).

    mkfdd.py out.fdd base.fdd FILE...   copy base.fdd, add the files
    mkfdd.py out.fdd - FILE...          a blank data disk (no system) with them
    mkfdd.py -l disk.fdd                list the directory

Names are the host file names, upper-cased to 8.3.  A file already on
the disk with that name is replaced.
"""
import os, sys

SIZE = 819200
DIR = 0x5000          # the directory's offset (two cylinders in)
BS = 2048             # a block
DIRBLKS = 2           # blocks of directory, 64 entries each
NBLK = (SIZE - DIR) // BS


def entries(img):
    out = []
    for i in range(DIRBLKS * BS // 32):
        o = DIR + i * 32
        e = img[o:o + 32]
        out.append(e)
    return out


def ent_name(e):
    return (bytes(c & 0x7F for c in e[1:9]).decode("ascii", "replace").rstrip() + "." +
            bytes(c & 0x7F for c in e[9:12]).decode("ascii", "replace").rstrip()).rstrip(".")


def used_blocks(img):
    used = set(range(DIRBLKS))
    for e in entries(img):
        if e[0] <= 15:
            for i in range(8):
                b = e[16 + 2 * i] | (e[17 + 2 * i] << 8)
                if b:
                    used.add(b)
    return used


def listing(img):
    files = {}
    for e in entries(img):
        if e[0] <= 15:
            n = ent_name(e)
            ex = e[12] | (e[14] << 5)
            files[n] = max(files.get(n, 0), ex * 16384 + e[15] * 128)
    for n in sorted(files):
        print(f"{files[n]:7d}  {n}")
    print(f"{len(files)} files, {len(used_blocks(img)) - DIRBLKS} of {NBLK - DIRBLKS} blocks used")


def cpm_name(path):
    base = os.path.basename(path).upper()
    name, _, ext = base.partition(".")
    return name[:8].ljust(8).encode("ascii"), ext[:3].ljust(3).encode("ascii")


def delete(img, name8, ext3):
    for i in range(DIRBLKS * BS // 32):
        o = DIR + i * 32
        if img[o] <= 15 and img[o + 1:o + 9] == name8 and img[o + 9:o + 12] == ext3:
            img[o] = 0xE5


def add(img, path):
    name8, ext3 = cpm_name(path)
    data = open(path, "rb").read()
    delete(img, name8, ext3)
    used = used_blocks(img)
    free = [b for b in range(DIRBLKS, NBLK) if b not in used]
    nblocks = (len(data) + BS - 1) // BS
    if nblocks > len(free):
        sys.exit(f"mkfdd: no room for {path}")
    blocks = free[:nblocks]
    for b, i in zip(blocks, range(0, len(data), BS)):
        chunk = data[i:i + BS]
        img[DIR + b * BS:DIR + b * BS + len(chunk)] = chunk
    # one directory entry per extent of up to eight blocks
    slots = [DIR + i * 32 for i in range(DIRBLKS * BS // 32) if img[DIR + i * 32] == 0xE5 or img[DIR + i * 32] > 15]
    nrec = (len(data) + 127) // 128
    for ex in range((nblocks + 7) // 8 or 1):
        if not slots:
            sys.exit("mkfdd: the directory is full")
        o = slots.pop(0)
        e = bytearray(32)
        e[0] = 0
        e[1:9] = name8
        e[9:12] = ext3
        e[12] = ex & 0x1F
        e[14] = ex >> 5
        recs = nrec - ex * 128
        e[15] = 128 if recs > 128 else recs
        for i, b in enumerate(blocks[ex * 8:ex * 8 + 8]):
            e[16 + 2 * i] = b & 0xFF
            e[17 + 2 * i] = b >> 8
        img[o:o + 32] = e
    print(f"{path}: {len(data)} bytes in {nblocks} block(s)")


def main():
    a = sys.argv[1:]
    if a and a[0] == "-l":
        listing(open(a[1], "rb").read())
        return
    out, base, files = a[0], a[1], a[2:]
    if base == "-":
        img = bytearray(b"\xE5" * SIZE)
        img[0:DIR] = b"\0" * DIR
    else:
        img = bytearray(open(base, "rb").read())
        if len(img) != SIZE:
            sys.exit(f"mkfdd: {base} is not an 819200-byte image")
    for f in files:
        add(img, f)
    open(out, "wb").write(img)
    listing(img)


if __name__ == "__main__":
    main()
