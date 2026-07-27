import 'move_notation.dart';
import 'piece.dart';
import 'position.dart';

/// How a game finished, as recorded by the formats we read.
enum GameResult { unknown, redWin, blackWin, draw }

/// Descriptive fields about a game. XQF carries all of these; our own format
/// stores them verbatim.
class GameMetadata {
  String title;
  String event;
  String date;
  String site;
  String red;
  String black;
  String annotator;
  GameResult result;

  GameMetadata({
    this.title = '',
    this.event = '',
    this.date = '',
    this.site = '',
    this.red = '',
    this.black = '',
    this.annotator = '',
    this.result = GameResult.unknown,
  });

  bool get isEmpty =>
      title.isEmpty &&
      event.isEmpty &&
      date.isEmpty &&
      site.isEmpty &&
      red.isEmpty &&
      black.isEmpty &&
      annotator.isEmpty;

  GameMetadata copy() => GameMetadata(
    title: title,
    event: event,
    date: date,
    site: site,
    red: red,
    black: black,
    annotator: annotator,
    result: result,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'event': event,
    'date': date,
    'site': site,
    'red': red,
    'black': black,
    'annotator': annotator,
    'result': result.name,
  };

  factory GameMetadata.fromJson(Map<String, dynamic> json) => GameMetadata(
    title: json['title'] as String? ?? '',
    event: json['event'] as String? ?? '',
    date: json['date'] as String? ?? '',
    site: json['site'] as String? ?? '',
    red: json['red'] as String? ?? '',
    black: json['black'] as String? ?? '',
    annotator: json['annotator'] as String? ?? '',
    result: GameResult.values.firstWhere(
      (r) => r.name == json['result'],
      orElse: () => GameResult.unknown,
    ),
  );
}

/// One position in the game tree: the move that led here plus whatever is
/// annotated on the resulting position.
///
/// Children are continuations, and the first one is the main line — the same
/// shape XQF stores as left-child / right-sibling.
class GameNode {
  /// The UCI move that led to this node; null only for the root.
  final String? move;

  /// The position after [move] has been played.
  final Position position;

  /// Free-text annotation shown for this position.
  String comment;

  final List<GameNode> children = [];

  GameNode? parent;

  GameNode({required this.position, this.move, this.comment = ''});

  bool get isRoot => parent == null;

  /// Distance from the root, i.e. how many moves have been played.
  int get ply {
    var count = 0;
    for (var node = parent; node != null; node = node.parent) {
      count++;
    }
    return count;
  }

  /// True when this node is reached by following only first children.
  bool get isMainline {
    for (var node = this; node.parent != null; node = node.parent!) {
      if (!identical(node.parent!.children.first, node)) return false;
    }
    return true;
  }

  /// The move number this node's move belongs to, counting from 1.
  int get moveNumber => (ply + 1) ~/ 2;

  /// True when [move] was played by Red.
  bool get isRedMove =>
      parent != null && parent!.position.sideToMove == PieceColor.red;

  /// Root-first list of nodes leading to this one, including itself.
  List<GameNode> get pathFromRoot {
    final path = <GameNode>[];
    for (GameNode? node = this; node != null; node = node.parent) {
      path.add(node);
    }
    return path.reversed.toList();
  }

  /// The child reached by [uci], or null if that continuation is not recorded.
  GameNode? childFor(String uci) {
    for (final child in children) {
      if (child.move == uci) return child;
    }
    return null;
  }

  /// Add [uci] as a continuation, reusing the existing child when the move has
  /// been played here before so replaying a line does not duplicate it.
  GameNode addMove(String uci) {
    final existing = childFor(uci);
    if (existing != null) return existing;
    final child = GameNode(
      move: uci,
      position: MoveNotation.applyUciMove(position, uci),
    )..parent = this;
    children.add(child);
    return child;
  }

  /// Play [uciMoves] from here, returning the node the line ends on.
  ///
  /// Moves already recorded are followed rather than duplicated, so adding a
  /// line that starts like an existing one extends it instead of forking.
  GameNode addLine(Iterable<String> uciMoves) {
    var node = this;
    for (final uci in uciMoves) {
      node = node.addMove(uci);
    }
    return node;
  }

  /// Detach this node (and its subtree) from its parent.
  void remove() {
    parent?.children.remove(this);
    parent = null;
  }

  /// Make this node its parent's main line, so the game reads through it.
  void promote() {
    final p = parent;
    if (p == null) return;
    p.children.remove(this);
    p.children.insert(0, this);
  }

  /// Deepest node reachable by always taking the main line from here.
  GameNode get mainlineEnd {
    var node = this;
    while (node.children.isNotEmpty) {
      node = node.children.first;
    }
    return node;
  }

  /// True when this node or anything below it carries a comment.
  bool get hasAnnotationBelow =>
      comment.isNotEmpty || children.any((c) => c.hasAnnotationBelow);

  Map<String, dynamic> toJson() => {
    if (move != null) 'move': move,
    if (comment.isNotEmpty) 'comment': comment,
    if (children.isNotEmpty)
      'children': [for (final child in children) child.toJson()],
  };

  /// Rebuild a subtree, replaying moves from [position] to recover the
  /// positions that are not stored in the file.
  factory GameNode.fromJson(Map<String, dynamic> json, Position position) {
    final node = GameNode(
      position: position,
      move: json['move'] as String?,
      comment: json['comment'] as String? ?? '',
    );
    for (final child in (json['children'] as List<dynamic>? ?? const [])) {
      final childJson = child as Map<String, dynamic>;
      final uci = childJson['move'] as String? ?? '';
      final childNode = GameNode.fromJson(
        childJson,
        MoveNotation.applyUciMove(position, uci),
      );
      childNode.parent = node;
      node.children.add(childNode);
    }
    return node;
  }
}

/// A game: where it starts, how it is described, and every line recorded in it.
class Game {
  final Position initialPosition;
  final GameNode root;
  GameMetadata metadata;

  Game._({
    required this.initialPosition,
    required this.root,
    required this.metadata,
  });

  factory Game.fromPosition(Position position, {GameMetadata? metadata}) {
    return Game._(
      initialPosition: position,
      root: GameNode(position: position),
      metadata: metadata ?? GameMetadata(),
    );
  }

  /// Build a game from a starting position and a single line of UCI moves.
  factory Game.fromMoves(
    Position position,
    List<String> moves, {
    GameMetadata? metadata,
  }) {
    final game = Game.fromPosition(position, metadata: metadata);
    var node = game.root;
    for (final move in moves) {
      node = node.addMove(move);
    }
    return game;
  }

  /// Number of moves on the main line.
  int get mainlineLength => root.mainlineEnd.ply;

  static const String formatId = 'pikaboard_game_v1';

  Map<String, dynamic> toJson() => {
    'format': formatId,
    'initialFen': initialPosition.toFen(),
    'metadata': metadata.toJson(),
    'root': root.toJson(),
  };

  factory Game.fromJson(Map<String, dynamic> json) {
    final position = Position.fromFen(json['initialFen'] as String);
    final root = GameNode.fromJson(
      json['root'] as Map<String, dynamic>? ?? const {},
      position,
    );
    return Game._(
      initialPosition: position,
      root: root,
      metadata: GameMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}
