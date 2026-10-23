# Rádio Palavra Antiga Android

Aplicação Android oficial da Rádio Cristã Portuguesa Palavra Antiga. A versão **1.1.9+20** foi testada pelo utilizador e aprovada para envio à Google Play.

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
| Radio-Palavra-Antiga-1.1.9-Play.aab | org.palavraantiga.radio | Pacote preparado para envio à Google Play. Publicação pendente. |

A confirmação física foi recebida. O envio à Google Play continua pendente; o pacote aprovado não foi alterado desde a compilação indicada.

## Catálogo público

O catálogo `catalog/official_playlists.json` é atualizado por `.github/workflows/update-playlist-catalog.yml`, com execução manual e agendamento horário (`17 * * * *`, UTC). O GitHub pode atrasar ou omitir execuções agendadas; esta frequência não garante uma latência máxima de uma hora.

São incluídas apenas playlists ativas com **Include in On-Demand Player** ligado e pelo menos uma música presente no catálogo público On-Demand do AzuraCast. Playlists vazias ou sem músicas públicas não aparecem. A rotina consulta todas as páginas da API e publica o catálogo apenas quando os dados mudam; por isso, `generated_at` indica a última alteração publicada e não a última verificação.

A app consulta a versão pública ao carregar a página e ao entrar em **Música**, com um intervalo mínimo de 15 minutos entre tentativas normais. Se não houver rede, usa a última versão válida guardada ou o catálogo incluído na app. As alterações de playlists não exigem uma nova versão da app. Não existe um temporizador contínuo de atualização do catálogo enquanto o utilizador permanece no mesmo ecrã.

As playlists pessoais criadas na app são distintas das playlists oficiais do AzuraCast. As chaves da API e de assinatura permanecem nos segredos do GitHub Actions; não pertencem ao código ou ao catálogo público.
