#!/usr/bin/env bash
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/l2tp.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ "$($S --version)" == 1.0.0 ]] || fail version
[[ "$($S --help)" == *"L2TP/IPsec 一键部署"* ]] || fail help
if "$S" --psk short >/dev/null 2>&1; then fail psk-length; fi
if "$S" --psk 'bad;injection;value' >/dev/null 2>&1; then fail psk-injection; fi
if "$S" --user '../root' >/dev/null 2>&1; then fail user; fi
if "$S" --password short >/dev/null 2>&1; then fail password-length; fi
if "$S" --vpn-cidr not-a-cidr >/dev/null 2>&1; then fail cidr; fi
if "$S" --client-pool '10.0.0.10;id-10.0.0.20' >/dev/null 2>&1; then fail pool-injection; fi
if "$S" --dns '' >/dev/null 2>&1; then fail dns-empty; fi
if "$S" --mtu 2000 >/dev/null 2>&1; then fail mtu; fi
if "$S" add --dry-run >/dev/null 2>&1; then fail dry-run-add; fi
echo "L2TP CLI tests passed"
