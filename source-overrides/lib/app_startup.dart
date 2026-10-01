import 'dart:async';

import 'package:flutter/material.dart';

/// Paint the first frame before waiting for platform services. Recovery restarts
/// the process, so a timed-out AudioService init cannot create a second handler.
class AppStartup<T> extends StatefulWidget {
  const AppStartup({
    required this.initialize,
    required this.builder,
    required this.restart,
    this.onError,
    this.timeout = const Duration(seconds: 25),
    super.key,
  });

  final Future<T> Function() initialize;
  final Widget Function(T) builder;
  final Future<void> Function() restart;
  final void Function(Object, StackTrace)? onError;
  final Duration timeout;

  @override
  State<AppStartup<T>> createState() => _AppStartupState<T>();
}

class _AppStartupState<T> extends State<AppStartup<T>> {
  T? _value;
  bool _ready = false;
  bool _failed = false;
  bool _restarting = false;
  bool _restartFailed = false;

  @override
  void initState() {
    super.initState();
    // Let Flutter paint even if an initializer throws synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    try {
      final T value = await widget.initialize().timeout(widget.timeout);
      if (!mounted) return;
      setState(() {
        _value = value;
        _ready = true;
      });
    } on Object catch (error, stack) {
      widget.onError?.call(error, stack);
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _restart() async {
    if (_restarting) return;
    setState(() {
      _restarting = true;
      _restartFailed = false;
    });
    try {
      await widget.restart().timeout(const Duration(seconds: 5));
    } on Object catch (error, stack) {
      widget.onError?.call(error, stack);
      if (mounted) {
        setState(() {
          _restarting = false;
          _restartFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(_value as T);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B3900)),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F2E9),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.radio, size: 56, color: Color(0xFF7B3900)),
                  const SizedBox(height: 20),
                  const Text('Rádio Palavra Antiga', style: TextStyle(fontSize: 24), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (!_failed) ...<Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('A preparar a rádio…'),
                  ] else ...<Widget>[
                    const Text('Não foi possível iniciar a rádio. Reinicia a aplicação para tentar novamente.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _restarting ? null : _restart,
                      icon: const Icon(Icons.restart_alt),
                      label: Text(_restarting ? 'A reiniciar…' : 'Reiniciar aplicação'),
                    ),
                    if (_restartFailed) ...<Widget>[
                      const SizedBox(height: 16),
                      const Text('Fecha a aplicação e volta a abri-la.', textAlign: TextAlign.center),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
