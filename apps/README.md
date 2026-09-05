# Portside applications

| Component                              | Responsibility                                                        |
| -------------------------------------- | --------------------------------------------------------------------- |
| [desktop](desktop/AGENTS.md)           | SwiftUI app, PortsideCore, PortsideAgent, PortsideInstaller and tests |
| [backend](backend/AGENTS.md)           | NestJS/Prisma API, workflow reconciliation worker and cron entrypoint |
| [landing](landing/README.md)           | TanStack Start/React site and checkout; built from this monorepo      |
| [runtime-host](runtime-host/README.md) | Native executable compiled inside the private runtime wrapper         |

[Architecture](../docs/ARCHITECTURE.md) connects these lifetimes and services.
[Documentation index](../docs/README.md) routes task context;
[STATUS](../docs/STATUS.md) distinguishes implementation and operational evidence.
