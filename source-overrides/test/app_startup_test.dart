import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/app_startup.dart';

void main() {
  testWidgets('paints a loading screen while platform startup is pending', (tester) async {
    final pending = Completer<String>();
    await tester.pumpWidget(AppStartup<String>(
      initialize: () => pending.future,
      builder: (value) => MaterialApp(home: Text(value)),
      restart: () async {},
    ));
    expect(find.text('A preparar a rádio…'), findsOneWidget);
    pending.complete('Interface pronta');
    await tester.pumpAndSettle();
    expect(find.text('Interface pronta'), findsOneWidget);
  });

  testWidgets('startup failure offers process recovery and reports the cause', (tester) async {
    Object? reported;
    int restarts = 0;
    int starts = 0;
    await tester.pumpWidget(AppStartup<String>(
      initialize: () { starts++; throw StateError('audio service failed'); },
      builder: (value) => Text(value),
      restart: () async { restarts++; },
      onError: (error, stack) => reported = error,
    ));
    await tester.pumpAndSettle();
    expect(reported, isA<StateError>());
    expect(find.text('Reiniciar aplicação'), findsOneWidget);
    await tester.tap(find.text('Reiniciar aplicação'));
    await tester.pump();
    expect(restarts, 1);
    expect(starts, 1);
  });

  testWidgets('a hung service times out; late completion cannot duplicate startup', (tester) async {
    final pending = Completer<String>();
    Object? reported;
    await tester.pumpWidget(AppStartup<String>(
      initialize: () => pending.future,
      timeout: const Duration(seconds: 2),
      builder: (value) => Text(value),
      restart: () async {},
      onError: (error, stack) => reported = error,
    ));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(reported, isA<TimeoutException>());
    expect(find.text('Reiniciar aplicação'), findsOneWidget);
    pending.complete('Late interface');
    await tester.pumpAndSettle();
    expect(find.text('Late interface'), findsNothing);
  });
}
