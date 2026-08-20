# Portside project guide

Este documento é o mapa operacional do monorepo. O repositório raiz é a única
fonte de código para o app macOS, a API, a landing page, os builds de runtime e
a automação de release. Saídas de build ficam em `build/` e `.build/`, que são
geradas localmente ou pelo CI e não são fonte de código.

## Organização do monorepo

```text
apps/
  desktop/          aplicativo macOS, agente, núcleo e testes Swift
  backend/          API NestJS, Prisma, worker, cron e testes Vitest
  landing/          landing page e fluxo comercial em TanStack Start/React
  runtime-host/     host nativo usado pelo wrapper produzido pelo Portside
runtime/
  wrapper-template/ template PortsideBaseline.app e configuração padrão
vendor/
  sikarugir/        snapshot de referência de fontes Sikarugir
  wrapper/          snapshot de referência do repositório Wrapper
  engines/          catálogo de engines de referência
  wine/             snapshot completo da árvore Wine usada no build
  winetricks/       snapshot do winetricks usado no build
  foss-sources/     fontes FOSS de referência e notices
upstream/
  lock.json         commits, licenças e checksums dos snapshots
  dependencies.json dependências de build fixadas por versão/checksum
  licenses/         cópias e inventários de licenças
  patches/          patches mantidos pelo Portside
scripts/
  build-runtime/    build, empacotamento e validação do runtime
  upstream/         sincronização e auditoria dos snapshots
  *.sh              build do app, assinatura, notarização e publicação
.github/workflows/  CI, sync, build, release e deploy/verificação
docs/               runbooks técnicos, segurança, compatibilidade e operação
```

### Aplicativos

`apps/desktop/` é um Swift Package com três produtos: `Portside`,
`PortsideAgent` e a biblioteca `PortsideCore`. A interface e o ciclo de vida
ficam em `Sources/Portside`; o download/verificação/rollback, compatibilidade,
diagnóstico e manifesto ficam em `Sources/PortsideCore`; os plist, entitlements,
logo e ícones ficam em `Resources/`; os unitários ficam em
`Tests/PortsideCoreTests/`.

`apps/backend/` é o control plane comercial. `src/core` carrega configuração,
`src/common` concentra guardas, segurança e sanitização, `src/database` integra
Prisma, e `src/modules` separa health, licenças, artefatos, runtime, admin e
sincronização. DTOs ficam em `dtos/` dentro do módulo e os unitários usam
`*.spec.ts` ao lado do código. `prisma/schema.prisma` e
`prisma/migrations/` definem o banco. `src/main.ts`, `src/worker.ts` e
`src/cron.ts` são as entradas dos serviços distintos.

`apps/landing/` é a fonte local da página de venda. O código foi importado do
repositório `andre-fig/portside-games-on-mac` no commit
`3cb34d47f85016b87152b41f2ce040a4c723d91b`; o diretório `.git` não foi
importado e o build não consulta aquele repositório. `src/routes` contém as
rotas públicas (`/`, `/comprar`, `/sucesso`, `/suporte`, `/termos` e
`/privacidade`); `src/components/site` contém cabeçalho, rodapé e logo;
`src/components/ui` contém componentes Radix reutilizáveis; `src/lib` contém
checkout, preço, pedido e utilitários de servidor; `public/` contém arquivos
estáticos, incluindo o logo local do Portside. O preço e as credenciais da
Stripe são lidos no servidor e nunca devem ser gravados no bundle ou no Git.

`apps/runtime-host/` não é um aplicativo de usuário separado. Ele contém o
executável nativo que o script de runtime compila e coloca em
`PortsideBaseline.app/Contents/MacOS/PortsideRuntimeHost`.

### Runtime e fontes

`runtime/wrapper-template/` é um template mínimo próprio: `Contents/Info.plist`
define a identidade do wrapper, `Contents/Resources/portside-runtime.json`
define WineD3D, MSYNC/ESYNC e os caminhos relativos, e os `.gitkeep` reservam
as áreas de prefixo e runtime. O engine compilado não é versionado nesse
diretório.

`vendor/` contém somente fontes e metadados de upstream, sem `.git` aninhado,
archives compilados, caches ou `node_modules`. A origem exata, o commit, a
licença, o checksum e o estado de validação ficam em `upstream/lock.json`.
`vendor/wine` é a base do engine que o Portside compila; `vendor/winetricks` é
empacotado como ferramenta de instalação; os demais snapshots são preservados
para auditoria e futuras reproduções. O Creator não é copiado porque não foi
provado necessário para construir o runtime.

## Origem dos artefatos e packages

| Saída | Fonte controlada | Como é produzida |
| --- | --- | --- |
| `Portside.app` | `apps/desktop` + dependências SwiftPM | `build_release.sh` compila os produtos e monta o bundle |
| `Portside-<versão>.dmg` | `Portside.app` assinado | `notarize_release.sh` cria o DMG, envia ao `notarytool`, staple e valida |
| `PortsideWrapper-<versão>.tar.xz` | `runtime/wrapper-template` + `apps/runtime-host` | `build-runtime/build-wrapper.sh` |
| `PortsideWineEngine-<versão>.tar.xz` | `vendor/wine` + toolchain fixado | `build-runtime/build-wine-engine.sh` |
| `PortsideWinetricks-<versão>.tar.xz` | `vendor/winetricks` | `build-runtime/build-winetricks.sh` |
| `runtime-manifest.json` | checksums e proveniência da build | `generate_manifest.sh` assina o manifesto Ed25519 |
| `appcast.xml` | ZIP notarizado do app | `generate_appcast.sh` usa o `generate_appcast` do Sparkle |
| landing build | `apps/landing` + `apps/landing/bun.lock` | `.github/workflows/build-landing.yml` executa Bun, lint e build |

Dependências Swift vêm de `apps/desktop/Package.swift` e são resolvidas em
`Package.resolved`: Sparkle e Sentry. Dependências do backend vêm de
`apps/backend/package.json` e `package-lock.json`, instaladas com `npm ci`.
Dependências da landing vêm de `apps/landing/package.json` e `bun.lock`,
instaladas com `bun install --frozen-lockfile`. Dependências de compilação do
Wine (bison, mingw-w64, LLVM, lld, freetype e pkgconf) têm versão, origem,
checksum, licença e papel registrados em `upstream/dependencies.json`.

Steam não é empacotada no Portside. O runtime instala a Steam pelo verbo
`steam` do winetricks durante a preparação do prefixo e a obtém diretamente
da Valve. Não copie a Steam nativa do macOS nem publique o instalador da Steam
nos buckets do Portside.

## Catálogo de scripts

### Build do app e release

- `scripts/package_app.sh`: build local de validação. Compila o app e o agente,
  monta `build/Portside.app`, assina ad hoc por padrão e cria dSYM. Não é uma
  release comercial.
- `scripts/build_release.sh`: build configurado de release. Injeta versão,
  API, feed Sparkle, chaves públicas, hosts de artefatos e canal em
  `Info.plist`; produz bundle ainda não assinado.
- `scripts/sign_release.sh`: gera/associa o manifesto assinado, assina
  Sparkle, agente e app com `Developer ID Application`, valida codesign e cria
  o ZIP intermediário.
- `scripts/notarize_release.sh`: submete ZIP e DMG ao `xcrun notarytool`, faz
  `stapler staple` no `.app` e no `.dmg`, valida ambos e registra checksums.
- `scripts/validate_release_bundle.sh`: verifica plist do app e agente,
  assinatura, presença e conteúdo básico do DMG.
- `scripts/generate_appcast.sh`: gera `appcast.xml` assinado com a chave
  privada Ed25519 do Sparkle, mantida fora do repositório.
- `scripts/generate_manifest.sh`: assina o manifesto JSON de runtime com uma
  chave privada Ed25519 externa; só recebe entrada com `signature: null`.
- `scripts/publish_release.sh`: publica ZIP, DMG, appcast, checksums,
  runtime, proveniência e SBOM nos buckets primário e secundário. Produção
  exige `PORTSIDE_CONFIRM_PRODUCTION=YES`.
- `scripts/publish_runtime_staging.sh`: publica apenas os três artefatos do
  runtime, manifesto assinado, proveniência e SBOM no canal `staging`.

### Build e validação do runtime

- `scripts/build-runtime/build.sh`: orquestra auditoria de fontes, wrapper,
  engine Wine e winetricks; calcula checksums, cria proveniência/SBOM, monta o
  manifesto unsigned e valida tudo.
- `scripts/build-runtime/build-wrapper.sh`: compila `PortsideRuntimeHost`,
  materializa `PortsideBaseline.app` e empacota o template.
- `scripts/build-runtime/build-wine-engine.sh`: configura e compila o Wine
  arm64/macOS e os binários PE necessários diretamente de `vendor/wine`, com a
  toolchain fixada; não baixa um engine pronto.
- `scripts/build-runtime/build-winetricks.sh`: empacota o script e os verbos
  do snapshot local de winetricks.
- `scripts/build-runtime/create-archive.sh`: cria arquivos tar.xz com IDs,
  metadados e timestamps normalizados para builds reproduzíveis.
- `scripts/build-runtime/source-audit.sh`: rejeita fonte ausente, `.git`,
  archives compilados e referências proibidas no material usado pela build.
- `scripts/build-runtime/validate-clean-layout.sh`: extrai os três archives
  para uma área temporária e confirma o layout mínimo, o host, o engine e o
  verbo winetricks.
- `scripts/build-runtime/validate-manifest.sh`: valida schema, canal,
  componentes, URLs HTTPS aprovadas, tamanho, SHA-256 e proveniência.
- `scripts/validate-production-policy.sh`: impede URLs de release do upstream,
  nomes legados em código de produção, fontes vendorizados inválidos e runtime
  compilado dentro de `vendor/`.

### Upstream e checksums

- `scripts/upstream/sync.sh`: clona snapshots autorizados de forma rasa,
  usa `--filter=blob:none` para Wine, resolve submódulos/LFS quando declarados,
  compara commits, valida o snapshot, detecta mudança de licença e atualiza
  `vendor/` e `upstream/lock.json`. A revisão e o merge continuam manuais.
- `scripts/upstream/validate_snapshot.sh`: rejeita `.git`, caches, diretórios
  gerados e symlinks que escapem do snapshot.
- `scripts/upstream/snapshot_checksum.sh`: calcula checksum estável de paths,
  conteúdos e destinos de symlink sem incluir metadados Git.
- `scripts/upstream/license_inventory_checksum.sh`: calcula checksum somente
  do inventário de licenses/copyright/notice para destacar mudanças legais.

## Como criar o app e o DMG

### Validação local sem assinatura comercial

```bash
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh
open build/Portside.app

ditto -c -k --sequesterRsrc --keepParent \
  build/Portside.app build/Portside-validation.app.zip
hdiutil create -volname Portside -srcfolder build/Portside.app \
  -ov -format UDZO build/Portside-validation.dmg
```

Esse DMG é apenas de validação e pode gerar aviso do macOS. Não o distribua a
clientes.

### Release comercial

Em um runner macOS aprovado, configure apenas variáveis públicas e referências
a segredos externos. As chaves privadas nunca devem ser salvas no repositório:

```bash
export PORTSIDE_VERSION=1.0.0
export PORTSIDE_UPDATE_CHANNEL=staging
export PORTSIDE_API_BASE_URL=https://api.example.com
export PORTSIDE_UPDATE_FEED_URL=https://artifacts.example.com/app/staging/appcast.xml
export PORTSIDE_SPARKLE_PUBLIC_KEY=...
export PORTSIDE_RUNTIME_MANIFEST_PUBLIC_KEY=...
export PORTSIDE_LICENSE_PUBLIC_KEY=...
export PORTSIDE_LICENSE_KEY_ID=...
export PORTSIDE_ARTIFACT_HOSTS=artifacts.example.com
export PORTSIDE_CODESIGN_IDENTITY='Developer ID Application: Sua Empresa (TEAMID)'
export PORTSIDE_NOTARY_PROFILE=portside-notary

./scripts/build_release.sh
PORTSIDE_MANIFEST_SIGNING_KEY_FILE=/fora-do-repo/manifest.key \
  PORTSIDE_RUNTIME_MANIFEST_INPUT=build/releases/runtime-manifest-unsigned.json \
  PORTSIDE_MANIFEST_SIGNING_KEY_ID=runtime-2026-01 \
  ./scripts/sign_release.sh
./scripts/notarize_release.sh
./scripts/validate_release_bundle.sh
```

O exemplo acima é um roteiro: `build_release.sh` exige todas as variáveis
listadas no próprio script e valores reais. O perfil `notarytool` deve ser
criado previamente no Keychain pelo operador autorizado. O resultado esperado é
um app assinado, um ZIP notarizado e um DMG notarizado com ticket stapled no
`.app` e no `.dmg`.

## Como lançar atualizações

1. Faça a mudança no app, landing, backend ou runtime e rode as validações
   locais.
2. Para runtime, execute `scripts/build-runtime/build.sh` no macOS fixado. A
   saída começa em `staging`; cada componente recebe SHA-256, tamanho, commit
   fonte, proveniência e SBOM.
3. O workflow `build-runtime.yml` publica somente staging depois de testes e
   validações. O app consulta o manifesto assinado e baixa somente hosts
   Portside autorizados.
4. Para o app macOS, `release-production.yml` compila, assina, notariza,
   publica staging e aguarda revisão. O job de produção requer promoção
   explícita e ambiente protegido.
5. `publish_release.sh` replica cada objeto no bucket primário e secundário;
   versões anteriores ficam disponíveis para rollback.
6. O backend registra source snapshot, build, artifact, release, canal,
   promoção e rollback. Um checksum correto, sem build/promoção, não torna um
   artefato production.
7. O Sparkle atualiza o app pelo `appcast.xml`; o runtime usa o manifesto
   assinado, instala atomicamente e mantém a versão anterior. Em caso de
   backend offline, continua usando a instalação válida já ativa.

Para voltar uma versão, promova o release anterior no backend e publique o
manifesto/appcast correspondente. Não apague `SteamLibrary`, saves, prefixos
de usuário ou dados de conta durante o rollback.

## Landing page e venda

```bash
cd apps/landing
bun install --frozen-lockfile
bun run dev
bun run lint
bun run build
```

O workflow `build-landing.yml` executa esses checks e guarda `.output` como
artefato de CI. O deploy público ainda exige um provedor de hospedagem e uma
configuração de ambiente; a origem do código já é o monorepo e não o antigo
repositório separado.

Variáveis de servidor esperadas pelo fluxo comercial:

- `STRIPE_SECRET_KEY` ou `STRIPE_TEST_API_KEY`;
- `STRIPE_PRICE_ID` (ou `PORTSIDE_PRICE_AMOUNT` e `PORTSIDE_PRICE_CURRENCY`);
- `PORTSIDE_PRICE_LOCALE`;
- `APP_BASE_URL`;
- `STRIPE_WEBHOOK_SECRET`, integração de pedidos/licenças no backend e
  `EMAIL_PROVIDER_API_KEY` quando a entrega por e-mail estiver habilitada.

O navegador recebe somente dados públicos do preço e a URL de checkout. A
confirmação de compra deve vir do webhook validado; o redirecionamento para
`/sucesso` não é prova de pagamento. Apple Pay depende de HTTPS, domínio
verificado na Stripe e disponibilidade real do dispositivo/navegador.

## Workflows

- `ci.yml`: política de fontes, testes Swift e checks do backend.
- `build-landing.yml`: lint, build e artifact da landing.
- `build-desktop.yml`: bundle e DMG de validação não comercial após CI.
- `build-runtime.yml`: build próprio do runtime no macOS fixado. Pushes fazem
  build source-only e guardam evidência; `workflow_dispatch` com secrets e
  buckets configurados também assina e publica em staging.
- `sync-upstreams.yml`: sincronização diária/manual, sem merge automático.
- `release-production.yml`: release staging, notarização e promoção protegida.
- `deploy-railway.yml`: verificação de health do backend já publicado no
  Railway; não usa o filesystem efêmero para artefatos.

## Secrets e infraestrutura

O CI precisa de Developer ID Application, perfil `notarytool`, chave privada
Sparkle, chave privada do manifesto, configuração da Stripe, token admin do
backend e credenciais dos buckets. Todos devem ficar em GitHub Environments,
Keychain ou secret manager. O Railway hospeda API/worker/cron e PostgreSQL; os
arquivos de runtime e releases ficam em storage de objetos primário e
secundário. O bucket e os hosts reais ainda precisam ser configurados pelo
operador antes de produção.

Arquivos `.env`, chaves, certificados, DMGs, ZIPs, `node_modules`, `.build` e
`build/` são ignorados. Confirme `git status` antes de adicionar qualquer
artefato para garantir que um segredo ou dado local não entrou no commit.

## Validação mínima antes de publicar

```bash
swift test --package-path apps/desktop
swift build --package-path apps/desktop

cd apps/backend
npm ci
npm run prisma:validate
npm run typecheck
npm run lint
npm test
npm run build
cd ../..

cd apps/landing
bun install --frozen-lockfile
bun run lint
bun run build
cd ../..

./scripts/validate-production-policy.sh
git diff --check
```

Além dos checks automatizados, a aceitação do app exige abrir o bundle em uma
sessão gráfica real e confirmar janela renderizada da Steam, login interativo,
`steamwebhelper` funcional e permanência após o updater. Processo, Dock ou
arquivo existente não são evidência visual.

## Limites conhecidos

- A venda real depende das credenciais Stripe, webhook, serviço de e-mail,
  domínio HTTPS e integração de licença no backend.
- A publicação final depende de Developer ID, notarização e buckets aprovados.
- O runtime é construído de fontes versionados pelo Portside, mas equivalência
  byte a byte com um engine histórico do upstream não é afirmada sem uma build
  comparativa validada.
- Steam continua sendo uma dependência externa obtida da Valve no momento da
  instalação; ela não é redistribuída pelo Portside.
- A compatibilidade varia por jogo. O produto não promete que todos os títulos,
  launchers, drivers ou sistemas anti-cheat funcionarão.
