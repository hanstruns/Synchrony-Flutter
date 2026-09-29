import 'package:flutter_test/flutter_test.dart';
import 'package:synchrony/models/game_state.dart';
import 'package:synchrony/services/ad_gate.dart';
import 'package:synchrony/services/game_connection.dart';

Map<String, dynamic> fixture(String phase) => {
  'code': 'aB3xY9',
  'phase': phase,
  'me': 'p1',
  'capacity': 2,
  'deck': 100,
  'round': 40,
  'lives': 5,
  'last': 99,
  'dealt': 80,
  'played': 80,
  'removed': 0,
  'revision': 8,
  'serverNow': 1000,
  'deadline': null,
  'countdownAt': null,
  'public': false,
  'event': {'id': 8, 'type': 'won', 'text': 'Victoria'},
  'hand': <int>[],
  'players': [
    {
      'id': 'p1',
      'name': 'Luna',
      'online': true,
      'ready': false,
      'excluded': false,
      'count': 0,
    },
  ],
};
void main() {
  test('El contrato del servidor distingue resultados y rondas', () {
    for (final phase in [
      'lobby',
      'retry',
      'between',
      'playing',
      'countdown',
      'abandoned',
    ]) {
      expect(GameState.fromJson(fixture(phase)).finished, false);
    }
    final state = GameState.fromJson(fixture('won'));
    expect(state.finished, true);
    expect(state.target, 79);
    expect(state.self!.name, 'Luna');
    expect(state.adKey, 'aB3xY9:p1');
  });
  test('Un fallo de ronda, abandono o espectador no muestra anuncios', () {
    final gate = AdGate([]);
    expect(gate.claim('a', 'retry', spectator: false), false);
    expect(gate.claim('a', 'between', spectator: false), false);
    expect(gate.claim('a', 'abandoned', spectator: false), false);
    expect(gate.claim('a', 'won', spectator: true), false);
    expect(gate.consumed, isEmpty);
  });
  test(
    'Solo una oportunidad de publicidad por partida, incluso al reiniciar',
    () {
      final gate = AdGate([]);
      expect(gate.claim('a', 'won', spectator: false), true);
      expect(gate.claim('a', 'won', spectator: false), false);
      final restored = AdGate(gate.consumed);
      expect(restored.claim('a', 'lost', spectator: false), false);
      expect(restored.claim('b', 'lost', spectator: false), true);
    },
  );
  test('Cambiar un evento SSE no cambia la identidad publicitaria', () {
    final first = GameState.fromJson(fixture('won'));
    final changed = fixture('won')
      ..['event'] = {'id': 20, 'type': 'leave', 'text': 'Leo sale'};
    expect(GameState.fromJson(changed).adKey, first.adKey);
  });
  test('Un espectador no puede jugar ni confirmar', () {
    final json = fixture('retry');
    (json['players'] as List).first['excluded'] = true;
    final state = GameState.fromJson(json);
    expect(state.canPlay, false);
    expect(state.canReady, false);
  });
  test('Acepta dominios HTTPS, rechaza URL con credenciales o rutas', () {
    expect(
      GameConnection.validateServer('https://example.onrender.com/'),
      'https://example.onrender.com',
    );
    for (final url in [
      'https://user:pass@example.com',
      'https://example.com/api',
      'javascript:alert(1)',
      'http://example.com',
      'https://example.com?token=secret',
    ]) {
      expect(() => GameConnection.validateServer(url), throwsFormatException);
    }
  });
}
