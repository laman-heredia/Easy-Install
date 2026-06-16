#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/mysql.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"MySQL 一键部署"* ]] || fail help
if "$S" --database 'bad-name' >/dev/null 2>&1; then fail database; fi
if "$S" --user '../root' >/dev/null 2>&1; then fail user; fi
if "$S" --port 70000 >/dev/null 2>&1; then fail port; fi
if "$S" --bind '0.0.0.0;id' >/dev/null 2>&1; then fail bind; fi
if "$S" --backup-dir relative >/dev/null 2>&1; then fail backup-dir; fi
if "$S" --password "bad'quote" >/dev/null 2>&1; then fail password-quote; fi
if "$S" create --dry-run >/dev/null 2>&1; then fail dry-run-create; fi
echo "MySQL CLI tests passed"
