# Rádio Palavra Antiga Android

Aplicação Android oficial da Rádio Cristã Portuguesa Palavra Antiga.

Este repositório é a fonte oficial do projeto Flutter/Android. A versão em preparação é a 1.0.10, com reprodução nativa no Android Auto, restauro automático da última fila/posição no carro e suspensão da WebView quando a interface não está visível. No telefone mantém a navegação Rádio | Música | WhatsApp, as playlists oficiais e os pedidos de músicas elegíveis.

O catálogo público em `catalog/official_playlists.json` é regenerado de hora a hora a partir das opções escolhidas no AzuraCast. Contém nomes de playlists, identificadores públicos e endereços das capas exportadas; a chave da API permanece protegida nos segredos do GitHub Actions. As [capas dos álbuns](catalog/README.md) podem ter qualquer nome: a rotina usa a imagem válida mais recente da pasta das músicas.

