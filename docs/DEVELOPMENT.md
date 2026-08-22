# Desenvolvimento do Portside

Este é o guia prático para desenvolver, validar e enviar alterações no
monorepo. Para regras permanentes de segurança e escopo, leia também
[`AGENTS.md`](../AGENTS.md), [`copilot-instructions.md`](../.github/copilot-instructions.md)
e [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Pré-requisitos

Instale somente as ferramentas necessárias para a área em que vai trabalhar:

- macOS 13+ e Xcode compatível com Swift tools version 6.0 para desktop e
  runtime;
- Node.js 22 e npm para backend;
- Bun 1.2.21 para landing;
- Homebrew e as dependências de `upstream/dependencies.json` para compilar o
  engine Wine;
- `jq`, `actionlint` e `gh` para validações e operação dos workflows.

O Portside suporta Apple silicon. Rosetta 2 é responsabilidade do instalador
do produto e não deve ser adicionada como dependência de desenvolvimento sem
necessidade.

## Primeiro setup

Na raiz do repositório:

```sh
git rev-parse --show-toplevel
git status --short --branch
./scripts/install-git-hooks.sh
```

Instale as dependências apenas dos aplicativos que serão alterados:

```sh
(cd apps/backend && npm ci)
(cd apps/landing && bun install --frozen-lockfile)
swift package resolve --package-path apps/desktop
```

Não versione `node_modules`, `.build`, arquivos `build/`, `.env`, certificados,
chaves ou dados de usuário.

## Desenvolvimento local

### Desktop macOS

Testes e build do Swift Package:

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
```

Para montar um bundle local ad hoc:

```sh
./scripts/package_app.sh
open build/Portside.app
```

Esse bundle é apenas para desenvolvimento. Ele não substitui assinatura
Developer ID, notarização, stapling ou a release comercial.

### Backend

Crie `.env` local a partir do exemplo e use um PostgreSQL descartável:

```sh
cd apps/backend
cp .env.example .env
npm run prisma:validate
npm run prisma:migrate:deploy
npm run dev
```

Os processos auxiliares podem ser executados separadamente:

```sh
npm exec tsx src/worker.ts
npm exec tsx src/cron.ts
```

Nunca use o banco de produção para migrações locais. Alterações no schema
exigem migration Prisma revisável.

### Landing

```sh
cd apps/landing
bun run dev
```

O build local é:

```sh
bun run lint
bun run typecheck
bun run build
```

A landing é código do monorepo. Não restaure dependência de build no antigo
repositório externo.

## Desenvolvimento do runtime

O runtime tem duas etapas distintas.

### Construir o engine

O engine é compilado no macOS a partir de `vendor/wine`:

```sh
PORTSIDE_ENGINE_BUILD_DIR=build/engine \
./scripts/build-runtime/build-engine.sh
```

Esse comando gera o archive persistente, metadata, checksum e proveniência.
Para publicação nos buckets, use o workflow `Build Portside Engine`; não use
credenciais reais em uma máquina de desenvolvimento sem autorização explícita.

### Montar o runtime

`build.sh` não compila Wine. Ele busca o engine aprovado pelo commit do
lockfile, verifica metadata/SHA-256/tamanho e monta wrapper e winetricks:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 \
PORTSIDE_RUNTIME_CHANNEL=production \
PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX=https://api.example.invalid/v1/runtime/artifacts/production/ \
PORTSIDE_PUBLIC_BUCKET=<bucket> \
PORTSIDE_S3_ACCESS_KEY_ID=<access-key> \
PORTSIDE_S3_SECRET_ACCESS_KEY=<secret> \
PORTSIDE_S3_REGION=<region> \
PORTSIDE_S3_ENDPOINT=<endpoint> \
./scripts/build-runtime/build.sh
```

O comando exige que o engine correspondente já exista no bucket privado. Se
ele não existir, a montagem falha e não usa fallback externo. O build local
gera evidência unsigned; não prova publicação, notarização ou Steam funcional.

Scripts principais:

| Script | Função |
| --- | --- |
| `resolve-engine.sh` | Calcula engine version e storage key pelo lockfile |
| `build-engine.sh` | Compila e descreve o engine persistente |
| `fetch-engine.sh` | Baixa e valida o engine aprovado para uma montagem |
| `build-wrapper.sh` | Compila o host e monta `PortsideBaseline.app` |
| `build-winetricks.sh` | Empacota o winetricks versionado no vendor |
| `build.sh` | Monta os componentes e gera manifesto/SBOM/proveniência |
| `validate-clean-layout.sh` | Verifica o layout dos três archives |
| `validate-manifest.sh` | Verifica canal, componentes, URLs e checksums |

O runtime não distribui a Steam. A instalação no Mac usa o verbo `steam` do
winetricks e mantém o prefixo isolado.

## Hooks e validações

O `pre-commit` é rápido: whitespace, sintaxe shell, JSON e `actionlint` para
workflows. O `pre-push` executa checks direcionados pela área alterada:

- desktop: `swift test`;
- backend: Prisma validate, typecheck, lint, testes e build;
- landing: lint e typecheck;
- runtime/workflows: sintaxe, política de fontes e `actionlint`.

Antes de enviar uma alteração, rode pelo menos:

```sh
git diff --check
./scripts/validate-production-policy.sh
for script in scripts/build-runtime/*.sh scripts/upstream/*.sh scripts/generate_manifest.sh scripts/publish_runtime.sh scripts/publish_engine.sh; do sh -n "$script"; done
actionlint .github/workflows/*.yml
```

Checks completos por área:

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop

(cd apps/backend && npm run prisma:validate && npm run typecheck && npm run lint && npm test && npm run build)

(cd apps/landing && bun run lint && bun run typecheck && bun run build)
```

Não desabilite validações para contornar um erro. Registre a limitação quando
uma validação exigir Mac, sessão gráfica, secret ou infraestrutura externa.

## Workflows

| Workflow | Quando usar | Resultado |
| --- | --- | --- |
| `CI` | push/PR relevante | Política, Prisma e build do backend |
| `Build Portside Engine` | Wine/toolchain/patches ou dispatch | Engine imutável nos buckets, metadata e evidência |
| `Build Portside Runtime` | wrapper/winetricks/montagem ou após engine | Runtime, manifesto assinado e publicação |
| `Build Desktop Validation` | mudanças no desktop/empacotamento | App, ZIP e DMG unsigned para inspeção |
| `Validate Clean Portside Runtime` | validação autorizada | Instalação limpa em Mac self-hosted e logs sanitizados |
| `Release Portside` | release comercial autorizada | Assinatura, notarização, stapling e publicação |

O build de engine é a parte pesada. Uma alteração somente no wrapper ou
winetricks reutiliza o engine aprovado; não deve disparar `make` do Wine. O
workflow de runtime detecta alterações de engine, aguarda o workflow de engine
e só então faz a montagem. Execuções antigas do mesmo branch são canceladas
quando seguro.

Para acompanhar uma execução:

```sh
gh run list --limit 10
gh run watch <RUN_ID> --interval 20 --exit-status
```

Um workflow verde não comprova interface gráfica. A aceitação visual deve
confirmar janela real da Steam, tela renderizada, interação, `steamwebhelper`
funcionando e persistência após a atualização.

## Alterações por área

### Desktop

Mantenha regras de negócio em `PortsideCore`, controllers de interface finos e
testes junto do código. Atualizações devem preservar offline, rollback,
verificação de assinatura, SHA-256, tamanho e allowlist de host.

### Backend

Siga a organização NestJS: controller fino, service responsável pelo caso de
uso, DTO em arquivo separado e spec ao lado do arquivo testado. Não transforme
um checksum correto em aprovação de production sem build, validação e promoção.

### Runtime/upstream

Não edite snapshots manualmente. Atualizações entram por sincronização,
lockfile, licença, checksum e PR revisável. Não importe artefatos compilados
para `vendor` e não crie fallback para repositórios upstream no desktop ou em
workflows de production.

### Interface comercial

Textos da interface devem ser claros, comerciais e compreensíveis para uma
pessoa usuária. Erros técnicos devem ser registrados em diagnóstico/Sentry de
forma sanitizada, não expostos como detalhes de implementação.

## Checklist antes do commit

- [ ] A alteração está no diretório correto e não duplica lógica existente.
- [ ] Não há secrets, dados pessoais, caches ou artefatos compilados no diff.
- [ ] Licenças, notices, manifestos e proveniência foram preservados.
- [ ] Testes e lint da área alterada passaram.
- [ ] Workflows foram validados com `actionlint`.
- [ ] Não há URL direta de upstream no caminho de produção.
- [ ] Mudanças de runtime incluem checksum, tamanho e rollback compatível.
- [ ] Validação manual pendente foi documentada sem declarar sucesso indevido.

## Documentação relacionada

- [`ARCHITECTURE.md`](ARCHITECTURE.md): limites e fluxo do sistema;
- [`DEVELOPER_GUIDE.md`](DEVELOPER_GUIDE.md): mapa detalhado do monorepo;
- [`RUNTIME_BUILD.md`](RUNTIME_BUILD.md): engine, montagem e publicação;
- [`VALIDATION.md`](VALIDATION.md): validação automatizada e gráfica;
- [`AUTOMATIC_UPDATES.md`](AUTOMATIC_UPDATES.md): atualizações e rollback;
- [`RAILWAY_DEPLOYMENT.md`](RAILWAY_DEPLOYMENT.md): API, worker, cron e storage.
