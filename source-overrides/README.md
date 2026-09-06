# Rádio Palavra Antiga — aplicação Android Flutter

Aplicação Android completa da **Rádio Palavra Antiga**. A interface é a página
`palavraantiga.org/app1`, apresentada numa WebView segura. A WebView apenas
envia comandos; a reprodução, o estado verdadeiro, a MediaSession e a
notificação pertencem sempre ao serviço nativo Flutter/Android.

Identificador Android reservado na Google Play: `org.palavraantiga.radio`.
Versão desta revisão: `1.0.12+13`.

> Regra de arquitectura: existe, no máximo, uma instância de `AudioPlayer`,
> criada em `RadioAudioHandler` apenas depois do primeiro PLAY. Recarregar,
> reconstruir ou fechar a WebView não cria outro leitor nem reinicia o stream.

## Estado da entrega

Na revisão `1.0.12+13`, o leitor continua a ser inicializado apenas após PLAY, a WebView
Android utiliza Hybrid Composition e gestos explícitos sem overlays Flutter,
as notificações são pedidas directamente ao sistema depois de a página estar
pronta, e a metadata é formatada uma única vez antes de seguir para WebView,
notificação, ecrã bloqueado e Bluetooth. A ponte mantém uma bateria própria
de testes, executada com:

```bash
node --test test/rpa_bridge_dom_test.js
```

Os testes cobrem bloqueio do áudio Web, estados e cliques do botão, títulos
recebidos do serviço nativo, capa, animação do disco, reinjecção segura e
ausência de efeitos pesados. A criação lazy e a formatação portuguesa são
verificadas pela bateria Flutter.

Esta revisão acrescenta ainda o catálogo automóvel da estação. No Android
Auto, a aplicação expõe a categoria **Em directo** e a opção reproduzível
**Ouvir em directo**, aceita selecção e pesquisa por voz e conserva um único
leitor nativo. O descritor automóvel reutiliza um recurso XML existente para
manter compatibilidade com o pacote Android já validado; a política de rede
continua a proibir tráfego HTTP através de `android:usesCleartextTraffic`.

Ao desligar a projecção Android Auto, um dispositivo Bluetooth ou uma ligação
de áudio USB, a emissão pára antes de passar para o altifalante do telefone. Se
estava a tocar, essa intenção é guardada e a aplicação retoma apenas quando o
mesmo carro ou dispositivo voltar a ligar. PAUSE ou STOP manuais anulam sempre
a retoma automática.

Histórico de validação da versão inicial, em 4 de Agosto de 2026:

- Flutter 3.44.8 stable;
- Dart 3.12.2;
- Java 17;
- Android Gradle Plugin 9.0.1;
- Kotlin 2.3.20;
- Gradle 9.1.0;
- `compileSdk 36`, `targetSdk 36`, `minSdk 26`;
- `flutter analyze`: sem problemas;
- `flutter test`: 21 testes aprovados;
- `flutter build apk --debug`: APK gerado com sucesso;
- `flutter build appbundle --release`: AAB assinado gerado com sucesso;
- APK auditado com API mínima 26, alvo 36, serviço
  `foregroundServiceType="mediaPlayback"` e assinatura Android v2 válida;
- AAB verificado como arquivo íntegro, com assinatura JAR válida e certificado
  idêntico ao da chave de upload.

O APK de depuração fica em:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Palavra Antiga Music (1.0.12)

A versão 1.0.8 mantém a área On-Demand sem criar um segundo motor de
áudio. O mesmo `just_audio.AudioPlayer` alterna entre dois modos exclusivos:

- **Rádio ao vivo**: stream fixo, PLAY/STOP, reconexão e metadata da emissão;
- **Music On-Demand**: faixa individual, PLAY/PAUSE, anterior, seguinte, fila e seek.

A aplicação tem uma barra nativa permanente com três destinos:
**Rádio**, **Música** e **WhatsApp**. Rádio e Música alternam entre as duas
áreas sem reiniciar o áudio; WhatsApp abre directamente a conversa da rádio no
número +351 800 500 321. A barra continua acessível mesmo quando a página Web
da rádio está temporariamente indisponível.

As músicas são lidas apenas pelo endpoint público do AzuraCast:

```text
https://radio.palavraantiga.org/api/station/palavraantiga/ondemand
```

O GitHub Actions consulta a API autenticada do AzuraCast de hora a hora para
associar cada faixa às playlists oficiais marcadas como
**Include in On-Demand Player** e publica apenas o catálogo seguro em
`catalog/official_playlists.json`. A app procura uma versão nova quando a
página abre e ao entrar em Música, guarda-a localmente e mantém como recurso a
última versão válida ou o catálogo incluído no APK. Assim, as alterações no
AzuraCast passam a aparecer sem ser necessário instalar outra versão da app.

O catálogo público contém apenas nomes de playlists e identificadores públicos
das músicas. A chave API vem do segredo `AZURACAST_API_KEY`: nunca é guardada
no código, compilada no APK ou colocada no JavaScript. As faixas
recebidas pela WebView são validadas e o áudio On-Demand só pode apontar para
`https://radio.palavraantiga.org`. As capas são limitadas aos domínios oficiais
da Palavra Antiga.

A interface Music é injectada por `web_integration/rpa_bridge.js` e inclui
cartões das playlists oficiais, pesquisa, favoritos, playlists pessoais e
mini-player. Quando uma faixa também está disponível no catálogo público de
pedidos do AzuraCast, surge a ação **🎙 Pedir** ao lado de **▶ Ouvir**. A app
pede confirmação antes de enviar e apresenta de forma clara o intervalo entre
pedidos definido no AzuraCast. Não é enviada qualquer credencial.

As duas ações são independentes de propósito. Esta versão ainda não identifica
doadores nem esconde o botão de reprodução; no futuro, uma autenticação de
contribuidores poderá controlar apenas **Ouvir**, mantendo **Pedir** disponível
segundo a política escolhida pela rádio.

Ao abrir uma playlist oficial, anterior, seguinte e reprodução seguem apenas
essa lista. Favoritos e playlists pessoais ficam em
`localStorage`. O site tem um widget separado em
`site_widget/palavra-antiga-music-widget.html`; no navegador, esse widget usa
um `<audio>` HTML simples, enquanto a aplicação Android continua sempre a usar
o leitor nativo.

Para o catálogo aparecer, o AzuraCast tem de ter **On-Demand Streaming** activo
e pelo menos uma playlist marcada como **Include in On-Demand Player**.

## Arquitectura

```text
WebView /app1
    │  RPA.postMessage("PLAY" | "STOP" | ...)
    ▼
WebViewBridge ──► RadioPlayerController ──► RadioAudioHandler
                                               │
                                               ├─ único just_audio.AudioPlayer
                                               ├─ audio_session / Audio Focus
                                               ├─ audio_service / foreground
                                               ├─ MediaSession e notificação
                                               ├─ metadados a cada 12 s
                                               └─ reconexão MP3 ⇄ HLS
    ▲
    │  window.__RPA_SET_STATE(estado, metadados)
    └──────────────── estado nativo verdadeiro ────────────────
```

Principais responsabilidades:

- `lib/config/radio_config.dart`: todos os URLs e valores fixos;
- `lib/radio_audio_handler.dart`: áudio, foco, interrupções, notificação,
  MediaSession, catálogo Android Auto, metadados e reconexão;
- `lib/radio_player_controller.dart`: serialização e bloqueio de comandos;
- `lib/radio_webview.dart`: WebView, navegação, SSL e interface alternativa;
- `lib/webview_bridge.dart`: validação do canal `RPA` e sincronização;
- `lib/now_playing_service.dart`: APIs de “Agora a tocar” e sanitização;
- `lib/connectivity_service.dart`: perda e recuperação de rede;
- `web_integration/rpa_bridge.js`: código exacto para a página `app1`.

## Árvore do projecto

```text
radio_palavra_antiga/
├── .vscode/
│   ├── extensions.json
│   ├── launch.json
│   └── tasks.json
├── android/
│   ├── app/
│   │   ├── proguard-rules.pro
│   │   ├── build.gradle.kts
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       ├── kotlin/.../MainActivity.kt
│   │       └── res/
│   │           ├── drawable/ic_stat_radio.xml
│   │           ├── mipmap-*/ic_launcher.png
│   │           ├── raw/keep.xml
│   │           └── xml/network_security_config.xml
│   ├── gradle/wrapper/gradle-wrapper.properties
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── key.properties.example
│   └── settings.gradle.kts
├── assets/images/logo.png
├── lib/
│   ├── config/radio_config.dart
│   ├── artwork_service.dart
│   ├── connectivity_service.dart
│   ├── error_mapper.dart
│   ├── main.dart
│   ├── notification_permission_service.dart
│   ├── now_playing_service.dart
│   ├── offline_player.dart
│   ├── radio_audio_handler.dart
│   ├── radio_player_controller.dart
│   ├── radio_state.dart
│   ├── radio_webview.dart
│   └── webview_bridge.dart
├── test/
│   ├── android_auto_media_library_test.dart
│   ├── now_playing_service_test.dart
│   ├── radio_player_controller_test.dart
│   ├── radio_state_and_reconnection_test.dart
│   ├── webview_bridge_state_test.dart
│   └── webview_command_parser_test.dart
├── web_integration/rpa_bridge.js
├── analysis_options.yaml
├── pubspec.lock
├── pubspec.yaml
└── README.md
```

Ficheiros gerados (`build/`, `.dart_tool/`, `android/local.properties`) não
devem ser guardados no controlo de versões.

## Abrir e executar no Visual Studio Code

1. Instalar o Flutter stable e o Android Studio/Android SDK.
2. Instalar no VS Code as extensões **Flutter** e **Dart**. O ficheiro
   `.vscode/extensions.json` sugere-as automaticamente.
3. Abrir a pasta `radio_palavra_antiga`, não a pasta que a contém.
4. Confirmar o ambiente:

   ```bash
   flutter doctor -v
   flutter pub get
   flutter analyze
   flutter test
   ```

5. Activar a depuração USB num dispositivo Android 8 ou superior, ou abrir um
   emulador.
6. Seleccionar o dispositivo na barra inferior do VS Code e premir `F5`.

A rádio não arranca automaticamente. O primeiro `PLAY` tem de resultar numa
acção explícita do utilizador.

## Ponte JavaScript da página

O ficheiro completo e pronto a colar está em:

```text
web_integration/rpa_bridge.js
```

Na página `app1`, colocá-lo depois dos elementos do player ou carregá-lo com
`defer`. O mesmo ficheiro já é injectado pela aplicação, por isso é idempotente.

O código utiliza os elementos reais encontrados na página:

- botão visível `appPlayBtn`;
- imagem do botão `appBtnImg`;
- botão antigo oculto `playBtn`;
- imagem antiga `btnImg`;
- capa `np-capa`;
- título `np-titulo`;
- animações opcionais `vinylDisc`, `tonearm` e `needleShadow`.

O script:

- remove os listeners antigos clonando os botões;
- liga o clique exclusivamente a `RPA.postMessage`;
- aceita o estado apenas por `window.__RPA_SET_STATE`;
- silencia e remove `audio#radioPlayer` e qualquer outro `<audio>`, sem
  executar `audio.load()` nem provocar ruído durante o arranque;
- bloqueia `HTMLAudioElement.play()`;
- não contém qualquer URL de stream;
- não cria temporizadores que finjam o estado do áudio;
- apresenta apenas capa, título, disco e botão; não cria linhas de artista
  nem de estado textual;
- apresenta exactamente o título já formatado por `NowPlayingService`, o
  mesmo que é enviado à notificação, MediaSession, ecrã bloqueado e Bluetooth;
- mostra uma luz azul fixa quando parado, amarela rápida durante ligação,
  vermelha lenta durante reprodução e vermelha muito rápida em caso de erro;
- anima apenas `opacity` e `transform` numa camada separada do botão, sem
  `MutationObserver`, `drop-shadow` animado ou reflows forçados;
- lida com IDs duplicados existentes na página actual.

O antigo leitor Web de `/app1` pode ser removido sem afectar a aplicação;
a ponte continua a neutralizar defensivamente qualquer elemento `<audio>`
legado. Os IDs visuais existentes devem permanecer.

Comandos aceites:

```javascript
RPA.postMessage("PLAY");
RPA.postMessage("STOP");
RPA.postMessage("PAUSE");
RPA.postMessage("TOGGLE");
RPA.postMessage("GET_STATE");
RPA.postMessage("RETRY");
RPA.postMessage(JSON.stringify({ action: "PLAY" }));
```

Comandos desconhecidos, URLs arbitrários e mensagens inválidas são ignorados. Para a área Music, a ponte aceita mensagens JSON validadas até 128 KiB, com uma fila máxima de 100 faixas e URLs de áudio limitados ao servidor `radio.palavraantiga.org`.

Resposta nativa:

```javascript
if (typeof window.__RPA_SET_STATE === "function") {
  window.__RPA_SET_STATE("PLAYING", {
    title: "Título da emissão",
    artist: "Artista ou programa",
    artwork: "https://...",
    isLive: true,
    error: null
  });
}
```

Depois de cada carregamento, a página pede `GET_STATE` e o Flutter envia
imediatamente o snapshot actual. A WebView nunca presume `STOPPED`.

## Áudio e segundo plano

`audio_service` mantém um foreground service oficial, MediaSession e wake lock
parcial enquanto a emissão está activa. `just_audio` usa o motor Android para o
stream de rede. O `AudioPlayer` e a sessão de áudio só são inicializados após
uma intenção real de reprodução; abrir a aplicação, pedir estado ou parar antes
do primeiro PLAY não activam a saída de áudio. `audio_session` configura a
sessão como música e trata:

- perda temporária de foco;
- redução temporária de volume (`duck`);
- chamadas, alarmes, navegação e outras aplicações multimédia;
- remoção de auscultadores/saída de áudio;
- botão multimédia principal de auscultadores Bluetooth e sistemas automóveis;
- retoma após uma interrupção temporária apenas se `userWantsPlayback`
  continuar verdadeiro. A fonte anterior é destruída e a ligação é refeita
  para o ponto actual da emissão, evitando tocar áudio que ficou em reserva.

A notificação é permanente enquanto a emissão está activa e o serviço não sai
do foreground numa pausa técnica temporária. Apagar o ecrã, bloquear o telefone,
trocar de aplicação ou retirar a Activity da lista de recentes não envia STOP.

Não é pedido `CHANGE_WIFI_STATE`, porque um Wi-Fi lock exigiria uma permissão
fora da lista aprovada. O serviço usa o wake lock parcial oficial suportado pelo
`audio_service`; não usa alarmes, Accessibility, administrador, sobreposições
nem pedidos para ignorar optimizações de bateria.

Nenhuma aplicação normal pode garantir que o Android nunca terminará o
processo. Esta implementação usa a prioridade máxima legítima para reprodução
multimédia. “Forçar paragem”, fabricantes com políticas agressivas ou falta
extrema de recursos continuam sob controlo do sistema.

## STOP, PAUSE e reconexão

`STOP`:

- põe `userWantsPlayback` a falso;
- invalida o token de carregamento;
- cancela o único temporizador de reconexão e o de metadados;
- pára o leitor e limpa a fonte;
- abandona o foco;
- publica `STOPPED`/`idle`, removendo foreground e notificação.

`PAUSE` também destrói a fonte e põe a intenção automática a falso. Um PLAY
posterior cria uma ligação nova ao directo. Não há reconexão ou retoma
espontânea depois de `STOP` ou `PAUSE`.

As falhas usam atrasos de 2, 5, 10, 20 e 30 segundos, com limite de 30 segundos.
As primeiras tentativas usam MP3; depois do limiar, MP3 e HLS alternam para que
um endpoint secundário indisponível não bloqueie a recuperação do principal.
Só existe um leitor e um temporizador.

## Metadados

Enquanto toca, o serviço consulta a API a cada 12 segundos. São actualizados:

- notificação;
- ecrã bloqueado;
- MediaSession;
- WebView.

Campos vazios, `null`, `undefined`, JSON bruto, capas HTTP e textos anormais são
rejeitados. Uma falha das APIs nunca interrompe o áudio. A capa local
`assets/images/logo.png` serve de fallback da notificação mesmo se a imagem
remota estiver indisponível.

## Segurança da WebView

- apenas HTTPS;
- navegação interna limitada aos três hosts configurados;
- HTTPS externo aberto no navegador do sistema;
- HTTP, `file:`, `content:`, intents e esquemas arbitrários bloqueados;
- file access, content access e geolocalização desactivados;
- pedidos de permissões web sempre recusados;
- selecção de ficheiros recusada;
- mixed content nunca permitido;
- certificado inválido sempre cancelado;
- erros de imagens/recursos não são confundidos com falha do documento;
- sem acesso do canal `RPA` a ficheiros, intents, permissões ou URLs de áudio.

## Permissões e notificação Android 13+

O manifesto principal declara apenas:

```text
INTERNET
ACCESS_NETWORK_STATE
WAKE_LOCK
FOREGROUND_SERVICE
FOREGROUND_SERVICE_MEDIA_PLAYBACK
POST_NOTIFICATIONS
```

Em Android 13 ou superior, antes do diálogo do sistema é mostrado:

> A notificação permite controlar a rádio enquanto está a tocar, inclusive no
> ecrã bloqueado.

Recusar não bloqueia o áudio. O Android pode limitar a visibilidade da
notificação, mas o comportamento permitido para o foreground service é
respeitado.

Ao fundir dependências, AndroidX declara ainda uma permissão privada de nível
`signature` chamada `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. Não é uma
permissão perigosa nem dá acesso a dados; protege receivers internos em versões
antigas do Android e é gerada com o identificador da própria aplicação.

## Gerar APK

Depuração:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

APK de lançamento, depois de configurar a assinatura:

```bash
flutter build apk --release
```

Para APKs separados por arquitectura e mais pequenos:

```bash
flutter build apk --release --split-per-abi
```

## Assinar a aplicação

Criar uma chave de upload e guardá-la em local seguro:

```bash
keytool -genkeypair -v \
  -keystore radio-palavra-antiga-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias radio-palavra-antiga
```

Copiar o modelo:

```bash
cp android/key.properties.example android/key.properties
```

Editar `android/key.properties`:

```properties
storePassword=A_TUA_PASSWORD
keyPassword=A_TUA_PASSWORD
keyAlias=radio-palavra-antiga
storeFile=/caminho/absoluto/radio-palavra-antiga-upload.jks
```

`key.properties` e ficheiros `.jks` já estão ignorados pelo Git. Nunca os
partilhar nem os incluir no ZIP de distribuição. Guardar cópias de segurança da
chave e das passwords; sem a chave de upload não é possível manter o fluxo
normal de actualizações.

## Gerar AAB para Google Play

Com a assinatura configurada:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Resultado:

```text
build/app/outputs/bundle/release/app-release.aab
```

Também é possível fornecer a assinatura por variáveis de ambiente, sem criar
`android/key.properties`:

```text
RPA_STORE_FILE=/caminho/absoluto/radio-palavra-antiga-upload.jks
RPA_STORE_PASSWORD=...
RPA_KEY_PASSWORD=...
RPA_KEY_ALIAS=radio-palavra-antiga
```

O projecto aponta para API 36, correspondente ao requisito anunciado para novas
aplicações e actualizações Google Play a partir de 31 de Agosto de 2026.

## Ícone e logótipo

- logótipo Flutter/fallback: `assets/images/logo.png`;
- ícones do launcher:
  `android/app/src/main/res/mipmap-*/ic_launcher.png`;
- ícone monocromático da notificação:
  `android/app/src/main/res/drawable/ic_stat_radio.xml`;
- conservação no shrinker:
  `android/app/src/main/res/raw/keep.xml`.

Para mudar a identidade visual, substituir o PNG por uma imagem quadrada de
alta resolução, voltar a gerar as densidades `mipmap-*` e manter o ícone da
notificação branco/transparente.

## Testes automáticos

```bash
flutter test
```

Cobertura implementada:

- `PLAY`, `STOP`, `PAUSE`, `TOGGLE`;
- bloqueio de `PLAY` duplicado;
- STOP a ultrapassar um carregamento pendente;
- estados e `userWantsPlayback`;
- invalidação/cancelamento da reconexão;
- atrasos progressivos e alternância MP3/HLS;
- perda e recuperação de ligação;
- perda temporária de foco, retoma condicionada e paragem inesperada;
- decisão do botão multimédia Bluetooth;
- parsing, sanitização e fallback de metadados;
- validação estrita de texto e JSON do canal `RPA`.

## Testes manuais num dispositivo real

Os testes de segundo plano, chamadas e Bluetooth dependem do fabricante e devem
ser executados num telemóvel real antes de publicar:

1. Abrir a aplicação e confirmar que não toca automaticamente.
2. Carregar em Play e confirmar `CONNECTING` seguido de `PLAYING`.
3. Apagar o ecrã.
4. Bloquear o telemóvel.
5. Abrir outra aplicação.
6. Esperar pelo menos dez minutos.
7. Controlar pela notificação.
8. Controlar pelo ecrã bloqueado.
9. Ligar auscultadores Bluetooth.
10. Controlar por Bluetooth.
11. Desligar Bluetooth e confirmar pausa segura quando recomendada.
12. Receber uma chamada.
13. Terminar a chamada e confirmar retoma apenas quando temporária.
14. Desligar o Wi-Fi.
15. Activar dados móveis e confirmar recuperação do stream.
16. Recarregar a página e confirmar que recebe o estado verdadeiro.
17. Rodar o telemóvel sem reiniciar o áudio.
18. Fechar a Activity/lista de recentes e confirmar o serviço legítimo.
19. Voltar a abrir e confirmar que aparece `PLAYING`.
20. Carregar em Stop.
21. Confirmar que a notificação desaparece.
22. Confirmar por audição e `adb logcat` que não existem dois áudios.

Testar também a recusa de notificações no Android 13+, modo poupança de bateria,
Wi-Fi/dados instáveis e versões Android de fabricantes diferentes.

## Verificação operacional dos endpoints

Na validação desta entrega, a página, o stream MP3 e a API principal responderam
com sucesso. Os endereços fixos fornecidos para HLS, API alternativa e imagem
remota predefinida responderam HTTP 404 nesse momento. Os endereços fornecidos
continuam centralizados em `radio_config.dart`. Para não apresentar uma capa
partida, a WebView usa o mesmo logótipo oficial publicado no website e a
notificação usa a cópia local. A aplicação mantém o MP3 e alterna novamente para
ele se o HLS falhar. Convém corrigir as três rotas no servidor antes da
publicação.
