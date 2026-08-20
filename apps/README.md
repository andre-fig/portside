# Portside applications

This directory contains the independently built parts of Portside:

- `desktop/`: the native macOS Swift package, including the app, agent, core
  runtime and tests.
- `backend/`: the NestJS/Prisma commercial control plane and its Railway
  services.
- `landing/`: the TanStack Start/React landing page, purchase flow and public
  commercial pages. It is built from this monorepo; the former standalone
  landing repository is not part of the production flow.
- `runtime-host/`: the small native host compiled into Portside-produced
  runtime wrappers.

Product documentation remains in the repository-level `docs/` directory;
release automation remains in `scripts/`.
