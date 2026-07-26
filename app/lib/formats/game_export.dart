import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';

/// Marker the annotator uses inside a comment to ask for a board diagram.
const String kBoardMarker = '[board]';

/// Turns a game into something readable outside the app.
///
/// Text export keeps the annotator's shape — two columns of moves with notes
/// indented underneath — and leaves `[board]` as a `[screenshot]` placeholder.
/// HTML export draws those markers as real board diagrams in SVG, so it prints
/// to PDF from a browser and opens in a word processor without needing an
/// image pipeline or an embedded CJK font.
class GameExport {
  const GameExport._();

  static String toText(
    Game game, {
    DisplayLanguage language = DisplayLanguage.simplified,
  }) {
    final out = StringBuffer();
    final metadata = game.metadata;
    out.writeln('=' * 50);
    out.writeln(metadata.title.isEmpty ? '象棋棋谱' : metadata.title);
    out.writeln('=' * 50);
    out.writeln();
    for (final line in _metadataLines(metadata)) {
      out.writeln(line);
    }
    out.writeln('初始局面 FEN: ${game.initialPosition.toFen()}');
    out.writeln();
    out.writeln('[screenshot]');
    out.writeln();
    if (game.root.comment.isNotEmpty) {
      out.writeln('【初始局面注释】');
      out.writeln(_plainComment(game.root.comment));
      out.writeln();
    }

    out.writeln('-' * 50);
    out.writeln('着法记录');
    out.writeln('-' * 50);
    out.writeln();

    final moves = _mainline(game);
    for (var i = 0; i < moves.length; i += 2) {
      final number = (i ~/ 2) + 1;
      final red = moves[i];
      final black = i + 1 < moves.length ? moves[i + 1] : null;
      final redText = _notation(red, language);
      final blackText = black == null ? '' : _notation(black, language);

      if (red.comment.isNotEmpty) {
        out.writeln(
          '${number.toString().padLeft(3)}. '
          '${redText.padRight(12)}  ......',
        );
        for (final line in _plainComment(red.comment).split('\n')) {
          out.writeln('     $line');
        }
        if (black != null) {
          out.writeln(
            '${number.toString().padLeft(3)}. '
            '${'......'.padRight(12)}  $blackText',
          );
        }
      } else {
        out.writeln(
          '${number.toString().padLeft(3)}. '
          '${redText.padRight(12)}  $blackText',
        );
      }

      if (black != null && black.comment.isNotEmpty) {
        for (final line in _plainComment(black.comment).split('\n')) {
          out.writeln('     $line');
        }
      }

      // Alternatives to either move of this pair.
      for (final node in [red, ?black]) {
        for (final variation in _siblings(node)) {
          out.writeln('     变着: ${_lineText(variation, language)}');
        }
      }
    }

    if (metadata.result != GameResult.unknown) {
      out.writeln();
      out.writeln('结果: ${resultText(metadata.result)}');
    }
    return out.toString();
  }

  static String toHtml(
    Game game, {
    DisplayLanguage language = DisplayLanguage.simplified,
  }) {
    final out = StringBuffer();
    final metadata = game.metadata;
    final title = metadata.title.isEmpty ? '象棋棋谱' : metadata.title;

    out.writeln('<!DOCTYPE html>');
    out.writeln('<html lang="zh"><head><meta charset="utf-8">');
    out.writeln('<title>${_escape(title)}</title>');
    out.writeln('<style>');
    out.writeln(
      'body{font-family:"PingFang SC","Songti SC","Microsoft YaHei",serif;'
      'max-width:44em;margin:2em auto;padding:0 1em;line-height:1.7;color:#222}'
      'h1{font-size:1.5em;margin-bottom:.2em}'
      '.meta{color:#666;font-size:.9em;margin-bottom:1.5em}'
      '.moves{width:100%;border-collapse:collapse}'
      '.moves td{padding:.15em .4em;vertical-align:top}'
      '.num{color:#888;text-align:right;width:3em}'
      '.mv{width:7em}'
      '.note{color:#333;background:#f6f6f4;padding:.5em .8em;margin:.3em 0 .6em;'
      'border-left:3px solid #c62828;white-space:pre-wrap}'
      '.var{color:#555;font-size:.95em;margin:.2em 0 .2em 1.5em}'
      'figure{margin:1em 0;text-align:center}',
    );
    out.writeln('</style></head><body>');
    out.writeln('<h1>${_escape(title)}</h1>');

    final metaLines = _metadataLines(metadata);
    if (metaLines.isNotEmpty) {
      out.writeln(
        '<div class="meta">${metaLines.map(_escape).join('<br>')}</div>',
      );
    }

    out.writeln(_diagram(game.initialPosition, language));
    if (game.root.comment.isNotEmpty) {
      out.writeln(
        _commentHtml(game.root.comment, game.root.position, language),
      );
    }

    out.writeln('<table class="moves">');
    final moves = _mainline(game);
    for (var i = 0; i < moves.length; i += 2) {
      final number = (i ~/ 2) + 1;
      final red = moves[i];
      final black = i + 1 < moves.length ? moves[i + 1] : null;
      out.writeln(
        '<tr><td class="num">$number.</td>'
        '<td class="mv">${_escape(_notation(red, language))}</td>'
        '<td class="mv">${black == null ? '' : _escape(_notation(black, language))}</td></tr>',
      );
      for (final node in [red, ?black]) {
        for (final variation in _siblings(node)) {
          out.writeln(
            '<tr><td></td><td colspan="2"><div class="var">变着: '
            '${_escape(_lineText(variation, language))}</div></td></tr>',
          );
        }
        if (node.comment.isNotEmpty) {
          out.writeln(
            '<tr><td></td><td colspan="2">'
            '${_commentHtml(node.comment, node.position, language)}</td></tr>',
          );
        }
      }
    }
    out.writeln('</table>');

    if (metadata.result != GameResult.unknown) {
      out.writeln('<p class="meta">结果: ${resultText(metadata.result)}</p>');
    }
    out.writeln('</body></html>');
    return out.toString();
  }

  /// A comment as HTML, with `[board]` markers replaced by a diagram of the
  /// position the note belongs to.
  static String _commentHtml(
    String comment,
    Position position,
    DisplayLanguage language,
  ) {
    final parts = comment.split(kBoardMarker);
    final out = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      final text = parts[i].trim();
      if (text.isNotEmpty) {
        out.writeln('<div class="note">${_escape(text)}</div>');
      }
      if (i < parts.length - 1) out.writeln(_diagram(position, language));
    }
    return out.toString();
  }

  /// The position drawn as an SVG board, so exports need no image pipeline.
  static String _diagram(Position position, DisplayLanguage language) {
    const cell = 44.0;
    const margin = 22.0;
    final width = margin * 2 + cell * 8;
    final height = margin * 2 + cell * 9;
    double x(int file) => margin + cell * file;
    double y(int rank) => margin + cell * (9 - rank);

    final svg = StringBuffer();
    svg.write(
      '<figure><svg xmlns="http://www.w3.org/2000/svg" width="$width" '
      'height="$height" viewBox="0 0 $width $height">',
    );
    svg.write('<rect width="$width" height="$height" fill="#f0d9a8"/>');

    // Ranks, then files broken at the river except on the edges.
    for (var rank = 0; rank < Position.ranks; rank++) {
      svg.write(
        '<line x1="${x(0)}" y1="${y(rank)}" x2="${x(8)}" y2="${y(rank)}" '
        'stroke="#000" stroke-width="1"/>',
      );
    }
    for (var file = 0; file < Position.files; file++) {
      if (file == 0 || file == 8) {
        svg.write(
          '<line x1="${x(file)}" y1="${y(0)}" x2="${x(file)}" y2="${y(9)}" '
          'stroke="#000" stroke-width="1"/>',
        );
      } else {
        svg.write(
          '<line x1="${x(file)}" y1="${y(0)}" x2="${x(file)}" y2="${y(4)}" '
          'stroke="#000" stroke-width="1"/>'
          '<line x1="${x(file)}" y1="${y(5)}" x2="${x(file)}" y2="${y(9)}" '
          'stroke="#000" stroke-width="1"/>',
        );
      }
    }
    // Palace diagonals.
    for (final base in [0, 7]) {
      svg.write(
        '<line x1="${x(3)}" y1="${y(base)}" x2="${x(5)}" y2="${y(base + 2)}" '
        'stroke="#000" stroke-width="1"/>'
        '<line x1="${x(5)}" y1="${y(base)}" x2="${x(3)}" y2="${y(base + 2)}" '
        'stroke="#000" stroke-width="1"/>',
      );
    }
    svg.write(
      '<text x="${width / 2}" y="${(y(4) + y(5)) / 2 + 6}" '
      'text-anchor="middle" font-size="18" fill="#555">楚河　　汉界</text>',
    );

    for (var square = 0; square < Position.squareCount; square++) {
      final piece = position.pieceAt(square);
      if (piece == null) continue;
      final file = square % Position.files;
      final rank = square ~/ Position.files;
      final colour = piece.color == PieceColor.red ? '#c62828' : '#222';
      svg.write(
        '<circle cx="${x(file)}" cy="${y(rank)}" r="18" fill="#fff8dc" '
        'stroke="$colour" stroke-width="2"/>'
        '<text x="${x(file)}" y="${y(rank) + 7}" text-anchor="middle" '
        'font-size="20" fill="$colour">${_escape(piece.labelFor(language))}</text>',
      );
    }

    svg.write('</svg></figure>');
    return svg.toString();
  }

  static List<String> _metadataLines(GameMetadata metadata) => [
    if (metadata.event.isNotEmpty) '赛事: ${metadata.event}',
    if (metadata.site.isNotEmpty) '地点: ${metadata.site}',
    if (metadata.date.isNotEmpty) '日期: ${metadata.date}',
    if (metadata.red.isNotEmpty || metadata.black.isNotEmpty)
      '红方: ${metadata.red}    黑方: ${metadata.black}',
    if (metadata.annotator.isNotEmpty) '评注: ${metadata.annotator}',
  ];

  static String resultText(GameResult result) => switch (result) {
    GameResult.redWin => '红胜',
    GameResult.blackWin => '黑胜',
    GameResult.draw => '和棋',
    GameResult.unknown => '未知',
  };

  /// Main line as a flat list of nodes.
  static List<GameNode> _mainline(Game game) {
    final nodes = <GameNode>[];
    var node = game.root;
    while (node.children.isNotEmpty) {
      node = node.children.first;
      nodes.add(node);
    }
    return nodes;
  }

  /// The alternatives recorded alongside [node].
  static List<GameNode> _siblings(GameNode node) {
    final parent = node.parent;
    if (parent == null) return const [];
    return parent.children.where((c) => !identical(c, node)).toList();
  }

  static String _notation(GameNode node, DisplayLanguage language) =>
      node.parent == null || node.move == null
      ? ''
      : MoveNotation.toNotation(node.move!, node.parent!.position, language);

  /// A whole line from [start] onwards, as notation.
  static String _lineText(GameNode start, DisplayLanguage language) {
    final parts = <String>[];
    var node = start;
    while (true) {
      parts.add(_notation(node, language));
      if (node.children.isEmpty) break;
      node = node.children.first;
    }
    return parts.join(', ');
  }

  /// Comment text for plain output: diagram markers become placeholders.
  static String _plainComment(String comment) =>
      comment.replaceAll(kBoardMarker, '[screenshot]').trim();

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
