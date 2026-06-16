#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/nodejs.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Node.js 一键部署"* ]] || fail help
if "$S" --major 18 >/dev/null 2>&1; then fail major; fi
if "$S" service --app-dir relative >/dev/null 2>&1; then fail app-dir; fi
if "$S" service --service 'bad/name' >/dev/null 2>&1; then fail service-name; fi
if "$S" service --start-cmd 'npm start; id' >/dev/null 2>&1; then fail start-cmd; fi
if "$S" --port 0 >/dev/null 2>&1; then fail port; fi
if "$S" status --dry-run >/dev/null 2>&1; then fail dry-run-status; fi
echo "Node.js CLI tests passed"
