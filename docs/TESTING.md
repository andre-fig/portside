# Testes do Portside

Este documento define o que deve ser validado em cada área. Testes automatizados
confirmam comportamento de código; eles não substituem a aceitação gráfica da
Steam em um Mac real.

## Princípios

- Teste a mudança no nível mais próximo possível do código alterado.
- Prefira testes determinísticos, isolados e sem rede.
- Use fixtures sanitizadas; nunca use senha, cookie, token, Steam ID, save ou
  biblioteca Steam reais.
- Não considere sucesso a existência de um processo ou arquivo sem verificar o
  comportamento observável correspondente.
- Teste explicitamente assinatura, checksum, tamanho, canal, host, path
  traversal e rollback.

## Comandos por área

### Desktop Swift

```sh
swift test --package-path apps/desktop
swift build --package-path apps/desktop
```

Os unitários ficam em `apps/desktop/Tests/PortsideCoreTests/`. Cubra, conforme a
mudança, manifesto e assinatura, allowlist de host, SHA-256, tamanho, cache,
backend offline, extração segura, ativação atômica, rollback, renderer,
detecção de processos e sanitização de diagnósticos.

### Backend NestJS

```sh
cd apps/backend
npm ci
npm run prisma:validate
npm run typecheck
npm run lint
npm test
npm run build
```

Specs ficam junto do código testado, em arquivos `*.spec.ts`. Use mocks para
S3, GitHub, Sentry e serviços externos. Não faça testes unitários contra o
Railway ou o banco de produção.

Cubra especialmente DTOs, guards, licenças, URLs assinadas, sincronização
idempotente, manifesto inválido, artefato adulterado, backend offline,
rollback, path traversal e symlink perigoso.

### Landing

```sh
cd apps/landing
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run build
```

Valide manualmente as rotas públicas, checkout, estados de sucesso/erro,
termos, privacidade, responsividade e ausência de segredos no bundle.

### Shell, manifests e workflows

```sh
git diff --check
./scripts/validate-production-policy.sh
for script in scripts/build-runtime/*.sh scripts/upstream/*.sh scripts/generate_manifest.sh scripts/publish_runtime.sh scripts/publish_engine.sh; do sh -n "$script"; done
actionlint .github/workflows/*.yml
```

Para scripts que modificam arquivos, use diretórios temporários estreitos e
confirme que snapshots e dados originais permanecem intactos.

## Testes do runtime

O runtime é testado em camadas:

1. `source-audit.sh` confirma fontes, notices e layout;
2. `resolve-engine.sh` relaciona versão Wine, commit e storage key;
3. `Build Portside Engine` compila e publica engine, metadata e checksum;
4. `fetch-engine.sh` verifica commit, snapshot checksum, SHA-256, tamanho,
   tarball, path traversal e diretório raiz;
5. `validate-clean-layout.sh` verifica wrapper, engine, winetricks e o verbo
   `steam`;
6. `validate-manifest.sh` verifica canal, componentes, URLs Portside,
   tamanho, SHA-256 e assinatura;
7. `validate-clean-install.yml` executa a instalação em Mac self-hosted;
8. uma pessoa confirma a janela real e a interação com a Steam.

Uma mudança somente no wrapper ou winetricks deve reutilizar um engine
aprovado. Uma mudança em Wine ou toolchain deve executar primeiro o workflow de
engine e só depois montar o runtime.

## Aceitação gráfica da Steam

Em uma sessão gráfica real e com dados de teste, confirme:

- janela real da Steam visível e renderizada;
- tela de login visível e interativa;
- `steamwebhelper` funcionando;
- atualização inicial concluída e segunda abertura limpa;
- ausência de loop ao fechar a Steam;
- comportamento correto após reinício e, quando aplicável, offline.

Se a automação não puder interagir com a GUI, registre o runtime, Mac, versão,
estágio e logs sanitizados e marque a aceitação como manual pendente. Nunca
declare UI funcional apenas por logs de processo.

## Testes negativos e segurança

Considere manifesto alterado, assinatura ausente, chave errada, checksum ou
tamanho divergente, URL fora da API Portside, canal não permitido, archive com
caminho absoluto ou `..`, symlink perigoso, download interrompido, API/buckets
offline, engine ausente ou com commit diferente do lockfile e processos de
outra instalação.

Logs não podem conter senha, token, cookie, Steam ID, dados de conta ou
conteúdo de janela.

## CI e evidências

O `pre-commit` executa checks rápidos; o `pre-push` executa os checks da área
alterada. O GitHub Actions mantém validações que dependem de runners, secrets,
macOS, sessão gráfica ou publicação.

```sh
gh run list --limit 20
gh run watch <RUN_ID> --interval 20 --exit-status
```

Ao concluir, registre comandos, resultado, commit, workflow/run ID, plataforma,
artefatos/checksums, validações manuais e limitações. Nunca anexe dados
sensíveis.
