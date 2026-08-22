#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

git config core.hooksPath .githooks
echo "Portside Git hooks enabled from .githooks/"
