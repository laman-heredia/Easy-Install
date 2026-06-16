#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/caddy.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Caddy 一键部署"* ]] || fail help
if "$S" --domain bad_domain >/dev/null 2>&1; then fail domain; fi
if "$S" --root relative >/dev/null 2>&1; then fail root; fi
if "$S" --proxy 'http://user:pass@127.0.0.1:3000' >/dev/null 2>&1; then fail proxy-auth; fi
if "$S" --root /var/www/app --proxy http://127.0.0.1:3000 >/dev/null 2>&1; then fail root-proxy; fi
if "$S" --email bad-email >/dev/null 2>&1; then fail email; fi
if "$S" reload --dry-run >/dev/null 2>&1; then fail dry-run-reload; fi
echo "Caddy CLI tests passed"
