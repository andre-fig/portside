# Contribuindo com o Portside

O Portside é um monorepo com cliente macOS, API, landing e pipeline de
runtime. Antes de começar, leia [`AGENTS.md`](AGENTS.md),
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), [`docs/TESTING.md`](docs/TESTING.md)
e [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Escopo de uma mudança

1. Confirme a raiz e o estado local:

   ```sh
   git rev-parse --show-toplevel
   git status --short --branch
   ```

2. Identifique o aplicativo, módulo, workflow ou script responsável.
3. Preserve alterações locais não relacionadas.
4. Faça a menor mudança coerente com o comportamento desejado.
5. Adicione ou atualize testes e documentação quando o contrato mudar.

Não recrie o produto, não remova funcionalidades existentes e não migre dados
de usuário, prefixos, bibliotecas Steam ou runtimes instalados.

## Ambiente local

Habilite os hooks uma vez:

```sh
./scripts/install-git-hooks.sh
```

Instale dependências somente na área necessária:

```sh
(cd apps/backend && npm ci)
(cd apps/landing && bun install --frozen-lockfile)
swift package resolve --package-path apps/desktop
```

Use banco PostgreSQL local/descartável. Nunca copie secrets de production para
`.env`, fixtures ou documentação.

## Regras de código

### Desktop

- Coloque lógica de negócio em `PortsideCore`.
- Mantenha a interface SwiftUI fina e testável.
- Preserve verificação de manifesto, checksum, tamanho, rollback e modo
  offline.
- Não mate processos que não pertençam ao wrapper/prefixo do Portside.
- Não declare sucesso de Steam sem confirmação visual real.

### Backend

- Use os módulos NestJS existentes.
- Mantenha controllers finos e casos de uso em services.
- Coloque DTOs em `dtos/` e testes unitários `*.spec.ts` junto do código.
- Toda mudança em Prisma deve ter migration revisável.
- Não aprove artefatos somente porque o download e o checksum funcionaram;
  build, fonte, validação e promoção também são obrigatórios.

### Landing

- Preserve acessibilidade, responsividade e linguagem comercial.
- Não coloque secrets no bundle ou em componentes client-side.
- Não adicione dependência do antigo repositório da landing.

### Runtime e upstream

- `vendor/` contém fontes e notices, nunca archives compilados, cache ou `.git`.
- Atualizações upstream entram por lockfile, checksum, licenças, notices e PR.
- `Build Portside Engine` é a única etapa que recompila Wine.
- `Build Portside Runtime` reutiliza somente engine aprovado e validado.
- Não adicione URL direta de upstream ao caminho de production e não crie
  fallback oculto.

## Segurança e privacidade

- Nunca versione chaves, certificados, tokens, cookies, `.env` ou dados de
  conta.
- Não imprima secrets em logs.
- Rejeite path traversal, symlink perigoso e archives inesperados.
- Preserve licenças, copyright, notices, SBOM e proveniência.
- Sentry deve receber somente diagnóstico sanitizado e allow-listed.
- A Steam continua sendo baixada diretamente da Valve; o Portside não
  redistribui o instalador nem jogos.

## Hooks e validação

O `pre-commit` executa checks rápidos. O `pre-push` executa os checks da área
alterada. Antes de abrir uma PR ou enviar para `main`, rode:

```sh
git diff --check
./scripts/validate-production-policy.sh
for script in scripts/build-runtime/*.sh scripts/upstream/*.sh scripts/generate_manifest.sh scripts/publish_runtime.sh scripts/publish_engine.sh; do sh -n "$script"; done
actionlint .github/workflows/*.yml
```

Checks completos:

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
(cd apps/backend && npm run prisma:validate && npm run typecheck && npm run lint && npm test && npm run build)
(cd apps/landing && bun run lint && bun run typecheck && bun run build)
```

Consulte [`docs/TESTING.md`](docs/TESTING.md) para testes negativos, runtime,
instalação limpa e aceitação gráfica.

## Workflows e custo

Antes de alterar um workflow:

- confirme se o job realmente precisa de macOS;
- mova validações determinísticas para Ubuntu ou hooks locais quando seguro;
- restrinja `paths` para evitar execuções desnecessárias;
- use `concurrency` para cancelar execução obsoleta;
- não exponha secrets a código de branches não confiáveis;
- mantenha promoção e publicação protegidas pelo Environment `production`.

O build do engine é pesado. Alterações no wrapper não devem recompilar Wine.
Se uma mudança alterar a seleção do engine, atualize documentação,
proveniência e testes correspondentes.

## Pull requests

Uma PR deve explicar:

- problema e comportamento esperado;
- áreas e arquivos alterados;
- riscos e compatibilidade;
- comandos e workflows executados;
- validação manual ainda pendente;
- secrets ou infraestrutura necessários para concluir.

Checklist mínimo:

- [ ] Não há secrets, dados pessoais, cache ou artefato indevido no diff.
- [ ] Testes, lint, typecheck e build da área alterada passaram.
- [ ] Workflows passaram por `actionlint`.
- [ ] Documentação foi atualizada quando o contrato mudou.
- [ ] Licenças e notices foram preservados.
- [ ] Mudanças de runtime incluem checksum, tamanho, proveniência e rollback.
- [ ] Nenhum sucesso gráfico, assinatura ou notarização foi declarado sem
  evidência.

Use commits pequenos e mensagens no imperativo, por exemplo:
`separate engine build from runtime assembly`. Não misture refatoração ampla
com mudança de produto sem necessidade.

## Release e produção

Não publique diretamente em buckets, Railway, App Store Connect, notarização,
Stripe ou GitHub Environments sem autorização explícita. Releases comerciais
exigem assinatura Developer ID, notarização, stapling, validação do bundle,
registro no backend e evidência dos artefatos.

O workflow de sincronização de upstream abre PR e não faz merge automático.
Uma build verde não é aprovação de production nem prova de interface funcional.

## Vulnerabilidades

Não publique uma vulnerabilidade com secrets, tokens, dados de conta ou
detalhes exploráveis em issue pública. Preserve evidências sanitizadas e
comunique o mantenedor por um canal privado autorizado.
