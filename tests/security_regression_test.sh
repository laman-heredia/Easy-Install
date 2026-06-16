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
grep -Fq 'systemctl restart docker' "$ROOT/scripts/docker.sh" ||
  fail "Docker daemon configuration is not applied after installation"
grep -Fq 'DAEMON_BACKUP=' "$ROOT/scripts/docker.sh" ||
  fail "Docker does not preserve a pre-existing daemon configuration"
grep -Fq 'Nginx 新配置校验失败，已恢复原配置' "$ROOT/scripts/nginx.sh" ||
  fail "Nginx site updates lack validation rollback"
grep -Fq '/^# Easy Install begin$/{skip=1;next}' "$ROOT/scripts/postgresql.sh" ||
  fail "PostgreSQL leaves stale managed pg_hba rules"
redis_validate_line="$(grep -nF 'redis-server "$temp" --test-memory 2' "$ROOT/scripts/redis.sh" | cut -d: -f1)"
redis_install_line="$(grep -nF 'mv "$temp" "$CONF"' "$ROOT/scripts/redis.sh" | cut -d: -f1)"
[[ -n "$redis_validate_line" && -n "$redis_install_line" && "$redis_validate_line" -le "$redis_install_line" ]] ||
  fail "Redis installs configuration before validating it"
grep -Fq 'MySQL 新配置启动失败，已恢复原配置' "$ROOT/scripts/mysql.sh" ||
  fail "MySQL configuration updates lack restart rollback"
grep -Fq "CREATE USER '\${DB_USER}'@'%'" "$ROOT/scripts/mysql.sh" ||
  fail "MySQL account creation uses unsafe or invalid quoting"
grep -Fq '((${#ports[@]} > 0))' "$ROOT/scripts/ufw.sh" ||
  fail "UFW accepts an empty port list"
grep -Fq 'fail2ban-client -t' "$ROOT/scripts/fail2ban.sh" ||
  fail "Fail2ban config is not syntax-tested"
grep -Fq 'caddy validate --config "$temp"' "$ROOT/scripts/caddy.sh" ||
  fail "Caddyfile is not validated before activation"
grep -Fq '127.0.0.1:9100' "$ROOT/scripts/node-exporter.sh" ||
  fail "Node Exporter does not default to local-only metrics"

echo "Security regression tests passed"
