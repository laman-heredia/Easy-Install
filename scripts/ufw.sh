#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"
COMMAND="install"; SSH_PORT="22"; ALLOW_PORTS="80,443"; DEFAULT_INCOMING="deny"; DEFAULT_OUTGOING="allow"; ASSUME_YES="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu UFW 防火墙一键初始化
用法：
  sudo ./ufw.sh [install] [选项]  安装并启用 UFW（默认）
  sudo ./ufw.sh allow --ports LIST  放行端口列表
  sudo ./ufw.sh status              查看规则
  sudo ./ufw.sh reset               重置 UFW
选项：
  --ssh-port PORT      SSH 端口，始终优先放行（默认 22）
  --ports LIST         逗号分隔端口或端口/协议，如 80,443,51820/udp
  --incoming POLICY    默认入站策略 deny/reject/allow（默认 deny）
  --outgoing POLICY    默认出站策略 allow/deny/reject（默认 allow）
  -y, --yes            无交互执行
  --dry-run            仅演练 install/allow
  --verbose            显示详细命令
  -h, --help           显示帮助
  -V, --version        显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|allow|status|reset)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --ssh-port) SSH_PORT="${2:?缺少端口}"; shift 2;; --ports) ALLOW_PORTS="${2:?缺少端口列表}"; shift 2;; --incoming) DEFAULT_INCOMING="${2:?缺少策略}"; shift 2;; --outgoing) DEFAULT_OUTGOING="${2:?缺少策略}"; shift 2;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
valid_port(){ [[ "$1" =~ ^([0-9]{1,5})(/(tcp|udp))?$ ]] && ((${BASH_REMATCH[1]}>=1&&${BASH_REMATCH[1]}<=65535)); }
validate(){ valid_port "$SSH_PORT" || die "SSH 端口无效。"; [[ "$DEFAULT_INCOMING" =~ ^(deny|reject|allow)$ ]] || die "入站策略无效。"; [[ "$DEFAULT_OUTGOING" =~ ^(allow|deny|reject)$ ]] || die "出站策略无效。"; [[ -n "$ALLOW_PORTS" ]] || die "端口列表不能为空。"; IFS=',' read -ra ports <<<"$ALLOW_PORTS"; ((${#ports[@]} > 0)) || die "端口列表不能为空。"; for port in "${ports[@]}"; do [[ -z "$port" ]] && die "端口列表不能为空。"; valid_port "$port" || die "端口无效：$port"; done; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
allow_ports(){ run ufw allow "${SSH_PORT}/tcp" comment 'Easy Install SSH'; IFS=',' read -ra ports <<<"$ALLOW_PORTS"; for port in "${ports[@]}"; do run ufw allow "$port" comment 'Easy Install service'; done; }
install_ufw(){ root_ubuntu; validate; confirm "启用 UFW？请确认 SSH 端口 $SSH_PORT 已正确。" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y ufw; run ufw default "$DEFAULT_INCOMING" incoming; run ufw default "$DEFAULT_OUTGOING" outgoing; allow_ports; run ufw --force enable; ok "UFW 已启用。"; }
allow(){ root_ubuntu; validate; [[ "$DRY_RUN" == true ]] || command -v ufw >/dev/null || die "请先执行 install。"; allow_ports; [[ "$DRY_RUN" == true ]] || ufw reload; ok "规则已更新。"; }
status(){ root_ubuntu; ufw status verbose; }
reset(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "reset 不支持 --dry-run。"; confirm "确定重置 UFW？" || die "已取消。"; ufw --force reset; ok "UFW 已重置。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" =~ ^(install|allow)$ ]] || die "--dry-run 仅支持 install/allow。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_ufw;; allow) allow;; status) status;; reset) reset;; esac; }
main "$@"
