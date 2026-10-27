# Rádio Palavra Antiga — Google TV / Android TV

Aplicação nativa para televisão, versão 1.3.0, código 1300001, pacote `org.palavraantiga.radio`.
O módulo independente `tv` destina-se exclusivamente a televisões com Android TV OS e Google Play.
Usa a chave de envio existente. Os módulos de telefone e automóvel não são modificados.

Emissão em direto, título, intérprete e capa, comandos grandes com foco visível, navegação
por setas/OK/Voltar e botões multimédia. O áudio continua no ecrã inicial com os controlos
da MediaSession. A ligação ao leitor não inicia áudio. A app permite Ambient Mode.
Não exige conta e não inclui compras, publicidade própria ou ligações para um navegador.

Java 17, Android SDK 36, Gradle 8.14.6:

```sh
gradle -p tv testDebugUnitTest lintRelease assembleDebug assembleDebugAndroidTest
gradle -p tv bundleRelease
```

O lançamento exige as variáveis de assinatura `RPA_STORE_FILE`, `RPA_STORE_PASSWORD`,
`RPA_KEY_PASSWORD` e `RPA_KEY_ALIAS`, mantidas nos segredos do GitHub Actions.
O workflow `build-tv.yml` valida os testes, o manifesto, a assinatura e a reprodução real
num emulador Google TV, com capturas sem edição a 1920 × 1080.

A publicação usa o formato Android TV e a faixa exclusiva da app já existente na Play Console.
A disponibilidade pública depende da aprovação da Google. Um ensaio numa televisão física
não é substituído pelos testes no emulador.
