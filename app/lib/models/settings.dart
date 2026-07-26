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

  const Settings({
    this.theme = ThemeSetting.dark,
    this.language = DisplayLanguage.simplified,
    this.scorePerspective = ScorePerspective.red,
    this.fontSize = FontSizeSetting.large,
    this.highlightLastMove = true,
    this.highlightBestMove = true,
    this.highlightPonderMove = true,
    this.enforceRules = true,
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
    );
  }
}
