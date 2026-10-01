import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_service.dart';
import 'app_restart.dart';
import 'app_startup.dart';
import 'config/radio_config.dart';
import 'foreground_interface.dart';
import 'native_music_catalog_service.dart';
import 'radio_audio_handler.dart';
import 'radio_player_controller.dart';
import 'radio_webview.dart';
import 'supporter_subscription.dart';
import 'collaborator_access.dart';
import 'user_music_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android Auto starts the shared engine without a phone surface. Initialize
  // audio immediately even when there is no Flutter frame to build the UI.
  final Future<RadioApp> initialization = initializeRadioApp();
  unawaited(initialization.then<void>((_) {}, onError: _reportStartupError));
  runApp(AppStartup<RadioApp>(
    initialize: () => initialization,
    builder: (RadioApp app) => app,
    restart: AppRestart.restartProcess,
    onError: (Object error, StackTrace stack) {
      if (error is TimeoutException) _reportStartupError(error, stack);
    },
  ));
}

void _reportStartupError(Object error, StackTrace stack) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'radio startup',
    context: ErrorDescription('while starting Rádio Palavra Antiga'),
  ));
}

Future<RadioApp> initializeRadioApp() async {

  final CollaboratorAccessController collaboratorController = CollaboratorAccessController(
    store: SharedPreferencesCollaboratorCodeStore(),
  );
  await collaboratorController.load();

  final SupporterSubscriptionController subscriptionController =
      SupporterSubscriptionController(
        billing: PlaySubscriptionBillingGateway(),
        entitlementStore: SharedPreferencesSubscriptionEntitlementStore(),
        complimentaryAccess: collaboratorController,
      );
  await subscriptionController.loadCachedEntitlement();
  unawaited(subscriptionController.start());

  final Uri? bundledArtwork = await ArtworkService.prepareBundledArtwork().timeout(
    const Duration(seconds: 3), onTimeout: () => null,
  );
  final String bundledOfficialPlaylists = await rootBundle.loadString(
    RadioConfig.officialPlaylistsAsset,
  );
  final UserMusicLibraryStore userMusicLibraryStore =
      SharedPreferencesUserMusicLibraryStore();
  final NativeMusicCatalogPort nativeMusicCatalog = NativeMusicCatalogService(
    bundledOfficialPlaylists: bundledOfficialPlaylists,
    userLibraryStore: userMusicLibraryStore,
  );
  final RadioAudioHandler audioHandler =
      await AudioService.init<RadioAudioHandler>(
        builder: () => RadioAudioHandler(
          bundledArtwork: bundledArtwork,
          nativeMusicCatalog: nativeMusicCatalog,
          musicAccess: subscriptionController,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: RadioConfig.notificationChannelId,
          androidNotificationChannelName: RadioConfig.notificationChannelName,
          androidNotificationIcon: RadioConfig.notificationIcon,
          notificationColor: Color(0xFF7B3900),
          // Com false/false, a notificação permanece obrigatória enquanto o
          // serviço continua em foreground, inclusive numa pausa técnica.
          androidNotificationOngoing: false,
          androidNotificationClickStartsActivity: true,
          androidResumeOnClick: true,
          androidStopForegroundOnPause: false,
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
        ),
      );
  // Media button availability must not prevent the phone interface from opening.
  unawaited(_enableMediaButtons());
  final RadioPlayerController playerController = RadioPlayerController(
    audioHandler,
  );

  return RadioApp(
      playerController: playerController,
      subscriptionController: subscriptionController,
      collaboratorController: collaboratorController,
      userMusicLibraryStore: userMusicLibraryStore,
  );
}

Future<void> _enableMediaButtons() async {
  try {
    await AudioService.androidForceEnableMediaButtons().timeout(
      const Duration(seconds: 3),
    );
  } on Object catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack,
      library: 'radio media buttons'));
  }
}

class RadioApp extends StatelessWidget {
  const RadioApp({
    required this.playerController,
    required this.subscriptionController,
    required this.collaboratorController,
    required this.userMusicLibraryStore,
    super.key,
  });

  final RadioPlayerController playerController;
  final SupporterSubscriptionController subscriptionController;
  final CollaboratorAccessController collaboratorController;
  final UserMusicLibraryStore userMusicLibraryStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: RadioConfig.stationName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B3900),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: ForegroundInterface(
        builder: (_) => RadioWebView(
          playerController: playerController,
          subscriptionController: subscriptionController,
          collaboratorController: collaboratorController,
          userMusicLibraryStore: userMusicLibraryStore,
        ),
      ),
    );
  }
}
