#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/postgresql.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"PostgreSQL 一键部署"* ]] || fail help
if "$S" --database '../bad' >/dev/null 2>&1; then fail database; fi
if "$S" --user 'bad-user' >/dev/null 2>&1; then fail user; fi
if "$S" --listen '*' >/dev/null 2>&1; then fail remote-without-cidr; fi
if "$S" --allow-cidr 10.0.0.0/99 >/dev/null 2>&1; then fail cidr; fi
if "$S" --backup-dir relative >/dev/null 2>&1; then fail backup-dir; fi
echo "PostgreSQL CLI tests passed"
