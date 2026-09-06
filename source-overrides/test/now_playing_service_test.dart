import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:radio_palavra_antiga/config/radio_config.dart';
import 'package:radio_palavra_antiga/now_playing_service.dart';
import 'package:radio_palavra_antiga/radio_state.dart';

void main() {
  test('preserva os títulos corrigidos na fonte, incluindo versões e números', () {
    for (final String title in <String>[
      'Salmo 23', 'Meu Deus é fiel (Versão 2)', '2026 faixa03',
      'Grande_É_o_Senhor 2026', 'ação de graças',
    ]) {
      final NowPlayingMetadata metadata = NowPlayingService.parse(
        <String, dynamic>{'now_playing': <String, dynamic>{
          'song': <String, dynamic>{'title': title},
        }},
      );
      expect(metadata.title, title);
      expect(metadata.toWebMap()['title'], title);
    }
  });

  test('interpreta a resposta AzuraCast e prefere o apresentador ao vivo', () {
    final NowPlayingMetadata metadata = NowPlayingService.parse(
      <String, dynamic>{
        'now_playing': <String, dynamic>{
          'song': <String, dynamic>{
            'title': 'Hino da Manhã',
            'artist': 'Coro Esperança',
            'album': 'Louvor',
            'art': 'https://radio.palavraantiga.org/capa.jpg',
          },
        },
        'live': <String, dynamic>{
          'is_live': true,
          'streamer_name': 'Programa Palavra Viva',
        },
        'station': <String, dynamic>{'name': 'Rádio Palavra Antiga'},
      },
    );

    expect(metadata.title, 'Hino da Manhã');
    expect(metadata.artist, 'Programa Palavra Viva');
    expect(metadata.album, 'Louvor');
    expect(
      metadata.artwork,
      Uri.parse('https://radio.palavraantiga.org/capa.jpg'),
    );
    expect(metadata.isLive, isTrue);
  });

  test('nunca expõe null, undefined, JSON ou capa insegura', () {
    final NowPlayingMetadata metadata = NowPlayingService.parse(
      <String, dynamic>{
        'now_playing': <String, dynamic>{
          'song': <String, dynamic>{
            'title': 'null',
            'artist': 'undefined',
            'album': '{"raw":true}',
            'art': 'http://inseguro.example/capa.jpg',
          },
        },
      },
    );

    expect(metadata.title, RadioConfig.defaultTitle);
    expect(metadata.artist, RadioConfig.defaultArtist);
    expect(metadata.album, isNull);
    expect(metadata.artwork, RadioConfig.defaultArtwork);
  });

  test('usa a API alternativa se a API principal falhar', () async {
    int requests = 0;
    final MockClient client = MockClient((http.Request request) async {
      requests += 1;
      if (request.url == RadioConfig.nowPlayingApi) {
        return http.Response('erro', 503);
      }
      return http.Response(
        '''
{"now_playing":{"song":{"title":"Emissão especial","artist":"Equipa"}}}
''',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final NowPlayingService service = NowPlayingService(client: client);

    final NowPlayingMetadata metadata = await service.fetch();

    expect(requests, 2);
    expect(metadata.title, 'Emissão especial');
    expect(metadata.artist, 'Equipa');
    service.close();
  });
}
