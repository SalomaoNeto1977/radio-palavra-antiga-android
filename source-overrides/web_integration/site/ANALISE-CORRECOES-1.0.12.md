# Rádio Palavra Antiga — análise e correções da app e do site

## Resultado

A revisão separa definitivamente os dois ambientes de reprodução:

- **App Android**: o áudio, a MediaSession, a notificação, o ecrã bloqueado e o Android Auto pertencem ao único `just_audio.AudioPlayer` nativo.
- **Site e PWA**: o navegador usa o novo `HTMLAudioElement` do leitor da página principal. No iPhone, o `play()` continua a ser chamado diretamente pelo toque do utilizador.
- **PWA dentro da app Android**: o identificador `RPA` e o User-Agent da app impedem que o leitor web tente abrir um segundo áudio. O bridge nativo controla apenas `#playBtn` e recebe os estados do serviço Flutter.

## Problemas encontrados

1. O BODY tinha CSS fora de `<style>` e o CSS do WhatsApp aparecia duplicado, com regras globais que podiam alterar outros leitores.
2. `limparPlayerDuplicado()` apagava elementos depois do carregamento. Isso podia remover um leitor legítimo criado pelo Odoo e introduzir uma corrida com o novo leitor.
3. O novo leitor web tinha o seu próprio áudio, enquanto a bridge Android também neutralizava áudio. Sem uma separação explícita, a página podia criar dois caminhos de reprodução.
4. O leitor web fazia polling sem abortar pedidos antigos e podia aceitar uma resposta fora de ordem.
5. Uma capa nova podia não ser aplicada quando o título da música permanecia igual.
6. A ponte Android substituía `onclick` sem o remover do clone, o que podia executar duas ações num toque.
7. A versão Android aplicava `RadioTitleFormatter`: trocava `_`, removia palavras com números e alterava maiúsculas. Isso contradizia os títulos já corrigidos no AzuraCast e destruiria nomes como `Salmo 23` ou `Versão 2`.
8. O bloco de votação consultava a API num intervalo próprio, duplicando o trabalho do leitor.
9. O slider de volume não tem controlo real do volume no iPhone; apresentá-lo nesse dispositivo era enganador.

## Correções aplicadas

- Removido por completo o formatador de títulos Dart. O título é agora o texto recebido do AzuraCast, preservado em todos os destinos: página, notificação, Bluetooth, Android Auto e PWA.
- Mantida a validação de segurança dos dados: valores vazios, `null`, `undefined`, JSON acidental e imagens HTTP continuam a ser rejeitados.
- A bridge Android só é instalada quando existe `window.RPA.postMessage`. Em qualquer navegador, Safari ou PWA, sai imediatamente e não toca nem remove áudio.
- O bridge continua a neutralizar o áudio legado apenas dentro da app nativa, antes de qualquer `load()` ou reprodução.
- O leitor web tem um único controlador idempotente, timeout de ligação, abort de pedidos, atualização de capa por resposta e suporte de Media Session.
- A instalação PWA usa um único listener delegado, não duplica manifest/viewport, não regista um segundo service worker e mostra instruções específicas para iPhone.
- O clique de instalação interrompe o `onclick` legado para não chamar o prompt duas vezes.
- O botão WhatsApp ficou num único bloco de HTML; os estilos estão confinados ao HEAD e respeitam `safe-area-inset-bottom`.
- A votação recebe os metadados do leitor através de `rpa:live-metadata` e deixa de manter um `setInterval` independente.
- O slider de volume fica oculto no iPhone, onde o volume é controlado pelos botões físicos/Centro de Controlo.

## Contrato que não pode ser alterado

A página `/app1` mantém estes IDs:

`#playBtn`, `#btnImg`, `#vinylDisc`, `#tonearm`, `#needleShadow`, `#np-capa`, `#np-titulo`, `#np-letra`, `#np-letra-box`.

A bridge Flutter usa o canal `RPA` e envia/recebe `PLAY`, `STOP`, `PAUSE`, `GET_STATE`, comandos de navegação, pedidos e ações On-Demand. O site principal usa IDs independentes (`paWebAudio`, `paPlayerButton`, `paPlayerCover`, etc.) e nunca deve reutilizar o bridge Android.

## Verificação

Foram executados 24 testes JavaScript: bridge Android, leitor web/PWA, estados, cliques repetidos, títulos com números/versões, capas, visibilidade, pausa do sistema, iPhone, votação e ausência de canal nativo. Todos passaram.

Também passaram os três testes Python do gerador de catálogo AzuraCast. O workflow GitHub acrescenta a análise Dart/Flutter, os testes Flutter, a validação de pedidos públicos, a assinatura e a inspeção do APK/AAB.

## Instalação dos códigos no site

1. Colar o conteúdo de `HEAD.html` no campo HEAD personalizado.
2. Colar o conteúdo de `BODY.html` no campo BODY personalizado usado para o botão WhatsApp e a área `/app1`.
3. No leitor da página principal, substituir o bloco antigo pelo conteúdo de `LEITOR-PAGINA-PRINCIPAL.html`.
4. Se a página `/app1` tiver o bloco de votos, substituir apenas o seu `<script>` pelo conteúdo de `VOTACAO-SCRIPT.html`.
5. Publicar o novo `service-worker.js` do site apenas se o servidor tiver uma versão mais antiga; o código PWA não faz cache do áudio.

A app corrigida está no ramo GitHub `fix/rpa-web-pwa-1.0.12`, a partir da revisão da 1.0.11, com versão Android `1.0.12+13` para permitir uma atualização instalável.
