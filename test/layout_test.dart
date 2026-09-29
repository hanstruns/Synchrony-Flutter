import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchrony/main.dart';
import 'package:synchrony/models/game_state.dart';
import 'package:synchrony/services/game_connection.dart';

class PreviewConnection extends GameConnection {
  PreviewConnection({bool playing = false}) {
    if (playing) {
      state = GameState.fromJson({
        'code': 'aB3xY9',
        'phase': 'playing',
        'me': 'p1',
        'capacity': 3,
        'deck': 100,
        'round': 3,
        'lives': 4,
        'last': 12,
        'dealt': 9,
        'played': 2,
        'removed': 0,
        'revision': 12,
        'serverNow': DateTime.now().millisecondsSinceEpoch,
        'deadline': DateTime.now().millisecondsSinceEpoch + 312000,
        'countdownAt': null,
        'public': false,
        'event': {'id': 12, 'type': 'card', 'text': 'Leo ha jugado 12.'},
        'hand': [24, 51, 78],
        'players': [
          {
            'id': 'p1',
            'name': 'Luna',
            'online': true,
            'ready': false,
            'excluded': false,
            'count': 3,
          },
          {
            'id': 'p2',
            'name': 'Leo',
            'online': true,
            'ready': false,
            'excluded': false,
            'count': 2,
          },
          {
            'id': 'p3',
            'name': 'Mar',
            'online': true,
            'ready': false,
            'excluded': false,
            'count': 2,
          },
        ],
      });
      connected = true;
    }
  }
  @override
  bool get hasSession => state != null;
  @override
  Future<void> restore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = Platform.environment['SYNCHRONY_FONT'];
    if (font != null) {
      final loader = FontLoader('Roboto');
      loader.addFont(
        Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
      );
      await loader.load();
    }
  });
  for (final playing in [false, true]) {
    for (final size in [
      const Size(390, 844),
      const Size(844, 390),
      const Size(320, 640),
    ]) {
      testWidgets('${playing ? 'Mesa' : 'Inicio'} sin desbordamientos a $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: SynchronyApp(
              prefs: prefs,
              connection: PreviewConnection(playing: playing),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['SYNCHRONY_SCREENSHOTS'];
        if (directory != null) {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            Directory(directory).createSync(recursive: true);
            File(
              '$directory/${playing ? 'mesa' : 'inicio'}-${size.width.toInt()}x${size.height.toInt()}.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
