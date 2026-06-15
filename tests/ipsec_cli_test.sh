#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/ipsec.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ "$($SCRIPT --version)" == "1.0.0" ]] || fail "version"
help="$($SCRIPT --help)"
[[ "$help" == *"Ubuntu IKEv2/IPsec 一键部署与管理"* ]] || fail "help title"
[[ "$help" == *"UDP 500、UDP 4500"* ]] || fail "ports note"
if "$SCRIPT" --user '../bad' >/dev/null 2>&1; then fail "invalid user accepted"; fi
if "$SCRIPT" --pool 10.10.0.0/33 >/dev/null 2>&1; then fail "invalid pool accepted"; fi
if "$SCRIPT" --dns custom >/dev/null 2>&1; then fail "empty custom DNS accepted"; fi
if "$SCRIPT" --cert-days 7 >/dev/null 2>&1; then fail "invalid certificate lifetime accepted"; fi
if "$SCRIPT" --endpoint $'vpn.example.com\nrightauth=psk' >/dev/null 2>&1; then fail "config injection accepted"; fi
echo "IPsec CLI tests passed"
