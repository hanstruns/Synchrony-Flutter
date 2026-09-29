import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchrony/widgets/playing_card.dart';

void main() {
  testWidgets('La carta juega su número una sola vez y se puede desactivar', (
    tester,
  ) async {
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayingCard(number: 150, deck: 150, onTap: () => plays++),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(InkWell));
    expect(plays, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayingCard(
              number: 150,
              deck: 150,
              enabled: false,
              onTap: () => plays++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(InkWell));
    expect(plays, 1);
  });
  testWidgets('Las cartas grandes caben con texto ampliado', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(child: PlayingCard(number: 100000, deck: 100000)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
