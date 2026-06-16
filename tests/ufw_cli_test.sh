#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/ufw.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"UFW 防火墙一键初始化"* ]] || fail help
if "$S" --ssh-port 70000 >/dev/null 2>&1; then fail ssh-port; fi
if "$S" --ports '' >/dev/null 2>&1; then fail empty-port-list; fi
if "$S" --ports '80,,443' >/dev/null 2>&1; then fail empty-port; fi
if "$S" --ports '80;id' >/dev/null 2>&1; then fail port-injection; fi
if "$S" --incoming drop >/dev/null 2>&1; then fail incoming; fi
if "$S" status --dry-run >/dev/null 2>&1; then fail dry-run-status; fi
echo "UFW CLI tests passed"
