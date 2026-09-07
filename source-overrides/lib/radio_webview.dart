import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'config/radio_config.dart';
import 'notification_permission_service.dart';
import 'official_playlist_catalog_service.dart';
import 'offline_player.dart';
import 'radio_player_controller.dart';
import 'supporter_subscription.dart';
import 'supporter_subscription_sheet.dart';
import 'user_music_library.dart';
import 'webview_bridge.dart';

class RadioWebView extends StatefulWidget {
  const RadioWebView({
    required this.playerController,
    required this.subscriptionController,
    required this.userMusicLibraryStore,
    super.key,
  });

  final RadioPlayerController playerController;
  final SupporterSubscriptionController subscriptionController;
  final UserMusicLibraryStore userMusicLibraryStore;

  @override
  State<RadioWebView> createState() => _RadioWebViewState();
}

class _RadioWebViewState extends State<RadioWebView>
    with WidgetsBindingObserver {
  late final WebViewController _webViewController;
  late final WebViewWidget _webViewWidget;
  late final WebViewBridge _bridge;
  late final OfficialPlaylistCatalogService _playlistCatalog;
  final NotificationPermissionService _notificationPermission =
      NotificationPermissionService();

  bool _pageUnavailable = false;
  bool _nativeBridgeReady = false;
  bool _disposed = false;
  bool _handlingBack = false;
  bool _mainFrameFailed = false;
  bool _playlistRefreshInProgress = false;
  int _selectedDestination = 0;
  DateTime? _lastPlaylistRefreshAttempt;
  Uri? _currentMainFrameUri;
  bool _appInForeground = false;
  bool _checkingPage = false;
  int _navigationGeneration = 0;
  Timer? _pageLoadTimer;
  bool? _lastWebRuntimeActive;
  late bool _hasMusicAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appInForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _hasMusicAccess = widget.subscriptionController.hasMusicAccess;
    widget.subscriptionController.addListener(_handleSubscriptionChanged);
    _webViewController = WebViewController(
      onPermissionRequest: (WebViewPermissionRequest request) {
        unawaited(request.deny());
      },
    );
    _webViewWidget = _buildWebView();
    _playlistCatalog = OfficialPlaylistCatalogService();
    _bridge = WebViewBridge(
      widget.playerController,
      _webViewController.runJavaScript,
      userMusicLibraryStore: widget.userMusicLibraryStore,
    );
    unawaited(_startWebView());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool foreground = state == AppLifecycleState.resumed;
    if (_appInForeground == foreground) return;
    _appInForeground = foreground;
    unawaited(_syncWebRuntime());
    if (foreground) {
      unawaited(_checkPageOnResume());
      unawaited(widget.subscriptionController.refresh());
    } else {
      _pageLoadTimer?.cancel();
    }
  }

  void _handleSubscriptionChanged() {
    final bool hasAccess = widget.subscriptionController.hasMusicAccess;
    if (_hasMusicAccess == hasAccess) return;
    if (mounted) {
      setState(() => _hasMusicAccess = hasAccess);
    } else {
      _hasMusicAccess = hasAccess;
    }
    unawaited(_syncMusicAccess());
  }

  Future<void> _syncMusicAccess() async {
    if (_disposed || !_nativeBridgeReady) return;
    try {
      await _webViewController.runJavaScript(
        'if (typeof window.__RPA_SET_MUSIC_ACCESS === "function") { '
        'window.__RPA_SET_MUSIC_ACCESS(${_hasMusicAccess ? 'true' : 'false'}); }',
      );
    } on Object {
      // A página pode estar a mudar durante a confirmação da subscrição.
    }
  }

  Future<void> _startWebView() async {
    _armPageLoadTimeout();
    try {
      await _initialiseWebView();
    } on Object {
      _showFallback();
    }
  }

  void _armPageLoadTimeout() {
    _pageLoadTimer?.cancel();
    if (_disposed || !_appInForeground || _nativeBridgeReady) return;
    _pageLoadTimer = Timer(const Duration(seconds: 30), () {
      if (!_disposed && _appInForeground && !_nativeBridgeReady) {
        _showFallback();
      }
    });
  }

  Future<void> _checkPageOnResume() async {
    if (_disposed || _checkingPage) return;
    if (!_nativeBridgeReady) {
      // Loading is asynchronous. Do not reload a healthy page mid-navigation.
      if (_pageUnavailable) {
        await _retryPage();
      } else {
        _armPageLoadTimeout();
      }
      return;
    }
    _checkingPage = true;
    final int generation = _navigationGeneration;
    try {
      final Object healthy = await _webViewController
          .runJavaScriptReturningResult(
            'Boolean(document.body && document.body.childElementCount > 0 && '
            'typeof window.__RPA_SET_STATE === "function")',
          )
          .timeout(const Duration(seconds: 4));
      if (_disposed || !_appInForeground ||
          generation != _navigationGeneration) return;
      if (healthy != true && healthy != 'true') {
        await _retryPage();
      } else {
        await _syncWebRuntime(force: true);
        await _bridge.markPageReady();
      }
    } on Object {
      if (!_disposed && _appInForeground &&
          generation == _navigationGeneration) {
        _showFallback();
      }
    } finally {
      _checkingPage = false;
    }
  }

  Future<void> _syncWebRuntime({bool force = false}) async {
    final bool active =
        _appInForeground && _nativeBridgeReady;
    if (_disposed || (!force && active == _lastWebRuntimeActive)) return;
    _lastWebRuntimeActive = active;
    try {
      await _webViewController.runJavaScript(
        'if (typeof window.__RPA_SET_ACTIVE === "function") { '
        'window.__RPA_SET_ACTIVE(${active ? 'true' : 'false'}); }',
      );
    } on Object {
      // A página pode estar a mudar enquanto o modo automóvel é activado.
    }
  }

  Future<void> _initialiseWebView() async {
    await _webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _webViewController.setBackgroundColor(const Color(0xFFF7F2E9));
    await _webViewController.setUserAgent(RadioConfig.userAgent);
    await _webViewController.addJavaScriptChannel(
      RadioConfig.javascriptChannel,
      onMessageReceived: (JavaScriptMessage message) {
        _handleJavaScriptMessage(message.message);
      },
    );
    await _webViewController.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) {
          _navigationGeneration += 1;
          _currentMainFrameUri = Uri.tryParse(url);
          _mainFrameFailed = false;
          _bridge.markPageLoading();
          _lastWebRuntimeActive = null;
          if (mounted && _nativeBridgeReady) {
            setState(() => _nativeBridgeReady = false);
          }
          _armPageLoadTimeout();
        },
        onPageFinished: (_) async {
          if (_disposed || _mainFrameFailed) {
            return;
          }
          final int generation = _navigationGeneration;
          try {
            final String playlistBootstrap =
                await _loadOfficialPlaylistsBootstrap();
            final String bridgeScript = await rootBundle.loadString(
              RadioConfig.bridgeAsset,
            );
            if (_disposed || generation != _navigationGeneration) {
              return;
            }
            await _webViewController.runJavaScript(playlistBootstrap);
            await _webViewController.runJavaScript(
              'window.__RPA_MUSIC_ACCESS = '
              '${_hasMusicAccess ? 'true' : 'false'};',
            );
            await _webViewController.runJavaScript(bridgeScript);
            if (_disposed || generation != _navigationGeneration) return;
            await _bridge.markPageReady();
            if (_disposed || generation != _navigationGeneration) return;
            _pageLoadTimer?.cancel();
            if (mounted) {
              setState(() {
                _pageUnavailable = false;
                _nativeBridgeReady = true;
              });
              if (_selectedDestination == 1) {
                await _webViewController.runJavaScript(
                  'if (typeof window.__RPA_SHOW_MUSIC === "function") { '
                  'window.__RPA_SHOW_MUSIC(); }',
                );
              }
              await _syncWebRuntime(force: true);
              unawaited(_refreshOfficialPlaylists(force: true));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_disposed && _appInForeground &&
                    _nativeBridgeReady) {
                  unawaited(_notificationPermission.requestWhenUseful());
                }
              });
            }
          } on Object {
            if (generation == _navigationGeneration) _showFallback();
          }
        },
        onNavigationRequest: _handleNavigation,
        onWebResourceError: (WebResourceError error) {
          if (error.isForMainFrame == true) {
            _showFallback();
          }
        },
        onHttpError: (HttpResponseError error) {
          final Uri? failedUri = error.request?.uri;
          final int? status = error.response?.statusCode;
          if (failedUri == _currentMainFrameUri &&
              status != null &&
              status >= 400) {
            _showFallback();
          }
        },
        onSslAuthError: (SslAuthError error) {
          unawaited(error.cancel());
          _showFallback();
        },
      ),
    );

    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      await AndroidWebViewController.enableDebugging(kDebugMode);
      await platform.setAllowFileAccess(false);
      await platform.setAllowContentAccess(false);
      await platform.setGeolocationEnabled(false);
      await platform.setMediaPlaybackRequiresUserGesture(true);
      await platform.setMixedContentMode(MixedContentMode.neverAllow);
      await platform.setOnShowFileSelector((_) async => const <String>[]);
    }

    if (!_disposed) {
      await _webViewController.loadRequest(RadioConfig.appPage);
    }
  }

  Future<String> _loadOfficialPlaylistsBootstrap() async {
    try {
      final String source = await rootBundle.loadString(
        RadioConfig.officialPlaylistsAsset,
      );
      final Map<String, Object?> catalog =
          await _playlistCatalog.loadBest(source);
      return 'window.__RPA_OFFICIAL_PLAYLISTS = ${jsonEncode(catalog)};';
    } on Object {
      return 'window.__RPA_OFFICIAL_PLAYLISTS = '
          '${jsonEncode(OfficialPlaylistCatalogService.emptyCatalog)};';
    }
  }

  Future<void> _refreshOfficialPlaylists({bool force = false}) async {
    if (_disposed || _playlistRefreshInProgress) {
      return;
    }
    final DateTime now = DateTime.now();
    if (!force &&
        _lastPlaylistRefreshAttempt != null &&
        now.difference(_lastPlaylistRefreshAttempt!) <
            const Duration(minutes: 15)) {
      return;
    }
    _playlistRefreshInProgress = true;
    _lastPlaylistRefreshAttempt = now;
    try {
      final Map<String, Object?>? catalog =
          await _playlistCatalog.refresh();
      if (catalog == null || _disposed || !_nativeBridgeReady) {
        return;
      }
      await _webViewController.runJavaScript(
        'if (typeof window.__RPA_UPDATE_OFFICIAL_PLAYLISTS === "function") { '
        'window.__RPA_UPDATE_OFFICIAL_PLAYLISTS(${jsonEncode(catalog)}); }',
      );
    } on Object {
      // O catálogo incorporado/em cache continua disponível.
    } finally {
      _playlistRefreshInProgress = false;
    }
  }

  WebViewWidget _buildWebView() {
    final Set<Factory<OneSequenceGestureRecognizer>> gestures =
        <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        };
    if (_webViewController.platform is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _webViewController.platform,
          gestureRecognizers: gestures,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(
      controller: _webViewController,
      gestureRecognizers: gestures,
    );
  }

  void _handleJavaScriptMessage(String message) {
    switch (message) {
      case 'NAV_RADIO':
        _setSelectedDestination(0);
        return;
      case 'NAV_MUSIC':
        _setSelectedDestination(1);
        return;
      case 'OPEN_SUBSCRIPTIONS':
        unawaited(_openSubscriptions());
        return;
      default:
        unawaited(_bridge.onMessage(message));
        return;
    }
  }

  void _setSelectedDestination(int destination) {
    if (mounted && _selectedDestination != destination) {
      setState(() => _selectedDestination = destination);
    }
  }

  Future<void> _selectDestination(int destination) async {
    switch (destination) {
      case 0:
        await _showRadioSection();
        return;
      case 1:
        await _showMusicSection();
        return;
      case 2:
        await _openWhatsapp();
        return;
    }
  }

  Future<void> _showRadioSection() async {
    _setSelectedDestination(0);
    if (!_nativeBridgeReady || _disposed) {
      return;
    }
    await _webViewController.runJavaScript(
      'if (typeof window.__RPA_SHOW_RADIO === "function") { '
      'window.__RPA_SHOW_RADIO(); }',
    );
  }

  Future<void> _showMusicSection() async {
    _setSelectedDestination(1);
    if (_pageUnavailable) {
      await _retryPage();
      return;
    }
    if (!_nativeBridgeReady || _disposed) {
      return;
    }
    unawaited(_refreshOfficialPlaylists());
    await _webViewController.runJavaScript(
      'if (typeof window.__RPA_SHOW_MUSIC === "function") { '
      'window.__RPA_SHOW_MUSIC(); }',
    );
  }

  Future<void> _openSubscriptions() async {
    if (!mounted || _disposed) return;
    await showSupporterSubscriptionSheet(
      context,
      widget.subscriptionController,
    );
  }

  Future<void> _openWhatsapp() async {
    bool launched = false;
    try {
      launched = await launchUrl(
        RadioConfig.whatsappContact,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        launched = await launchUrl(RadioConfig.whatsappContact);
      }
    } on Object {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final Uri? uri = Uri.tryParse(request.url);
    if (uri != null && RadioConfig.isAllowedHttpsUri(uri)) {
      return NavigationDecision.navigate;
    }

    if (request.isMainFrame &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.hasAuthority) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
    return NavigationDecision.prevent;
  }

  void _showFallback() {
    if (_disposed) return;
    _pageLoadTimer?.cancel();
    _mainFrameFailed = true;
    _bridge.markPageLoading();
    if (mounted && !_pageUnavailable) {
      setState(() {
        _pageUnavailable = true;
        _nativeBridgeReady = false;
      });
    }
  }

  Future<void> _retryPage() async {
    if (_disposed) return;
    _mainFrameFailed = false;
    if (mounted) {
      setState(() {
        _pageUnavailable = false;
        _nativeBridgeReady = false;
      });
    }
    _bridge.markPageLoading();
    _armPageLoadTimeout();
    try {
      await _webViewController.loadRequest(RadioConfig.appPage);
    } on Object {
      _showFallback();
    }
  }

  Future<void> _handleBack() async {
    if (_handlingBack) {
      return;
    }
    _handlingBack = true;
    try {
      if (_selectedDestination == 1) {
        await _showRadioSection();
        return;
      }
      if (await _webViewController.canGoBack()) {
        await _webViewController.goBack();
      } else {
        await SystemNavigator.pop();
      }
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: Scaffold(
        // Keep the native platform view mounted, including when a recoverable
        // page error is shown. Car audio is owned by AudioService, not this UI.
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _webViewWidget,
            if (_pageUnavailable)
              Positioned.fill(
                child: OfflinePlayer(
                  playerController: widget.playerController,
                  onRetryPage: () => unawaited(_retryPage()),
                ),
              )
            else if (!_nativeBridgeReady)
              const ColoredBox(
                color: Color(0xFFF7F2E9),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('A carregar a rádio…'),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            height: 68,
            selectedIndex: _selectedDestination,
            onDestinationSelected: (int destination) {
              unawaited(_selectDestination(destination));
            },
            backgroundColor: const Color(0xFFFFFBF5),
            indicatorColor: const Color(0xFFEBC9A4),
            destinations: <NavigationDestination>[
              const NavigationDestination(
                icon: Icon(Icons.radio_outlined),
                selectedIcon: Icon(Icons.radio),
                label: 'Rádio',
              ),
              NavigationDestination(
                icon: Icon(
                  _hasMusicAccess
                      ? Icons.library_music_outlined
                      : Icons.lock_outline,
                ),
                selectedIcon: Icon(
                  _hasMusicAccess ? Icons.library_music : Icons.lock_open,
                ),
                label: 'Música',
              ),
              const NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: 'WhatsApp',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.subscriptionController.removeListener(_handleSubscriptionChanged);
    _pageLoadTimer?.cancel();
    _playlistCatalog.close();
    unawaited(_bridge.dispose());
    super.dispose();
  }
}
