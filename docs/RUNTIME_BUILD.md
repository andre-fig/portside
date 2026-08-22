# Portside runtime build

O runtime é montado a partir dos fontes versionados no repositório. O engine
Wine é uma unidade de build independente: ele só é recompilado quando o
`vendor/wine`, seus patches, a toolchain ou o commit Wine do lockfile mudam.

## Componentes

- `PortsideWrapper-<versão>.tar.xz`: `PortsideBaseline.app`, incluindo o
  `PortsideRuntimeHost` compilado e a configuração WineD3D-only;
- `PortsideWineEngine-<versão>.tar.xz`: cópia do engine persistente aprovado,
  renomeada para a versão do runtime que o consome;
- `PortsideWinetricks-<versão>.tar.xz`: fonte e notices de `vendor/winetricks`;
- `runtime-manifest.json`: manifesto assinado com checksums, tamanho e
  proveniência de cada componente.

## Build independente do engine

No Mac com a toolchain registrada em `upstream/dependencies.json`:

```sh
PORTSIDE_ENGINE_BUILD_DIR=build/engine \
./scripts/build-runtime/build-engine.sh
```

Esse comando compila `vendor/wine` usando `build-wine-engine.sh`, cria um
engine versionado como `wine-<WineVersion>-<commit curto>` e gera:

- `engine-metadata.json`, com commit fonte, snapshot checksum, checksum e
  tamanho do archive, storage key, build ID e toolchain;
- `engine-provenance.json`, com a política de fontes usada;
- archive e checksum do engine.

O workflow `Build Portside Engine` publica esses arquivos nos dois buckets
privados em:

```text
runtime/engines/validated/<engine-version>/
```

Esse prefixo é armazenamento interno de componentes validados; não é um
canal de atualização do usuário. O engine só entra em um runtime quando o
commit e o snapshot checksum do lockfile correspondem ao `engine-metadata.json`
baixado, e quando o SHA-256 e o tamanho do archive conferem.

## Montagem do runtime

Com um engine validado disponível nos buckets, o Mac monta wrapper e
winetricks sem recompilar Wine:

```sh
PORTSIDE_RUNTIME_VERSION=0.1.0 \
PORTSIDE_RUNTIME_CHANNEL=production \
PORTSIDE_RUNTIME_DOWNLOAD_URL_PREFIX=https://api.example.invalid/v1/runtime/artifacts/production/ \
PORTSIDE_PUBLIC_BUCKET=... \
PORTSIDE_S3_ACCESS_KEY_ID=... \
PORTSIDE_S3_SECRET_ACCESS_KEY=... \
PORTSIDE_S3_REGION=... \
PORTSIDE_S3_ENDPOINT=... \
./scripts/build-runtime/build.sh
```

`build.sh` executa `fetch-engine.sh`, que baixa o engine aprovado do bucket
privado, verifica metadata, checksum e tamanho, e então monta o archive com o
nome da versão do runtime. Ele nunca baixa um engine do Sikarugir nem aceita
um archive local sem metadata correspondente. A Steam continua sendo obtida
diretamente da Valve pelo verbo `steam` do winetricks durante a instalação do
usuário.

O runtime final contém wrapper, engine e winetricks, além de
`engine-input.json`, `provenance.json` e `sbom.spdx.json`. O manifesto aponta
para a rota estável da API Portside, e não para o bucket privado.

## Workflows

`build-engine.yml` roda seu preflight em Ubuntu e, somente quando há mudança
real no engine, usa macOS para compilar e publicar o componente persistente.
Ele mantém cache de compilação para acelerar recompilações, mas o bucket é a
fonte durável usada por montagens futuras.

`build-runtime.yml` roda quando wrapper, host, winetricks ou scripts de
montagem mudam. Em uma alteração do Wine, ele aguarda a conclusão bem-sucedida
de `Build Portside Engine` e só então monta o runtime. Uma alteração somente
de wrapper ou winetricks reutiliza o engine já validado. Execuções concorrentes
são canceladas por branch.

Ambos os workflows usam o Environment GitHub `production` e as credenciais
dos dois buckets. O build de engine não publica um manifesto de runtime nem a
Steam; o build de runtime é responsável pela publicação do manifesto assinado
e dos archives de consumo.

## Rollback e falhas

Engines antigos permanecem no storage pelo próprio identificador imutável.
Uma falha na compilação do novo engine não remove o engine anterior nem uma
release funcional. Se `fetch-engine.sh` não encontrar o engine correspondente
ao commit do lockfile, a montagem falha explicitamente e não usa fallback.

`release-production.yml` não recompila Wine. Ele seleciona o último runtime
validado, reutiliza seus metadados e segue com a compilação, assinatura,
notarização e publicação do app.
