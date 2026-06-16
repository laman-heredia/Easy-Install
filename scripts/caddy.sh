#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"; readonly CADDYFILE="/etc/caddy/Caddyfile"; readonly BACKUP="/etc/caddy/Caddyfile.easy-install.bak"
COMMAND="install"; DOMAIN=":80"; ROOT_DIR=""; PROXY_PASS=""; EMAIL=""; FORCE="false"; KEEP_DATA="false"; ASSUME_YES="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Caddy 一键部署与自动 HTTPS
用法：
  sudo ./caddy.sh [install] [选项]  安装 Caddy 并写入站点（默认）
  sudo ./caddy.sh reload             校验并重载配置
  sudo ./caddy.sh status             查看服务状态
  sudo ./caddy.sh uninstall          卸载 Caddy
选项：
  --domain DOMAIN       域名，默认 :80（无自动 HTTPS）
  --root DIR            静态站点目录
  --proxy URL           反向代理地址，如 http://127.0.0.1:3000
  --email EMAIL         ACME 邮箱（可选）
  --force               覆盖已有 Caddyfile
  --keep-data           卸载时保留配置和站点文件
  -y, --yes             无交互执行
  --dry-run             仅演练 install
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|reload|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --domain) DOMAIN="${2:?缺少域名}"; shift 2;; --root) ROOT_DIR="${2:?缺少目录}"; shift 2;; --proxy) PROXY_PASS="${2:?缺少 URL}"; shift 2;; --email) EMAIL="${2:?缺少邮箱}"; shift 2;; --force) FORCE="true"; shift;; --keep-data) KEEP_DATA="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
valid_proxy(){ python3 - "$1" <<'PY'
from urllib.parse import urlsplit
import re, sys
try:
    p=urlsplit(sys.argv[1]); assert p.scheme in ('http','https') and p.hostname and not p.username and not p.password and not p.fragment
    assert re.fullmatch(r'[A-Za-z0-9_.:/?=&%~+\-]*', p.path + (('?' + p.query) if p.query else ''))
    if p.port is not None: assert 1 <= p.port <= 65535
except Exception:
    raise SystemExit(1)
PY
}
validate(){ [[ "$DOMAIN" == :80 || "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || die "域名格式无效。"; [[ -z "$ROOT_DIR" || "$ROOT_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "--root 必须是安全的绝对路径。"; [[ -z "$PROXY_PASS" ]] || valid_proxy "$PROXY_PASS" || die "反向代理 URL 无效。"; [[ -z "$ROOT_DIR" || -z "$PROXY_PASS" ]] || die "--root 与 --proxy 不能同时使用。"; [[ -z "$EMAIL" || "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "邮箱格式无效。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
write_caddyfile(){ [[ ! -e "$CADDYFILE" || "$FORCE" == true ]] || die "$CADDYFILE 已存在；使用 --force 覆盖。"; [[ -n "$ROOT_DIR" ]] || ROOT_DIR="/var/www/easy-install/caddy"; [[ -n "$PROXY_PASS" ]] || { install -d -m 755 "$ROOT_DIR"; [[ -e "$ROOT_DIR/index.html" ]] || printf '<!doctype html><meta charset="utf-8"><h1>Caddy is ready</h1>\n' >"$ROOT_DIR/index.html"; }; [[ ! -e "$CADDYFILE" || -e "$BACKUP" ]] || cp -a "$CADDYFILE" "$BACKUP"; local temp; temp="$(mktemp /etc/caddy/.Caddyfile.XXXXXX)"; { [[ -z "$EMAIL" ]] || printf '{\n\temail %s\n}\n\n' "$EMAIL"; printf '%s {\n' "$DOMAIN"; if [[ -n "$PROXY_PASS" ]]; then printf '\treverse_proxy %s\n' "$PROXY_PASS"; else printf '\troot * %s\n\tfile_server\n' "$ROOT_DIR"; fi; printf '}\n'; } >"$temp"; caddy validate --config "$temp" >/dev/null; chmod 644 "$temp"; mv "$temp" "$CADDYFILE"; }
install_caddy(){ root_ubuntu; validate; confirm "安装 Caddy？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y caddy python3-minimal; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; write_caddyfile; systemctl enable --now caddy; systemctl reload caddy; ok "Caddy 已启用：$DOMAIN"; }
reload(){ root_ubuntu; caddy validate --config "$CADDYFILE"; systemctl reload caddy; ok "Caddy 已重载。"; }
status(){ root_ubuntu; caddy version; systemctl --no-pager --full status caddy || true; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Caddy？" || die "已取消。"; systemctl disable --now caddy 2>/dev/null || true; apt-get purge -y caddy; if [[ "$KEEP_DATA" == true ]]; then ok "已保留 Caddy 配置和站点文件。"; else rm -rf /etc/caddy /var/www/easy-install/caddy; fi; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_caddy;; reload) reload;; status) status;; uninstall) uninstall;; esac; }
main "$@"
