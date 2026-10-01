import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/app_startup.dart';
import 'package:radio_palavra_antiga/collaborator_access.dart';
import 'package:radio_palavra_antiga/supporter_subscription.dart';

void main() {
  testWidgets('slow preference reads cannot later overwrite restored access', (tester) async {
    final offered = _PendingCodeStore();
    final cache = _PendingEntitlements();
    final collaborator = CollaboratorAccessController(store: offered, acceptedHashes: {'offered'});
    final subscriber = SupporterSubscriptionController(billing: _NoBilling(), entitlementStore: cache);
    addTearDown(collaborator.dispose);
    addTearDown(subscriber.dispose);
    final loads = Future.wait([collaborator.load(), subscriber.loadCachedEntitlement()]);
    await tester.pump(const Duration(seconds: 4));
    await loads;
    offered.pending.complete('offered');
    cache.pending.complete(CachedSubscriptionEntitlement(active: true, productId: 'apoio_mensal_999', verifiedAt: DateTime.now()));
    await tester.pump();
    expect(collaborator.hasMusicAccess, isFalse);
    expect(subscriber.hasMusicAccess, isFalse);
  });

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

class _PendingCodeStore implements CollaboratorCodeStore {
  final pending = Completer<String?>();
  @override
  Future<String?> readHash() => pending.future;
  @override
  Future<void> writeHash(String value) async {}
  @override
  Future<void> clear() async {}
}

class _PendingEntitlements implements SubscriptionEntitlementStore {
  final pending = Completer<CachedSubscriptionEntitlement>();
  @override
  Future<CachedSubscriptionEntitlement> read() => pending.future;
  @override
  Future<void> clear() async {}
  @override
  Future<void> writeActive(String id, DateTime date) async {}
}

class _NoBilling implements SubscriptionBillingGateway {
  @override
  Stream<List<BillingPurchase>> get purchaseUpdates => const Stream.empty();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<BillingProductsResult> queryProducts(Set<String> ids) async => const BillingProductsResult(products: []);
  @override
  Future<bool> purchase(String id) async => false;
  @override
  Future<List<BillingPurchase>> restorePurchases() async => [];
  @override
  Future<void> completePurchase(BillingPurchase purchase) async {}
  @override
  Future<void> dispose() async {}
}
