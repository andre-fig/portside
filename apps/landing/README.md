# Portside landing page

Esta aplicação faz parte do monorepo Portside e é a fonte oficial da landing
page e da página de compra. Ela foi importada do repositório
`andre-fig/portside-games-on-mac` no commit `3cb34d47f85016b87152b41f2ce040a4c723d91b`.
O repositório externo não é usado pelo build ou pelo deploy do Portside.

## Desenvolvimento local

```bash
bun install --frozen-lockfile
bun run dev
```

Validações disponíveis:

```bash
bun run lint
bun run build
```

As variáveis de pagamento são somente de servidor. Não crie `.env` versionado;
configure segredos no ambiente de deploy. Os nomes esperados estão descritos
em `docs/PROJECT_GUIDE.md`.

---

# Product brief: Mac Gaming Unleashed

Desenvolvimento Portside e implemente sua landing page comercial completa. A logo oficial será fornecida em anexo: utilize-a no cabeçalho, favicon, página de pagamento e demais pontos adequados, sem redesenhá-la nem substituí-la.

Produto

Portside é um aplicativo para Macs com Apple Silicon que prepara automaticamente um ambiente de compatibilidade, abre a versão Windows da Steam e permite instalar e executar jogos Windows da biblioteca do usuário. Toda a complexidade de Wine, engines, renderers e configurações deve permanecer escondida.

A comunicação deve transmitir:

instalar, abrir a Steam e jogar;

acesso a mais jogos da biblioteca Steam no Mac;

configuração automática;

experiência simples e integrada ao macOS;

compatibilidade variável conforme o jogo;

independência da Valve e da Apple.

Não afirme que todos os jogos funcionam. Explique de maneira discreta que alguns títulos, especialmente os dependentes de determinados sistemas anticheat, drivers ou launchers, podem não ser compatíveis.

Design

Crie um visual extremamente clean, premium e minimalista, inspirado na qualidade visual do site da Apple:

muito espaço em branco;

hierarquia tipográfica forte;

títulos grandes e objetivos;

animações suaves e discretas;

cartões com cantos arredondados;

sombras leves;

navegação simples;

excelente aparência em Mac, iPhone e iPad;

fundo predominantemente branco;

cinzas neutros, preto suave e tons de azul semelhantes aos usados em interfaces da Apple;

utilize também as cores da logo do Portside para manter identidade própria.

Use a fonte nativa do sistema com uma stack como:

font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display",
             "SF Pro Text", "Helvetica Neue", Arial, sans-serif;


Não distribua arquivos proprietários de fontes da Apple. Use as fontes instaladas no sistema e fallbacks adequados.

O resultado pode ser inspirado na clareza da Apple, mas não deve copiar páginas, componentes, ilustrações ou identidade visual da Apple.

Estrutura da landing page

Implemente:

Cabeçalho com logo, nome Portside, “Como funciona”, “Compatibilidade”, “Preço”, “FAQ” e botão “Comprar”.

Hero com mensagem semelhante a:

Mais jogos da sua Steam. Agora no Mac.

O Portside prepara tudo automaticamente para você abrir a Steam do Windows, instalar seus jogos e começar a jogar no seu Mac com Apple Silicon.


Botões:

“Comprar Portside”

“Veja como funciona”

Demonstração visual simples do fluxo:

abra o Portside;

entre na Steam;

instale e jogue.

Seção destacando:

configuração automática;

integração amigável com o macOS;

atualização do ambiente de compatibilidade;

perfis automáticos por jogo;

reparação e diagnóstico simplificados.

Seção transparente sobre compatibilidade.

Card de preço, cujo valor deve vir de configuração/backend, sem ficar duplicado ou rigidamente gravado no frontend.

FAQ.

Rodapé com termos, privacidade, suporte e o aviso:

Portside é um produto independente e não é afiliado, patrocinado ou endossado pela Valve Corporation ou pela Apple Inc. Steam é uma marca da Valve Corporation.


Pagamento

Ao clicar em “Comprar Portside”, direcione o usuário para uma página de pagamento pertencente ao mesmo site e com o mesmo design.

Use Stripe para oferecer:

pagamento com cartão de crédito;

Apple Pay quando disponível;

fallback automático para cartão quando o navegador ou dispositivo não suportar Apple Pay.

Use Stripe Checkout ou Stripe Payment Element conforme for mais adequado à arquitetura existente. Não implemente processamento próprio de cartão e nunca envie dados completos do cartão ao backend do Portside.

O preço e o priceId devem ser configuráveis por ambiente. Utilize modo de teste enquanto não existirem credenciais de produção.

Para Apple Pay:

utilize a integração oficial do Stripe;

documente a verificação do domínio;

exija HTTPS em produção;

mostre o botão somente quando estiver realmente disponível;

não confunda Apple Pay com compra pela App Store ou “Iniciar sessão com a Apple”.

Entrega após a compra

O pagamento só pode ser considerado confirmado após validação segura pelo webhook do Stripe. Não libere o produto apenas porque o navegador foi redirecionado para uma página de sucesso.

Após a confirmação:

crie o pedido no backend;

gere uma licença criptograficamente aleatória;

vincule a licença à compra e ao e-mail informado;

disponibilize uma página segura de confirmação;

envie também um e-mail com o link de download e a licença.

A página de confirmação deve apresentar:

“Pagamento confirmado”;

botão “Baixar Portside”;

chave de licença;

botão “Copiar chave”;

botão “Baixar chave”;

instrução curta para instalação;

opção para reenviar as informações por e-mail.

O botão “Baixar chave” deve gerar um arquivo como:

portside-license.txt


ou um formato próprio seguro, contendo apenas a licença e instruções mínimas. Não inclua dados de pagamento.

O link do aplicativo deve utilizar URL temporária ou assinada gerada pelo backend. A chave nunca deve aparecer em parâmetros de URL, logs, analytics ou mensagens de erro.

Implemente idempotência para impedir que webhooks repetidos gerem múltiplas compras ou licenças.

Arquitetura

Antes de alterar o projeto:

inspecione o repositório atual;

preserve o aplicativo macOS, o backend e as funcionalidades existentes;

reutilize a arquitetura e o padrão visual já existentes quando aplicável;

se ainda não existir frontend web, crie uma aplicação TypeScript moderna e adequada para SEO;

mantenha frontend, pagamento, licenciamento e distribuição desacoplados.

Prepare variáveis de ambiente para:

STRIPE_SECRET_KEY
STRIPE_PUBLISHABLE_KEY
STRIPE_WEBHOOK_SECRET
STRIPE_PRICE_ID
PORTSIDE_DOWNLOAD_BASE_URL
EMAIL_PROVIDER_API_KEY
APP_BASE_URL


Nenhuma chave secreta pode ser enviada ao navegador ou incluída no repositório.

Segurança e privacidade

Valide a assinatura do webhook do Stripe.

Utilize IDs de pedidos não previsíveis.

Proteja a página de entrega com sessão ou token temporário.

Implemente limitação de requisições nos endpoints sensíveis.

Não armazene dados completos de cartão.

Não registre licença completa em logs.

Não coloque binários diretamente no repositório.

Não libere o download antes da confirmação do pagamento.

Não declare que pagamentos reais ou Apple Pay funcionam sem validação efetiva.

Qualidade

A página deve ser:

responsiva;

acessível por teclado e leitores de tela;

rápida;

otimizada para SEO e compartilhamento;

compatível com Safari, Chrome e Firefox;

visualmente consistente em telas Retina;

sem dependências visuais desnecessariamente pesadas.

Adicione testes para:

criação do checkout;

confirmação pelo webhook;

rejeição de webhook inválido;

idempotência;

geração da licença;

página de sucesso sem pagamento;

liberação após pagamento confirmado;

download da licença;

fallback quando Apple Pay não estiver disponível;

ausência de segredos no bundle frontend.

Ao finalizar, execute build, testes e lint. Informe os arquivos criados ou alterados, comandos para execução, variáveis necessárias e quais partes ainda dependem de credenciais, domínio verificado, serviço de e-mail ou artefato real do Portside.
