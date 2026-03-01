class SearchInfo {
  final int depth;
  final int selDepth;
  final int multiPV;
  final int? scoreCp;
  final int? scoreMate;
  final bool isLowerbound;
  final bool isUpperbound;
  final int nodes;
  final int nps;
  final int timeMs;
  final int hashfull;
  final List<String> pv;

  const SearchInfo({
    required this.depth,
    required this.selDepth,
    required this.multiPV,
    this.scoreCp,
    this.scoreMate,
    this.isLowerbound = false,
    this.isUpperbound = false,
    required this.nodes,
    required this.nps,
    required this.timeMs,
    required this.hashfull,
    required this.pv,
  });

  String get scoreText {
    if (scoreMate != null && scoreMate != 0) {
      return 'M${scoreMate! > 0 ? '+' : ''}$scoreMate';
    }
    if (scoreCp != null) {
      final v = scoreCp! / 100.0;
      final sign = v >= 0 ? '+' : '';
      return '$sign${v.toStringAsFixed(2)}';
    }
    return '?';
  }

  String get nodesText {
    if (nodes >= 1000000000) {
      return '${(nodes / 1000000000).toStringAsFixed(1)}G';
    } else if (nodes >= 1000000) {
      return '${(nodes / 1000000).toStringAsFixed(1)}M';
    } else if (nodes >= 1000) {
      return '${(nodes / 1000).toStringAsFixed(1)}K';
    }
    return '$nodes';
  }

  String get npsText {
    if (nps >= 1000000) {
      return '${(nps / 1000000).toStringAsFixed(1)}M';
    } else if (nps >= 1000) {
      return '${(nps / 1000).toStringAsFixed(1)}K';
    }
    return '$nps';
  }

  String get timeText {
    if (timeMs >= 60000) {
      final min = timeMs ~/ 60000;
      final sec = (timeMs % 60000) / 1000;
      return '${min}m${sec.toStringAsFixed(1)}s';
    } else if (timeMs >= 1000) {
      return '${(timeMs / 1000).toStringAsFixed(1)}s';
    }
    return '${timeMs}ms';
  }

  String get pvText => pv.join(' ');
}

class BestMove {
  final String move;
  final String? ponder;

  const BestMove({required this.move, this.ponder});
}
