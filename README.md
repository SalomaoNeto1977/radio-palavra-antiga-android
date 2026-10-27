# Rádio Palavra Antiga Android

## Google TV / Android TV — versão 1.3.0

A versão própria para televisão foi enviada para produção a **27/10/2026**, em **178 países/regiões**. A Play Console confirmou **«Lançamento 1.3.0 — Rádio para Google TV em revisão»**, com verificações automáticas ainda em curso e publicação automática após aprovação. O envio não confirma disponibilidade pública. Para acrescentar a TV, a Google reiniciou a revisão conjunta das versões de telefone, automóvel e televisão.

O módulo independente [tv](tv/README.md) usa o mesmo identificador e chave de envio, com versão 1.3.0 e código **1300002**, Android 7.0/API 24 ou posterior e proteção automática da Play. A interface nativa apresenta a emissão, título, intérprete e capa, com botões grandes e navegação por comando. O serviço gere o áudio em segundo plano e os controlos do sistema, sem impedir o modo de ambiente. A escuta é gratuita e não exige conta.

Os **19 testes** e a análise Android passaram; o ensaio completo num **Google TV API 36** confirmou áudio real, navegação, pausa, paragem, Home/regresso e Voltar. Foram capturadas quatro imagens nativas Full HD, e três foram carregadas na ficha. O [ensaio 40580279762](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/40580279762) valida os pacotes de `b6940e098de0c98ec19ac01ceb28e928bcc53bb0`. Um ensaio numa televisão física continua por realizar.

AAB enviado SHA-256: `b7edfb6d2ba7c2645d080e1e3454a9279fea23d31a73eafe8384d5c41c124f21`. A faixa de testes internos está ativa, com a lista existente de 34 testadores. Os módulos de telefone e automóvel não foram modificados nesta implementação.

## Android Automotive OS — versão 1.2.1

O módulo independente [automotive](automotive/README.md) prepara a instalação direta em carros com Android Automotive OS e Google Play. O leitor do veículo apresenta o separador **Em direto**, a emissão da Rádio, título, intérprete e capa. O módulo usa Media3 e uma única instância de ExoPlayer, com foco de áudio, recuperação após falhas de rede e cancelamento da recuperação ao pausar. Não exige iniciar sessão.

O pacote automóvel mantém o identificador `org.palavraantiga.radio` e a chave de envio existente, com versão 1.2.1 e código 1200002. A app de telefone permanece na versão 1.1.10.

A versão 1.2.0 foi publicada em testes internos a 27/10/2026, com 34 testadores associados. A atualização 1.2.1 acrescenta a imagem dourada fornecida pelo responsável da Rádio como capa predefinida da estação; as capas próprias das músicas mantêm-se.

Na validação da versão 1.2.0, os 17 testes de políticas, metadados e serviço passaram, a inspeção Android terminou sem erros e foram gerados o APK e o AAB assinado. O ensaio no Android Automotive API 35-ext15 confirmou catálogo, separador visível, reprodução da emissão real e pausa, em horizontal e vertical. O [ensaio de validação](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/40532185963) reúne os pacotes, relatórios e capturas.

A versão automóvel **1.2.1 foi enviada para produção a 27/10/2026**, em 178 países/regiões, com o estado «Alterações em revisão» confirmado na Play Console. Um ensaio num Polestar físico continua por realizar.

## Correção validada e enviada para produção — 1.1.10+21

Ao fechar a janela com o áudio ainda ativo e reabrir pelo ícone ou pela Play Store, a 1.1.9 podia manter os botões do menu a receber toques enquanto a camada Flutter ficava invisível, incluindo Conta. A 1.1.10 recria a interface do telefone quando a Activity anterior é destruída e apresenta a WebView através de uma textura, evitando a composição antiga com superfícies Flutter sobrepostas. O serviço de áudio e os controladores permanecem fora dessa interface.

A análise e os **88 testes Flutter, 26 testes JavaScript e 5 testes Python** passaram. O APK de teste e o AAB assinado foram compilados e validados no [ensaio 39995515253](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/39995515253), a partir de `2a792f2ae2a640360ed9b0382aada64da5a466b9`. Os testes de ciclo de vida distinguem segundo plano de destruição da janela, incluindo reabertura sem um frame intermédio.

A verificação Android foi alargada para conferir áudio contínuo, menu e Conta após fechar e reabrir a Activity. No emulador Android 13, a captura inicial mostra o menu visível, mas a ligação ADB ficou offline antes de completar o arranque e executar os ciclos de reabertura. **Esta validação automática não ficou concluída**. Depois de atualizar pelos testes internos, o utilizador confirmou num telefone real: «Agora está a funcionar perfeitamente», e autorizou a publicação pública em 23/10/2026.

A versão **1.1.10+21** foi disponibilizada nos testes internos e, após essa confirmação física, o mesmo pacote foi promovido e enviado para **produção em 23/10/2026**, lançamento «1.1.10 — Reabertura com áudio ativo». A Play Console confirmou **«Alterações em revisão»**, com verificações rápidas ainda em curso. A implementação está definida para **100%** dos utilizadores nos países já selecionados e a publicação gerida está desativada, pelo que a atualização será publicada automaticamente após aprovação. O envio não confirma disponibilidade pública. O AAB aprovado não foi recompilado nem alterado e tem SHA-256 `4794bb1726885fc9fddf2d5da58af4907e7f07f095541ad8b41bf31a6379f3e5`.

Aplicação Android oficial da Rádio Cristã Portuguesa Palavra Antiga. A versão **1.1.9+20** foi testada pelo utilizador e enviada à Google Play em **23/10/2026**.

No telefone, a app mantém os destinos **Rádio | Música | Conta | WhatsApp**. A interface web é apresentada numa WebView; a emissão, a biblioteca, a MediaSession e o Android Auto usam o serviço de áudio nativo.

## Fontes e compilação

As fontes completas são reconstruídas a partir de `ci/rpa106-nav-source.tar.xz.b64`, aplicando depois `source-overrides/` sobre a base extraída. O procedimento e a verificação do resumo SHA-256 estão em `.github/workflows/build-debug-apk.yml`. Os ficheiros Flutter mais recentes estão em `source-overrides/lib/` e os testes adicionais em `source-overrides/test/`.

Esta revisão parte das fontes da 1.0.18+19. A versão 1.1.9+20 prepara uma correção para o desaparecimento intermitente do menu inferior ao regressar do segundo plano. O menu recebe uma nova camada de desenho após a retoma ou alteração das dimensões do ecrã, incluindo o fundo da margem inferior. O Android também pede uma atualização da janela ao recuperar o foco. O separador selecionado, a WebView e o serviço de áudio mantêm o seu estado.

## Validação da 1.1.9

- Análise Flutter concluída sem erros de compilação.
- 86 testes Flutter, 26 testes JavaScript e 5 testes Python aprovados.
- APK de teste e AAB de lançamento compilados e validados. O AAB usa o certificado de envio existente.
- Teste num aparelho real: o utilizador confirmou «Parece estar ok» e autorizou a publicação em 23/10/2026. Sendo um problema intermitente, esta confirmação não constitui garantia de ausência de recorrência.
- Validação automática completa no emulador: **não concluída**. As execuções perderam a ligação ADB ou terminaram antes de completar os testes de retoma, incluindo a tentativa com outro motor gráfico.

A compilação está no [ensaio de compilação](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/39874168182). A verificação visual reutiliza o mesmo AAB assinado e confirma que as fontes da app não mudaram: [última verificação Android](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/39876655707).

| Ficheiro | Pacote Android | Utilização |
| --- | --- | --- |
| Radio-Palavra-Antiga-1.1.9-teste.apk | org.palavraantiga.radio.debug | Instala a app independente «Palavra Antiga — Teste». |
| Radio-Palavra-Antiga-1.1.9-Play.aab | org.palavraantiga.radio | Enviado à Google Play para produção. Aguarda verificações e revisão da Google. |

A confirmação física foi recebida e o envio do lançamento **1.1.9 — Menu e retoma da app** foi confirmado na Play Console em 23/10/2026. O pacote aprovado não foi alterado desde a compilação indicada. A implementação está configurada para 100% dos utilizadores nos países já selecionados, com publicação automática após aprovação. Foi necessário reiniciar a revisão anterior da 1.0.18; o estado inicial após o envio era «Alterações em revisão», com as verificações rápidas da Google ainda em curso. O envio não significa que a versão já esteja disponível na loja.

## Catálogo público

O catálogo `catalog/official_playlists.json` é atualizado por `.github/workflows/update-playlist-catalog.yml`, com execução manual e agendamento horário (`17 * * * *`, UTC). O GitHub pode atrasar ou omitir execuções agendadas; esta frequência não garante uma latência máxima de uma hora.

São incluídas apenas playlists ativas com **Include in On-Demand Player** ligado e pelo menos uma música presente no catálogo público On-Demand do AzuraCast. Playlists vazias ou sem músicas públicas não aparecem. A rotina consulta todas as páginas da API e publica o catálogo apenas quando os dados mudam; por isso, `generated_at` indica a última alteração publicada e não a última verificação.

A app consulta a versão pública ao carregar a página e ao entrar em **Música**, com um intervalo mínimo de 15 minutos entre tentativas normais. Se não houver rede, usa a última versão válida guardada ou o catálogo incluído na app. As alterações de playlists não exigem uma nova versão da app. Não existe um temporizador contínuo de atualização do catálogo enquanto o utilizador permanece no mesmo ecrã.

As playlists pessoais criadas na app são distintas das playlists oficiais do AzuraCast. As chaves da API e de assinatura permanecem nos segredos do GitHub Actions; não pertencem ao código ou ao catálogo público.
