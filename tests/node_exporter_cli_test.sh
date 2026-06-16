#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/node-exporter.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"Node Exporter 一键部署"* ]] || fail help
if "$S" --listen 127.0.0.1 >/dev/null 2>&1; then fail listen-no-port; fi
if "$S" --listen 127.0.0.1:70000 >/dev/null 2>&1; then fail listen-port; fi
if "$S" --extra-args '--collector.systemd;id' >/dev/null 2>&1; then fail extra-args; fi
if "$S" status --dry-run >/dev/null 2>&1; then fail dry-run-status; fi
echo "Node Exporter CLI tests passed"
