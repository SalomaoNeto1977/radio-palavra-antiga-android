import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:radio_palavra_antiga/connectivity_service.dart';
import 'package:radio_palavra_antiga/now_playing_service.dart';
import 'package:radio_palavra_antiga/radio_audio_handler.dart';
import 'package:radio_palavra_antiga/radio_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RadioAudioHandler: criação lazy do AudioPlayer', () {
    test('abrir a aplicação não cria nem activa o leitor de áudio', () async {
      int creations = 0;
      final RadioAudioHandler handler = RadioAudioHandler(
        connectivity: _FakeConnectivity(),
        playerFactory: () {
          creations += 1;
          return _FakeAudioPlayer();
        },
      );

      expect(creations, 0);
      expect(handler.hasCreatedPlayer, isFalse);
      expect(handler.snapshot.state, RadioPlaybackState.stopped);
      expect(handler.snapshot.userWantsPlayback, isFalse);

      await handler.disposeHandler();
      expect(creations, 0);
    });

    test('STOP antes do primeiro PLAY não cria AudioPlayer', () async {
      int creations = 0;
      final RadioAudioHandler handler = RadioAudioHandler(
        connectivity: _FakeConnectivity(),
        playerFactory: () {
          creations += 1;
          return _FakeAudioPlayer();
        },
      );

      await handler.stop();

      expect(creations, 0);
      expect(handler.hasCreatedPlayer, isFalse);
      expect(handler.snapshot.state, RadioPlaybackState.stopped);
      await handler.disposeHandler();
    });

    test('PAUSE antes do primeiro PLAY não cria AudioPlayer', () async {
      int creations = 0;
      final RadioAudioHandler handler = RadioAudioHandler(
        connectivity: _FakeConnectivity(),
        playerFactory: () {
          creations += 1;
          return _FakeAudioPlayer();
        },
      );

      await handler.pause();

      expect(creations, 0);
      expect(handler.hasCreatedPlayer, isFalse);
      await handler.disposeHandler();
    });

    test(
      'o primeiro acesso cria um leitor e os seguintes reutilizam-no',
      () async {
        int creations = 0;
        final _FakeAudioPlayer player = _FakeAudioPlayer();
        final RadioAudioHandler handler = RadioAudioHandler(
          connectivity: _FakeConnectivity(),
          playerFactory: () {
            creations += 1;
            return player;
          },
        );

        final just_audio.AudioPlayer first = handler.ensurePlayerForTesting();
        final just_audio.AudioPlayer second = handler.ensurePlayerForTesting();

        expect(creations, 1);
        expect(identical(first, second), isTrue);
        expect(handler.hasCreatedPlayer, isTrue);
        await handler.disposeHandler();
        expect(player.disposeCalls, 1);
      },
    );

    test(
      'dispose sem leitor é seguro e dispose com leitor acontece uma vez',
      () async {
        final _FakeAudioPlayer player = _FakeAudioPlayer();
        final RadioAudioHandler handler = RadioAudioHandler(
          connectivity: _FakeConnectivity(),
          playerFactory: () => player,
        );

        handler.ensurePlayerForTesting();
        await handler.disposeHandler();
        await handler.disposeHandler();

        expect(player.stopCalls, 1);
        expect(player.clearCalls, 1);
        expect(player.disposeCalls, 1);
        expect(handler.hasCreatedPlayer, isFalse);
      },
    );

    test('MediaItem preserva o título recebido do AzuraCast, tal como a WebView', () async {
      final RadioAudioHandler handler = RadioAudioHandler(
        connectivity: _FakeConnectivity(),
        playerFactory: _FakeAudioPlayer.new,
      );
      final NowPlayingMetadata metadata = NowPlayingService.parse(
        <String, dynamic>{
          'now_playing': <String, dynamic>{
            'song': <String, dynamic>{'title': 'meu_deus_2026_e_fiel faixa03'},
          },
        },
      );

      final MediaItem mediaItem = handler.mediaItemForTesting(metadata);

      expect(mediaItem.title, 'meu_deus_2026_e_fiel faixa03');
      expect(mediaItem.title, metadata.toWebMap()['title']);
      expect(handler.hasCreatedPlayer, isFalse);
      await handler.disposeHandler();
    });
  });
}

class _FakeConnectivity implements ConnectivityPort {
  @override
  Future<bool> hasNetwork() async => true;

  @override
  Stream<bool> get networkChanges => const Stream<bool>.empty();
}

class _FakeAudioPlayer extends Fake implements just_audio.AudioPlayer {
  int stopCalls = 0;
  int clearCalls = 0;
  int disposeCalls = 0;

  @override
  bool get playing => false;

  @override
  Stream<just_audio.PlayerState> get playerStateStream =>
      const Stream<just_audio.PlayerState>.empty();

  @override
  Stream<just_audio.PlaybackEvent> get playbackEventStream =>
      const Stream<just_audio.PlaybackEvent>.empty();

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> clearAudioSources() async {
    clearCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
