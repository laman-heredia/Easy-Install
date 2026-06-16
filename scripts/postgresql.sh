#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"
COMMAND="install"; DB_NAME="app"; DB_USER="app"; DB_PASSWORD=""; LISTEN="localhost"; PORT="5432"; ALLOW_CIDR=""; BACKUP_DIR="$PWD"; ASSUME_YES="false"; FORCE="false"; PURGE_DATA="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }; run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }; trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu PostgreSQL 一键部署与管理
用法：
  sudo ./postgresql.sh [install] [选项]  安装并创建数据库（默认）
  sudo ./postgresql.sh create [选项]     创建数据库与用户
  sudo ./postgresql.sh backup [选项]     导出压缩备份
  sudo ./postgresql.sh list              列出数据库与角色
  sudo ./postgresql.sh status            查看服务和连接信息
  sudo ./postgresql.sh uninstall         卸载 PostgreSQL
选项：
  --database NAME       数据库名（默认 app）
  --user NAME           数据库用户（默认 app）
  --password PASSWORD   密码（默认随机生成）
  --listen ADDRESS      监听地址（默认 localhost；远程可用 *）
  --port PORT           监听端口（默认 5432）
  --allow-cidr CIDR     允许密码认证的客户端网段；远程监听时必需
  --backup-dir DIR      备份输出目录（默认当前目录）
  --force               更新已有用户密码/数据库所有者
  --purge-data          卸载时删除数据库数据
  -y, --yes             无交互执行
  --dry-run             仅演练 install
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|create|backup|list|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --database) DB_NAME="${2:?缺少数据库名}"; shift 2;; --user) DB_USER="${2:?缺少用户名}"; shift 2;; --password) DB_PASSWORD="${2:?缺少密码}"; shift 2;; --listen) LISTEN="${2:?缺少地址}"; shift 2;; --port) PORT="${2:?缺少端口}"; shift 2;; --allow-cidr) ALLOW_CIDR="${2:?缺少 CIDR}"; shift 2;; --backup-dir) BACKUP_DIR="${2:?缺少目录}"; shift 2;; --force) FORCE="true"; shift;; --purge-data) PURGE_DATA="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ [[ "$DB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || die "数据库名格式无效。"; [[ "$DB_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || die "数据库用户名格式无效。"; [[ "$LISTEN" == localhost || "$LISTEN" == "*" || "$LISTEN" =~ ^[A-Fa-f0-9:.]+$ ]] || die "监听地址无效。"; if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT<1||PORT>65535)); then die "端口无效。"; fi; [[ "$BACKUP_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "备份目录必须是安全的绝对路径。"; [[ "$DB_PASSWORD" != *$'\n'* && "$DB_PASSWORD" != *$'\r'* ]] || die "密码不能包含换行。"; [[ "$LISTEN" == localhost || -n "$ALLOW_CIDR" ]] || die "远程监听必须使用 --allow-cidr。"; [[ -z "$ALLOW_CIDR" ]] || python3 - "$ALLOW_CIDR" <<'PY' || die "CIDR 无效。"
import ipaddress, sys
ipaddress.ip_network(sys.argv[1], strict=False)
PY
}
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
password(){ [[ -n "$DB_PASSWORD" ]] || DB_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"; }
pg_file(){ find /etc/postgresql -mindepth 3 -maxdepth 3 -type f -name "$1" | sort -V | tail -n1; }
configure(){ local conf hba temp; conf="$(pg_file postgresql.conf)"; hba="$(pg_file pg_hba.conf)"; [[ -n "$conf" && -n "$hba" ]] || die "找不到 PostgreSQL 配置。"; temp="$(mktemp)"; awk '/^# Easy Install begin$/{skip=1;next} /^# Easy Install end$/{skip=0;next} !skip' "$conf" >"$temp"; cat >>"$temp" <<EOF_CONF
# Easy Install begin
listen_addresses = '${LISTEN}'
port = ${PORT}
password_encryption = 'scram-sha-256'
# Easy Install end
EOF_CONF
install -m 644 "$temp" "$conf"; rm -f "$temp"; if [[ -n "$ALLOW_CIDR" ]]; then grep -Fq "host all all $ALLOW_CIDR scram-sha-256" "$hba" || printf '\n# Easy Install\nhost all all %s scram-sha-256\n' "$ALLOW_CIDR" >>"$hba"; fi; systemctl restart postgresql; }
create_db(){ password; local exists; exists="$(runuser -u postgres -- psql -Atqc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")"; if [[ "$exists" == 1 ]]; then [[ "$FORCE" == true ]] || die "角色已存在；使用 --force 更新。"; printf "ALTER ROLE \"%s\" WITH LOGIN PASSWORD :'pwd';\n" "$DB_USER" | runuser -u postgres -- psql -v pwd="$DB_PASSWORD"; else printf "CREATE ROLE \"%s\" WITH LOGIN PASSWORD :'pwd';\n" "$DB_USER" | runuser -u postgres -- psql -v pwd="$DB_PASSWORD"; fi; exists="$(runuser -u postgres -- psql -Atqc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")"; if [[ "$exists" == 1 ]]; then [[ "$FORCE" == true ]] || die "数据库已存在；使用 --force 更新所有者。"; runuser -u postgres -- psql -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$DB_USER\";"; else runuser -u postgres -- createdb --owner="$DB_USER" "$DB_NAME"; fi; ok "数据库：$DB_NAME；用户：$DB_USER；密码：$DB_PASSWORD"; }
install_pg(){ root_ubuntu; validate; confirm "安装 PostgreSQL？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y postgresql postgresql-contrib openssl python3-minimal; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; systemctl enable --now postgresql; configure; create_db; }
create(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "create 不支持 --dry-run。"; create_db; }
backup(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "backup 不支持 --dry-run。"; mkdir -p "$BACKUP_DIR"; local out; out="$BACKUP_DIR/${DB_NAME}-$(date -u +%Y%m%dT%H%M%SZ).dump"; runuser -u postgres -- pg_dump --format=custom "$DB_NAME" >"$out"; chmod 600 "$out"; ok "备份：$out"; }
list(){ root_ubuntu; runuser -u postgres -- psql -c '\l'; runuser -u postgres -- psql -c '\du'; }
status(){ root_ubuntu; systemctl --no-pager --full status postgresql || true; pg_isready -h localhost -p "$PORT"; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 PostgreSQL？" || die "已取消。"; systemctl disable --now postgresql 2>/dev/null || true; apt-get purge -y 'postgresql*'; if [[ "$PURGE_DATA" == true ]]; then rm -rf /var/lib/postgresql /etc/postgresql /var/log/postgresql; else warn "数据库数据仍保留在 /var/lib/postgresql。"; fi; ok "PostgreSQL 已卸载。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_pg;; create) create;; backup) backup;; list) list;; status) status;; uninstall) uninstall;; esac; }
main "$@"
