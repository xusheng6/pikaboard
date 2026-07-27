meta:
  id: ccbridge
  title: CCBridge Xiangqi game record and library
  file-extension:
    - cbr
    - cbl
  endian: le
  encoding: UTF-16LE
  license: GPL-3.0-or-later

doc: |
  Files written by CCBridge (象棋桥): `.cbr` holds one game, `.cbl` a library
  of many. Nothing is encrypted, so unlike XQF the whole format — including
  the move stream — is expressible here.

  Two warnings for anyone reading these files. The gaps between documented
  fields hold uninitialised memory, so nothing can be inferred from them; and
  a library's records do not start at a fixed offset, but after an index sized
  by the slot count in the header.

  See ccbridge-format.md alongside this file for the details, including where
  it departs from the published write-up.

seq:
  - id: magic
    size: 16
    type: str
    encoding: ASCII
    doc: '"CCBridgeLibrary" or "CCBridge Record", NUL padded.'
  - id: body
    type:
      switch-on: kind
      cases:
        'file_kind::library': library
        'file_kind::record': record_body

instances:
  kind:
    value: >-
      magic.substring(0, 15) == "CCBridgeLibrary" ? file_kind::library
      : (magic.substring(0, 15) == "CCBridge Record" ? file_kind::record
      : file_kind::unknown)

types:
  library:
    doc: A header, an index sized by the slot count, then the records.
    seq:
      - id: reserved_1
        size: 36
      - id: limit
        type: u4
        doc: Always 0x7FFFFFFF in files seen.
      - id: has_deleted
        type: u1
      - id: reserved_2
        size: 3
      - id: num_index
        type: u4
        doc: |
          How many slots the index was built for — not the number of games.
          Named for Kaitai's convention on repeat counts; the format document
          calls it the slot count.
      - id: name
        type: strz
        size: 512
      - id: source
        type: strz
        size: 256
      - id: creator
        type: strz
        size: 64
      - id: creator_email
        type: strz
        size: 64
      - id: created
        type: strz
        size: 64
      - id: modified
        type: strz
        size: 64
      - id: remarks
        type: strz
        size: 65536
      - id: index
        type: index_entry
        size: 276
        repeat: expr
        repeat-expr: num_index
    instances:
      first_record_offset:
        value: 66624 + num_index * 276
        doc: |
          Records follow the index on 4096-byte boundaries. A game longer than
          one slot simply continues into the next, so enumerate by stepping
          4096 bytes and taking the offsets that carry the record magic rather
          than assuming one record per slot.

  index_entry:
    doc: |
      A summary of one slot. Only the name is reliably useful; the rest of the
      entry is largely uninitialised.
    seq:
      - id: state
        type: u4
      - id: order
        type: u4
      - id: reserved_1
        size: 12
      - id: reserved_2
        size: 80
      - id: name
        type: strz
        size: 128

  record_body:
    doc: The record structure, less the magic that precedes it.
    seq:
      - id: reserved_1
        size: 3
      - id: kind
        type: u1
        enum: record_kind
      - id: reserved_2
        size: 32
      - id: script
        type: strz
        size: 128
      - id: title
        type: strz
        size: 128
      - id: category_path
        type: strz
        size: 256
      - id: source
        type: strz
        size: 64
      - id: event_category
        type: strz
        size: 64
      - id: event
        type: strz
        size: 64
      - id: round
        type: strz
        size: 64
      - id: group
        type: strz
        size: 32
      - id: board_number
        type: strz
        size: 32
      - id: date
        type: strz
        size: 64
      - id: site
        type: strz
        size: 64
      - id: time_rule
        type: strz
        size: 64
      - id: red_player
        type: strz
        size: 64
      - id: red_team
        type: strz
        size: 64
      - id: red_time
        type: strz
        size: 64
      - id: red_score
        type: strz
        size: 32
      - id: black_player
        type: strz
        size: 64
      - id: black_team
        type: strz
        size: 64
      - id: black_time
        type: strz
        size: 64
      - id: black_score
        type: strz
        size: 32
      - id: referee
        type: strz
        size: 64
      - id: recorder
        type: strz
        size: 64
      - id: commentator
        type: strz
        size: 64
      - id: commentator_email
        type: strz
        size: 64
      - id: creator
        type: strz
        size: 64
      - id: creator_email
        type: strz
        size: 64
      - id: created
        type: strz
        size: 40
      - id: reserved_3
        size: 24
      - id: modified
        type: strz
        size: 40
      - id: reserved_4
        size: 24
      - id: game_kind
        type: u1
        enum: game_kind
      - id: reserved_5
        size: 3
      - id: nature
        type: strz
        size: 32
      - id: result
        type: u1
        enum: result
      - id: reserved_6
        size: 3
      - id: ending
        type: strz
        size: 32
      - id: first_mover
        type: u1
        enum: side
      - id: reserved_7
        size: 3
      - id: start_move_number
        type: u2
      - id: reserved_8
        size: 2
      - id: board
        size: 90
        doc: |
          One byte per square, left to right and top row first, so index 0 is
          Black's back rank. Colour is the high nibble — 1 Red, 2 Black — and
          the piece the low: 1 rook, 2 horse, 3 elephant, 4 advisor, 5 king,
          6 cannon, 7 pawn. Note these are hexadecimal, not the decimal 11…17
          the published write-up gives.
      - id: playback_state
        type: u4
      - id: opening
        type: move
        doc: |
          Not a move: the record that opens the stream carries only flags and
          the comment on the starting position.
      - id: moves
        type: move
        repeat: until
        repeat-until: _.ends_line and not _.has_alternative

  move:
    doc: |
      One move, or the opening record. Reading is a stack walk: a move with
      `has_alternative` promises a sibling later, and when a line ends the
      next move belongs to the most recently promised branch.

      This flat repeat-until therefore reads the stream but does not rebuild
      the tree; do that from `flags` as the format document describes. The
      terminating condition here is approximate for the same reason — it stops
      at the first line end that has no outstanding branch.
    seq:
      - id: flags
        type: u1
      - id: reserved
        type: u1
      - id: from_square
        type: u1
      - id: to_square
        type: u1
      - id: comment_size
        type: u4
        if: has_comment
        doc: In bytes, so half this many UTF-16 characters.
      - id: comment
        type: str
        size: comment_size
        if: has_comment
    instances:
      ends_line:
        value: 'flags & 0x01 != 0'
      has_alternative:
        value: 'flags & 0x02 != 0'
      has_comment:
        value: 'flags & 0x04 != 0'

enums:
  file_kind:
    0: unknown
    1: library
    2: record
  record_kind:
    1: dialog
    2: record
    3: newer_format
  side:
    1: red
    2: black
  result:
    0: unknown
    1: red_wins
    2: black_wins
    3: draw
    4: several
  game_kind:
    0: played_opening
    1: composed_opening
    2: played_endgame
    3: composed_endgame
