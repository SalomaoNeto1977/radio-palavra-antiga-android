import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/account_page.dart';
import 'package:radio_palavra_antiga/supporter_subscription.dart';
import 'package:radio_palavra_antiga/user_music_library.dart';

class _Billing implements SubscriptionBillingGateway {
  @override
  Stream<List<BillingPurchase>> get purchaseUpdates => const Stream.empty();
  @override
  Future<void> completePurchase(BillingPurchase purchase) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> purchase(String productId) async => false;
  @override
  Future<BillingProductsResult> queryProducts(Set<String> ids) async => const BillingProductsResult(products: []);
  @override
  Future<List<BillingPurchase>> restorePurchases() async => [];
}

class _Entitlements implements SubscriptionEntitlementStore {
  @override
  Future<CachedSubscriptionEntitlement> read() async => CachedSubscriptionEntitlement(
    active: true, productId: 'apoio_mensal_999', verifiedAt: DateTime.now(),
  );
  @override
  Future<void> clear() async {}
  @override
  Future<void> writeActive(String id, DateTime at) async {}
}

class _Library implements UserMusicLibraryStore {
  @override
  Future<UserMusicLibrary> read() async => const UserMusicLibrary(favorites: ['a', 'b'], playlists: {'Louvor': ['a']});
  @override
  Future<void> write(UserMusicLibrary value) async {}
}

void main() {
  testWidgets('account shows actual plan and library; restart requires confirmation', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SupporterSubscriptionController(billing: _Billing(), entitlementStore: _Entitlements());
    addTearDown(controller.dispose);
    await controller.loadCachedEntitlement();
    int restarts = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountPage(
      controller: controller,
      libraryStore: _Library(),
      onSupport: () async {},
      onRestart: () async { restarts++; },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Apoio Companheiro'), findsOneWidget);
    expect(find.text('2 favoritos · 1 playlists pessoais'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Reiniciar aplicação e leitor'), 250);
    await tester.tap(find.text('Reiniciar aplicação e leitor'));
    await tester.pumpAndSettle();
    expect(restarts, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(restarts, 0);
    await tester.tap(find.text('Reiniciar aplicação e leitor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reiniciar'));
    await tester.pumpAndSettle();
    expect(restarts, 1);
    expect(tester.takeException(), isNull);
  });
}
