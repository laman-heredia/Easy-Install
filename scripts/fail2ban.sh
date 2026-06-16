#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"; readonly JAIL_LOCAL="/etc/fail2ban/jail.d/easy-install.local"
COMMAND="install"; SSH_PORT="22"; BANTIME="1h"; FINDTIME="10m"; MAXRETRY="5"; IGNORE_IP="127.0.0.1/8 ::1"; EXTRA_JAILS=""; ASSUME_YES="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Fail2ban 一键部署与 SSH 防爆破
用法：
  sudo ./fail2ban.sh [install] [选项]  安装并启用 SSH jail（默认）
  sudo ./fail2ban.sh status            查看 jail 状态
  sudo ./fail2ban.sh unban --ip IP     解除指定 IP 封禁
  sudo ./fail2ban.sh uninstall         卸载 Fail2ban
选项：
  --ssh-port PORT       SSH 端口（默认 22）
  --bantime TIME        封禁时长，如 1h/24h/3600（默认 1h）
  --findtime TIME       统计窗口，如 10m/1h（默认 10m）
  --maxretry COUNT      失败次数阈值（默认 5）
  --ignore-ip LIST      空格分隔白名单 CIDR/IP
  --jails LIST          额外 jail，逗号分隔：nginx-http-auth,sshd
  -y, --yes             无交互执行
  --dry-run             仅演练 install
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|status|unban|uninstall)$ ]]; then COMMAND="$1"; shift; fi; UNBAN_IP=""; while (($#)); do case "$1" in --ssh-port) SSH_PORT="${2:?缺少端口}"; shift 2;; --bantime) BANTIME="${2:?缺少时长}"; shift 2;; --findtime) FINDTIME="${2:?缺少时长}"; shift 2;; --maxretry) MAXRETRY="${2:?缺少次数}"; shift 2;; --ignore-ip) IGNORE_IP="${2:?缺少白名单}"; shift 2;; --jails) EXTRA_JAILS="${2:?缺少 jail}"; shift 2;; --ip) UNBAN_IP="${2:?缺少 IP}"; shift 2;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
valid_time(){ [[ "$1" =~ ^[1-9][0-9]*[smhdw]?$ ]]; }
validate(){ if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || ((SSH_PORT<1||SSH_PORT>65535)); then die "SSH 端口无效。"; fi; valid_time "$BANTIME" || die "bantime 无效。"; valid_time "$FINDTIME" || die "findtime 无效。"; [[ "$MAXRETRY" =~ ^[1-9][0-9]*$ ]] || die "maxretry 必须是正整数。"; [[ "$IGNORE_IP" =~ ^[A-Fa-f0-9:./\ ]+$ ]] || die "ignore-ip 只能包含 IP/CIDR 和空格。"; [[ -z "$EXTRA_JAILS" || "$EXTRA_JAILS" =~ ^[A-Za-z0-9_,.-]+$ ]] || die "jail 名称格式无效。"; [[ -z "$UNBAN_IP" || "$UNBAN_IP" =~ ^[A-Fa-f0-9:.]+$ ]] || die "IP 格式无效。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
write_jail(){ local temp; temp="$(mktemp /etc/fail2ban/jail.d/.easy-install.XXXXXX)"; cat >"$temp" <<EOF_JAIL
[DEFAULT]
bantime = ${BANTIME}
findtime = ${FINDTIME}
maxretry = ${MAXRETRY}
ignoreip = ${IGNORE_IP}
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
EOF_JAIL
IFS=',' read -ra jails <<<"$EXTRA_JAILS"; for jail in "${jails[@]}"; do [[ -z "$jail" || "$jail" == sshd ]] && continue; printf '\n[%s]\nenabled = true\n' "$jail" >>"$temp"; done; chmod 644 "$temp"; local backup=""; if [[ -e "$JAIL_LOCAL" ]]; then backup="$(mktemp /etc/fail2ban/jail.d/.easy-install-backup.XXXXXX)"; cp -a "$JAIL_LOCAL" "$backup"; fi; mv "$temp" "$JAIL_LOCAL"; if ! fail2ban-client -t -c /etc/fail2ban >/dev/null; then if [[ -n "$backup" ]]; then mv "$backup" "$JAIL_LOCAL"; else rm -f "$JAIL_LOCAL"; fi; die "Fail2ban 新配置校验失败，已恢复原配置。"; fi; [[ -z "$backup" ]] || rm -f "$backup"; }
install_fail2ban(){ root_ubuntu; validate; confirm "安装 Fail2ban 并保护 SSH？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y fail2ban; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; write_jail; systemctl enable --now fail2ban; systemctl restart fail2ban; ok "Fail2ban 已启用。"; }
status(){ root_ubuntu; fail2ban-client status; fail2ban-client status sshd || true; systemctl --no-pager --full status fail2ban || true; }
unban(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "unban 不支持 --dry-run。"; [[ -n "$UNBAN_IP" ]] || die "unban 需要 --ip。"; fail2ban-client set sshd unbanip "$UNBAN_IP"; ok "已解除封禁：$UNBAN_IP"; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Fail2ban？" || die "已取消。"; systemctl disable --now fail2ban 2>/dev/null || true; apt-get purge -y fail2ban; rm -f "$JAIL_LOCAL"; ok "Fail2ban 已卸载。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_fail2ban;; status) status;; unban) unban;; uninstall) uninstall;; esac; }
main "$@"
