/// How the app chooses light vs dark appearance.
enum ThemeSetting { light, dark, auto }

/// Language used to render pieces on the board and moves in notation.
enum DisplayLanguage { simplified, traditional, english }

/// Which side analysis scores are reported from.
enum ScorePerspective { red, sideToMove }

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

  const Settings({
    this.theme = ThemeSetting.dark,
    this.language = DisplayLanguage.simplified,
    this.scorePerspective = ScorePerspective.red,
  });

  Settings copyWith({
    ThemeSetting? theme,
    DisplayLanguage? language,
    ScorePerspective? scorePerspective,
  }) {
    return Settings(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      scorePerspective: scorePerspective ?? this.scorePerspective,
    );
  }

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'language': language.name,
    'scorePerspective': scorePerspective.name,
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
    );
  }
}
