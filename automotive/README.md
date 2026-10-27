# Rádio Palavra Antiga — Android Automotive OS

Versão própria para instalação direta em veículos com Android Automotive OS e Google Play, como os Polestar compatíveis. O pacote mantém o identificador `org.palavraantiga.radio`, usa a assinatura de envio existente e destina-se exclusivamente ao canal Android Automotive OS. A app de telefone e o seu Android Auto continuam na versão 1.1.10.

A versão 1.2.1 inclui a imagem dourada da Rádio sobre a Bíblia como capa predefinida da estação, preservando as capas próprias das músicas. A imagem fornecida é incluída sem recorte ou alteração em `automotive/assets/station-artwork.jpg`.

A app oferece a emissão em direto, título, intérprete e capa da emissão, controlos do leitor do carro e pesquisa pelo nome da rádio. O automóvel apresenta a interface através de MediaLibraryService e MediaSession. Não é necessário iniciar sessão. O módulo não contém Activity, WebView, compras ou comandos Bluetooth do telefone. Usa uma instância de ExoPlayer, com gestão de foco de áudio pelo Media3 e recuperação após falhas de rede. Uma pausa manual cancela as tentativas de recuperação.

## Compilação

Java 17, Android SDK 36 e Gradle 8.14.6. A compilação é independente do Flutter. Na raiz do repositório:

```sh
gradle -p automotive testDebugUnitTest lintRelease assembleDebug
```

O lançamento exige as variáveis de assinatura existentes `RPA_STORE_FILE`, `RPA_STORE_PASSWORD`, `RPA_KEY_PASSWORD` e `RPA_KEY_ALIAS`. As credenciais nunca pertencem ao repositório.

```sh
gradle -p automotive bundleRelease
```

A versão automóvel é 1.2.1, código 1200002. A versão 1.2.0 foi publicada em testes internos a 27/10/2026, com a lista dos 34 testadores da Rádio associada. Reservar os códigos a partir de 1200001 para AAOS e manter únicos os códigos das próximas versões para telefone. O pacote de depuração tem o identificador `org.palavraantiga.radio.automotive.debug`.

## Validação e publicação

O workflow `.github/workflows/build-automotive.yml` compila, executa testes de políticas, metadados e serviço com Robolectric, verifica o manifesto e confere a assinatura. Estes ensaios não substituem a validação no emulador AAOS ou num carro.

Antes de disponibilizar ao público:

1. Na Play Console da app existente, adicionar o formato Android Automotive OS em Configurações avançadas > Formatos.
2. Escolher o canal exclusivo Android Automotive OS e carregar o AAB assinado num teste interno.
3. Testar no emulador AAOS e, idealmente, num Polestar: instalação, arranque pelo leitor do carro, emissão, capa e título, pausa, comandos no volante, perda e recuperação de rede, interrupção por outra fonte áudio, reinício do sistema e fim da sessão do veículo.
4. Confirmar que a ligação ao serviço sem uma ordem de reprodução não liga o áudio e que uma pausa manual impede retomas por rede.
5. Capturar a versão real num emulador genérico, sem marcas de fabricantes: pelo menos duas capturas verticais e duas horizontais, com as dimensões atuais exigidas pela Play Console.
6. Rever os países, a ficha e a declaração de segurança de dados; aceitar a política de revisão automóvel e submeter a versão para avaliação.

A disponibilidade final depende da aprovação da Google e da compatibilidade de cada veículo. Não se deve anunciar disponibilidade na loja do carro antes da confirmação.

Referências oficiais:

- https://developer.android.com/training/cars/media/automotive-os
- https://developer.android.com/training/cars/distribute
- https://www.polestar.com/global/developer/
