# The XQF game record format

XQF is the game record format of **XQStudio** (象棋演播室) by DONG Shiwei
(董世伟), and by adoption the most widely shared Xiangqi record format there
is. A file holds one game: where it starts, who played it, the moves — with
every variation the annotator recorded — and a comment on any of them.

This document describes the format as implemented in
[`app/lib/formats/xqf.dart`](../app/lib/formats/xqf.dart) and machine-readably
in [`xqf.ksy`](xqf.ksy). It was written from XQStudio's own `XQFileRW.pas`
(BSD licensed) and checked against 399 files found in the wild: all parsed,
and all 36,194 moves in them were legal by an independent move generator.

## Shape

    ┌─────────────────────────────┐
    │ header, 1024 bytes          │  plaintext
    ├─────────────────────────────┤
    │ move tree                   │  obfuscated
    └─────────────────────────────┘

The tree is a depth-first walk of records, each a move plus flags saying what
follows it. Both halves go through the same cipher; the header simply comes
out unchanged because the key it is encrypted with is zero.

## Header

All little-endian. Offsets are decimal.

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0 | 2 | signature | `"XQ"` (0x58 0x51) |
| 2 | 1 | version | Format version; see [Versions](#versions) |
| 3 | 1 | key_mask | Mask used to build the stream key |
| 4 | 4 | product_id | Writing program's identifier |
| 8 | 4 | key_or_a…d | OR-ed into the four stream key bytes |
| 12 | 1 | keys_sum | Checksum byte |
| 13 | 1 | key_xy | Seed for the layout key |
| 14 | 1 | key_xy_f | Seed for the from-square key |
| 15 | 1 | key_xy_t | Seed for the to-square key |
| 16 | 32 | piece_layout | Starting square of each of the 32 pieces |
| 48 | 2 | start_ply | Ply this record starts from |
| 50 | 1 | who_plays | 0 = Red to move, 1 = Black |
| 51 | 1 | result | 0 unknown, 1 Red wins, 2 Black wins, 3 draw |
| 52 | 4 | node_count | Number of nodes; not maintained by every writer |
| 56 | 4 | tree_offset | Where the tree starts; in practice always 1024 |
| 60 | 4 | — | Reserved |
| 64 | 16 | codes | Eight 16-bit opening and category codes |
| 80 | 64 | title | Game title |
| 144 | 64 | title_secondary | Second title line |
| 208 | 64 | event | Competition |
| 272 | 16 | date | Free text, commonly `YYYYMMDD` |
| 288 | 16 | site | Venue |
| 304 | 16 | red_player | Red's name |
| 320 | 16 | black_player | Black's name |
| 336 | 64 | time_rule | Time control |
| 400 | 16 | red_time | Red's clock |
| 416 | 16 | black_time | Black's clock |
| 432 | 32 | — | Reserved |
| 464 | 16 | annotator | Who wrote the comments |
| 480 | 16 | author | Who made the file |
| 496 | 528 | — | Reserved |

Every text field is a **Delphi ShortString**: one length byte followed by that
many bytes of text, padded out to the field's fixed width. The text is
GB2312/GB18030 — decode accordingly, and expect the length byte to be capped
at the field's capacity rather than trusted blindly.

### Key checksum

A valid file satisfies

    (keys_sum + key_xy + key_xy_f + key_xy_t) mod 256 == 0

XQStudio refuses to open a file that fails this, and so should you: it is the
only integrity check the format has.

### Derived keys

Files of version 0x0A and older are unencrypted — all four derived keys are
zero. Otherwise, with byte arithmetic throughout (results truncated to 8
bits):

    f(k)        = ((((( k*k )*3 + 9)*3 + 8)*2 + 1)*3 + 8)

    KEY_XY      = f(key_xy)   * key_xy
    KEY_FROM    = f(key_xy_f) * KEY_XY
    KEY_TO      = f(key_xy_t) * KEY_FROM

    KEY_REMARK  = ((keys_sum * 256 + key_xy) mod 32000) + 767

`KEY_REMARK` is a 16-bit value, and note that it is **767 even when every key
byte is zero** — a writer that emits "unencrypted" files still has to add it
to comment lengths.

## Obfuscation

The body is enciphered byte by byte against a 32-byte rolling key built from a
copyright string:

    key_source = "[(C) Copyright Mr. Dong Shiwei.]"     # exactly 32 characters

    b = [ (keys_sum  & key_mask) | key_or_a,
          (key_xy    & key_mask) | key_or_b,
          (key_xy_f  & key_mask) | key_or_c,
          (key_xy_t  & key_mask) | key_or_d ]

    stream_key[i] = ord(key_source[i]) & b[i mod 4]      # i in 0..31

    plain[pos]  = (cipher[pos] - stream_key[pos mod 32]) mod 256    # reading
    cipher[pos] = (plain[pos]  + stream_key[pos mod 32]) mod 256    # writing

`pos` is the **absolute file offset**, not an offset within the tree, so the
first tree byte at 1024 uses `stream_key[0]` only because 1024 is a multiple
of 32.

Writing a file with all four key bytes zero is legal — the checksum is then
satisfied trivially and the stream key becomes all zeros, leaving the body in
the clear. XQStudio reads such files happily.

## Coordinates

A square is packed into one byte:

    xy = file * 10 + rank

with file 0…8 running left to right (a…i in ICCS terms) and rank 0…9 counted
from **Red's back rank**, which is the same orientation ICCS and most engines
use. Red's file numbering in Chinese notation runs the other way, so file 0 is
Red's 九 and file 8 is Red's 一.

## Starting position

`piece_layout` gives the square of each piece in a fixed order — Red's sixteen
then Black's sixteen, each as

    R N B A K A B N R C C P P P P P
    (rook horse elephant advisor king advisor elephant horse rook,
     cannon cannon, then five pawns)

From version 0x0C the array is also rotated by the layout key. Reading it,
with zero-based indices:

    if version >= 12:  slot[(i + 1 + KEY_XY) mod 32] = raw[i]
    else:              slot[i] = raw[i]

    square = (slot[i] - KEY_XY) mod 256

The rotation's `+ 1` comes from XQStudio indexing its array from one. A square
value above 89 means the piece is off the board — captured, or never placed in
a composed position.

## Move tree

Each record is four bytes, optionally followed by a comment length and the
comment itself:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | from square, offset by 0x18 |
| 1 | 1 | to square, offset by 0x20 |
| 2 | 1 | flags |
| 3 | 1 | reserved |
| 4 | 4 | comment length, when present |

The squares are keyed as well as offset:

    from = (from_raw - 0x18 - KEY_FROM) mod 256
    to   = (to_raw   - 0x20 - KEY_TO)   mod 256

and unpack as `file * 10 + rank` like the layout.

Flags, for versions above 0x0A:

| Bit | Meaning |
|---|---|
| 0x80 | A continuation follows: the next move of this line |
| 0x40 | An alternative to *this* move follows, after the continuation's subtree |
| 0x20 | A comment length and comment follow this record |

Version 0x0A and below pack them differently: any bit of the high nibble means
a continuation, any bit of the low nibble means an alternative, and the
comment length is **always** present, whether or not there is a comment.

When a comment is present its stored length is keyed:

    length = stored_length - KEY_REMARK

then that many bytes of GB2312/GB18030 text follow, still enciphered like
everything else.

### Tree shape

The layout is left-child / right-sibling. Reading a record:

1. Take the record. Its move is a move of the game.
2. If 0x80 is set, the **next** record is its continuation — recurse with it
   as the parent.
3. If 0x40 is set, the record after that subtree is an **alternative to this
   same move** — recurse with the same parent.

Which maps onto the usual game-tree shape, where a node's children are its
continuations and the first child is the main line:

    record.child   -> node.children[0]
    record.sibling -> parent.children[1..]

The **first record in the tree is the starting position**, not a move: its
square bytes are meaningless and should be ignored, but its comment is the
game's opening remark. In practice its 0x40 bit is unset; if it is set, the
sensible reading is an alternative first move.

## Versions

| Version | Behaviour |
|---|---|
| ≤ 0x0A | No encryption; flags packed by nibble; comment length always present |
| 0x0B | Encrypted; flags as documented; layout not rotated |
| ≥ 0x0C | As 0x0B, plus the piece layout array is rotated by `KEY_XY` |

Version 0x12 (18) is what current writers produce and what all 399 sample
files use.

## Practical notes

- **Trust the moves, not the counters.** `node_count` and `tree_offset` are
  written inconsistently; walking the tree is authoritative.
- **A record can be unplayable.** Composed positions and damaged files do
  occur; a reader is better off ending that line than rejecting the file.
- **Comments are the point.** Of the 399 files checked, 1,292 nodes carried a
  comment and 848 were branch points — this format is used for annotated
  study material at least as much as for bare game scores.

## See also

- [`xqf.ksy`](xqf.ksy) — Kaitai Struct definition of the header, and of a tree
  record for use after decryption. Kaitai has no built-in process for a
  subtraction cipher, so the body must be decrypted before parsing. The
  compiler warns that `GB18030` is an unrecognised encoding name; the
  generated code passes it to the target language's decoder, which knows it.
- [`app/lib/formats/xqf.dart`](../app/lib/formats/xqf.dart) — the reader this
  document describes.
- XQStudio's `XQFileRW.pas` — the original, and the final authority.
