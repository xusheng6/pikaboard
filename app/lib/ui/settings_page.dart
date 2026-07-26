import 'package:flutter/material.dart';

import '../models/settings.dart';

/// Settings screen. Applies changes immediately via [onChanged] while keeping
/// a local copy so the selection updates instantly.
class SettingsPage extends StatefulWidget {
  final Settings settings;
  final ValueChanged<Settings> onChanged;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _current = widget.settings;

  void _apply(Settings next) {
    setState(() => _current = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _sectionHeader(context, 'Appearance'),
          for (final t in ThemeSetting.values)
            _choice(
              label: _themeLabel(t),
              selected: _current.theme == t,
              onTap: () => _apply(_current.copyWith(theme: t)),
            ),
          const Divider(),
          _sectionHeader(context, 'Display language'),
          for (final l in DisplayLanguage.values)
            _choice(
              label: _languageLabel(l),
              selected: _current.language == l,
              onTap: () => _apply(_current.copyWith(language: l)),
            ),
          const Divider(),
          _sectionHeader(context, 'Score perspective'),
          for (final s in ScorePerspective.values)
            _choice(
              label: _scoreLabel(s),
              selected: _current.scorePerspective == s,
              onTap: () => _apply(_current.copyWith(scorePerspective: s)),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }

  static String _themeLabel(ThemeSetting t) {
    switch (t) {
      case ThemeSetting.light:
        return 'Light';
      case ThemeSetting.dark:
        return 'Dark';
      case ThemeSetting.auto:
        return 'System (auto)';
    }
  }

  static String _languageLabel(DisplayLanguage l) {
    switch (l) {
      case DisplayLanguage.simplified:
        return '简体中文 (Simplified)';
      case DisplayLanguage.traditional:
        return '繁體中文 (Traditional)';
      case DisplayLanguage.english:
        return 'English';
    }
  }

  static String _scoreLabel(ScorePerspective s) {
    switch (s) {
      case ScorePerspective.red:
        return 'Always from Red';
      case ScorePerspective.sideToMove:
        return 'From side to move';
    }
  }
}
