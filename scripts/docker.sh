#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"
readonly KEYRING="/etc/apt/keyrings/docker.asc"
readonly SOURCE_FILE="/etc/apt/sources.list.d/docker.sources"
readonly DAEMON_FILE="/etc/docker/daemon.json"
COMMAND="install"; USER_NAME=""; DATA_ROOT=""; LOG_SIZE="10m"; LOG_FILES="3"; IPV6="false"; LIVE_RESTORE="true"; ASSUME_YES="false"; FORCE="false"; PURGE_DATA="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Docker Engine 一键部署与管理
用法：
  sudo ./docker.sh [install] [选项]  从 Docker 官方仓库安装（默认）
  sudo ./docker.sh upgrade           升级 Docker Engine 与插件
  sudo ./docker.sh status            查看版本、服务与磁盘状态
  sudo ./docker.sh uninstall [选项]  卸载 Docker
选项：
  --user NAME          将用户加入 docker 组（该组等同 root 权限）
  --data-root DIR      自定义 Docker 数据目录
  --log-size SIZE      单个容器日志上限（默认 10m）
  --log-files COUNT    保留日志文件数（默认 3）
  --ipv6               启用 Docker IPv6
  --no-live-restore    禁用 daemon 重启时容器存活
  --force              覆盖已有 daemon.json
  --purge-data         卸载时删除 /var/lib/docker、containerd 和自定义数据目录
  -y, --yes            无交互执行
  --dry-run            仅展示命令（仅 install/upgrade）
  --verbose            显示详细命令
  -h, --help           显示帮助
  -V, --version        显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|upgrade|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --user) USER_NAME="${2:?缺少用户名}"; shift 2;; --data-root) DATA_ROOT="${2:?缺少目录}"; shift 2;; --log-size) LOG_SIZE="${2:?缺少大小}"; shift 2;; --log-files) LOG_FILES="${2:?缺少数量}"; shift 2;; --ipv6) IPV6="true"; shift;; --no-live-restore) LIVE_RESTORE="false"; shift;; --force) FORCE="true"; shift;; --purge-data) PURGE_DATA="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ [[ -z "$USER_NAME" || "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "用户名格式无效。"; [[ "$LOG_SIZE" =~ ^[1-9][0-9]*[kKmMgG]$ ]] || die "--log-size 示例：10m。"; [[ "$LOG_FILES" =~ ^[1-9][0-9]*$ ]] || die "--log-files 必须是正整数。"; [[ -z "$DATA_ROOT" || "$DATA_ROOT" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "--data-root 必须是安全的绝对路径。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
repo(){ run install -m 0755 -d /etc/apt/keyrings; if [[ "$DRY_RUN" == true ]]; then run curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$KEYRING"; else curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$KEYRING"; chmod a+r "$KEYRING"; fi; local arch codename; arch="$(dpkg --print-architecture)"; codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"; if [[ "$DRY_RUN" == true ]]; then echo "[dry-run] write $SOURCE_FILE for $arch/$codename"; else cat >"$SOURCE_FILE" <<EOF_SOURCE
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: ${KEYRING}
EOF_SOURCE
fi; }
write_daemon(){ [[ ! -e "$DAEMON_FILE" || "$FORCE" == true ]] || die "$DAEMON_FILE 已存在；使用 --force 覆盖。"; install -d -m 755 /etc/docker; local temp; temp="$(mktemp /etc/docker/.daemon.json.XXXXXX)"; cat >"$temp" <<EOF_JSON
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "${LOG_SIZE}", "max-file": "${LOG_FILES}"},
  "live-restore": ${LIVE_RESTORE},
  "ipv6": ${IPV6}$( [[ -n "$DATA_ROOT" ]] && printf ',\n  "data-root": "%s"' "$DATA_ROOT" )
}
EOF_JSON
python3 -m json.tool "$temp" >/dev/null; chmod 600 "$temp"; mv "$temp" "$DAEMON_FILE"; }
install_docker(){ root_ubuntu; validate; confirm "安装 Docker Engine？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y ca-certificates curl python3-minimal; repo; run apt-get update -q; run apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true; run apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; write_daemon; systemctl enable --now docker; [[ -z "$USER_NAME" ]] || { id "$USER_NAME" >/dev/null || die "用户不存在：$USER_NAME"; usermod -aG docker "$USER_NAME"; warn "docker 组具有 root 权限，用户需重新登录。"; }; docker run --rm hello-world >/dev/null; ok "Docker Engine 安装完成。"; }
upgrade(){ root_ubuntu; run apt-get update -q; run apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; [[ "$DRY_RUN" == true ]] || systemctl restart docker; }
status(){ root_ubuntu; docker version; docker compose version; systemctl --no-pager --full status docker || true; docker system df || true; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Docker？" || die "已取消。"; systemctl disable --now docker containerd 2>/dev/null || true; apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; rm -f "$SOURCE_FILE" "$KEYRING" "$DAEMON_FILE"; if [[ "$PURGE_DATA" == true ]]; then rm -rf /var/lib/docker /var/lib/containerd; [[ -z "$DATA_ROOT" ]] || rm -rf -- "$DATA_ROOT"; else warn "镜像、容器和卷数据仍保留。"; fi; apt-get update -q; ok "Docker 已卸载。"; }
main(){ parse "$@"; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_docker;; upgrade) root_ubuntu; validate; upgrade;; status) status;; uninstall) uninstall;; esac; }
main "$@"
