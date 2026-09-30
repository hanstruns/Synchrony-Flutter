import 'package:flutter/services.dart';

/// Sonidos propios, sin depender de los clics de sistema del teléfono.
class FeedbackService {
  static const channel = MethodChannel('synchrony/feedback');
  final Map<String, Uint8List> _sounds = {};
  bool _disposed = false;
  int _generation = 0;

  Future<String?> play(
    String cue, {
    bool sound = false,
    bool vibration = false,
  }) async {
    if (_disposed || (!sound && !vibration)) return null;
    final generation = _generation;
    try {
      Uint8List? bytes;
      if (sound) {
        bytes = _sounds[cue];
        if (bytes == null) {
          final data = await rootBundle.load('assets/sounds/$cue.wav');
          bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          _sounds[cue] = bytes;
        }
      }
      if (_disposed || generation != _generation) return null;
      final available = await channel.invokeMethod<bool>('play', {
        'cue': cue,
        'sound': sound,
        'vibration': vibration,
        'bytes': bytes,
      });
      if (vibration && available == false) {
        return 'Este dispositivo no tiene vibrador disponible.';
      }
      return null;
    } on MissingPluginException {
      return 'Recompila y reinstala la app para activar sonido y vibración.';
    } catch (_) {
      return 'No se pudo reproducir el efecto. Revisa el volumen y los ajustes del dispositivo.';
    }
  }

  Future<void> stop() async {
    ++_generation;
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {
      /* Canal no disponible en pruebas. */
    }
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
