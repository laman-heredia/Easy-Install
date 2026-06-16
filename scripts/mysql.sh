#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"
COMMAND="install"; DB_NAME="app"; DB_USER="app"; DB_PASSWORD=""; BIND="127.0.0.1"; PORT="3306"; BACKUP_DIR="/var/backups/easy-install/mysql"; FORCE="false"; PURGE_DATA="false"; ASSUME_YES="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu MySQL 一键部署与管理
用法：
  sudo ./mysql.sh [install] [选项]  安装 MySQL 并创建数据库（默认）
  sudo ./mysql.sh create [选项]     创建或更新数据库和用户
  sudo ./mysql.sh backup [选项]     备份数据库
  sudo ./mysql.sh list              列出数据库和用户
  sudo ./mysql.sh status            查看服务状态
  sudo ./mysql.sh uninstall         卸载 MySQL
选项：
  --database NAME      数据库名（默认 app）
  --user NAME          数据库用户名（默认 app）
  --password VALUE     数据库密码（默认随机生成）
  --bind ADDRESS       监听地址（默认 127.0.0.1；远程可用 0.0.0.0）
  --port PORT          监听端口（默认 3306）
  --backup-dir DIR     备份目录（默认 /var/backups/easy-install/mysql）
  --force              覆盖已有用户密码和数据库所有权
  --purge-data         卸载时删除 /var/lib/mysql 和配置
  -y, --yes            无交互执行
  --dry-run            仅演练 install
  --verbose            显示详细命令
  -h, --help           显示帮助
  -V, --version        显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|create|backup|list|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --database) DB_NAME="${2:?缺少数据库名}"; shift 2;; --user) DB_USER="${2:?缺少用户名}"; shift 2;; --password) DB_PASSWORD="${2:?缺少密码}"; shift 2;; --bind) BIND="${2:?缺少监听地址}"; shift 2;; --port) PORT="${2:?缺少端口}"; shift 2;; --backup-dir) BACKUP_DIR="${2:?缺少目录}"; shift 2;; --force) FORCE="true"; shift;; --purge-data) PURGE_DATA="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ [[ "$DB_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || die "数据库名格式无效。"; [[ "$DB_USER" =~ ^[A-Za-z_][A-Za-z0-9_]{0,31}$ ]] || die "用户名格式无效。"; [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" =~ ^[A-Za-z0-9_.:@%+=,-]+$ ]] || die "密码只能包含安全的可打印字符。"; [[ "$BIND" == localhost || "$BIND" =~ ^[A-Fa-f0-9:.]+$ ]] || die "监听地址无效。"; if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT<1||PORT>65535)); then die "端口无效。"; fi; [[ "$BACKUP_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "备份目录必须是安全的绝对路径。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
password(){ [[ -n "$DB_PASSWORD" ]] || DB_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"; }
configure(){ local conf="/etc/mysql/mysql.conf.d/easy-install.cnf" temp backup=""; temp="$(mktemp /etc/mysql/mysql.conf.d/.easy-install.XXXXXX)"; cat >"$temp" <<EOF_CONF
[mysqld]
bind-address = ${BIND}
port = ${PORT}
local_infile = 0
skip_name_resolve = ON
EOF_CONF
chmod 644 "$temp"; mysqld --defaults-extra-file="$temp" --validate-config >/dev/null; if [[ -e "$conf" ]]; then backup="$(mktemp /etc/mysql/mysql.conf.d/.easy-install-backup.XXXXXX)"; cp -a "$conf" "$backup"; fi; mv "$temp" "$conf"; if ! systemctl restart mysql; then if [[ -n "$backup" ]]; then mv "$backup" "$conf"; else rm -f "$conf"; fi; systemctl restart mysql || true; die "MySQL 新配置启动失败，已恢复原配置。"; fi; [[ -z "$backup" ]] || rm -f "$backup"; }
create_db(){ password; local exists; exists="$(mysql --batch --skip-column-names -e "SELECT COUNT(*) FROM mysql.user WHERE user='${DB_USER}' AND host='%';")"; if [[ "$exists" == 0 ]]; then mysql --execute="CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"; else [[ "$FORCE" == true ]] || die "用户已存在；使用 --force 更新密码。"; mysql --execute="ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"; fi; mysql --execute="CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%'; FLUSH PRIVILEGES;"; ok "数据库：$DB_NAME；用户：$DB_USER；密码：$DB_PASSWORD"; }
install_mysql(){ root_ubuntu; validate; password; [[ "$BIND" == 127.0.0.1 || "$BIND" == localhost || "$BIND" == ::1 ]] || warn "远程 MySQL 暴露风险高，请仅向可信 CIDR 开放 TCP $PORT。"; confirm "安装 MySQL？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y mysql-server openssl; [[ "$DRY_RUN" == true ]] && { ok "演练完成；生成密码不会写入系统。"; return; }; systemctl enable --now mysql; configure; create_db; }
create(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "create 不支持 --dry-run。"; create_db; }
backup(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "backup 不支持 --dry-run。"; install -d -m 700 "$BACKUP_DIR"; local out; out="$BACKUP_DIR/${DB_NAME}-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"; mysqldump --single-transaction --databases "$DB_NAME" | gzip -9 >"$out"; chmod 600 "$out"; ok "备份：$out"; }
list(){ root_ubuntu; mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user ORDER BY user,host;'; }
status(){ root_ubuntu; systemctl --no-pager --full status mysql || true; mysqladmin ping; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 MySQL？" || die "已取消。"; systemctl disable --now mysql 2>/dev/null || true; apt-get purge -y mysql-server mysql-client mysql-common; if [[ "$PURGE_DATA" == true ]]; then rm -rf /var/lib/mysql /etc/mysql /var/log/mysql; else warn "MySQL 数据仍保留在 /var/lib/mysql。"; fi; ok "MySQL 已卸载。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_mysql;; create) create;; backup) backup;; list) list;; status) status;; uninstall) uninstall;; esac; }
main "$@"
