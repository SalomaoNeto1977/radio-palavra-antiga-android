import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/foreground_interface.dart';

void main() {
  testWidgets('service-only start does not construct phone platform views', (
    WidgetTester tester,
  ) async {
    int constructions = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pumpWidget(
      MaterialApp(
        home: ForegroundInterface(
          builder: (_) {
            constructions += 1;
            return const Text('Phone WebView');
          },
        ),
      ),
    );
    expect(constructions, 0);
    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(constructions, 0);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(constructions, 1);
    expect(find.text('Phone WebView'), findsOneWidget);
  });

  testWidgets('background and car reconnects retain the same phone view', (
    WidgetTester tester,
  ) async {
    int constructions = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: ForegroundInterface(
          builder: (_) {
            constructions += 1;
            return const Material(child: TextField());
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Música escolhida');
    final Element original = tester.element(find.byType(TextField));
    for (int cycle = 0; cycle < 3; cycle += 1) {
      for (final AppLifecycleState state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
    }
    expect(constructions, 1);
    expect(tester.element(find.byType(TextField)), same(original));
    expect(find.text('Música escolhida'), findsOneWidget);
  });

  for (final bool frameWhileDetached in <bool>[true, false]) {
    testWidgets(
      'closing the Activity replaces phone views on reopen '
      '(detached frame: $frameWhileDetached)',
      (WidgetTester tester) async {
        int constructions = 0;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(
          MaterialApp(
            home: ForegroundInterface(
              builder: (_) {
                constructions += 1;
                return const Material(child: TextField());
              },
            ),
          ),
        );
        for (int cycle = 1; cycle <= 3; cycle += 1) {
          await tester.enterText(find.byType(TextField), 'Old Activity');
          final Element oldView = tester.element(find.byType(TextField));
          for (final AppLifecycleState state in <AppLifecycleState>[
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
          if (frameWhileDetached) {
            await tester.pump();
            expect(find.byType(TextField), findsNothing);
          }
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
          expect(constructions, cycle + 1);
          expect(tester.element(find.byType(TextField)), isNot(same(oldView)));
          expect(find.text('Old Activity'), findsNothing);
          expect(find.byType(TextField), findsOneWidget);
        }
      },
    );
  }

  testWidgets('resume followed by pause before build defers first creation', (
    WidgetTester tester,
  ) async {
    int constructions = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pumpWidget(
      MaterialApp(
        home: ForegroundInterface(
          builder: (_) {
            constructions += 1;
            return const Text('Phone WebView');
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(constructions, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(constructions, 1);
  });
}
