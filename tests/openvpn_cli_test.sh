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
if "$SCRIPT" --subnet 999.8.0.0 >/dev/null 2>&1; then fail "invalid subnet accepted"; fi
if "$SCRIPT" --netmask 255.0.255.0 >/dev/null 2>&1; then fail "non-contiguous netmask accepted"; fi
if "$SCRIPT" --ipv6-subnet $'fd42::/64\npush evil' >/dev/null 2>&1; then fail "invalid IPv6 subnet accepted"; fi
if "$SCRIPT" add --dry-run >/dev/null 2>&1; then fail "management dry-run accepted"; fi
echo "CLI tests passed"
