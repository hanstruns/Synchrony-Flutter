import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchrony/services/feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FeedbackService.channel, (call) async {
          calls.add(call);
          return call.method == 'play' ? true : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FeedbackService.channel, null),
  );
  test('Silencio no envía efectos y vibración no carga audio', () async {
    final service = FeedbackService();
    await service.play('card');
    expect(calls, isEmpty);
    expect(await service.play('card', vibration: true), isNull);
    expect(calls.single.arguments['sound'], false);
    expect(calls.single.arguments['vibration'], true);
    expect(calls.single.arguments['bytes'], isNull);
  });
  test('Cada efecto envía WAV válido al canal nativo', () async {
    final service = FeedbackService();
    for (final cue in [
      'card',
      'countdown',
      'start',
      'success',
      'won',
      'mistake',
      'lost',
      'test',
    ]) {
      expect(await service.play(cue, sound: true), isNull);
      final bytes = calls.last.arguments['bytes'] as Uint8List;
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, greaterThan(1000));
    }
  });
  test('Informa de motor ausente sin bloquear el juego', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FeedbackService.channel, (_) async => false);
    expect(
      await FeedbackService().play('test', vibration: true),
      contains('vibrador'),
    );
  });
  test('Después de dispose no reproduce efectos', () async {
    final service = FeedbackService();
    service.dispose();
    await service.play('test', sound: true);
    expect(calls.where((c) => c.method == 'play'), isEmpty);
  });
}
