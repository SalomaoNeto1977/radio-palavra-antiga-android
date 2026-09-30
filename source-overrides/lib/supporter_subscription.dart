import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_access.dart';

class SupporterPlan {
  const SupporterPlan({
    required this.productId,
    required this.name,
    required this.fallbackPrice,
  });

  final String productId;
  final String name;
  final String fallbackPrice;
}

abstract final class SupporterPlans {
  static const List<SupporterPlan> all = <SupporterPlan>[
    SupporterPlan(
      productId: 'apoio_mensal_590',
      name: 'Apoio Amigo',
      fallbackPrice: '5,99 €',
    ),
    SupporterPlan(
      productId: 'apoio_mensal_999',
      name: 'Apoio Companheiro',
      fallbackPrice: '9,99 €',
    ),
    SupporterPlan(
      productId: 'apoio_mensal_1999',
      name: 'Apoio Fiel',
      fallbackPrice: '19,99 €',
    ),
    SupporterPlan(
      productId: 'apoio_mensal_4999',
      name: 'Apoio Semeador',
      fallbackPrice: '49,99 €',
    ),
  ];

  static const Set<String> productIds = <String>{
    'apoio_mensal_590',
    'apoio_mensal_999',
    'apoio_mensal_1999',
    'apoio_mensal_4999',
  };
}

class BillingProduct {
  const BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;
  final String price;
}

class BillingProductsResult {
  const BillingProductsResult({
    required this.products,
    this.notFoundIds = const <String>{},
    this.error,
  });

  final List<BillingProduct> products;
  final Set<String> notFoundIds;
  final String? error;
}

enum BillingPurchaseStatus { pending, purchased, restored, cancelled, error }

class BillingPurchase {
  const BillingPurchase({
    required this.eventId,
    required this.productId,
    required this.status,
    required this.verificationData,
    required this.needsCompletion,
    this.error,
  });

  final String eventId;
  final String productId;
  final BillingPurchaseStatus status;
  final String verificationData;
  final bool needsCompletion;
  final String? error;
}

abstract interface class SubscriptionBillingGateway {
  Stream<List<BillingPurchase>> get purchaseUpdates;

  Future<bool> isAvailable();

  Future<BillingProductsResult> queryProducts(Set<String> productIds);

  Future<bool> purchase(String productId);

  Future<List<BillingPurchase>> restorePurchases();

  Future<void> completePurchase(BillingPurchase purchase);

  Future<void> dispose();
}

class PlaySubscriptionBillingGateway implements SubscriptionBillingGateway {
  PlaySubscriptionBillingGateway({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseDetails,
      onError: _purchaseUpdates.addError,
    );
  }

  final InAppPurchase _inAppPurchase;
  final StreamController<List<BillingPurchase>> _purchaseUpdates =
      StreamController<List<BillingPurchase>>.broadcast(sync: true);
  final Map<String, ProductDetails> _products = <String, ProductDetails>{};
  final Map<String, PurchaseDetails> _rawPurchases =
      <String, PurchaseDetails>{};
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;

  @override
  Stream<List<BillingPurchase>> get purchaseUpdates =>
      _purchaseUpdates.stream;

  @override
  Future<bool> isAvailable() => _inAppPurchase.isAvailable();

  @override
  Future<BillingProductsResult> queryProducts(Set<String> productIds) async {
    final ProductDetailsResponse response =
        await _inAppPurchase.queryProductDetails(productIds);
    _products
      ..clear()
      ..addEntries(
        response.productDetails.map(
          (ProductDetails product) => MapEntry<String, ProductDetails>(
            product.id,
            product,
          ),
        ),
      );
    return BillingProductsResult(
      products: response.productDetails
          .map(
            (ProductDetails product) => BillingProduct(
              id: product.id,
              title: product.title,
              description: product.description,
              price: product.price,
            ),
          )
          .toList(growable: false),
      notFoundIds: response.notFoundIDs.toSet(),
      error: response.error?.message,
    );
  }

  @override
  Future<bool> purchase(String productId) async {
    final ProductDetails? product = _products[productId];
    if (product == null) return false;
    return _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  @override
  Future<List<BillingPurchase>> restorePurchases() async {
    final Completer<List<BillingPurchase>> restored =
        Completer<List<BillingPurchase>>();
    late final StreamSubscription<List<BillingPurchase>> subscription;
    subscription = purchaseUpdates.listen((List<BillingPurchase> purchases) {
      if (!restored.isCompleted) restored.complete(purchases);
    });
    try {
      await _inAppPurchase.restorePurchases();
      return await restored.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => const <BillingPurchase>[],
      );
    } finally {
      await subscription.cancel();
    }
  }

  void _handlePurchaseDetails(List<PurchaseDetails> details) {
    final List<BillingPurchase> converted = details.map((PurchaseDetails raw) {
      final String eventId = <String>[
        raw.productID,
        raw.purchaseID ?? '',
        raw.transactionDate ?? '',
      ].join('|');
      _rawPurchases[eventId] = raw;
      return BillingPurchase(
        eventId: eventId,
        productId: raw.productID,
        status: switch (raw.status) {
          PurchaseStatus.pending => BillingPurchaseStatus.pending,
          PurchaseStatus.purchased => BillingPurchaseStatus.purchased,
          PurchaseStatus.restored => BillingPurchaseStatus.restored,
          PurchaseStatus.canceled => BillingPurchaseStatus.cancelled,
          PurchaseStatus.error => BillingPurchaseStatus.error,
        },
        verificationData: raw.verificationData.serverVerificationData,
        needsCompletion: raw.pendingCompletePurchase,
        error: raw.error?.message,
      );
    }).toList(growable: false);
    _purchaseUpdates.add(converted);
  }

  @override
  Future<void> completePurchase(BillingPurchase purchase) async {
    final PurchaseDetails? raw = _rawPurchases[purchase.eventId];
    if (raw != null && raw.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(raw);
    }
  }

  @override
  Future<void> dispose() async {
    await _purchaseSubscription.cancel();
    await _purchaseUpdates.close();
  }
}

class CachedSubscriptionEntitlement {
  const CachedSubscriptionEntitlement({
    required this.active,
    this.productId,
    this.verifiedAt,
  });

  final bool active;
  final String? productId;
  final DateTime? verifiedAt;
}

abstract interface class SubscriptionEntitlementStore {
  Future<CachedSubscriptionEntitlement> read();

  Future<void> writeActive(String productId, DateTime verifiedAt);

  Future<void> clear();
}

class SharedPreferencesSubscriptionEntitlementStore
    implements SubscriptionEntitlementStore {
  SharedPreferencesSubscriptionEntitlementStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _activeKey = 'rpa.subscription.active.v1';
  static const String _productKey = 'rpa.subscription.product.v1';
  static const String _verifiedAtKey = 'rpa.subscription.verified_at.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<CachedSubscriptionEntitlement> read() async {
    final bool active = await _preferences.getBool(_activeKey) ?? false;
    final String? productId = await _preferences.getString(_productKey);
    final DateTime? verifiedAt = DateTime.tryParse(
      await _preferences.getString(_verifiedAtKey) ?? '',
    );
    return CachedSubscriptionEntitlement(
      active: active,
      productId: productId,
      verifiedAt: verifiedAt,
    );
  }

  @override
  Future<void> writeActive(String productId, DateTime verifiedAt) async {
    await _preferences.setBool(_activeKey, true);
    await _preferences.setString(_productKey, productId);
    await _preferences.setString(
      _verifiedAtKey,
      verifiedAt.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_activeKey);
    await _preferences.remove(_productKey);
    await _preferences.remove(_verifiedAtKey);
  }
}

class SupporterSubscriptionController extends ChangeNotifier
    implements MusicAccessPort {
  SupporterSubscriptionController({
    required SubscriptionBillingGateway billing,
    required SubscriptionEntitlementStore entitlementStore,
    DateTime Function()? clock,
  }) : _billing = billing,
       _entitlementStore = entitlementStore,
       _clock = clock ?? DateTime.now {
    _purchaseSubscription = _billing.purchaseUpdates.listen(
      (List<BillingPurchase> purchases) {
        unawaited(_processPurchases(purchases));
      },
      onError: (Object _) {
        _setMessage('Não foi possível confirmar a compra na Google Play.');
      },
    );
  }

  static const Duration offlineGracePeriod = Duration(days: 3);

  final SubscriptionBillingGateway _billing;
  final SubscriptionEntitlementStore _entitlementStore;
  final DateTime Function() _clock;
  final StreamController<bool> _accessChanges =
      StreamController<bool>.broadcast(sync: true);
  late final StreamSubscription<List<BillingPurchase>> _purchaseSubscription;
  final Map<String, BillingProduct> _products = <String, BillingProduct>{};
  final Set<String> _completedEvents = <String>{};

  bool _hasMusicAccess = false;
  bool _loading = true;
  bool _storeAvailable = false;
  bool _purchasePending = false;
  bool _started = false;
  bool _refreshing = false;
  bool _disposed = false;
  String? _activeProductId;
  String? _message;

  @override
  bool get hasMusicAccess => _hasMusicAccess;

  @override
  Stream<bool> get musicAccessChanges => _accessChanges.stream;

  bool get loading => _loading;
  bool get storeAvailable => _storeAvailable;
  bool get purchasePending => _purchasePending;
  String? get activeProductId => _activeProductId;
  String? get message => _message;

  BillingProduct? productFor(String productId) => _products[productId];

  Future<void> loadCachedEntitlement() async {
    try {
      final CachedSubscriptionEntitlement cached =
          await _entitlementStore.read();
      final DateTime? verifiedAt = cached.verifiedAt;
      final bool fresh = cached.active &&
          cached.productId != null &&
          SupporterPlans.productIds.contains(cached.productId) &&
          verifiedAt != null &&
          _clock().toUtc().difference(verifiedAt.toUtc()) <=
              offlineGracePeriod;
      _activeProductId = fresh ? cached.productId : null;
      _setAccess(fresh);
      if (!fresh && cached.active) await _entitlementStore.clear();
    } on Object {
      _setAccess(false);
    }
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    _setLoading(true);
    try {
      _storeAvailable = await _billing.isAvailable();
      if (!_storeAvailable) {
        _setMessage(
          _hasMusicAccess
              ? 'A usar temporariamente a última confirmação da subscrição.'
              : 'Instala a aplicação pela Google Play para ativar os apoios.',
        );
        return;
      }

      final BillingProductsResult result =
          await _billing.queryProducts(SupporterPlans.productIds);
      _products
        ..clear()
        ..addEntries(
          result.products.map(
            (BillingProduct product) =>
                MapEntry<String, BillingProduct>(product.id, product),
          ),
        );
      if (result.error != null) {
        _setMessage('A Google Play ainda não devolveu os planos de apoio.');
      }
      final List<BillingPurchase> restored =
          await _billing.restorePurchases();
      final bool hasValidPurchase = await _processPurchases(restored);
      if (!hasValidPurchase) {
        _activeProductId = null;
        _setAccess(false);
        await _entitlementStore.clear();
      }
      if (result.error == null && result.notFoundIds.isEmpty) {
        _setMessage(null);
      } else if (_products.isEmpty) {
        _setMessage('Os planos de apoio ainda não estão ativos na Google Play.');
      }
    } on Object {
      _setMessage(
        _hasMusicAccess
            ? 'A usar temporariamente a última confirmação da subscrição.'
            : 'Não foi possível ligar à Google Play. Tenta novamente.',
      );
    } finally {
      _refreshing = false;
      _setLoading(false);
    }
  }

  Future<void> purchase(SupporterPlan plan) async {
    if (_disposed || _purchasePending) return;
    if (!_storeAvailable || !_products.containsKey(plan.productId)) {
      _setMessage('Este apoio ainda não está disponível na Google Play.');
      return;
    }
    _purchasePending = true;
    _setMessage(null);
    notifyListeners();
    try {
      final bool launched = await _billing.purchase(plan.productId);
      if (!launched) {
        _purchasePending = false;
        _setMessage('Não foi possível abrir o pagamento da Google Play.');
      }
    } on Object {
      _purchasePending = false;
      _setMessage('Não foi possível iniciar o pagamento. Tenta novamente.');
    }
  }

  Future<void> restore() async {
    if (_disposed || _purchasePending) return;
    _purchasePending = true;
    _setMessage('A confirmar a subscrição na Google Play…');
    notifyListeners();
    try {
      final bool available = await _billing.isAvailable();
      if (!available) {
        _setMessage('Não foi possível ligar à Google Play.');
        return;
      }
      final List<BillingPurchase> restored =
          await _billing.restorePurchases();
      final bool active = await _processPurchases(restored);
      if (!active) {
        _activeProductId = null;
        _setAccess(false);
        await _entitlementStore.clear();
        _setMessage('Não foi encontrada uma subscrição ativa nesta conta.');
      }
    } on Object {
      _setMessage('Não foi possível restaurar a subscrição.');
    } finally {
      _purchasePending = false;
      notifyListeners();
    }
  }

  Future<bool> _processPurchases(List<BillingPurchase> purchases) async {
    bool hasValidPurchase = false;
    for (final BillingPurchase purchase in purchases) {
      if (!SupporterPlans.productIds.contains(purchase.productId)) continue;
      switch (purchase.status) {
        case BillingPurchaseStatus.pending:
          _purchasePending = true;
          _setMessage('O pagamento está pendente na Google Play.');
          continue;
        case BillingPurchaseStatus.purchased ||
              BillingPurchaseStatus.restored:
          final bool valid = purchase.verificationData.isNotEmpty;
          if (valid) {
            hasValidPurchase = true;
            _purchasePending = false;
            _activeProductId = purchase.productId;
            _setAccess(true);
            await _entitlementStore.writeActive(
              purchase.productId,
              _clock().toUtc(),
            );
            _setMessage('Obrigado pelo teu apoio à Rádio Palavra Antiga!');
          } else {
            _purchasePending = false;
            _setMessage('A compra não pôde ser validada.');
          }
          if (valid &&
              purchase.needsCompletion &&
              _completedEvents.add(purchase.eventId)) {
            await _billing.completePurchase(purchase);
          }
          continue;
        case BillingPurchaseStatus.cancelled:
          _purchasePending = false;
          _setMessage(null);
          continue;
        case BillingPurchaseStatus.error:
          _purchasePending = false;
          _setMessage(
            purchase.error ?? 'A Google Play não conseguiu concluir a compra.',
          );
          continue;
      }
    }
    notifyListeners();
    return hasValidPurchase;
  }

  void _setAccess(bool value) {
    if (_hasMusicAccess == value) return;
    _hasMusicAccess = value;
    if (!_disposed) {
      _accessChanges.add(value);
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }

  void _setMessage(String? value) {
    if (_message == value) return;
    _message = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_purchaseSubscription.cancel());
    unawaited(_billing.dispose());
    unawaited(_accessChanges.close());
    super.dispose();
  }
}
