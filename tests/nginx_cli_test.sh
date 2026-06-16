#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/nginx.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Nginx 一键部署"* ]] || fail help
if "$S" --domain '../bad' >/dev/null 2>&1; then fail domain; fi
if "$S" --port 70000 >/dev/null 2>&1; then fail port; fi
if "$S" --proxy 'file:///etc/passwd' >/dev/null 2>&1; then fail proxy; fi
if "$S" --root relative >/dev/null 2>&1; then fail root; fi
if "$S" --tls --domain example.com >/dev/null 2>&1; then fail email; fi
if "$S" --proxy $'http://127.0.0.1:3000;\nroot /;' >/dev/null 2>&1; then fail proxy-injection; fi
echo "Nginx CLI tests passed"
