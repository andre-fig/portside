# Instruções para agentes e contribuidores

Estas regras valem para todo o repositório `portside`. Antes de alterar um
subdiretório, procure por um `AGENTS.md` mais específico; arquivos dentro de
`.build/` são checkouts gerados de dependências e não fazem parte do código do
Portside.

## Antes de começar

- Confirme a raiz do repositório com `git rev-parse --show-toplevel`.
- Registre `git status --short --branch` e preserve mudanças locais que já
  existirem. Não use `git reset --hard`, `git checkout --` ou comandos
  destrutivos para “limpar” a árvore.
- Não apague, substitua ou reutilize dados do usuário, prefixos, bibliotecas
  Steam, runtimes instalados ou credenciais locais.
- Leia [`docs/DEVELOPER_GUIDE.md`](docs/DEVELOPER_GUIDE.md) para o fluxo de
  desenvolvimento e [`docs/PROJECT_GUIDE.md`](docs/PROJECT_GUIDE.md) para o
  catálogo de scripts e runbooks.
- Não faça commit, push, merge ou publicação externa sem solicitação explícita
  nesta tarefa.

## Limites do produto

- O Portside é um app macOS nativo que prepara um wrapper privado e local para
  abrir a Steam oficial. Não distribui a Steam, jogos, saves ou mecanismos de
  bypass de DRM/anti-cheat.
- A Steam é instalada pelo verbo `steam` do winetricks durante a preparação do
  prefixo e continua sendo obtida diretamente da Valve. Nunca copie a sessão
  Steam nativa do macOS para um prefixo Portside.
- O runtime de produção deve vir de artefatos Portside, descritos por
  manifesto assinado. Não adicione fallback silencioso para
  `github.com/Sikarugir-App` ou `raw.githubusercontent.com/Sikarugir-App`.
- Os snapshots em `vendor/` são fontes auditadas. Não edite manualmente um
  snapshot para corrigir uma build; altere o processo de sincronização ou
  mantenha um patch documentado em `upstream/patches/`.
- Não declare que a Steam abriu ou que uma UI funciona apenas por existir
  `steam.exe`, `steamwebhelper`, um processo ou um ícone no Dock. A aceitação
  exige uma janela real renderizada e confirmação de interação em uma sessão
  gráfica; veja [`docs/VALIDATION.md`](docs/VALIDATION.md).

## Organização e estilo

- Desktop: mantenha lógica reutilizável em `apps/desktop/Sources/PortsideCore`;
  a camada SwiftUI em `Sources/Portside` deve orquestrar a interface, não
  duplicar pipeline de runtime.
- Backend: siga a organização NestJS existente em
  `apps/backend/src/modules`. Use DTOs em `dtos/`, serviços em arquivos
  próprios, controllers finos e testes unitários `*.spec.ts` ao lado do código
  testado. Mudanças no banco exigem migration Prisma correspondente.
- Landing: mantenha componentes e rotas dentro de `apps/landing`; não
  reintroduza dependência de build no repositório antigo da landing.
- Shell: use `set -eu` ou equivalente, valide entradas e caminhos, prefira
  caminhos temporários estreitos e nunca imprima secrets, tokens, cookies,
  chaves privadas ou conteúdo de conta.
- Manifestos, checksums e proveniência são parte do contrato de segurança. Não
  remova validações para fazer uma build passar.

## Validação por área

Execute o conjunto mínimo relacionado à alteração:

```sh
# desktop
swift test --package-path apps/desktop
swift build --package-path apps/desktop

# backend
cd apps/backend
npm ci
npm run prisma:validate
npm run typecheck
npm run lint
npm test
npm run build
cd ../..

# landing
cd apps/landing
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run build
cd ../..

# política de produção e formatação
./scripts/validate-production-policy.sh
git diff --check
```

Para alterações no runtime, também execute no macOS com a toolchain de
`upstream/dependencies.json`:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 \
PORTSIDE_RUNTIME_CHANNEL=production \
PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX=https://api.example.invalid/v1/runtime/artifacts/production/ \
./scripts/build-runtime/build.sh
```

Uma build local gera evidência unsigned. Ela não prova assinatura, publicação,
download pelo desktop ou funcionamento visual da Steam.

### Hooks locais

Depois de clonar, habilite os hooks versionados uma vez:

```sh
./scripts/install-git-hooks.sh
```

O `pre-commit` executa somente verificações rápidas dos arquivos staged:
diff whitespace, sintaxe shell, JSON e `actionlint` quando instalado. O
`pre-push` identifica as áreas alteradas e executa lint, typecheck, testes e
build locais correspondentes: Swift, backend, landing, política de produção e
validações de scripts. O CI mantém somente validações de integração, política
de produção e builds necessários para a infraestrutura do GitHub. Hooks podem
ser ignorados em uma emergência, mas a rotina normal deve passar por eles
antes do push.

## Workflows e autoridade de cada um

- `CI`: valida política de fontes, schema Prisma e build do backend em push/PR
  para `main`.
- `Build Desktop Validation`: depois de um CI bem-sucedido, cria app, ZIP,
  DMG e dSYM de validação; não é release comercial e não é notarizado.
- `Build Landing`: gera o build da landing em PR, push relevante ou execução
  manual e armazena `.output` como artifact.
- `Build Portside Runtime`: em mudanças de fontes/runtime na `main` ou
  manualmente, compila wrapper, Wine e winetricks a partir de `vendor`, assina
  o manifesto e publica somente no canal de validação, replicando nos dois
  buckets configurados. O Wine usa cache por snapshot e toolchain.
- `Sync Upstreams`: roda diariamente às 03:17 UTC ou manualmente, atualiza
  snapshots autorizados e abre PR. Nunca faz merge, promoção ou publicação.
- `Validate Clean Portside Runtime`: execução manual em Mac self-hosted com
  sessão gráfica real. Instala em área descartável, usa o artefato selecionado
  e coleta logs sanitizados; exige revisão manual da janela/login.
- `Verify Railway`: após CI na `main`, aguarda `GET /health` da API pública.
  É uma verificação de saúde, não uma validação de release de cliente.
- `Release Portside`: execução manual. O job de validação testa, reutiliza o
  último runtime validado, assina, notariza e publica; o job production só
  aparece quando `promote=true` e usa Environment protegido.

O workflow é uma automação, não uma autorização. A promoção para production,
a aceitação visual e a configuração de secrets continuam sendo decisões
explícitas.

## Secrets e infraestrutura

- Secrets ficam em GitHub Environments, Keychain ou secret manager. Nunca os
  grave em `.env` versionado, `Info.plist`, logs, fixtures ou documentação.
- O Railway hospeda API, worker, cron, PostgreSQL e os dois buckets S3
  compatíveis. O runner GitHub precisa receber cópias das credenciais dos
  buckets no Environment `production`; ele não lê variáveis do Railway sozinho.
- A chave privada do manifesto permanece no CI/secret manager. O backend recebe
  apenas a chave pública. O mesmo princípio vale para Sparkle, Developer ID,
  notarização, Stripe e token administrativo.
- Os buckets de runtime atualmente são privados. A publicação dual e a
  assinatura já estão operacionais em production, mas o desktop ainda precisa de
  uma rota Portside que entregue URL temporária assinada (ou de uma política
  pública deliberadamente revisada) antes de um rollout para usuários.

## Pull requests e releases

Antes de abrir uma PR:

1. confira `git diff` e `git diff --check`;
2. confirme que não há `node_modules`, `.build`, `build`, DMG, chaves ou dados
   de usuário no diff;
3. rode os checks da área alterada e registre limitações reais;
4. para upstream, confira commit completo, checksum, licença e notices no
   `upstream/lock.json`;
5. para runtime, confirme manifest, SHA-256, tamanho, proveniência, SBOM,
   build ID, canal e resultado dos testes;
6. para produção, preserve aceitação gráfica e rollback planejado; não há um
   ambiente intermediário.

Não faça afirmações de “notarizado”, “compatível” ou “UI funcional” sem o
comando/evidência correspondente. Consulte
[`docs/DEVELOPER_GUIDE.md`](docs/DEVELOPER_GUIDE.md) para o procedimento
completo.
