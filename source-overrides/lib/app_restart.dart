import 'package:flutter/services.dart';

import 'playback_selection_store.dart';
import 'radio_audio_handler.dart';
import 'radio_player_controller.dart';

class AppRestart {
  static const MethodChannel channel = MethodChannel('org.palavraantiga.radio/restart');

  static Future<void> restart(RadioPlayerController player) async {
    // Even an unresponsive audio player must not block the recovery action.
    try {
      await player.handle(RadioCommand.stop).timeout(const Duration(seconds: 3));
    } on Object {
      // The native restart also stops the audio service and its process.
    }
    await SharedPreferencesVehicleResumeStore().writeResumeState(
      pending: false, routes: const <String>{},
    );
    await SharedPreferencesPlaybackSelectionStore().clear();
    await channel.invokeMethod<void>('restart');
  }
}
