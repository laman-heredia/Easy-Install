#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/redis.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Redis 一键部署"* ]] || fail help
if "$S" --port 70000 >/dev/null 2>&1; then fail port; fi
if "$S" --maxmemory unlimited >/dev/null 2>&1; then fail memory; fi
if "$S" --policy unsafe >/dev/null 2>&1; then fail policy; fi
if "$S" --remote --password short >/dev/null 2>&1; then fail remote-password; fi
if "$S" --password 'bad&config' >/dev/null 2>&1; then fail injection; fi
echo "Redis CLI tests passed"
