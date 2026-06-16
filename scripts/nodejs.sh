#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"
COMMAND="install"; readonly START_CMD_RE='^[A-Za-z0-9_./: @%+=,-]+$'; MAJOR="22"; USER_NAME=""; APP_DIR=""; SERVICE_NAME=""; START_CMD="npm start"; PORT="3000"; ASSUME_YES="false"; FORCE="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Node.js 一键部署与 systemd 管理
用法：
  sudo ./nodejs.sh [install] [选项]   安装 Node.js LTS 与构建工具（默认）
  sudo ./nodejs.sh service [选项]     为已有应用创建 systemd 服务
  sudo ./nodejs.sh status             查看 Node.js/npm 和服务状态
  sudo ./nodejs.sh uninstall          卸载 Node.js
选项：
  --major VERSION       Node.js 主版本（默认 22；支持 20/22/24）
  --user NAME           运行应用的系统用户
  --app-dir DIR         应用目录（service 必需）
  --service NAME        systemd 服务名（默认从目录名生成）
  --start-cmd CMD       启动命令（默认 npm start）
  --port PORT           注入 PORT 环境变量（默认 3000）
  --force               覆盖已有 systemd unit
  -y, --yes             无交互执行
  --dry-run             仅演练 install/service
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|service|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --major) MAJOR="${2:?缺少版本}"; shift 2;; --user) USER_NAME="${2:?缺少用户}"; shift 2;; --app-dir) APP_DIR="${2:?缺少目录}"; shift 2;; --service) SERVICE_NAME="${2:?缺少服务名}"; shift 2;; --start-cmd) START_CMD="${2:?缺少命令}"; shift 2;; --port) PORT="${2:?缺少端口}"; shift 2;; --force) FORCE="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ [[ "$MAJOR" =~ ^(20|22|24)$ ]] || die "--major 仅支持 20/22/24。"; [[ -z "$USER_NAME" || "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "用户名格式无效。"; [[ -z "$APP_DIR" || "$APP_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "--app-dir 必须是安全的绝对路径。"; [[ -z "$SERVICE_NAME" || "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "服务名格式无效。"; [[ "$START_CMD" =~ $START_CMD_RE ]] || die "启动命令包含不安全字符。"; if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT<1||PORT>65535)); then die "端口无效。"; fi; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
install_node(){ root_ubuntu; validate; confirm "安装 Node.js $MAJOR？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y ca-certificates curl gnupg build-essential; run install -d -m 0755 /etc/apt/keyrings; if [[ "$DRY_RUN" == true ]]; then run curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.gpg; echo "[dry-run] write /etc/apt/sources.list.d/nodesource.list for nodistro node_$MAJOR.x"; ok "演练完成。"; return; fi; curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; chmod a+r /etc/apt/keyrings/nodesource.gpg; echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${MAJOR}.x nodistro main" >/etc/apt/sources.list.d/nodesource.list; apt-get update -q; apt-get install -y nodejs; npm install -g npm@latest; node --version; npm --version; ok "Node.js 已安装。"; }
service(){ root_ubuntu; validate; [[ -n "$APP_DIR" ]] || die "service 需要 --app-dir。"; [[ -n "$USER_NAME" ]] || USER_NAME="www-data"; [[ -n "$SERVICE_NAME" ]] || SERVICE_NAME="easy-install-$(basename "$APP_DIR")"; local unit="/etc/systemd/system/${SERVICE_NAME}.service"; if [[ "$DRY_RUN" == true ]]; then echo "[dry-run] write $unit and restart service as $USER_NAME"; return; fi; [[ -d "$APP_DIR" ]] || die "应用目录不存在：$APP_DIR"; id "$USER_NAME" >/dev/null || die "用户不存在：$USER_NAME"; [[ ! -e "$unit" || "$FORCE" == true ]] || die "服务已存在；使用 --force 覆盖。"; local temp; temp="$(mktemp /etc/systemd/system/.easy-install-node.XXXXXX)"; cat >"$temp" <<EOF_UNIT
[Unit]
Description=Easy Install Node.js service ${SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
Environment=PORT=${PORT}
ExecStart=/usr/bin/env bash -lc '${START_CMD}'
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF_UNIT
chmod 644 "$temp"; mv "$temp" "$unit"; systemd-analyze verify "$unit"; systemctl daemon-reload; systemctl enable --now "$SERVICE_NAME"; ok "服务已启动：$SERVICE_NAME"; }
status(){ root_ubuntu; node --version; npm --version; [[ -z "$SERVICE_NAME" ]] || systemctl --no-pager --full status "$SERVICE_NAME" || true; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Node.js？" || die "已取消。"; apt-get purge -y nodejs; rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg; apt-get update -q; ok "Node.js 已卸载；应用目录未删除。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" =~ ^(install|service)$ ]] || die "--dry-run 仅支持 install/service。"; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_node;; service) service;; status) root_ubuntu; validate; status;; uninstall) uninstall;; esac; }
main "$@"
