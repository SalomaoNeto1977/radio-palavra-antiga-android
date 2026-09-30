import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/collaborator_access.dart';
import 'package:radio_palavra_antiga/collaborator_code_dialog.dart';

class MemoryCodes implements CollaboratorCodeStore {
  String? hash;
  bool fail = false;
  @override
  Future<String?> readHash() async => hash;
  @override
  Future<void> writeHash(String value) async {
    if (fail) throw StateError('disk error');
    hash = value;
  }
  @override
  Future<void> clear() async { hash = null; }
}

void main() {
  final accepted = <String>{sha256.convert(utf8.encode('0472')).toString()};
  CollaboratorAccessController controller(MemoryCodes store) =>
      CollaboratorAccessController(store: store, acceptedHashes: accepted);

  test('valid code, including a leading zero, survives restarting the controller', () async {
    final store = MemoryCodes();
    final first = controller(store);
    final events = <bool>[];
    final subscription = first.musicAccessChanges.listen(events.add);
    expect(await first.activate('0472'), isTrue);
    expect(first.hasMusicAccess, isTrue);
    expect(store.hash, accepted.single);
    expect(events, [true]);
    final second = controller(store);
    await second.load();
    expect(second.hasMusicAccess, isTrue);
    await second.remove();
    expect(second.hasMusicAccess, isFalse);
    expect(store.hash, isNull);
    await subscription.cancel();
    first.dispose();
    second.dispose();
  });

  test('incorrect or incomplete code never grants access or writes storage', () async {
    final store = MemoryCodes();
    final access = controller(store);
    for (final code in ['1234', '047', '04720', ' 0472', 'abcd']) {
      expect(await access.activate(code), isFalse);
      expect(access.hasMusicAccess, isFalse);
      expect(store.hash, isNull);
    }
    access.dispose();
  });

  test('failed storage write does not grant access; unknown saved hash is removed', () async {
    final store = MemoryCodes()..fail = true;
    final access = controller(store);
    expect(await access.activate('0472'), isFalse);
    expect(access.hasMusicAccess, isFalse);
    store.hash = 'unknown';
    await access.load();
    expect(store.hash, isNull);
    expect(access.hasMusicAccess, isFalse);
    access.dispose();
  });

  testWidgets('small dialog rejects an invalid code and accepts a valid code', (tester) async {
    final access = controller(MemoryCodes());
    addTearDown(access.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showCollaboratorCodeDialog(context, access),
        child: const Text('Abrir'),
      ),
    ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('O código não é válido. Confirma os quatro dígitos.'), findsOneWidget);
    expect(access.hasMusicAccess, isFalse);
    await tester.enterText(find.byType(TextField), '0472');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(access.hasMusicAccess, isTrue);
    expect(tester.takeException(), isNull);
  });
}
