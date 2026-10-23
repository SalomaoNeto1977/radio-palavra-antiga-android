# Capas dos álbuns

Coloca a imagem na mesma pasta das músicas do álbum no AzuraCast. O nome é livre: não precisa de se chamar `cover.jpg`.

- Formatos aceites: JPG/JPEG, PNG, WebP, GIF, BMP, TIFF e AVIF, até 20 MiB e 25 milhões de píxeis.
- Se existirem várias imagens, usa-se a mais recente segundo a data de alteração no servidor. Em caso de empate, a ordem alfabética torna a escolha estável. Se essa imagem estiver danificada, tenta-se a seguinte.
- A capa aplica-se às playlists oficiais cujas músicas públicas estão todas nessa pasta. Playlists que misturam pastas mantêm as capas individuais das músicas.
- As imagens são convertidas em JPEG, com um máximo de 1024 píxeis por lado, sem metadados. Uma alteração visual produz um novo endereço, evitando reutilizar uma capa antiga em cache. Os originais no AzuraCast não são alterados.

A rotina `.github/workflows/update-playlist-catalog.yml` verifica o catálogo e as capas de hora a hora e também pode ser executada manualmente. Os agendamentos do GitHub podem sofrer atrasos. A app procura o catálogo ao abrir e ao entrar em Música, respeitando o intervalo mínimo de 15 minutos entre tentativas normais. Não é necessária uma nova versão Android para estas capas.

Se o servidor não responder, o catálogo anterior continua publicado. O registo da rotina mostra o número de álbuns com capa e de pastas verificadas, sem publicar caminhos internos nem a chave da API.
