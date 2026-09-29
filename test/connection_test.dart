import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:synchrony/services/game_connection.dart';

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('El estado esperado no llegó a tiempo.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dos clientes Dart juegan y se reconectan al servidor Node real',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      FlutterSecureStorage.setMockInitialValues({});
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final server = await Process.start(
        'node',
        ['server/server.js'],
        environment: {'PORT': '$port'},
      );
      final errors = <String>[];
      final err = server.stderr.transform(utf8.decoder).listen(errors.add);
      final ready = Completer<void>();
      final out = server.stdout.transform(utf8.decoder).listen((line) {
        if (line.contains('Synchrony disponible') && !ready.isCompleted) {
          ready.complete();
        }
      });
      final a = GameConnection(), b = GameConnection();
      try {
        await ready.future.timeout(const Duration(seconds: 10));
        final url = 'http://127.0.0.1:$port';
        await a.enter(url, 'Luna', 'create', players: 2, deck: 2);
        expect(a.state, isNotNull, reason: a.message);
        await b.enter(url, 'Leo', 'join', code: a.state!.code);
        await until(
          () => a.connected && b.connected && a.state!.players.length == 2,
        );
        await a.action('ready');
        await until(() => b.state!.players.first.ready);
        await b.action('ready');
        await until(
          () => a.state!.phase == 'playing' && b.state!.phase == 'playing',
        );
        expect(a.state!.hand.length, 1);
        expect(b.state!.hand.length, 1);
        final hand = [...a.state!.hand];
        a.suspend();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        a.resume();
        await until(() => a.connected);
        expect(a.state!.hand, hand);
        final first = a.state!.hand.first < b.state!.hand.first ? a : b;
        final second = identical(first, a) ? b : a;
        await until(() => first.state!.revision == second.state!.revision);
        await first.action('play', card: 1);
        await until(() => second.state!.last == 1);
        await second.action('play', card: 2);
        await until(() => a.state!.finished && b.state!.finished);
        expect(a.state!.phase, 'won');
        expect(b.state!.lives, 5);
        await a.leave();
        await b.leave();
        expect(a.hasSession, false);
        expect(b.hasSession, false);
        expect(errors, isEmpty);
      } finally {
        a.dispose();
        b.dispose();
        server.kill();
        await out.cancel();
        await err.cancel();
      }
    },
    skip: Platform.environment['SYNCHRONY_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(seconds: 50)),
  );
}
