# The CCBridge CBR / CBL formats

CCBridge (象棋桥) writes two related files: **`.cbr`**, one game, and
**`.cbl`**, a library holding many. A library is a header, an index, and then
the records themselves — each byte-for-byte the same structure a `.cbr`
holds.

Neither is encrypted. Both are fixed-offset structures with UTF-16LE text,
which makes them far easier to read than [XQF](xqf-format.md).

This document is based on [an existing write-up][zhihu] and on
[`app/lib/formats/ccbridge.dart`](../app/lib/formats/ccbridge.dart), checked
against 14 libraries holding 248 games: all parsed, and all 79,082 moves in
them were legal by an independent move generator. Where this document and the
write-up disagree, the differences are called out below — they are the places
where following the write-up literally will not parse real files.

[zhihu]: https://zhuanlan.zhihu.com/p/682174695

## A record (`.cbr`, and each entry of a `.cbl`)

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | `"CCBridge Record"` |
| 19 | 1 | Kind: 02 a record, 03 a newer format, 01 shows a dialog |
| 52 | 128 | Script file |
| 180 | 128 | Title |
| 308 | 256 | Category path |
| 564 | 64 | Source |
| 628 | 64 | Event category |
| 692 | 64 | Event |
| 756 | 64 | Round |
| 820 | 32 | Group |
| 852 | 32 | Board number |
| 884 | 64 | Date |
| 948 | 64 | Site |
| 1012 | 64 | Time rule |
| 1076 | 64 | Red player |
| 1140 | 64 | Red team |
| 1204 | 64 | Red time used |
| 1268 | 32 | Red score |
| 1300 | 64 | Black player |
| 1364 | 64 | Black team |
| 1428 | 64 | Black time used |
| 1492 | 32 | Black score |
| 1524 | 64 | Referee |
| 1588 | 64 | Recorder |
| 1652 | 64 | Commentator |
| 1716 | 64 | Commentator email |
| 1780 | 64 | Creator |
| 1844 | 64 | Creator email |
| 1908 | 40 | Created |
| 1972 | 40 | Last saved |
| 2040 | 1 | Game kind: 00 played opening, 01 composed opening, 02 played middle/endgame, 03 composed middle/endgame |
| 2044 | 32 | Nature of the game |
| 2076 | 1 | Result: 00 unknown, 01 Red wins, 02 Black wins, 03 draw, 04 several |
| 2080 | 32 | How it ended |
| 2112 | 1 | Who moves first: 01 Red, 02 Black |
| 2116 | 2 | Starting move number |
| 2120 | 90 | The board — see below |
| 2210 | 4 | Playback state; usually FF FF FF FF |
| 2214 | … | The move stream — see below |

Text fields are UTF-16LE, NUL-terminated within their fixed width, so a
64-byte field holds at most 31 characters.

A record occupies 4096 bytes in a library. A game with more moves than that
holds simply continues into the following slots.

### The board

Ninety bytes, one per square, laid out left to right and **top row first** —
so index 0 is Black's back rank and index 89 is Red's. Anything counting ranks
from Red's side, as ICCS and most engines do, needs the row flipped:

    rank = 9 - (index / 9)
    file = index % 9

Each byte packs colour in the high nibble and piece in the low:

| Nibble | Piece |
|---|---|
| 1 | Rook 车 |
| 2 | Horse 马 |
| 3 | Elephant 相/象 |
| 4 | Advisor 仕/士 |
| 5 | King 帅/将 |
| 6 | Cannon 炮 |
| 7 | Pawn 兵/卒 |

with `0x1n` for Red and `0x2n` for Black. So the opening position begins
`21 22 23 24 25 24 23 22 21` and ends `11 12 13 14 15 14 13 12 11`.

> **Differs from the write-up.** It lists these codes as decimal 11…17 and
> 21…27, and separately gives the piece order as 车马炮帅仕相兵 — which puts
> the cannon third. Both are wrong for real files: the values are hexadecimal,
> and the order is the one above, as its own board diagram shows. Reading them
> as decimal turns rooks into pawns and produces a position no engine will
> accept.

### The move stream

From offset 2214, four bytes per move:

| Byte | Meaning |
|---|---|
| 0 | Flags |
| 1 | Unused |
| 2 | From square, as a board index |
| 3 | To square |

Flags combine freely:

| Bit | Meaning |
|---|---|
| 0x01 | This line ends here |
| 0x02 | An alternative to this move appears later |
| 0x04 | A comment follows this record |

A comment is a 4-byte little-endian **byte** length followed by that many
bytes of UTF-16LE text — so the character count is half the length.

Reading is a stack walk:

    node    = root
    pending = []                     # moves that promised an alternative

    loop:
        read flags, from, to
        if flags & 0x04: read the comment
        play the move, attaching any comment to it
        if flags & 0x02: remember this move's parent in pending
        if flags & 0x01:
            if pending is empty: stop
            node = pending.pop()     # continue with the promised alternative

The moves that follow a pending branch point are **siblings** of the move that
set 0x02, not continuations of it.

> **Not in the write-up.** The stream opens with a record that is not a move:
> its square bytes are zero and only its flags and comment matter, carrying the
> annotation on the starting position. Treating it as a move yields a null move
> from square 0 to square 0 at the head of every game — which is exactly what a
> literal reading produces, in 101 of the 248 games checked here.

## A library (`.cbl`)

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | `"CCBridgeLibrary"` |
| 52 | 4 | FF FF FF 7F |
| 56 | 1 | Whether deleted entries are present |
| 60 | 4 | Slot count the index was built for |
| 64 | 512 | Library name |
| 576 | 256 | Source |
| 832 | 64 | Creator |
| 896 | 64 | Creator email |
| 960 | 64 | Created |
| 1024 | 64 | Last modified |
| 1088 | 65536 | Remarks |
| 66624 | 276 × slots | Index, one entry per slot |
| … | 4096 × n | The records |

### Where the records start

    first_record = 66624 + slot_count * 276

The index entry is 276 bytes and there is one per **slot**, not per game: a
library built for 128 slots holding a single game still puts its first record
at 66624 + 128 × 276 = 101952.

> **Differs from the write-up.** It gives two fixed offsets — 101952 for
> libraries of up to 128 records and 349248 beyond — which are just this
> formula evaluated at 128 and 1024 slots. A library built for any other
> number, 140 for instance, starts its records at 105264 and will not be found
> by either constant.

Records then follow on 4096-byte boundaries. Since a long game spans several
slots, the reliable way to enumerate them is to step 4096 bytes at a time from
the first record and take the offsets that actually carry the magic.

## Uninitialised memory

CCBridge writes whole structures without clearing them first, so the gaps
between documented fields contain whatever was in memory: stack addresses,
fragments of the program's own UI strings, pointers. It is harmless, but it
means **no structure can be inferred from the undocumented bytes** — they
differ between two saves of the same game. It also means these files leak
small amounts of whatever the machine was doing when they were written.

## See also

- [`app/lib/formats/ccbridge.dart`](../app/lib/formats/ccbridge.dart) — the
  reader this describes.
- [`ccbridge.ksy`](ccbridge.ksy) — a Kaitai Struct definition. Unlike XQF,
  nothing here is encrypted, so the whole format including the move stream is
  expressible.
- [The XQF format](xqf-format.md) — the other format this app reads.
