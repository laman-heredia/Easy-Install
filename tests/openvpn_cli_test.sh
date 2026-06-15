#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/openvpn.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ "$($SCRIPT --version)" == "1.0.0" ]] || fail "version"
help="$($SCRIPT --help)"
[[ "$help" == *"Ubuntu OpenVPN 一键部署与管理"* ]] || fail "help title"
[[ "$help" == *"--split-tunnel"* ]] || fail "advanced options"
if "$SCRIPT" --port 70000 >/dev/null 2>&1; then fail "invalid port accepted"; fi
if "$SCRIPT" --client '../bad' >/dev/null 2>&1; then fail "invalid client accepted"; fi
if "$SCRIPT" --protocol sctp >/dev/null 2>&1; then fail "invalid protocol accepted"; fi
if "$SCRIPT" --dns custom >/dev/null 2>&1; then fail "empty custom DNS accepted"; fi
echo "CLI tests passed"
