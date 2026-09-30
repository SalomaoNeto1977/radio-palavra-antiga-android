import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/radio_config.dart';
import 'supporter_subscription.dart';
import 'user_music_library.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    required this.controller,
    required this.libraryStore,
    required this.onSupport,
    required this.onRestart,
    super.key,
  });

  final SupporterSubscriptionController controller;
  final UserMusicLibraryStore libraryStore;
  final Future<void> Function() onSupport;
  final Future<void> Function() onRestart;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final Future<UserMusicLibrary> _library = widget.libraryStore.read();
  bool _restarting = false;

  String get _version => '${RadioConfig.appVersion}${kDebugMode ? ' · Teste' : ''}';

  Future<void> _open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } on Object {
      // A missing email or browser app should leave the account page usable.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(
        'Não foi possível abrir. Contacta-nos em radio@palavraantiga.org.',
      )),
    );
  }

  Future<void> _report({required bool email}) async {
    final String body = 'Olá, Rádio Palavra Antiga!\n'
        'Encontrei um problema na aplicação $_version.\n\n'
        'O que aconteceu:\n\n'
        'O que estava a fazer:\n\n'
        'Modelo do telefone e versão do Android:\n';
    final Uri uri = email
        ? Uri(
            scheme: 'mailto',
            path: RadioConfig.supportEmail,
            query: 'subject=${Uri.encodeComponent('Problema na app — $_version')}'
                '&body=${Uri.encodeComponent(body)}',
          )
        : RadioConfig.whatsappContact.replace(
            queryParameters: <String, String>{'text': body},
          );
    await _open(uri);
  }

  Future<void> _restart() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar a aplicação?'),
        content: const Text(
          'O som vai parar e o leitor das notificações será encerrado. '
          'A aplicação volta a abrir sem tocar automaticamente. '
          'Os teus favoritos, playlists e dados do apoio serão preservados.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reiniciar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restarting = true);
    try {
      await widget.onRestart();
    } on Object {
      if (mounted) {
        setState(() => _restarting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível reiniciar. Fecha a aplicação e volta a abri-la.'),
        ));
      }
    }
  }

  void _showTerms() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Condições do apoio'),
        content: const SingleChildScrollView(child: Text(
          'Todos os planos de apoio incluem o acesso a todo o catálogo, '
          'às playlists e aos favoritos. Escolhes o valor com que desejas apoiar a rádio.\n\n'
          'Os apoios são subscrições mensais com renovação automática, '
          'processadas pela Google Play. O preço é apresentado antes da confirmação da compra.\n\n'
          'Podes cancelar a qualquer momento na Google Play e manténs o acesso '
          'até ao fim do período já pago.\n\n'
          'A rádio em direto e os pedidos de músicas continuam gratuitos.',
        )),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Widget _link(IconData icon, String title, VoidCallback? onTap, {String? subtitle}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: const Color(0xFF28573C)),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      enabled: onTap != null,
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFBF5),
    child: SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          SupporterPlan? plan;
          for (final candidate in SupporterPlans.all) {
            if (candidate.productId == controller.activeProductId) plan = candidate;
          }
          final bool busy = controller.loading || controller.purchasePending;
          final String status = controller.hasMusicAccess
              ? plan?.name ?? 'Apoiante'
              : controller.loading
                  ? 'A verificar o teu apoio…'
                  : controller.purchasePending
                      ? 'A confirmar o apoio…'
                      : controller.message != null
                          ? 'Apoio por confirmar'
                          : 'Ouvinte da rádio';
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: <Widget>[
              const Text('A tua conta', style: TextStyle(fontSize: 24, fontFamily: 'serif', fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF173222), borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(children: <Widget>[
                    Icon(controller.hasMusicAccess ? Icons.verified : Icons.person_outline, color: const Color(0xFFE8AD66)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 8),
                  Text(controller.hasMusicAccess
                      ? 'Todo o catálogo contigo. Obrigado pelo teu apoio!'
                      : 'A rádio em direto e os pedidos de músicas estão sempre contigo.',
                    style: const TextStyle(color: Color(0xFFD5E2D9), fontSize: 13)),
                  if (controller.message != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(controller.message!, style: const TextStyle(color: Color(0xFFD5E2D9), fontSize: 12)),
                  ],
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8AD66), foregroundColor: const Color(0xFF173222)),
                    onPressed: () => unawaited(widget.onSupport()),
                    child: Text(controller.hasMusicAccess ? 'Ver planos de apoio' : 'Conhecer as vantagens'),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              const Text('Usas a rádio sem criar uma conta. O teu apoio fica associado à conta da Google Play usada na compra.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              const Text('O nome, o email e a data de renovação consultam-se na Google Play.', style: TextStyle(fontSize: 12, color: Color(0xFF6C625A))),
              _link(Icons.restore, 'Restaurar apoio', busy ? null : () => unawaited(controller.restore()), subtitle: 'Usa a mesma conta Google da compra.'),
              _link(Icons.manage_accounts_outlined, 'Gerir subscrição na Google Play', () => unawaited(_open(RadioConfig.googlePlaySubscriptions))),
              const Divider(),
              FutureBuilder<UserMusicLibrary>(
                future: _library,
                builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  const Text('A tua música neste telefone', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(snapshot.hasData
                      ? '${snapshot.data!.favorites.length} favoritos · ${snapshot.data!.playlists.length} playlists pessoais'
                      : 'A carregar a tua biblioteca…', style: const TextStyle(fontSize: 13)),
                ]),
              ),
              const Divider(height: 28),
              _link(Icons.description_outlined, 'Termos do apoio', _showTerms),
              _link(Icons.privacy_tip_outlined, 'Política de privacidade', () => unawaited(_open(RadioConfig.privacyPolicy))),
              _link(Icons.email_outlined, 'Comunicar um problema por email', () => unawaited(_report(email: true))),
              _link(Icons.chat_outlined, 'Pedir ajuda pelo WhatsApp', () => unawaited(_report(email: false))),
              const Divider(),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                onPressed: _restarting ? null : _restart,
                icon: const Icon(Icons.restart_alt, size: 20),
                label: Text(_restarting ? 'A reiniciar…' : 'Reiniciar aplicação e leitor'),
              )),
              Text('Versão $_version', style: const TextStyle(fontSize: 12, color: Color(0xFF6C625A))),
            ],
          );
        },
      ),
    ),
  );
}
