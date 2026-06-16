#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/docker.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Docker Engine 一键部署"* ]] || fail help
if "$S" --user '../root' >/dev/null 2>&1; then fail user; fi
if "$S" --log-size unlimited >/dev/null 2>&1; then fail log-size; fi
if "$S" --log-files 0 >/dev/null 2>&1; then fail log-files; fi
if "$S" --data-root relative >/dev/null 2>&1; then fail data-root; fi
if "$S" --data-root '/tmp/x"evil' >/dev/null 2>&1; then fail data-injection; fi
echo "Docker CLI tests passed"
