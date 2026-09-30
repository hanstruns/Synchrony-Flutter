import 'dart:async';
import 'package:flutter/services.dart';

/// Pistas locales en bucle. Los efectos y la música tienen reproductores separados.
class MusicService {
  static const channel = MethodChannel('synchrony/feedback');
  final Duration fadeStep;
  MusicService({this.fadeStep = const Duration(milliseconds: 50)});
  final Map<String, Uint8List> _cache = {};
  String _wanted = '', _current = '';
  double _volume = .22, _level = 0;
  int _revision = 0;
  bool _running = false, _disposed = false;

  static String trackForPhase(String? phase) =>
      phase == null || phase == 'lobby' ? 'menu' : 'partida';

  void update({
    required String track,
    required bool enabled,
    required bool active,
    required double volume,
  }) {
    if (_disposed) return;
    final wanted = enabled && active ? track : '';
    final target = volume.clamp(0.0, .5).toDouble();
    if (wanted == _wanted && target == _volume) return;
    _wanted = wanted;
    _volume = target;
    ++_revision;
    unawaited(_drain());
  }

  Future<bool> _fade(double to, int revision) async {
    final from = _level;
    for (var i = 1; i <= 12; i++) {
      if (_disposed || revision != _revision) return false;
      _level = from + (to - from) * i / 12;
      await channel.invokeMethod<void>('musicVolume', _level);
      await Future<void>.delayed(fadeStep);
    }
    return !_disposed && revision == _revision;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    var processed = -1;
    try {
      while (!_disposed && processed != _revision) {
        final revision = _revision;
        processed = revision;
        final wanted = _wanted;
        try {
          if (wanted.isEmpty) {
            await channel.invokeMethod<void>('musicStop');
            _current = '';
            _level = 0;
            continue;
          }
          if (_current != wanted) {
            if (_current.isNotEmpty && !await _fade(0, revision)) continue;
            var bytes = _cache[wanted];
            if (bytes == null) {
              final data = await rootBundle.load('assets/music/$wanted.wav');
              bytes = data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              );
              _cache[wanted] = bytes;
            }
            if (_disposed || revision != _revision) continue;
            await channel.invokeMethod<void>('musicLoad', bytes);
            _current = wanted;
            _level = 0;
          }
          await _fade(_volume, revision);
        } catch (_) {
          // Audio no disponible: nunca impide jugar ni altera la conexión.
          _current = '';
          _level = 0;
        }
      }
    } finally {
      _running = false;
      if (_disposed) {
        try {
          await channel.invokeMethod<void>('musicStop');
        } catch (_) {}
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_revision;
    _cache.clear();
    if (!_running) unawaited(_drain());
  }
}
