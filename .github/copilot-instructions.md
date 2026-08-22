# Instruções para o GitHub Copilot

Antes de editar qualquer arquivo, leia [`AGENTS.md`](../AGENTS.md),
[`docs/DEVELOPER_GUIDE.md`](../docs/DEVELOPER_GUIDE.md) e a documentação
específica da área alterada. Preserve mudanças locais existentes e não use
comandos destrutivos para limpar a árvore.

## Produto e limites

- Portside é um aplicativo macOS nativo que prepara um runtime isolado para a
  Steam oficial.
- A Steam é obtida diretamente da Valve pelo verbo `steam` do winetricks. Não
  copie a Steam nativa do macOS, jogos, saves, cookies, tokens ou dados da
  conta.
- Não implemente bypass de DRM ou anti-cheat.
- Não declare que uma interface funciona apenas porque existe um processo,
  `steamwebhelper` ou ícone no Dock. Sucesso exige uma janela real renderizada
  e interação confirmada em sessão gráfica.
- Mensagens exibidas ao usuário devem ser comerciais, claras e não técnicas.

## Organização do monorepo

- `apps/desktop`: cliente macOS em Swift Package; mantenha lógica reutilizável
  em `Sources/PortsideCore` e testes `*.swift` em `Tests/`.
- `apps/backend`: API NestJS, Prisma, worker e cron. Use módulos, controllers
  finos, services próprios, DTOs em `dtos/` e specs `*.spec.ts` junto do código.
- `apps/landing`: landing e fluxo comercial; não dependa do repositório antigo
  da landing.
- `apps/runtime-host`: host nativo compilado dentro do wrapper.
- `runtime/wrapper-template`: template do `PortsideBaseline.app`.
- `vendor`: snapshots de fontes auditadas, sem `.git` aninhado e sem artefatos
  compilados.
- `upstream`: lockfiles, dependências, licenças, notices e patches.
- `scripts`: automação de build, validação, publicação e release.

## Runtime

O runtime tem dois fluxos independentes:

1. `Build Portside Engine` compila `vendor/wine` no macOS somente quando Wine,
   patches, toolchain ou o commit Wine do lockfile mudam. Publica nos dois
   buckets privados um engine imutável com commit, snapshot checksum, SHA-256,
   tamanho, build ID e proveniência.
2. `Build Portside Runtime` compila wrapper e winetricks, baixa o engine
   aprovado correspondente ao lockfile e verifica metadata, SHA-256, tamanho e
   layout antes de montar o runtime.

O runtime nunca deve:

- compilar Wine novamente durante uma montagem comum;
- baixar binários do Sikarugir ou de `raw.githubusercontent.com`;
- usar fallback externo oculto;
- aceitar um engine local sem metadata e checksum correspondentes;
- publicar em canal intermediário inexistente; o ambiente operacional é
  `production`.

O desktop baixa apenas pela rota assinada da API Portside, valida assinatura,
host, SHA-256 e tamanho, instala atomicamente e preserva rollback/offline.
Não coloque artefatos de runtime dentro do `Portside.app` nem no repositório.

## Segurança e dados

- Nunca versione secrets, certificados, chaves privadas, `.env`, tokens ou
  dados de usuários.
- Não imprima secrets em logs, fixtures, erros ou documentação.
- Valide caminhos, rejeite path traversal e symlinks perigosos ao extrair
  archives.
- Preserve licenças, copyright, notices, SBOM e proveniência dos componentes.
- Alterações de banco exigem migration Prisma correspondente.
- Não remova dados de usuário, prefixos, bibliotecas Steam ou runtimes
  instalados.

## Workflows e custos

- `ci.yml` mantém somente política de fontes, validação Prisma e build do
  backend.
- Lint, typecheck e testes ficam nos hooks locais `pre-push` para evitar
  repetir a bateria no GitHub.
- `Build Desktop Validation` deve usar macOS somente quando houver mudança no
  desktop, empacotamento ou recursos relevantes.
- Workflows devem usar `concurrency` quando execuções antigas puderem ser
  canceladas com segurança.
- Validações baratas e determinísticas devem rodar em Ubuntu; builds que
  exigem Swift, Xcode, codesign ou Wine macOS continuam em macOS.
- Não mover compilação do Wine para Railway sem confirmar compatibilidade com
  a toolchain Darwin/Xcode usada pelo script.

## Validação local

Execute os checks da área alterada:

```sh
git diff --check
./scripts/validate-production-policy.sh
for script in scripts/build-runtime/*.sh scripts/upstream/*.sh scripts/generate_manifest.sh scripts/publish_runtime.sh scripts/publish_engine.sh; do sh -n "$script"; done
actionlint .github/workflows/*.yml
```

Para código:

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
(cd apps/backend && npm run prisma:validate && npm run typecheck && npm run lint && npm test && npm run build)
(cd apps/landing && bun run lint && bun run typecheck && bun run build)
```

Não declare assinatura, notarização, publicação, instalação limpa ou Steam
funcional sem evidência real correspondente. Ao finalizar, descreva arquivos
alterados, testes executados e qualquer validação manual ou secret ainda
necessário.
