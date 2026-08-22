# Arquitetura do Portside

Este documento descreve a arquitetura operacional atual do monorepo. O
Portside é dividido em três produtos implantáveis e um pipeline de runtime:

```text
Portside.app (macOS)
        │ manifesto assinado, downloads e ativação
        ▼
API Portside (NestJS/Railway) ───── PostgreSQL/Prisma
        │ URLs temporárias para objetos privados
        ▼
Buckets Portside primário + réplica

Fontes versionados em vendor/ e upstream/
        │
        ├── Build Portside Engine ──► engine Wine imutável
        │                              (bucket privado)
        └── Build Portside Runtime ─► wrapper + engine aprovado + winetricks
                                       + manifesto assinado
```

## Fronteiras do sistema

| Área | Responsabilidade | Não deve fazer |
| --- | --- | --- |
| `apps/desktop` | Interface macOS, licença, atualização, instalação, rollback e diagnóstico | Compilar runtime, acessar buckets diretamente ou copiar a Steam nativa |
| `apps/backend` | Licenças, manifestos, artefatos, builds, releases, promoção e URLs assinadas | Confiar somente em checksum ou armazenar binários em filesystem efêmero |
| `apps/landing` | Página de venda, checkout, suporte e termos comerciais | Executar lógica de runtime ou depender do repositório antigo da landing |
| `apps/runtime-host` | Host nativo colocado dentro do wrapper | Ser um aplicativo de usuário independente |
| `vendor/` + `upstream/` | Fontes, lockfiles, licenças, notices e patches auditados | Conter caches, `.git` aninhado ou archives compilados |
| GitHub Actions | Validação, compilação, publicação e notarização | Expor secrets ou fazer promoção implícita sem proteção |

O runtime não fica embutido no `Portside.app`. O aplicativo baixa somente
componentes descritos pelo manifesto assinado e os instala em diretórios de
Application Support controlados pelo Portside.

## Desktop macOS

`apps/desktop` é um Swift Package com três produtos principais:

- `Portside`: interface SwiftUI e ciclo de vida do aplicativo;
- `PortsideAgent`: processo auxiliar usado pelo wrapper;
- `PortsideCore`: caminhos, licenças, downloads, manifesto, verificação,
  rollback, compatibilidade, Steam flow e diagnósticos.

O fluxo de instalação/atualização é:

```text
manifesto da API
  → assinatura/host/versão compatíveis
  → download por URL temporária Portside
  → SHA-256 + tamanho
  → extração segura em diretório temporário
  → validação do layout
  → ativação atômica
  → wrapper/prefixo anterior preservado para rollback
```

O desktop continua funcionando offline com o runtime local verificado. Uma
atualização inválida, incompleta ou incompatível nunca substitui uma versão
funcional. O rollback cobre wrapper, engine e winetricks; não cobre
`SteamLibrary`, saves, prefixos de usuário ou dados da conta.

O fluxo da Steam usa um prefixo novo e o verbo oficial `steam` do winetricks.
Não copia a sessão nativa do macOS, não distribui o instalador da Steam e não
captura senha, cookie, token, Steam ID ou conteúdo de janela.

### Baseline do wrapper

```text
Wrapper: PortsideBaseline.app
Renderer: WineD3D
D3DMetal: desabilitado
DXMT: desabilitado
DXVK: desabilitado
MSYNC/ESYNC: habilitados conforme manifesto
```

A existência de `steam.exe`, `steamwebhelper` ou um ícone no Dock não prova
sucesso. A aceitação exige uma janela real da Steam renderizada e interação
confirmada em uma sessão gráfica.

## Backend e control plane

`apps/backend` é uma API NestJS organizada em módulos. `core` carrega
configuração, `common` concentra guards/sanitização/políticas, `database`
integra Prisma e `modules` separa health, licenças, artefatos, runtime, admin
e sincronização.

O backend diferencia explicitamente:

```text
source snapshot → build → artifact → release → channel → promotion/rollback
```

Um arquivo com checksum correto não entra em `production` sem fonte registrada,
build bem-sucedida, validação, release e promoção compatíveis. O worker
reconcilia execuções autorizadas do GitHub Actions; ele registra estado e
proveniência, mas não substitui a proteção do Environment nem aprova uma
release sozinho.

As rotas de download do desktop apontam para a API Portside. A API valida que
o nome pertence ao canal e ao artefato aprovado, gera uma URL S3 temporária e
faz redirect. O desktop não recebe credenciais dos buckets.

## Pipeline do runtime

### 1. Fontes

`vendor/wine`, `vendor/winetricks`, `runtime/wrapper-template` e
`apps/runtime-host` são fontes locais. `upstream/lock.json` registra commits,
licenças, checksums de snapshots e estado de validação. O processo de
sincronização abre uma PR; não publica automaticamente uma release.

### 2. Engine persistente

`Build Portside Engine` é acionado por mudança real no Wine, patches, toolchain
ou commit Wine do lockfile. Em Ubuntu ele valida as entradas; em `macos-15`
ele compila o Wine e publica nos dois buckets:

```text
runtime/engines/validated/<engine-version>/
  PortsideWineEngine-<engine-version>.tar.xz
  PortsideWineEngine-<engine-version>.sha256
  engine-metadata.json
```

`engine-metadata.json` relaciona engine, commit fonte, snapshot checksum,
checksum do archive, tamanho, build ID e toolchain. O prefixo é armazenamento
interno de componentes validados, não um canal de atualização de usuário.

### 3. Montagem do runtime

`Build Portside Runtime` é acionado por mudanças no wrapper, host, winetricks
ou scripts de montagem. `fetch-engine.sh` calcula o engine esperado pelo
lockfile, baixa sua metadata do bucket privado e verifica:

- commit e snapshot checksum do Wine;
- storage key e nome do arquivo;
- SHA-256 e tamanho do archive;
- integridade do tarball e ausência de path traversal;
- diretório raiz esperado após a extração.

Somente depois disso o pipeline monta o wrapper, reempacota o engine com o
nome da versão do runtime e empacota winetricks. O engine não é recompilado
nessa etapa.

Os artefatos finais são:

```text
PortsideWrapper-<runtime>.tar.xz
PortsideWineEngine-<runtime>.tar.xz
PortsideWinetricks-<runtime>.tar.xz
runtime-manifest.json
engine-input.json
provenance.json
sbom.spdx.json
```

O manifesto assinado contém versão, componente, URL da API, SHA-256, tamanho,
fonte e renderer padrão. A publicação replica os objetos nos buckets primário
e secundário. Versões anteriores permanecem disponíveis para rollback.

## App, runtime e atualização

São dois ciclos independentes:

```text
Sparkle appcast assinado ──► atualização do Portside.app
Manifesto runtime assinado ─► atualização do wrapper/engine/winetricks
```

Uma release do app reutiliza o último runtime validado; `release-production`
não recompila Wine. O app só publica depois de assinatura Developer ID,
notarização, stapling, validação do bundle e registro da release no backend.

## Workflows

| Workflow | Runner principal | Função |
| --- | --- | --- |
| `ci.yml` | Ubuntu | Política de fontes, Prisma e build do backend |
| `build-engine.yml` | Ubuntu + macOS | Engine Wine persistente e metadata |
| `build-runtime.yml` | Ubuntu + macOS | Montagem, manifesto e publicação do runtime |
| `build-desktop.yml` | Ubuntu + macOS condicional | Build unsigned de validação do app |
| `build-landing.yml` | Ubuntu | Build da landing |
| `sync-upstreams.yml` | Ubuntu | PR de sincronização de fontes |
| `validate-clean-install.yml` | Mac self-hosted | Instalação limpa e validação gráfica |
| `release-production.yml` | macOS | Assinatura, notarização e publicação comercial |
| `deploy-railway.yml` | Ubuntu | Verificação da API Railway |

Os workflows de engine e runtime usam `concurrency` para cancelar trabalho
antigo do mesmo branch. O preflight barato roda em Ubuntu; macOS fica reservado
para Wine, Swift, empacotamento, codesign e notarização.

## Segurança, privacidade e observabilidade

- Buckets são privados; acesso externo passa pela API e por URLs temporárias.
- Chaves privadas, certificados, tokens e credenciais ficam em secrets ou
  Keychain, nunca no Git.
- Archives são extraídos somente após validação de caminhos e estrutura.
- Sentry recebe contexto sanitizado: versão do app/runtime/engine, estágio,
  arquitetura, renderer, códigos de erro e estados operacionais. Não recebe
  senha, cookie, token, Steam ID, conteúdo de janela ou dados de conta.
- Processos gerenciados só são encerrados quando seus argumentos apontam para
  o wrapper/prefixo do Portside; Steam nativa e outros wrappers não são
  afetados.
- O runtime baseline não solicita microfone e não possui caminho de captura de
  áudio; qualquer recurso futuro de voz exige decisão e permissão explícitas.

## Falhas e recuperação

| Falha | Comportamento |
| --- | --- |
| upstream indisponível | Mantém snapshots existentes; sincronização falha sem apagar fontes |
| engine não publicado | Montagem falha claramente, sem fallback externo |
| checksum/manifesto inválido | Artefato é rejeitado e runtime ativo permanece intacto |
| bucket primário indisponível | Publicação exige réplica; cliente usa a API e o estado local verificado |
| API offline | Cliente usa manifesto/runtime local válido |
| Steam não cria janela | Instalação não é considerada sucesso; logs e diagnóstico registram o estágio |
| update interrompido | Diretório temporário é descartado e rollback preserva a versão anterior |

Para procedimentos operacionais, consulte [`DEVELOPER_GUIDE.md`](DEVELOPER_GUIDE.md),
[`RUNTIME_BUILD.md`](RUNTIME_BUILD.md), [`AUTOMATIC_UPDATES.md`](AUTOMATIC_UPDATES.md),
[`VALIDATION.md`](VALIDATION.md) e [`ROLLBACK.md`](ROLLBACK.md).
