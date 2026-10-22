import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/persistent_navigation_bar.dart';

Widget phoneShell({required Widget body, required ValueChanged<int> onSelect}) {
  return MaterialApp(
    home: Scaffold(
          body: body,
          bottomNavigationBar: PersistentNavigationBar(
            selectedIndex: 2,
            onDestinationSelected: onSelect,
          ),
    ),
  );
}

void main() {
  testWidgets('all destinations remain usable after thirty background cycles', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final List<int> selected = <int>[];
    await tester.pumpWidget(phoneShell(
      body: const TextField(),
      onSelect: selected.add,
    ));
    await tester.enterText(find.byType(TextField), 'Pesquisa guardada');
    final Element originalBody = tester.element(find.byType(TextField));
    for (int cycle = 0; cycle < 30; cycle += 1) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
      for (final String label in <String>['Rádio', 'Música', 'Conta', 'WhatsApp']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
        await tester.tap(find.text(label));
      }
      expect(tester.takeException(), isNull);
    }
    expect(selected, List<int>.generate(120, (int i) => i % 4));
    expect(tester.element(find.byType(TextField)), same(originalBody));
    expect(find.text('Pesquisa guardada'), findsOneWidget);
  });

  testWidgets('screen metrics change keeps menu and body available', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(phoneShell(body: const TextField(), onSelect: (_) {}));
    final Element originalBody = tester.element(find.byType(TextField));
    tester.view.physicalSize = const Size(720, 1280);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    expect(find.text('Conta').hitTestable(), findsOneWidget);
    expect(tester.element(find.byType(TextField)), same(originalBody));
    expect(tester.takeException(), isNull);
  });

  testWidgets('queued redraw is safe if backgrounded or disposed first', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(phoneShell(body: const SizedBox(), onSelect: (_) {}));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
