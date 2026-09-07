import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'artwork_service.dart';
import 'config/radio_config.dart';
import 'foreground_interface.dart';
import 'native_music_catalog_service.dart';
import 'radio_audio_handler.dart';
import 'radio_player_controller.dart';
import 'radio_webview.dart';
import 'supporter_subscription.dart';
import 'user_music_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SupporterSubscriptionController subscriptionController =
      SupporterSubscriptionController(
        billing: PlaySubscriptionBillingGateway(),
        entitlementStore: SharedPreferencesSubscriptionEntitlementStore(),
      );
  await subscriptionController.loadCachedEntitlement();
  unawaited(subscriptionController.start());

  final Uri? bundledArtwork = await ArtworkService.prepareBundledArtwork();
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
  await AudioService.androidForceEnableMediaButtons();
  final RadioPlayerController playerController = RadioPlayerController(
    audioHandler,
  );

  runApp(
    RadioApp(
      playerController: playerController,
      subscriptionController: subscriptionController,
      userMusicLibraryStore: userMusicLibraryStore,
    ),
  );
}

class RadioApp extends StatelessWidget {
  const RadioApp({
    required this.playerController,
    required this.subscriptionController,
    required this.userMusicLibraryStore,
    super.key,
  });

  final RadioPlayerController playerController;
  final SupporterSubscriptionController subscriptionController;
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
          userMusicLibraryStore: userMusicLibraryStore,
        ),
      ),
    );
  }
}
