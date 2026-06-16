#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/wireguard.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ "$($SCRIPT --version)" == "1.0.0" ]] || fail "version"
help="$($SCRIPT --help)"
[[ "$help" == *"Ubuntu WireGuard 一键部署与管理"* ]] || fail "help title"
[[ "$help" == *"UDP 端口（默认 51820）"* ]] || fail "port note"
if "$SCRIPT" --port 70000 >/dev/null 2>&1; then fail "invalid port accepted"; fi
if "$SCRIPT" --client '../bad' >/dev/null 2>&1; then fail "invalid client accepted"; fi
if "$SCRIPT" --subnet 10.66.66.0/33 >/dev/null 2>&1; then fail "invalid subnet accepted"; fi
if "$SCRIPT" --subnet 999.66.66.0/24 >/dev/null 2>&1; then fail "invalid subnet address accepted"; fi
if "$SCRIPT" --allowed-ips 10.0.0.0/99 >/dev/null 2>&1; then fail "invalid AllowedIPs accepted"; fi
if "$SCRIPT" --dns custom >/dev/null 2>&1; then fail "empty custom DNS accepted"; fi
if "$SCRIPT" --mtu 100 >/dev/null 2>&1; then fail "invalid MTU accepted"; fi
if "$SCRIPT" --endpoint $'vpn.example.com\nPostUp=evil' >/dev/null 2>&1; then fail "config injection accepted"; fi
if "$SCRIPT" add --dry-run >/dev/null 2>&1; then fail "management dry-run accepted"; fi
echo "WireGuard CLI tests passed"
