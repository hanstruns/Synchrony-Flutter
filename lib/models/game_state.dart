class Player {
  final String id, name;
  final bool online, ready, excluded;
  final int count;
  Player.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      online = j['online'] == true,
      ready = j['ready'] == true,
      excluded = j['excluded'] == true,
      count = (j['count'] as num).toInt();
}

class GameState {
  final String code, phase, me, eventType, eventText;
  final int capacity,
      deck,
      round,
      lives,
      last,
      dealt,
      played,
      removed,
      revision,
      eventId,
      serverNow;
  final int? deadline, countdownAt;
  final bool isPublic;
  final List<int> hand;
  final List<Player> players;
  GameState.fromJson(Map<String, dynamic> j)
    : code = j['code'] as String,
      phase = j['phase'] as String,
      me = j['me'] as String,
      capacity = (j['capacity'] as num).toInt(),
      deck = (j['deck'] as num).toInt(),
      round = (j['round'] as num).toInt(),
      lives = (j['lives'] as num).toInt(),
      last = (j['last'] as num).toInt(),
      dealt = (j['dealt'] as num).toInt(),
      played = (j['played'] as num).toInt(),
      removed = (j['removed'] as num).toInt(),
      revision = (j['revision'] as num).toInt(),
      serverNow = (j['serverNow'] as num).toInt(),
      deadline = (j['deadline'] as num?)?.toInt(),
      countdownAt = (j['countdownAt'] as num?)?.toInt(),
      isPublic = j['public'] == true,
      eventId = ((j['event'] as Map)['id'] as num?)?.toInt() ?? 0,
      eventType = (j['event'] as Map)['type'] as String,
      eventText = (j['event'] as Map)['text'] as String,
      hand = List<int>.unmodifiable((j['hand'] as List).cast<int>()),
      players = List<Player>.unmodifiable(
        (j['players'] as List).map(
          (p) => Player.fromJson(Map<String, dynamic>.from(p as Map)),
        ),
      );
  Player? get self {
    for (final p in players) {
      if (p.id == me) return p;
    }
    return null;
  }

  bool get finished => phase == 'won' || phase == 'lost';
  bool get waiting => const ['lobby', 'between', 'retry'].contains(phase);
  bool get canReady => waiting && self != null && !self!.excluded;
  bool get canPlay => phase == 'playing' && self != null && !self!.excluded;
  int get target => (deck * .79).ceil();
  String get adKey => '$code:$me';
}
