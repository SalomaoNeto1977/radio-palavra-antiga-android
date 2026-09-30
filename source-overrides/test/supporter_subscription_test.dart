import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:radio_palavra_antiga/collaborator_access.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/supporter_subscription.dart';

class _Codes implements CollaboratorCodeStore {
  String? hash;
  @override
  Future<String?> readHash() async => hash;
  @override
  Future<void> writeHash(String value) async { hash = value; }
  @override
  Future<void> clear() async { hash = null; }
}

void main() {
  test('Play restore without a purchase preserves offered collaborator access', () async {
    final access = CollaboratorAccessController(store: _Codes(),
        acceptedHashes: {sha256.convert(utf8.encode('0472')).toString()});
    final controller = SupporterSubscriptionController(
      billing: _FakeBilling(available: true),
      entitlementStore: _MemoryEntitlementStore.empty(),
      complimentaryAccess: access,
    );
    await access.activate('0472');
    expect(controller.hasMusicAccess, isTrue);
    await controller.start();
    expect(controller.hasMusicAccess, isTrue);
    expect(controller.activeProductId, isNull);
    await access.remove();
    expect(controller.hasMusicAccess, isFalse);
    controller.dispose();
    access.dispose();
  });

  test('removing collaborator access preserves an active paid subscription', () async {
    final access = CollaboratorAccessController(store: _Codes(),
        acceptedHashes: {sha256.convert(utf8.encode('0472')).toString()});
    final controller = SupporterSubscriptionController(
      billing: _FakeBilling(available: false),
      entitlementStore: _MemoryEntitlementStore(CachedSubscriptionEntitlement(
        active: true, productId: SupporterPlans.all.first.productId, verifiedAt: DateTime.now())),
      complimentaryAccess: access,
    );
    await controller.loadCachedEntitlement();
    await access.activate('0472');
    await access.remove();
    expect(controller.hasMusicAccess, isTrue);
    controller.dispose();
    access.dispose();
  });

  final DateTime now = DateTime.utc(2026, 9, 4, 12);

  test('mantém por três dias a última confirmação para uso offline', () async {
    final _FakeBilling billing = _FakeBilling(available: false);
    final _MemoryEntitlementStore store = _MemoryEntitlementStore(
      CachedSubscriptionEntitlement(
        active: true,
        productId: SupporterPlans.all.first.productId,
        verifiedAt: now.subtract(const Duration(days: 2)),
      ),
    );
    final SupporterSubscriptionController controller =
        SupporterSubscriptionController(
          billing: billing,
          entitlementStore: store,
          clock: () => now,
        );

    await controller.loadCachedEntitlement();
    await controller.start();

    expect(controller.hasMusicAccess, isTrue);
    expect(controller.message, contains('última confirmação'));
    controller.dispose();
  });

  test('uma confirmação antiga não mantém acesso indefinidamente', () async {
    final _FakeBilling billing = _FakeBilling(available: false);
    final _MemoryEntitlementStore store = _MemoryEntitlementStore(
      CachedSubscriptionEntitlement(
        active: true,
        productId: SupporterPlans.all.first.productId,
        verifiedAt: now.subtract(const Duration(days: 4)),
      ),
    );
    final SupporterSubscriptionController controller =
        SupporterSubscriptionController(
          billing: billing,
          entitlementStore: store,
          clock: () => now,
        );

    await controller.loadCachedEntitlement();

    expect(controller.hasMusicAccess, isFalse);
    expect(store.cleared, isTrue);
    controller.dispose();
  });

  test('restauro válido ativa música e conclui a compra', () async {
    final SupporterPlan plan = SupporterPlans.all[1];
    final BillingPurchase purchase = BillingPurchase(
      eventId: 'purchase-1',
      productId: plan.productId,
      status: BillingPurchaseStatus.restored,
      verificationData: 'token-google-play',
      needsCompletion: true,
    );
    final _FakeBilling billing = _FakeBilling(
      available: true,
      restored: <BillingPurchase>[purchase],
    );
    final _MemoryEntitlementStore store = _MemoryEntitlementStore.empty();
    final SupporterSubscriptionController controller =
        SupporterSubscriptionController(
          billing: billing,
          entitlementStore: store,
          clock: () => now,
        );

    await controller.loadCachedEntitlement();
    await controller.start();

    expect(controller.hasMusicAccess, isTrue);
    expect(controller.activeProductId, plan.productId);
    expect(store.value.active, isTrue);
    expect(billing.completed, <String>['purchase-1']);
    controller.dispose();
  });

  test('conta sem subscrição ativa fica apenas com o acesso gratuito', () async {
    final _FakeBilling billing = _FakeBilling(
      available: true,
      restored: const <BillingPurchase>[],
    );
    final _MemoryEntitlementStore store = _MemoryEntitlementStore(
      CachedSubscriptionEntitlement(
        active: true,
        productId: SupporterPlans.all.first.productId,
        verifiedAt: now,
      ),
    );
    final SupporterSubscriptionController controller =
        SupporterSubscriptionController(
          billing: billing,
          entitlementStore: store,
          clock: () => now,
        );

    await controller.loadCachedEntitlement();
    expect(controller.hasMusicAccess, isTrue);
    await controller.start();

    expect(controller.hasMusicAccess, isFalse);
    expect(store.cleared, isTrue);
    controller.dispose();
  });

  test('a escolha inicia o produto mensal correspondente', () async {
    final SupporterPlan plan = SupporterPlans.all[2];
    final _FakeBilling billing = _FakeBilling(
      available: true,
      restored: const <BillingPurchase>[],
    );
    final SupporterSubscriptionController controller =
        SupporterSubscriptionController(
          billing: billing,
          entitlementStore: _MemoryEntitlementStore.empty(),
          clock: () => now,
        );
    await controller.loadCachedEntitlement();
    await controller.start();

    await controller.purchase(plan);

    expect(billing.purchased, <String>[plan.productId]);
    expect(controller.purchasePending, isTrue);
    controller.dispose();
  });
}

class _FakeBilling implements SubscriptionBillingGateway {
  _FakeBilling({required this.available, this.restored = const <BillingPurchase>[]});

  final bool available;
  final List<BillingPurchase> restored;
  final StreamController<List<BillingPurchase>> _updates =
      StreamController<List<BillingPurchase>>.broadcast(sync: true);
  final List<String> purchased = <String>[];
  final List<String> completed = <String>[];

  @override
  Stream<List<BillingPurchase>> get purchaseUpdates => _updates.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BillingProductsResult> queryProducts(Set<String> productIds) async {
    return BillingProductsResult(
      products: SupporterPlans.all
          .map(
            (SupporterPlan plan) => BillingProduct(
              id: plan.productId,
              title: plan.name,
              description: 'Apoio mensal',
              price: plan.fallbackPrice,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<bool> purchase(String productId) async {
    purchased.add(productId);
    return true;
  }

  @override
  Future<List<BillingPurchase>> restorePurchases() async => restored;

  @override
  Future<void> completePurchase(BillingPurchase purchase) async {
    completed.add(purchase.eventId);
  }

  @override
  Future<void> dispose() async => _updates.close();
}

class _MemoryEntitlementStore implements SubscriptionEntitlementStore {
  _MemoryEntitlementStore(this.value);

  _MemoryEntitlementStore.empty()
    : value = const CachedSubscriptionEntitlement(active: false);

  CachedSubscriptionEntitlement value;
  bool cleared = false;

  @override
  Future<CachedSubscriptionEntitlement> read() async => value;

  @override
  Future<void> writeActive(String productId, DateTime verifiedAt) async {
    value = CachedSubscriptionEntitlement(
      active: true,
      productId: productId,
      verifiedAt: verifiedAt,
    );
    cleared = false;
  }

  @override
  Future<void> clear() async {
    value = const CachedSubscriptionEntitlement(active: false);
    cleared = true;
  }
}
