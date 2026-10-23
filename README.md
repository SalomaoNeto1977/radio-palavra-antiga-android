# Rádio Palavra Antiga Android

Aplicação Android oficial da Rádio Cristã Portuguesa Palavra Antiga. A versão de teste em preparação é **1.1.9+20**.

No telefone, a app mantém os destinos **Rádio | Música | Conta | WhatsApp**. A interface web é apresentada numa WebView; a emissão, a biblioteca, a MediaSession e o Android Auto usam o serviço de áudio nativo.

## Fontes e compilação

As fontes completas são reconstruídas a partir de `ci/rpa106-nav-source.tar.xz.b64`, aplicando depois `source-overrides/` sobre a base extraída. O procedimento e a verificação do resumo SHA-256 estão em `.github/workflows/build-debug-apk.yml`. Os ficheiros Flutter mais recentes estão em `source-overrides/lib/` e os testes adicionais em `source-overrides/test/`.

Esta revisão parte das fontes da 1.0.18+19. A versão 1.1.9+20 prepara uma correção para o desaparecimento intermitente do menu inferior ao regressar do segundo plano. O menu recebe uma nova camada de desenho após a retoma ou alteração das dimensões do ecrã, incluindo o fundo da margem inferior. O Android também pede uma atualização da janela ao recuperar o foco. O separador selecionado, a WebView e o serviço de áudio mantêm o seu estado.

## Validação da 1.1.9

- Análise Flutter concluída sem erros de compilação.
- 86 testes Flutter, 26 testes JavaScript e 5 testes Python aprovados.
- APK de teste e AAB de lançamento compilados e validados. O AAB usa o certificado de envio existente.
- Validação visual completa no Android: **não confirmada**. As execuções do emulador perderam a ligação ADB ou terminaram antes de completar os testes de retoma, incluindo a tentativa com outro motor gráfico. A correção continua como candidata de teste, sem confirmação no telefone do utilizador.

A compilação está no [ensaio de compilação](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/39874168182). A verificação visual reutiliza o mesmo AAB assinado e confirma que as fontes da app não mudaram: [última verificação Android](https://github.com/SalomaoNeto1977/radio-palavra-antiga-android/actions/runs/39876655707).

| Ficheiro | Pacote Android | Utilização |
| --- | --- | --- |
| Radio-Palavra-Antiga-1.1.9-teste.apk | org.palavraantiga.radio.debug | Instala a app independente «Palavra Antiga — Teste». |
| Radio-Palavra-Antiga-1.1.9-Play.aab | org.palavraantiga.radio | Pacote preparado para envio à Google Play. Publicação pendente. |

É necessária confirmação num aparelho real antes de considerar resolvido o comportamento intermitente observado pelo utilizador.

## Catálogo público

O catálogo `catalog/official_playlists.json` é atualizado pela rotina de exportação das opções do AzuraCast. As chaves da API e de assinatura permanecem nos segredos do GitHub Actions; não pertencem ao código ou ao catálogo público.
