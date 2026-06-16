#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/fail2ban.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Fail2ban 一键部署"* ]] || fail help
if "$S" --ssh-port 70000 >/dev/null 2>&1; then fail ssh-port; fi
if "$S" --bantime forever >/dev/null 2>&1; then fail bantime; fi
if "$S" --maxretry 0 >/dev/null 2>&1; then fail maxretry; fi
if "$S" --ignore-ip '127.0.0.1;id' >/dev/null 2>&1; then fail ignore-ip; fi
if "$S" --jails 'sshd;id' >/dev/null 2>&1; then fail jails; fi
if "$S" unban --dry-run --ip 127.0.0.1 >/dev/null 2>&1; then fail dry-run-unban; fi
echo "Fail2ban CLI tests passed"
