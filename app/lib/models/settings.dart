/// How the app chooses light vs dark appearance.
enum ThemeSetting { light, dark, auto }

/// Language used to render pieces on the board and moves in notation.
enum DisplayLanguage { simplified, traditional, english }

/// Which side analysis scores are reported from.
enum ScorePerspective { red, sideToMove }

/// Overall text size, applied as a scale factor to every text style in the app.
enum FontSizeSetting { small, medium, large, extraLarge }

extension FontSizeSettingScale on FontSizeSetting {
  /// Multiplier applied to the app's text scale.
  double get scale {
    switch (this) {
      case FontSizeSetting.small:
        return 0.9;
      case FontSizeSetting.medium:
        return 1.0;
      case FontSizeSetting.large:
        return 1.15;
      case FontSizeSetting.extraLarge:
        return 1.3;
    }
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// User-configurable preferences, persisted as JSON.
class Settings {
  final ThemeSetting theme;
  final DisplayLanguage language;
  final ScorePerspective scorePerspective;
  final FontSizeSetting fontSize;

  /// Highlight the squares of the move that was just played.
  final bool highlightLastMove;

  /// Highlight the engine's best move for the side to move.
  final bool highlightBestMove;

  /// Highlight the opponent's best reply to that move (the ponder move).
  final bool highlightPonderMove;

  /// Reject moves that break the Xiangqi rules. Setup mode ignores this so
  /// arbitrary positions can still be built.
  final bool enforceRules;

  /// Show a board preview when hovering a point on the score chart.
  final bool previewOnChart;

  /// Show a board preview when hovering a move in the move tree.
  final bool previewOnMoveTree;

  /// Show a board preview when hovering a move in an engine line.
  final bool previewOnEngineLine;

  /// How many lines the engine reports per iteration (UCI MultiPV).
  final int multiPv;

  /// Board width in logical pixels, as dragged by the user. Null lets the
  /// layout pick the size that fits the window.
  final double? boardWidth;

  /// Width of the game-score column in the wide layout; null for the default.
  final double? moveTableWidth;

  /// Width of the notes/variations column in the wide layout; null for the
  /// default.
  final double? sidePanelWidth;

  /// Share of that column's height given to the notes pane, 0..1; null for the
  /// default split.
  final double? notesFraction;

  const Settings({
    this.theme = ThemeSetting.dark,
    this.language = DisplayLanguage.simplified,
    this.scorePerspective = ScorePerspective.red,
    this.fontSize = FontSizeSetting.large,
    this.highlightLastMove = true,
    this.highlightBestMove = true,
    this.highlightPonderMove = true,
    this.enforceRules = true,
    this.previewOnChart = true,
    this.previewOnMoveTree = true,
    this.previewOnEngineLine = true,
    this.multiPv = 1,
    this.boardWidth,
    this.moveTableWidth,
    this.sidePanelWidth,
    this.notesFraction,
  });

  Settings copyWith({
    ThemeSetting? theme,
    DisplayLanguage? language,
    ScorePerspective? scorePerspective,
    FontSizeSetting? fontSize,
    bool? highlightLastMove,
    bool? highlightBestMove,
    bool? highlightPonderMove,
    bool? enforceRules,
    bool? previewOnChart,
    bool? previewOnMoveTree,
    bool? previewOnEngineLine,
    int? multiPv,
  }) {
    return Settings(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      scorePerspective: scorePerspective ?? this.scorePerspective,
      fontSize: fontSize ?? this.fontSize,
      highlightLastMove: highlightLastMove ?? this.highlightLastMove,
      highlightBestMove: highlightBestMove ?? this.highlightBestMove,
      highlightPonderMove: highlightPonderMove ?? this.highlightPonderMove,
      enforceRules: enforceRules ?? this.enforceRules,
      previewOnChart: previewOnChart ?? this.previewOnChart,
      previewOnMoveTree: previewOnMoveTree ?? this.previewOnMoveTree,
      previewOnEngineLine: previewOnEngineLine ?? this.previewOnEngineLine,
      multiPv: multiPv ?? this.multiPv,
      boardWidth: boardWidth,
      moveTableWidth: moveTableWidth,
      sidePanelWidth: sidePanelWidth,
      notesFraction: notesFraction,
    );
  }

  /// Replace the draggable pane sizes wholesale. Unlike [copyWith], a null
  /// field here means "back to the automatic size", so a pane can be reset.
  Settings withLayout({
    double? boardWidth,
    double? moveTableWidth,
    double? sidePanelWidth,
    double? notesFraction,
  }) {
    return Settings(
      theme: theme,
      language: language,
      scorePerspective: scorePerspective,
      fontSize: fontSize,
      highlightLastMove: highlightLastMove,
      highlightBestMove: highlightBestMove,
      highlightPonderMove: highlightPonderMove,
      enforceRules: enforceRules,
      previewOnChart: previewOnChart,
      previewOnMoveTree: previewOnMoveTree,
      previewOnEngineLine: previewOnEngineLine,
      multiPv: multiPv,
      boardWidth: boardWidth,
      moveTableWidth: moveTableWidth,
      sidePanelWidth: sidePanelWidth,
      notesFraction: notesFraction,
    );
  }

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'language': language.name,
    'scorePerspective': scorePerspective.name,
    'fontSize': fontSize.name,
    'highlightLastMove': highlightLastMove,
    'highlightBestMove': highlightBestMove,
    'highlightPonderMove': highlightPonderMove,
    'enforceRules': enforceRules,
    'previewOnChart': previewOnChart,
    'previewOnMoveTree': previewOnMoveTree,
    'previewOnEngineLine': previewOnEngineLine,
    'multiPv': multiPv,
    'boardWidth': boardWidth,
    'moveTableWidth': moveTableWidth,
    'sidePanelWidth': sidePanelWidth,
    'notesFraction': notesFraction,
  };

  factory Settings.fromJson(Map<String, dynamic> json) {
    const d = Settings();
    return Settings(
      theme: _enumByName(ThemeSetting.values, json['theme'], d.theme),
      language: _enumByName(
        DisplayLanguage.values,
        json['language'],
        d.language,
      ),
      scorePerspective: _enumByName(
        ScorePerspective.values,
        json['scorePerspective'],
        d.scorePerspective,
      ),
      fontSize: _enumByName(
        FontSizeSetting.values,
        json['fontSize'],
        d.fontSize,
      ),
      highlightLastMove:
          json['highlightLastMove'] as bool? ?? d.highlightLastMove,
      highlightBestMove:
          json['highlightBestMove'] as bool? ?? d.highlightBestMove,
      highlightPonderMove:
          json['highlightPonderMove'] as bool? ?? d.highlightPonderMove,
      enforceRules: json['enforceRules'] as bool? ?? d.enforceRules,
      previewOnChart: json['previewOnChart'] as bool? ?? d.previewOnChart,
      previewOnMoveTree:
          json['previewOnMoveTree'] as bool? ?? d.previewOnMoveTree,
      previewOnEngineLine:
          json['previewOnEngineLine'] as bool? ?? d.previewOnEngineLine,
      // Clamped: the engine accepts up to 128, but the panel is not the place
      // to read a hundred lines.
      multiPv: ((json['multiPv'] as num?)?.toInt() ?? d.multiPv).clamp(1, 8),
      // Sizes from an older window can be wider than the current one; the
      // layout clamps them again to what fits before using them.
      boardWidth: (json['boardWidth'] as num?)?.toDouble(),
      moveTableWidth: (json['moveTableWidth'] as num?)?.toDouble(),
      sidePanelWidth: (json['sidePanelWidth'] as num?)?.toDouble(),
      notesFraction: (json['notesFraction'] as num?)?.toDouble(),
    );
  }
}
