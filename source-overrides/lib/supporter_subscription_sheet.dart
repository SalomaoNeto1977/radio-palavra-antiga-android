import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/radio_config.dart';
import 'supporter_subscription.dart';

Future<void> showSupporterSubscriptionSheet(
  BuildContext context,
  SupporterSubscriptionController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: const Color(0xFFFFFBF5),
  builder: (BuildContext context) => _SupporterSubscriptionSheet(
    controller: controller,
  ),
);

class _SupporterSubscriptionSheet extends StatelessWidget {
  const _SupporterSubscriptionSheet({required this.controller});

  final SupporterSubscriptionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Column(
            children: <Widget>[
              const _SheetHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: <Widget>[
                    const _Introduction(),
                    if (controller.hasMusicAccess)
                      _ActiveSubscription(controller: controller),
                    if (controller.message case final String message)
                      _StatusMessage(
                        message: message,
                        positive: controller.hasMusicAccess,
                      ),
                    const SizedBox(height: 10),
                    for (final SupporterPlan plan in SupporterPlans.all)
                      _PlanCard(controller: controller, plan: plan),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: controller.purchasePending
                          ? null
                          : () => unawaited(controller.restore()),
                      icon: const Icon(Icons.restore),
                      label: const Text('Restaurar subscrição'),
                    ),
                    if (controller.hasMusicAccess)
                      TextButton.icon(
                        onPressed: () => unawaited(
                          launchUrl(
                            RadioConfig.googlePlaySubscriptions,
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Gerir na Google Play'),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Os apoios são subscrições mensais com renovação '
                      'automática. Podes cancelar a qualquer momento na '
                      'Google Play e manténs o acesso até ao fim do período '
                      'já pago.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6C625A),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Apoia a nossa rádio',
              style: TextStyle(
                color: Color(0xFF44210A),
                fontFamily: 'serif',
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Fechar',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF173222),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.library_music, color: Color(0xFFE8AD66)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Toda a nossa música, contigo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 9),
          Text(
            'Ao apoiares a rádio, podes ouvir todo o catálogo quando '
            'quiseres, criar playlists e guardar os teus favoritos.',
            style: TextStyle(
              color: Color(0xFFD5E2D9), fontSize: 13, height: 1.35,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Todos os planos incluem estas vantagens. '
            'Escolhe o valor do teu apoio.',
            style: TextStyle(
              color: Color(0xFFD5E2D9), fontSize: 13, height: 1.35,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Rádio em direto e pedidos de músicas: sempre gratuitos.',
            style: TextStyle(
              color: Color(0xFF9BE1B5),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSubscription extends StatelessWidget {
  const _ActiveSubscription({required this.controller});

  final SupporterSubscriptionController controller;

  @override
  Widget build(BuildContext context) {
    SupporterPlan? activePlan;
    for (final SupporterPlan plan in SupporterPlans.all) {
      if (plan.productId == controller.activeProductId) {
        activePlan = plan;
        break;
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F4E8),
        border: Border.all(color: const Color(0xFF65A979)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.verified, color: Color(0xFF26723D)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              activePlan == null
                  ? 'A tua subscrição está ativa.'
                  : '${activePlan.name} ativo — obrigado!',
              style: const TextStyle(
                color: Color(0xFF19562D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.positive});

  final String message;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: positive
            ? const Color(0xFFEAF6ED)
            : const Color(0xFFFFF1DF),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: positive
              ? const Color(0xFF245E35)
              : const Color(0xFF78450E),
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.controller, required this.plan});

  final SupporterSubscriptionController controller;
  final SupporterPlan plan;

  @override
  Widget build(BuildContext context) {
    final BillingProduct? product = controller.productFor(plan.productId);
    final bool active = controller.activeProductId == plan.productId;
    final bool canPurchase = controller.storeAvailable &&
        product != null &&
        !controller.purchasePending &&
        !controller.hasMusicAccess;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: active ? 2 : 0,
      color: active ? const Color(0xFFFFEBD3) : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: active
              ? const Color(0xFFB36B1E)
              : const Color(0xFFE1D7CD),
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    plan.name,
                    style: const TextStyle(
                      color: Color(0xFF3C281A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${product?.price ?? plan.fallbackPrice} por mês',
                    style: const TextStyle(color: Color(0xFF75685F)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: canPurchase
                  ? () => unawaited(controller.purchase(plan))
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7B3900),
              ),
              child: Text(active ? 'Ativo' : 'Escolher'),
            ),
          ],
        ),
      ),
    );
  }
}
