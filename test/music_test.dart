import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchrony/services/music_service.dart';

Future<void> until(bool Function() done) async {
  final limit = DateTime.now().add(const Duration(seconds: 3));
  while (!done()) {
    if (DateTime.now().isAfter(limit)) {
      throw StateError('La música no alcanzó el estado esperado');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MusicService.channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MusicService.channel, null),
  );
  test(
    'Menú en inicio/sala; otra pista desde cuenta atrás hasta resultado',
    () {
      expect(MusicService.trackForPhase(null), 'menu');
      expect(MusicService.trackForPhase('lobby'), 'menu');
      for (final phase in [
        'countdown',
        'playing',
        'retry',
        'between',
        'won',
        'lost',
      ]) {
        expect(MusicService.trackForPhase(phase), 'partida');
      }
    },
  );
  test(
    'Carga WAV y no reinicia la canción al llegar eventos de juego',
    () async {
      final service = MusicService(fadeStep: Duration.zero);
      service.update(track: 'menu', enabled: true, active: true, volume: .22);
      await until(
        () => calls.any(
          (c) => c.method == 'musicVolume' && (c.arguments as double) >= .219,
        ),
      );
      final bytes =
          calls.firstWhere((c) => c.method == 'musicLoad').arguments
              as Uint8List;
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      service.update(track: 'menu', enabled: true, active: true, volume: .22);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(calls.where((c) => c.method == 'musicLoad').length, 1);
      service.dispose();
      await until(() => calls.any((c) => c.method == 'musicStop'));
    },
  );
  test(
    'Cambiar de escena funde y carga la segunda pista una sola vez',
    () async {
      final service = MusicService(fadeStep: Duration.zero);
      service.update(track: 'menu', enabled: true, active: true, volume: .2);
      await until(
        () => calls.where((c) => c.method == 'musicVolume').length >= 12,
      );
      service.update(track: 'partida', enabled: true, active: true, volume: .2);
      await until(
        () => calls.where((c) => c.method == 'musicVolume').length >= 36,
      );
      expect(calls.where((c) => c.method == 'musicLoad').length, 2);
      expect(
        calls
            .where((c) => c.method == 'musicVolume')
            .any((c) => (c.arguments as double).abs() < .0001),
        true,
      );
      service.dispose();
      await until(() => calls.any((c) => c.method == 'musicStop'));
    },
  );
  test('Segundo plano interrumpe el fundido y no vuelve a cargar', () async {
    final service = MusicService(fadeStep: const Duration(milliseconds: 2));
    service.update(track: 'partida', enabled: true, active: true, volume: .2);
    await until(() => calls.any((c) => c.method == 'musicLoad'));
    service.update(track: 'partida', enabled: true, active: false, volume: .2);
    await until(() => calls.any((c) => c.method == 'musicStop'));
    final loads = calls.where((c) => c.method == 'musicLoad').length;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls.where((c) => c.method == 'musicLoad').length, loads);
    service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 3));
  });
}
