# Google Play Billing — apoios mensais

## Produtos a criar na Play Console

Criar quatro produtos de subscrição, cada um com um plano base mensal de
renovação automática, sem período experimental. Todos concedem exatamente o
mesmo direito: acesso ao `Palavra Antiga Music`.

| ID do produto | Nome apresentado | Preço mensal em Portugal/Bélgica |
| --- | --- | ---: |
| `apoio_mensal_590` | Apoio Amigo | 5,99 € |
| `apoio_mensal_999` | Apoio Companheiro | 9,99 € |
| `apoio_mensal_1999` | Apoio Fiel | 19,99 € |
| `apoio_mensal_4999` | Apoio Semeador | 49,99 € |

Usar o mesmo texto de benefício nos quatro produtos:

> Desbloqueia o catálogo Palavra Antiga Music, as playlists e os favoritos.
> A rádio em direto e os pedidos de músicas continuam gratuitos.

## Regras aplicadas pela aplicação

- A emissão em direto é sempre gratuita.
- Os pedidos ao AzuraCast são sempre gratuitos.
- O catálogo pode ser consultado sem subscrição, mas os controlos de
  reprodução mostram um cadeado.
- Uma compra ou restauro válido desbloqueia a reprodução sob demanda.
- O Android Auto só expõe o catálogo sob demanda quando existe acesso ativo.
- A última confirmação da Google Play é aceite durante três dias sem rede.
- Se a Google Play confirmar que já não existe uma subscrição, o acesso é
  removido e qualquer reprodução sob demanda é parada.
- A compra é concluída/confirmada junto da Google Play depois de o direito ser
  atribuído, evitando o reembolso automático por falta de confirmação.

## Teste antes da produção

1. Criar e ativar os quatro produtos e respetivos planos base.
2. Publicar o AAB numa faixa de teste interno ou fechado.
3. Adicionar as contas Google dos testadores de licença.
4. Instalar exclusivamente pela ligação da Play Store.
5. Testar compra aprovada, compra pendente, cancelamento, restauro e mudança de
   conta Google.
6. Confirmar que uma conta gratuita ainda consegue ouvir a emissão e pedir uma
   música, mas não reproduzir o catálogo no telemóvel nem no Android Auto.


## Versão 1.0.16 — colaboradores e capas

A área Conta contém **Tenho um código de colaborador**. Os dez códigos locais de
quatro dígitos oferecem acesso a todo o catálogo, sem autenticação, servidor ou
pagamento. A app guarda a ativação no dispositivo e preserva-a ao reiniciar.
Cada código pode ser usado em mais de um telefone. Reinstalar a app exige voltar
a introduzir o código. A lista privada é entregue ao responsável, separadamente.
O acesso de colaborador e o acesso pago são independentes: restaurar compras
sem uma subscrição não remove o acesso oferecido.

Para a capa de um álbum, colocar um **JPEG verdadeiro chamado `cover.jpg`** na
mesma pasta das músicas no AzuraCast (aconselhável quadrado, 1000 × 1000).
O catálogo público é atualizado de hora a hora e exporta a imagem, sem expor
chaves API ou caminhos internos. A capa da pasta tem prioridade na app, no
leitor e no Android Auto. Playlists que misturam pastas mantêm a capa existente.
Sem `cover.jpg`, continua a ser usada a imagem da música. O ficheiro pode ter até
5 MiB. Trocar a imagem cria um novo URL e evita manter uma capa antiga em cache.

Os preços de referência são 5,99 €, 9,99 €, 19,99 € e 49,99 € por mês.
O ID legado `apoio_mensal_590` mantém-se para o plano de 5,99 €.
O valor apresentado pela Google Play tem prioridade sobre o valor de referência.
Os planos estão configurados para Portugal e Bélgica, conforme os dados fornecidos.

Antes de disponibilizar ao público: carregar o AAB assinado numa faixa de teste
Google Play e testar comprar, cancelar e restaurar os quatro planos com a versão
instalada pela Play Store. A compilação e os testes automáticos não substituem
esse teste real. O APK de teste utiliza `org.palavraantiga.radio.debug`.
