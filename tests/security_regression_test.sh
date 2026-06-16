#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck disable=SC2016
grep -Fq 'elif [[ "$ROUTE_ALL" == "true" ]]' "$ROOT/scripts/openvpn.sh" ||
  fail "OpenVPN split tunnel would block IPv6"
# shellcheck disable=SC2016
grep -Fq 'cat >"$temp_output"' "$ROOT/scripts/openvpn.sh" ||
  fail "OpenVPN profile is not staged atomically"
# shellcheck disable=SC2016
grep -Fq 'cat >"$temp_dir/client.conf"' "$ROOT/scripts/wireguard.sh" ||
  fail "WireGuard client profile is not staged"
grep -Fq '已恢复客户端' "$ROOT/scripts/wireguard.sh" ||
  fail "WireGuard peer removal lacks rollback"
[[ "$(grep -c 'run ipsec restart' "$ROOT/scripts/ipsec.sh")" -ge 2 ]] ||
  fail "IPsec credential changes do not terminate active sessions"
for script in ipsec openvpn wireguard; do
  grep -Fq 'ensure_bootstrap' "$ROOT/scripts/${script}.sh" ||
    fail "$script lacks dependency bootstrap"
done

echo "Security regression tests passed"
