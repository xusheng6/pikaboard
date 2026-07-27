meta:
  id: xqf
  title: XQF Xiangqi game record (XQStudio)
  file-extension: xqf
  endian: le
  encoding: GB18030
  license: GPL-3.0-or-later

doc: |
  Game records written by XQStudio (象棋演播室) and the many programs that
  adopted its format: a 1024-byte plaintext header followed by a move tree
  whose bytes are obfuscated with a rolling key derived from that header.

  This describes the header completely. The move tree cannot be parsed by
  Kaitai alone, because its bytes must first be put through a subtraction
  cipher that Kaitai has no built-in process for: decrypt the region after
  the header yourself, then parse the result with the `tree_node` type below.

  Decryption, for the bytes at absolute file offsets 1024 onwards:

      key_source = "[(C) Copyright Mr. Dong Shiwei.]"      # exactly 32 chars
      b = [ (keys_sum  & key_mask) | key_or_a,
            (key_xy    & key_mask) | key_or_b,
            (key_xy_f  & key_mask) | key_or_c,
            (key_xy_t  & key_mask) | key_or_d ]
      stream_key[i] = ord(key_source[i]) & b[i % 4]        # i in 0..31
      plain[pos]    = (cipher[pos] - stream_key[pos % 32]) & 0xFF

  Note that the index runs on the absolute position in the file, not on an
  offset from the start of the tree. The header itself is produced by the same
  routine with all four key bytes zero, which is why it reads as plaintext.

  Three further keys are derived from the header, used inside the tree rather
  than on its bytes. In files of version 1.0 and older they are all zero:

      f(k)         = ((((( k*k )*3+9)*3+8)*2+1)*3+8)       # truncated to 8 bits
      key_xy'      = (f(key_xy)   * key_xy)   & 0xFF
      key_xy_f'    = (f(key_xy_f) * key_xy')  & 0xFF
      key_xy_t'    = (f(key_xy_t) * key_xy_f') & 0xFF
      key_remark   = ((keys_sum * 256 + key_xy) % 32000) + 767

  Reference: XQStudio's own XQFileRW.pas, by DONG Shiwei (董世伟), BSD
  licensed. Validated against 399 files in the wild.

seq:
  - id: signature
    contents: "XQ"
  - id: version
    type: u1
    doc: |
      Format version. 0x0A and below are unencrypted and pack the tree's child
      flags differently; 0x0C and above rotate the piece layout.
  - id: key_mask
    type: u1
  - id: product_id
    type: u4
  - id: key_or_a
    type: u1
  - id: key_or_b
    type: u1
  - id: key_or_c
    type: u1
  - id: key_or_d
    type: u1
  - id: keys_sum
    type: u1
    doc: The four key bytes sum to zero modulo 256 in a valid file.
  - id: key_xy
    type: u1
  - id: key_xy_f
    type: u1
  - id: key_xy_t
    type: u1
  - id: piece_layout
    size: 32
    doc: |
      Where each of the 32 pieces starts, in the fixed order

        red:   R N B A K A B N R C C P P P P P
        black: r n b a k a b n r c c p p p p p

      Each byte is obfuscated, and from version 0x0C the array itself is
      rotated. To read it (indices zero-based):

        if version >= 12: slot[(i + 1 + key_xy') % 32] = raw[i]
        else:             slot[i] = raw[i]
        value = (slot[i] - key_xy') & 0xFF

      A value above 89 means the piece is off the board. Otherwise it packs a
      square as file * 10 + rank, with file 0..8 running a..i and rank 0..9
      counted from Red's back rank.
  - id: start_ply
    type: u2
    doc: Ply the record starts from, for positions taken out of a longer game.
  - id: who_plays
    type: u1
    enum: side
  - id: result
    type: u1
    enum: result
  - id: node_count
    type: u4
    doc: Not maintained by every writer; treat as a hint.
  - id: tree_offset
    type: u4
    doc: Likewise unreliable — the tree follows the header in practice.
  - id: reserved_1
    size: 4
  - id: codes
    type: u2
    repeat: expr
    repeat-expr: 8
    doc: Opening and category codes used by XQStudio's own database.
  - id: title
    type: pascal_str(63)
    size: 64
  - id: title_secondary
    type: pascal_str(63)
    size: 64
  - id: event
    type: pascal_str(63)
    size: 64
  - id: date
    type: pascal_str(15)
    size: 16
  - id: site
    type: pascal_str(15)
    size: 16
  - id: red_player
    type: pascal_str(15)
    size: 16
  - id: black_player
    type: pascal_str(15)
    size: 16
  - id: time_rule
    type: pascal_str(63)
    size: 64
  - id: red_time
    type: pascal_str(15)
    size: 16
  - id: black_time
    type: pascal_str(15)
    size: 16
  - id: reserved_2
    size: 32
  - id: annotator
    type: pascal_str(15)
    size: 16
  - id: author
    type: pascal_str(15)
    size: 16
  - id: reserved_3
    size: 16
  - id: reserved_4
    size: 512
  - id: obfuscated_tree
    size-eos: true
    doc: |
      The move tree, still enciphered. Decrypt as described above, then parse
      the result as a sequence of `tree_node` records: the first is the
      starting position and each one is followed by its child, then its
      sibling, depth first.

instances:
  keys_valid:
    value: (keys_sum + key_xy + key_xy_f + key_xy_t) % 256 == 0
    doc: A file whose key bytes do not sum to zero is corrupt or not XQF.

types:
  pascal_str:
    doc: |
      A Delphi ShortString: one length byte, then that many bytes of text,
      then padding out to the field's fixed width.
    params:
      - id: capacity
        type: u1
    seq:
      - id: len
        type: u1
      - id: value
        type: str
        size: 'len > capacity ? capacity : len'
      - id: padding
        size: 'capacity - (len > capacity ? capacity : len)'

  tree_node:
    doc: |
      One move, in the decrypted tree. Records appear depth first: a node,
      then the node it continues into, then the alternative to it.

      The two squares are offset as well as keyed:

        from = (from_raw - 0x18 - key_xy_f') & 0xFF
        to   = (to_raw   - 0x20 - key_xy_t') & 0xFF

      and unpack as file * 10 + rank like the layout above. The first record
      in the tree describes the starting position, so its squares carry no
      move and should be ignored.

      Comment sizes are keyed too: the real length is
      (remark_size - key_remark), and only versions above 0x0A store the field
      conditionally.
    seq:
      - id: from_raw
        type: u1
      - id: to_raw
        type: u1
      - id: tag
        type: u1
      - id: reserved
        type: u1
      - id: remark_size
        type: u4
        if: has_remark
        doc: Present unconditionally in version 0x0A and below.
    instances:
      has_child:
        value: 'tag & 0x80 != 0'
        doc: |
          A continuation follows this record — the next move of the line.
          In version 0x0A and below the flag is any bit of the high nibble.
      has_sibling:
        value: 'tag & 0x40 != 0'
        doc: |
          An alternative to this very move follows after the child subtree.
          In version 0x0A and below the flag is any bit of the low nibble.
      has_remark:
        value: 'tag & 0x20 != 0'

enums:
  side:
    0: red
    1: black
  result:
    0: unknown
    1: red_wins
    2: black_wins
    3: draw
