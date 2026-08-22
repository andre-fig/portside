# Guia de desenvolvimento do Portside

Este é o ponto de entrada para uma pessoa que acabou de clonar o monorepo.
Ele explica o que existe, onde cada mudança deve ser feita, como os workflows
se encadeiam e quais partes ainda exigem operação manual. O guia descreve o
estado atual do projeto; os runbooks especializados continuam sendo a fonte de
detalhes de segurança, licenciamento e operação.

## 1. O que é o Portside

Portside é um aplicativo macOS nativo que prepara um runtime local isolado e
abre a Steam oficial para acessar uma biblioteca Windows no Mac. O produto
tem três superfícies:

| Área | Responsabilidade | Deploy/build |
| --- | --- | --- |
| Desktop | Interface macOS, instalação/atualização do runtime, compatibilidade e diagnóstico | Swift Package, runner macOS |
| Backend | API comercial, licenças, artefatos, manifestos, promoções e reconciliação | NestJS/Prisma no Railway |
| Landing | Página pública, compra e suporte comercial | TanStack Start/React, build Bun |

O runtime não fica embutido no `Portside.app`. O desktop recebe um manifesto
assinado, valida os componentes, baixa-os da infraestrutura Portside e instala
uma versão local. A Steam não é distribuída pelo projeto: durante a criação de
um prefixo novo, o runtime usa o verbo `steam` do winetricks para obter a Steam
diretamente da Valve.

O produto não copia a Steam nativa do macOS, não distribui jogos, não copia a
pasta `steamapps` durante uma atualização, não tenta contornar DRM/anti-cheat e
não captura senha, cookie, token, Steam ID ou conteúdo de janela.

### Estado operacional registrado em 20/08/2026

- `main` estava sincronizada com `origin/main` no commit `2ee0dc1` quando esta
  documentação foi escrita.
- A execução [`Build Portside Runtime`](https://github.com/andre-fig/portside/actions/runs/32325605325)
  terminou com sucesso em production: runtime `0.1.6`, build ID
  `32325605325-1`, manifesto assinado e evidência replicada nos buckets
  primário e secundário.
- A API Railway respondia em `/health`; os buckets eram privados e o acesso
  anônimo direto ao objeto do manifesto retornava `403`.
- A publicação de runtime não substitui a aceitação visual em um Mac
  self-hosted, a publicação do manifesto no backend, a notarização de uma
  release de cliente ou a promoção para production. A rota de download
  assinada para os artefatos de runtime já existe, mas o manifesto ainda
  precisa ser publicado para o cliente conseguir descobrir a versão.

Esse bloco é um retrato de operação, não um valor permanente: após mudanças de
infraestrutura ou release, atualize a data e a evidência correspondente.

## 2. Primeiros minutos no repositório

### Pré-requisitos

O caminho suportado para o desktop/runtime é um Mac Apple silicon com macOS
13 ou mais recente e Xcode/Swift compatíveis com `swift-tools-version: 6.0`.
Para as demais áreas, use:

- Node.js 22 para o backend e os workflows que executam checks Node;
- npm com `apps/backend/package-lock.json` através de `npm ci`;
- Bun 1.2.21 para a landing, conforme `build-landing.yml`;
- Homebrew e as dependências listadas em `upstream/dependencies.json` para
  compilar o Wine;
- Railway CLI apenas para operações autorizadas de infraestrutura;
- `gh` é opcional, mas ajuda a acompanhar PRs, checks e execuções.

Não é necessário instalar o Creator, copiar o launcher upstream ou manter um
checkout separado do antigo repositório da landing para desenvolver o
monorepo.

### Verificação inicial

```sh
git rev-parse --show-toplevel
git status --short --branch
git remote -v

swift test --package-path apps/desktop
```

Se a árvore já tiver mudanças, não as descarte: identifique o escopo antes de
editar. O `README.md` apresenta o resumo; `AGENTS.md` contém as regras que
devem ser seguidas por agentes e contribuidores.

### Rodar cada produto localmente

Desktop em modo de desenvolvimento/teste:

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh
open build/Portside.app
```

O `package_app.sh` cria um bundle de validação com assinatura ad hoc. Isso é
útil para desenvolvimento local, mas não substitui Developer ID, notarização,
stapling ou a release comercial.

Backend:

```sh
cd apps/backend
cp .env.example .env # preencha localmente; nunca versione o arquivo
npm ci
npm run prisma:validate
npm run prisma:migrate:deploy # somente contra um banco local/descartável autorizado
npm run dev
```

Os serviços do backend têm entradas separadas:

- `src/main.ts`: API HTTP;
- `src/worker.ts`: worker de sincronização/reconciliação;
- `src/cron.ts`: tarefas agendadas.

Landing:

```sh
cd apps/landing
bun install --frozen-lockfile
bun run dev
```

O build da landing não busca código no repositório antigo
`portside-games-on-mac`; o código está dentro de `apps/landing`.

## 3. Mapa do monorepo

```text
apps/
  desktop/          app macOS, agente, core Swift e testes
  backend/          API NestJS, Prisma, worker, cron e testes Vitest
  landing/          landing page e fluxo comercial
  runtime-host/     host nativo colocado dentro do wrapper
runtime/
  wrapper-template/ template próprio do PortsideBaseline.app
vendor/             snapshots de fontes upstream sem diretórios .git
upstream/           lockfiles, toolchain, licenças e patches
scripts/            build, validação, sincronização, release e publicação
.github/workflows/  CI, builds, sincronização, deploy e release
docs/               documentação técnica e runbooks
```

### Desktop

`apps/desktop` é um Swift Package com:

- produto `Portside`: interface SwiftUI e ciclo de vida do app;
- produto `PortsideAgent`: processo auxiliar do wrapper;
- biblioteca `PortsideCore`: caminhos locais, manifesto, downloads,
  verificação, rollback, compatibilidade, Steam flow e diagnósticos;
- `Tests/PortsideCoreTests`: testes unitários do núcleo.

As dependências Swift estão declaradas em `Package.swift` e fixadas em
`Package.resolved`: Sparkle para atualizações do app e Sentry para diagnósticos
sanitizados. Não adicione dependências sem avaliar tamanho, licença, origem e
efeito no bundle/notarização.

### Backend

`apps/backend/src` usa módulos NestJS. `core` carrega configuração, `common`
concentra guards/sanitização, `database` integra Prisma e `modules` separa
health, artifacts, licenses, runtime, admin e synchronization. DTOs ficam em
`dtos/`, serviços em arquivos próprios e specs `*.spec.ts` ficam junto do
código. O schema e as migrations estão em `prisma/`.

O backend diferencia fonte, build, artefato, release, canal, promoção e
rollback. Um arquivo com SHA correto não entra em production sem build,
validação e promoção registradas.

### Landing

`apps/landing/src/routes` contém as rotas públicas; `src/components/site`
contém layout/logo; `src/components/ui` contém componentes reutilizáveis;
`src/lib` concentra checkout, preço, pedidos e utilitários de servidor.
Credenciais da Stripe e segredos de servidor só entram por ambiente.

### Runtime e vendor

`runtime/wrapper-template` define o wrapper `PortsideBaseline.app`, seu
`Info.plist` e `portside-runtime.json`. O wrapper usa WineD3D, MSYNC/ESYNC
habilitados e D3DMetal, DXMT e DXVK desabilitados no baseline.

`vendor/wine` é a fonte compilada para o engine; `vendor/winetricks` é a
fonte/verb empacotada; snapshots de wrapper, engines, Sikarugir e FOSS são
mantidos para proveniência, auditoria e licença. `upstream/lock.json` registra
commit completo, licença, checksum, submódulos/LFS e data. Não existem
submódulos Git aninhados no snapshot versionado.

## 4. Fluxo de dados e de uma atualização

```text
upstreams autorizados
        ↓ sync-upstreams.yml
vendor/ + upstream/lock.json
        ↓ PR revisada e merge em main
Build Portside Engine (somente quando Wine/toolchain muda)
        ↓ engine imutável + metadata/checksum nos buckets Portside
Build Portside Runtime (wrapper/winetricks + engine aprovado)
        ↓ checksums, proveniência, SBOM e manifesto assinado
Railway object storage: production primário + réplica
        ↓ validação limpa/GUI e promoção explícita
API Portside → manifesto compatível
        ↓ assinatura, host allowlist, SHA-256 e tamanho
PortsideCore → cache → instalação atômica → wrapper ativo
        ↓
Steam instalada pela Valve no prefixo do usuário
```

O app mantém a versão válida anterior até que o novo wrapper passe pelas
validações. Em modo offline, usa o runtime instalado e verificado; não troca
uma instalação funcional por um download inválido. Rollback atua sobre runtime,
manifesto/appcast e release, nunca sobre `SteamLibrary`, saves ou dados de
conta.

Há dois canais de atualização diferentes:

- Sparkle atualiza o `Portside.app` pelo `appcast.xml` assinado;
- o pipeline de runtime atualiza wrapper/engine/winetricks pelo manifesto
  Ed25519 assinado.

Não confunda uma atualização do app com uma atualização do runtime.

## 5. Workflows do GitHub Actions

| Workflow | Quando roda | Resultado | O que ainda é manual |
| --- | --- | --- | --- |
| `ci.yml` / CI | push e PR para `main` | política de produção, Prisma e build do backend | corrigir/revisar e mergear |
| `build-desktop.yml` | CI concluído com sucesso na `main` ou dispatch | ZIP, DMG e dSYM unsigned de validação | abrir/inspecionar localmente se necessário |
| `build-landing.yml` | mudanças na landing, PR, push ou dispatch | `.output` e artifact de build | deploy público do provedor |
| `build-engine.yml` | mudança real em Wine, patches, toolchain ou dispatch | engine Wine persistente, metadata, checksum e proveniência nos dois buckets | validar a build e a compatibilidade |
| `build-runtime.yml` | mudança real em wrapper/winetricks/montagem ou após engine aprovado | runtime próprio, manifesto assinado, evidência e publicação production | validar GUI e registrar |
| `sync-upstreams.yml` | diariamente às 03:17 UTC ou dispatch | PR com novos snapshots/lock/checksums | revisar licença/diff e mergear |
| `validate-clean-install.yml` | dispatch | instalação limpa e logs de aceitação em Mac self-hosted | sessão gráfica, login e janela real |
| `deploy-railway.yml` / Verify Railway | CI concluído na `main` | healthcheck da API | investigar se `/health` falhar |
| `release-production.yml` | dispatch | release app/runtime production, assinatura/notarização e registro no backend | configurar secrets |

### CI e desktop

Um push/PR em `main` começa por `CI`. O job de produção impede que URLs diretas
do Sikarugir ou artefatos compilados indevidos sejam usados pelo caminho de
produção. O backend roda em Ubuntu com Node 22, valida o schema Prisma e faz o
build de produção usando um `DATABASE_URL` local de validação. Lint, typecheck
e testes ficam no `pre-push` para evitar repetir a mesma bateria no GitHub a
cada push.

Depois de CI bem-sucedido em `main`, `Build Desktop Validation` compila o app
testado, cria `Portside-validation.app.zip`, `Portside-validation.dmg`, dSYM e
checksums por 14 dias. Esses arquivos são apenas para validação e podem gerar
avisos do macOS.

### ESLint e tipagem

Backend e landing usam ESLint flat config com regras tipadas do
`typescript-eslint`. O lint falha com qualquer warning (`--max-warnings 0`) e
verifica, entre outras regras, imports de tipo, variáveis não utilizadas,
`any` explícito, comparações estritas, blocos condicionais, imports duplicados,
uso de `const`, promessas não aguardadas e APIs assíncronas mal conectadas.

O backend usa `strictTypeChecked` sobre `src/**/*.ts`, além do
`tsc --noEmit`. A landing usa `recommendedTypeChecked`, `tsc --noEmit` e as
regras de hooks do React. O arquivo gerado `src/routeTree.gen.ts` fica fora do
ESLint, e o adaptador compartilhado de Recharts possui apenas uma exceção
local para a API `any` fornecida pela dependência; o restante do código não
recebe essa exceção.

Comandos locais:

```sh
(cd apps/backend && npm run lint && npm run typecheck)
(cd apps/landing && bun run lint && bun run typecheck)
```

O `pre-push` executa esses checks quando a área correspondente foi alterada.
Os workflows mantêm apenas validação de workflow, política, build de produção
e geração de artifacts necessária no GitHub.

### Runtime

`Build Portside Engine` começa com um preflight em Ubuntu. Somente quando há
mudança real em `vendor/wine`, patches, toolchain ou no commit Wine do lockfile
o job `macos-15` compila o engine, gera metadata/checksum/proveniência e publica
uma versão imutável nos dois buckets. O cache por snapshot, arquitetura, flags
e toolchain acelera recompilações, mas o bucket é a fonte durável usada por
montagens futuras.

`Build Portside Runtime` também começa com preflight em Ubuntu. O job macOS
compila apenas wrapper e winetricks; `fetch-engine.sh` baixa o engine aprovado
correspondente ao commit do lockfile e verifica metadata, SHA-256 e tamanho.
Quando uma mudança de Wine é mergeada, o workflow aguarda a conclusão bem-
sucedida de `Build Portside Engine` e então monta o runtime automaticamente.
Execuções concorrentes são canceladas para não manter dois macOS pagos
trabalhando no mesmo branch. A versão automática continua sendo
`0.1.<run_number>`.

O artifact de runtime contém arquivos necessários para auditoria, incluindo:

- archives do wrapper, engine e winetricks;
- `engine-input.json`, identificando o engine persistente consumido;
- `runtime-manifest.json` assinado;
- `provenance.json` com commit Portside, commits fonte, build ID e toolchain;
- SBOM, checksums e evidência de validação.

O workflow de engine compila somente `vendor/wine`; o workflow de runtime não
recompila Wine e falha se não encontrar o engine persistente correspondente.
Nenhum workflow publica a Steam: ela continua sendo obtida da Valve durante a
instalação do usuário.

### Como consultar a versão atual

A versão do runtime não deve ser deduzida pelo commit ou pelo valor padrão do
`Info.plist`. Para consultar a versão validada:

1. Abra o workflow [`Build Portside Runtime`](https://github.com/andre-fig/portside/actions/workflows/build-runtime.yml).
2. Abra a execução mais recente com status verde.
3. Role até a seção `Artifacts`.
4. Leia a versão no nome do artefato, por exemplo
   `portside-runtime-production-0.1.6`.

O último runtime confirmado no registro operacional desta documentação é o
`0.1.6`. A execução seguinte usa a versão automática `0.1.<run_number>`; por
isso, a execução número 7 está configurada para produzir `0.1.7`, mas essa
versão só deve ser considerada existente se a execução terminar com sucesso e
o artefato aparecer no GitHub Actions.

A versão comercial do app é separada: não existe uma versão comercial atual
enquanto não houver uma release notarizada e promovida. O workflow
`release-production.yml` usa automaticamente a versão do runtime validado
selecionado para o app, o DMG e o ZIP. O `0.1.0` presente no `Info.plist` é
apenas o valor padrão de desenvolvimento e não representa a última versão
publicada.

### Sincronização upstream

O cron cria clones temporários rasos, usa filtro de blobs para Wine quando
necessário, resolve submódulos/LFS declarados, preserva notices, calcula
checksums e compara o lockfile. Se houver alteração, abre uma branch e PR.
Se o upstream falhar ou desaparecer, o script falha antes de substituir o
snapshot existente. O merge da PR é a autorização para receber a mudança; ele
não publica automaticamente uma release de usuário, embora mudanças em
`vendor/` possam disparar a build de runtime no canal de validação depois do
merge.

### Release do app

`release-production.yml` é manual e sempre publica em `production`. Ele seleciona o último runtime
validado com sucesso, usa a
versão do manifesto desse runtime para o app e escolhe o artifact
correspondente. O estágio:

1. testa Swift e backend;
2. valida a política de fontes;
3. baixa e valida o runtime já construído;
4. compila o app configurado;
5. assina app, agente, Sparkle e manifesto;
6. notariza e faz staple no app/ZIP/DMG;
7. valida o bundle;
8. gera appcast assinado;
9. publica production nos dois buckets.

O job de publicação usa o Environment GitHub protegido `production`. A
aprovação desse Environment continua sendo obrigatória; uma build verde não
publica produção sem essa proteção.

## 6. Railway e secrets

O Railway tem API, worker, cron, PostgreSQL e dois buckets S3-compatible. A API
pública atualmente usada pelo workflow de health é:

```text
https://api-production-6d06.up.railway.app
```

O filesystem dos serviços Railway é efêmero. Runtime, appcast, ZIP/DMG,
manifestos, SBOM e backups precisam ficar no storage de objetos primário e na
réplica. O backend e os workflows devem usar credenciais separadas para cada
bucket.

O GitHub Environment `production` contém, sem expor valores no repositório, o
prefixo de URL, key ID/chave do manifesto, nomes dos buckets e credenciais S3
primária/secundária. A chave privada usada para assinar manifestos fica apenas
no CI/secret manager; a API recebe a chave pública para verificação.

### Acesso aos buckets privados

Os buckets Railway continuam privados. Os manifestos novos devem apontar para
`/v1/runtime/artifacts/production/<fileName>` na API Portside. O backend valida
o canal e o nome do archive, cria uma URL S3 temporária para
`runtime/production/<fileName>` no bucket primário e responde com redirect; as
credenciais do bucket nunca chegam ao desktop.

O desktop precisa ter na allowlist o host da API e o host de storage usado pelo
redirect, mas continua verificando assinatura do manifesto, HTTPS, tamanho e
SHA-256 após o download. A rota resolve o `403` do acesso direto ao bucket; a
API ainda precisa ter um manifesto de produção publicado e a
instalação limpa precisa ser validada antes do rollout. O detalhe operacional
está em [`RAILWAY_DEPLOYMENT.md`](RAILWAY_DEPLOYMENT.md).

Nunca documente ou comite valores de `PORTSIDE_*_SECRET_*`, chaves privadas,
tokens GitHub/Railway, credenciais Stripe, certificados ou perfis de
notarização.

## 7. Upstream, fontes e licenças

O Portside mantém snapshots em `vendor/` sem `.git` aninhado. A fonte de
verdade é `upstream/lock.json`; `UPSTREAM_VERSIONS.json` permanece como ponte
de compatibilidade. A atualização normal é:

1. executar ou aguardar `Sync Upstreams`;
2. revisar a PR criada, commits, diff, licenças, notices, submódulos/LFS,
   exclusões e checksums;
3. confirmar que não entraram caches, releases, arquivos compilados,
   symlinks perigosos ou dados temporários;
4. revisar e mergear a PR;
5. acompanhar CI e `Build Portside Runtime` em production;
6. executar a aceitação limpa/GUI antes de qualquer promoção.

Se o repositório upstream desaparecer, os snapshots já versionados continuam
disponíveis para manutenção e build conforme suas licenças. A sincronização
futura falhará de forma preservadora, sem apagar o estado existente.

O Creator e o launcher não integram o produto: o Creator é mantido como
proveniência quando aplicável e não é copiado para o bundle Portside. Não
espelhamos nem redistribuímos o instalador da Steam. Consulte
`RUNTIME_LICENSES.md`, `THIRD_PARTY_NOTICES.md`, `docs/THIRD_PARTY_LICENSES.md`
e `SIKARUGIR_AUTHORIZATION.md` antes de publicar.

## 8. Scripts mais importantes

| Script | Uso |
| --- | --- |
| `scripts/package_app.sh` | bundle local ad hoc para validação |
| `scripts/build_release.sh` | bundle configurado para release |
| `scripts/sign_release.sh` | codesign e geração de proveniência/manifesto assinado |
| `scripts/notarize_release.sh` | notarytool, staple e validação Apple |
| `scripts/validate_release_bundle.sh` | validação final de plist/assinatura/DMG |
| `scripts/generate_appcast.sh` | appcast Sparkle assinado |
| `scripts/publish_release.sh` | publicação de app/runtime em dois buckets |
| `scripts/build-runtime/build.sh` | orquestra build e checks do runtime |
| `scripts/build-runtime/build-wrapper.sh` | compila host e monta wrapper |
| `scripts/build-runtime/build-wine-engine.sh` | compila Wine local de `vendor/wine` |
| `scripts/build-runtime/build-winetricks.sh` | empacota winetricks vendorizado |
| `scripts/generate_manifest.sh` | assina manifesto Ed25519 |
| `scripts/validate-clean-install.sh` | aceitação assistida em prefixo descartável |
| `scripts/validate-production-policy.sh` | bloqueia dependências upstream no release |
| `scripts/upstream/sync.sh` | sincroniza snapshots autorizados |
| `scripts/upstream/validate_snapshot.sh` | valida layout, symlinks e exclusões |
| `scripts/install-git-hooks.sh` | habilita os hooks locais de pre-commit/pre-push |

Use [`PROJECT_GUIDE.md`](PROJECT_GUIDE.md) para o catálogo completo e os
parâmetros esperados por cada script. Leia o script antes de alterar suas
variáveis: vários comandos usam diretórios temporários, chaves externas e
contratos de manifesto.

### Checks locais antes do push

Após clonar o repositório, habilite os hooks com:

```sh
./scripts/install-git-hooks.sh
```

O `pre-commit` faz apenas verificações rápidas nos arquivos staged. O
`pre-push` detecta as áreas alteradas e executa os testes locais relevantes,
sem reconstruir o Wine ou publicar artefatos. Esses hooks não substituem o CI:
eles são uma camada de feedback local e podem ser ignorados, enquanto o GitHub
continua sendo a autoridade para proteger a `main`.

## 9. Como criar um DMG

### Validação local

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
./scripts/package_app.sh

ditto -c -k --sequesterRsrc --keepParent \
  build/Portside.app build/Portside-validation.app.zip
./scripts/create_dmg.sh build/Portside.app build/Portside-validation.dmg Portside
shasum -a 256 build/Portside-validation.app.zip build/Portside-validation.dmg
```

O DMG contém somente `Portside.app`. A configuração pode ser concluída pela
própria janela do Portside mesmo quando ele for aberto diretamente do DMG; o
app não bloqueia esse fluxo nem exige uma segunda abertura.

Esse DMG não é para clientes.

### Release distribuível

Use `release-production.yml` ou o conjunto de scripts com Developer ID,
Sparkle, manifesto e Team API Key do App Store Connect configurados fora do
Git. A sequência
é `build_release.sh` → `sign_release.sh` → `notarize_release.sh` →
`validate_release_bundle.sh` → `generate_appcast.sh` → `publish_release.sh`.

Uma release só pode ser anunciada como distribuível quando a evidência mostra
assinatura de todos os componentes, notarização e ticket stapled no `.app` e no
`.dmg`. Um DMG de CI de validação não atende esse critério.

## 10. Testes e aceitação real

Checks automatizados não substituem a sessão gráfica. Para um runtime novo,
selecione no dispatch de `Validate Clean Portside Runtime` o run/artifact e a
versão corretos. O Mac self-hosted precisa estar com:

- sessão gráfica do usuário de execução aberta;
- Accessibility habilitado para o runner;
- Rosetta 2 disponível quando necessário;
- nenhum wrapper/prefixo Portside antigo sendo reutilizado;
- área descartável e logs separados.

A aceitação deve registrar, sem dados sensíveis:

1. criação do prefixo novo;
2. instalação pelo verbo upstream-local `steam`;
3. término do updater inicial;
4. encerramento da primeira execução;
5. segunda abertura limpa;
6. ícone no Dock e janela real renderizada;
7. login visível e campos interativos;
8. `steamwebhelper` funcional;
9. Steam permanecendo aberta após o updater;
10. estado MSYNC/ESYNC, caminho/argumentos e sequência de processos.

Se a GUI não puder ser observada, o resultado é “não validado”, nunca
“sucesso”. Preserve logs sanitizados e indique o estágio exato da falha.

## 11. Diagnóstico operacional

Com GitHub CLI:

```sh
gh run list --limit 20
gh run view <run-id> --log-failed
gh pr checks <pr-number>
```

Para a API Railway:

```sh
curl --fail --show-error https://api-production-6d06.up.railway.app/health
curl --fail --show-error https://api-production-6d06.up.railway.app/ready
```

Para problemas de runtime, comece por:

1. `scripts/validate-production-policy.sh` e o diff do commit;
2. origem/commit/checksum em `upstream/lock.json`;
3. toolchain e arquitetura registradas em `provenance.json`;
4. assinatura do manifesto e SHA-256 dos três componentes;
5. presença em ambos os buckets e canal correto;
6. allowlist de hosts e acesso privado/público ao objeto;
7. cache, diretório temporário e rollback no desktop;
8. somente então processos da Steam e evidência visual.

Não “corrija” um erro de download adicionando uma URL upstream escondida. Não
mate processos globais pelo nome `steam`; use apenas o wrapper/prefixo Portside
gerenciado para não afetar a Steam nativa ou outro usuário.

## 12. Checklist para uma mudança

- [ ] Li `AGENTS.md` e confirmei o escopo da mudança.
- [ ] Preservei mudanças locais e não incluí saídas/segredos.
- [ ] Atualizei testes, docs, notices ou migrations quando necessário.
- [ ] Rodei os checks da área afetada.
- [ ] Rodei `validate-production-policy.sh` para mudanças de runtime/release.
- [ ] Para upstream, atualizei lock, checksum, licença e provenance sem editar
      `vendor/` manualmente.
- [ ] Para artefato, confirmei SHA-256, tamanho, build ID, canal, assinatura e
      origem.
- [ ] Para release, mantive validação, publicação production e rollback como etapas distintas.
- [ ] Documentei qualquer bloqueio ou validação manual pendente.
- [ ] Só fiz commit/push/merge quando isso foi explicitamente solicitado.

## 13. Documentação de referência

- [`README.md`](../README.md): visão geral e comandos rápidos.
- [`ARCHITECTURE.md`](../ARCHITECTURE.md): limites do runtime, baseline e
  diagnóstico.
- [`PROJECT_GUIDE.md`](PROJECT_GUIDE.md): mapa detalhado, scripts e runbooks.
- [`BACKEND.md`](BACKEND.md): API, módulos e modelo comercial.
- [`RAILWAY_DEPLOYMENT.md`](RAILWAY_DEPLOYMENT.md): serviços, buckets e
  configuração de ambiente.
- [`RUNTIME_BUILD.md`](RUNTIME_BUILD.md): build e publicação do runtime.
- [`UPSTREAM_MIRRORING.md`](UPSTREAM_MIRRORING.md): sincronização de fontes.
- [`VALIDATION.md`](VALIDATION.md): aceitação funcional e GUI.
- [`AUTOMATIC_UPDATES.md`](AUTOMATIC_UPDATES.md): Sparkle, manifesto e
  atualização offline.
- [`ROLLBACK.md`](ROLLBACK.md): rollback de app/runtime e preservação de dados.
- [`ARTIFACT_SECURITY.md`](ARTIFACT_SECURITY.md): assinatura, checksums,
  provenance e hosts.
- [`RUNTIME_LICENSES.md`](../RUNTIME_LICENSES.md) e
  [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md): obrigações legais.
