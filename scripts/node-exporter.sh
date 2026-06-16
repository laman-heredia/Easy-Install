#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"
COMMAND="install"; LISTEN="127.0.0.1:9100"; EXTRA_ARGS=""; ASSUME_YES="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Prometheus Node Exporter 一键部署
用法：
  sudo ./node-exporter.sh [install] [选项]  安装并启动 node_exporter（默认）
  sudo ./node-exporter.sh status            查看指标端点和服务
  sudo ./node-exporter.sh uninstall         卸载 node_exporter
选项：
  --listen ADDRESS:PORT  监听地址（默认 127.0.0.1:9100）
  --extra-args ARGS      额外安全参数，如 --collector.systemd
  -y, --yes              无交互执行
  --dry-run              仅演练 install
  --verbose              显示详细命令
  -h, --help             显示帮助
  -V, --version          显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --listen) LISTEN="${2:?缺少监听地址}"; shift 2;; --extra-args) EXTRA_ARGS="${2:?缺少参数}"; shift 2;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ [[ "$LISTEN" =~ ^[A-Fa-f0-9:.]+:[0-9]{1,5}$ ]] || die "监听地址格式无效。"; local port="${LISTEN##*:}"; ((port>=1&&port<=65535)) || die "监听端口无效。"; [[ -z "$EXTRA_ARGS" || "$EXTRA_ARGS" =~ ^[A-Za-z0-9_.=,:/\ -]+$ ]] || die "额外参数包含不安全字符。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
write_defaults(){ local file="/etc/default/prometheus-node-exporter" temp; temp="$(mktemp /etc/default/.prometheus-node-exporter.XXXXXX)"; printf 'ARGS="--web.listen-address=%s %s"\n' "$LISTEN" "$EXTRA_ARGS" >"$temp"; chmod 644 "$temp"; mv "$temp" "$file"; }
install_exporter(){ root_ubuntu; validate; [[ "$LISTEN" == 127.0.0.1:* || "$LISTEN" == ::1:* ]] || log "请使用防火墙限制 Node Exporter 指标端口。"; confirm "安装 Prometheus Node Exporter？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y prometheus-node-exporter; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; write_defaults; systemctl enable --now prometheus-node-exporter; systemctl restart prometheus-node-exporter; ok "Node Exporter 已启动：$LISTEN"; }
status(){ root_ubuntu; systemctl --no-pager --full status prometheus-node-exporter || true; curl -fsS "http://${LISTEN}/metrics" | head -n 10 || true; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Node Exporter？" || die "已取消。"; systemctl disable --now prometheus-node-exporter 2>/dev/null || true; apt-get purge -y prometheus-node-exporter; rm -f /etc/default/prometheus-node-exporter; ok "Node Exporter 已卸载。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_exporter;; status) status;; uninstall) uninstall;; esac; }
main "$@"
