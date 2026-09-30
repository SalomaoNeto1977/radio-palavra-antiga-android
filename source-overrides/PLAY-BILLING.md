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
