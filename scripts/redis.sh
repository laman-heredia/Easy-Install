#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"; readonly CONF="/etc/redis/redis.conf"; readonly BACKUP="/etc/redis/redis.conf.easy-install.bak"
COMMAND="install"; BIND="127.0.0.1 ::1"; PORT="6379"; PASSWORD=""; MAXMEMORY="0"; POLICY="noeviction"; DATABASES="16"; REMOTE="false"; ASSUME_YES="false"; FORCE="false"; PURGE_DATA="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }; run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }; trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Redis 一键部署与管理
用法：
  sudo ./redis.sh [install] [选项]  安装并安全配置 Redis（默认）
  sudo ./redis.sh status            查看服务、内存和持久化状态
  sudo ./redis.sh test [选项]       测试认证与 PING
  sudo ./redis.sh uninstall         卸载 Redis
选项：
  --bind ADDRESSES      监听地址（默认 127.0.0.1 ::1）
  --port PORT           端口（默认 6379）
  --password PASSWORD   认证密码（默认随机生成）
  --remote              监听 0.0.0.0（必须设置强密码并自行配置防火墙）
  --maxmemory SIZE      内存上限，如 512mb；默认 0（由系统决定）
  --policy POLICY       noeviction/allkeys-lru/allkeys-lfu/volatile-lru/volatile-lfu/allkeys-random/volatile-random/volatile-ttl
  --databases COUNT     逻辑数据库数量（默认 16）
  --force               覆盖已有 Easy Install 配置
  --purge-data          卸载时删除 /var/lib/redis
  -y, --yes             无交互执行
  --dry-run             仅演练 install
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|status|test|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --bind) BIND="${2:?缺少地址}"; shift 2;; --port) PORT="${2:?缺少端口}"; shift 2;; --password) PASSWORD="${2:?缺少密码}"; shift 2;; --remote) REMOTE="true"; BIND="0.0.0.0 ::"; shift;; --maxmemory) MAXMEMORY="${2:?缺少内存值}"; shift 2;; --policy) POLICY="${2:?缺少策略}"; shift 2;; --databases) DATABASES="${2:?缺少数量}"; shift 2;; --force) FORCE="true"; shift;; --purge-data) PURGE_DATA="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT<1||PORT>65535)); then die "端口无效。"; fi; [[ "$BIND" =~ ^[A-Fa-f0-9:.\ *]+$ ]] || die "监听地址无效。"; [[ "$MAXMEMORY" == 0 || "$MAXMEMORY" =~ ^[1-9][0-9]*(kb|mb|gb)$ ]] || die "--maxmemory 示例：512mb。"; [[ "$POLICY" =~ ^(noeviction|allkeys-lru|allkeys-lfu|volatile-lru|volatile-lfu|allkeys-random|volatile-random|volatile-ttl)$ ]] || die "淘汰策略无效。"; [[ "$DATABASES" =~ ^[1-9][0-9]*$ ]] || die "数据库数量无效。"; [[ -z "$PASSWORD" || "$PASSWORD" =~ ^[A-Za-z0-9_.:@%+=,-]+$ ]] || die "密码只能包含安全的可打印字符。"; [[ "$REMOTE" != true || ${#PASSWORD} -ge 16 ]] || die "--remote 必须显式提供至少 16 字符的 --password。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
password(){ [[ -n "$PASSWORD" ]] || PASSWORD="$(openssl rand -hex 24)"; }
set_conf(){ local key="$1" value="$2" file="$3"; if grep -Eq "^[#[:space:]]*${key}[[:space:]]" "$file"; then sed -ri "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"; else printf '%s %s\n' "$key" "$value" >>"$file"; fi; }
configure(){ [[ ! -e "$BACKUP" || "$FORCE" == true ]] || die "Redis 已由本脚本配置；使用 --force 更新。"; [[ -e "$BACKUP" ]] || cp -a "$CONF" "$BACKUP"; local temp; temp="$(mktemp /etc/redis/.redis.conf.XXXXXX)"; cp "$CONF" "$temp"; set_conf bind "$BIND" "$temp"; set_conf port "$PORT" "$temp"; set_conf protected-mode yes "$temp"; set_conf requirepass "$PASSWORD" "$temp"; set_conf maxmemory "$MAXMEMORY" "$temp"; set_conf maxmemory-policy "$POLICY" "$temp"; set_conf databases "$DATABASES" "$temp"; set_conf supervised systemd "$temp"; set_conf appendonly yes "$temp"; chown redis:redis "$temp"; chmod 640 "$temp"; mv "$temp" "$CONF"; redis-server "$CONF" --test-memory 2 >/dev/null; systemctl restart redis-server; }
install_redis(){ root_ubuntu; validate; password; [[ "$REMOTE" != true ]] || warn "远程 Redis 暴露风险极高，请仅允许可信 CIDR 访问 TCP $PORT。"; confirm "安装 Redis？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y redis-server openssl; [[ "$DRY_RUN" == true ]] && { ok "演练完成；生成密码不会写入系统。"; return; }; configure; systemctl enable --now redis-server; redis-cli -h 127.0.0.1 -p "$PORT" -a "$PASSWORD" --no-auth-warning PING | grep -qx PONG; ok "Redis 已安装；密码：$PASSWORD"; }
status(){ root_ubuntu; systemctl --no-pager --full status redis-server || true; if [[ -n "$PASSWORD" ]]; then redis-cli -h 127.0.0.1 -p "$PORT" -a "$PASSWORD" --no-auth-warning INFO server | head -n 20; else warn "使用 --password 查看认证后的 INFO。"; fi; }
test_redis(){ root_ubuntu; validate; [[ -n "$PASSWORD" ]] || die "test 需要 --password。"; redis-cli -h 127.0.0.1 -p "$PORT" -a "$PASSWORD" --no-auth-warning PING | grep -qx PONG; ok "Redis PING 成功。"; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Redis？" || die "已取消。"; systemctl disable --now redis-server 2>/dev/null || true; apt-get purge -y redis-server redis-tools; if [[ -e "$BACKUP" ]]; then mv "$BACKUP" "$CONF"; fi; if [[ "$PURGE_DATA" == true ]]; then rm -rf /var/lib/redis /var/log/redis; else warn "Redis 数据仍保留在 /var/lib/redis。"; fi; ok "Redis 已卸载。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_redis;; status) status;; test) test_redis;; uninstall) uninstall;; esac; }
main "$@"
