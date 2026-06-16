#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"; readonly MANAGED_DIR="/etc/nginx/easy-install"; readonly WEB_ROOT_BASE="/var/www/easy-install"
COMMAND="install"; DOMAIN="default"; PORT="80"; ROOT_DIR=""; PROXY_PASS=""; MAX_BODY="10m"; EMAIL=""; ENABLE_TLS="false"; REDIRECT_HTTPS="true"; ASSUME_YES="false"; FORCE="false"; KEEP_DATA="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }; run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }; trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu Nginx 一键部署与站点管理
用法：
  sudo ./nginx.sh [install] [选项]  安装 Nginx 并创建站点（默认）
  sudo ./nginx.sh add [选项]        添加或更新站点
  sudo ./nginx.sh remove --domain D 删除站点
  sudo ./nginx.sh list              列出受管站点
  sudo ./nginx.sh status            检查配置与服务
  sudo ./nginx.sh uninstall         卸载 Nginx
选项：
  --domain DOMAIN       域名（默认 default，作为默认站点）
  --port PORT           监听端口（默认 80）
  --root DIR            静态站点目录
  --proxy URL           反向代理，例如 http://127.0.0.1:3000
  --max-body SIZE       请求体上限（默认 10m）
  --tls                 使用 Certbot 申请 Let's Encrypt 证书
  --email EMAIL         TLS 到期通知邮箱（--tls 必需）
  --no-https-redirect   TLS 后不强制跳转 HTTPS
  --force               覆盖同名站点
  --keep-data           卸载时保留站点文件和配置
  -y, --yes             无交互执行
  --dry-run             仅演练 install/add
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|add|remove|list|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --domain) DOMAIN="${2:?缺少域名}"; shift 2;; --port) PORT="${2:?缺少端口}"; shift 2;; --root) ROOT_DIR="${2:?缺少目录}"; shift 2;; --proxy) PROXY_PASS="${2:?缺少 URL}"; shift 2;; --max-body) MAX_BODY="${2:?缺少大小}"; shift 2;; --tls) ENABLE_TLS="true"; shift;; --email) EMAIL="${2:?缺少邮箱}"; shift 2;; --no-https-redirect) REDIRECT_HTTPS="false"; shift;; --force) FORCE="true"; shift;; --keep-data) KEEP_DATA="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
validate(){ [[ "$DOMAIN" == default || "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || die "域名格式无效。"; if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT<1||PORT>65535)); then die "端口无效。"; fi; [[ -z "$ROOT_DIR" || "$ROOT_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "--root 必须是安全的绝对路径。"; [[ -z "$PROXY_PASS" ]] || valid_proxy "$PROXY_PASS" || die "反向代理 URL 无效。"; [[ "$MAX_BODY" =~ ^[1-9][0-9]*[kKmMgG]$ ]] || die "--max-body 示例：10m。"; [[ "$ENABLE_TLS" != true || "$DOMAIN" != default ]] || die "默认站点不能申请 TLS。"; [[ "$ENABLE_TLS" != true || "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "--tls 需要有效 --email。"; [[ -z "$PROXY_PASS" || -z "$ROOT_DIR" ]] || die "--root 与 --proxy 不能同时使用。"; }
valid_proxy(){ python3 - "$1" <<'PY_PROXY'
from urllib.parse import urlsplit
import re, sys
try:
    value = sys.argv[1]
    parsed = urlsplit(value)
    assert parsed.scheme in ("http", "https") and parsed.hostname and not parsed.username and not parsed.password and not parsed.fragment
    assert re.fullmatch(r"[A-Za-z0-9_.:/?=&%~+\-]*", parsed.path + (("?" + parsed.query) if parsed.query else ""))
    if parsed.port is not None: assert 1 <= parsed.port <= 65535
except (AssertionError, ValueError):
    raise SystemExit(1)
PY_PROXY
}
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
ensure_bootstrap(){ command -v python3 >/dev/null && return; [[ "$DRY_RUN" != true ]] || die "演练模式需要预先安装 python3。"; apt-get update -q; apt-get install -y --no-install-recommends python3-minimal; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
site_name(){ [[ "$DOMAIN" == default ]] && echo default || echo "$DOMAIN"; }
write_site(){ local name conf temp listen server_name location tls_flag backup="" had_default="false"; name="$(site_name)"; conf="/etc/nginx/sites-available/easy-install-${name}.conf"; [[ ! -e "$conf" || "$FORCE" == true ]] || die "站点已存在；使用 --force 更新。"; [[ -n "$ROOT_DIR" ]] || ROOT_DIR="$WEB_ROOT_BASE/$name"; listen="$PORT"; server_name="$DOMAIN"; [[ "$DOMAIN" == default ]] && { listen="$PORT default_server"; server_name="_"; }; if [[ -n "$PROXY_PASS" ]]; then location="proxy_pass ${PROXY_PASS};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";"; else install -d -m 755 "$ROOT_DIR"; [[ -e "$ROOT_DIR/index.html" ]] || printf '<!doctype html><meta charset="utf-8"><title>%s</title><h1>%s is ready</h1>\n' "$DOMAIN" "$DOMAIN" >"$ROOT_DIR/index.html"; location="root ${ROOT_DIR};
        index index.html;
        try_files \$uri \$uri/ =404;"; fi; temp="$(mktemp /etc/nginx/sites-available/.easy-install.XXXXXX)"; cat >"$temp" <<EOF_CONF
server {
    listen ${listen};
    listen [::]:${listen};
    server_name ${server_name};
    client_max_body_size ${MAX_BODY};
    location / {
        ${location}
    }
}
EOF_CONF
chmod 644 "$temp"; if [[ -e "$conf" ]]; then backup="$(mktemp /etc/nginx/sites-available/.easy-install-backup.XXXXXX)"; cp -a "$conf" "$backup"; fi; [[ ! -e /etc/nginx/sites-enabled/default ]] || had_default="true"; mv "$temp" "$conf"; ln -sfn "$conf" "/etc/nginx/sites-enabled/easy-install-${name}.conf"; [[ "$name" != default ]] || rm -f /etc/nginx/sites-enabled/default; if ! nginx -t; then if [[ -n "$backup" ]]; then mv "$backup" "$conf"; ln -sfn "$conf" "/etc/nginx/sites-enabled/easy-install-${name}.conf"; else rm -f "$conf" "/etc/nginx/sites-enabled/easy-install-${name}.conf"; fi; [[ "$had_default" != true ]] || ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default; die "Nginx 新配置校验失败，已恢复原配置。"; fi; [[ -z "$backup" ]] || rm -f "$backup"; systemctl reload nginx; if [[ "$ENABLE_TLS" == true ]]; then [[ "$REDIRECT_HTTPS" == true ]] && tls_flag="--redirect" || tls_flag="--no-redirect"; certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive "$tls_flag"; fi; ok "站点已启用：http://${DOMAIN}:$PORT"; }
install_nginx(){ root_ubuntu; ensure_bootstrap; validate; confirm "安装 Nginx？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y nginx python3-minimal; [[ "$ENABLE_TLS" == true ]] && run apt-get install -y certbot python3-certbot-nginx; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; install -d -m 755 "$MANAGED_DIR"; systemctl enable --now nginx; write_site; }
add(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || { echo "[dry-run] create site $DOMAIN on port $PORT"; return; }; command -v nginx >/dev/null || die "请先执行 install。"; [[ "$ENABLE_TLS" != true || -x /usr/bin/certbot ]] || apt-get install -y certbot python3-certbot-nginx; write_site; }
remove(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "remove 不支持 --dry-run。"; local name; name="$(site_name)"; confirm "删除站点 $name？" || die "已取消。"; rm -f "/etc/nginx/sites-enabled/easy-install-${name}.conf" "/etc/nginx/sites-available/easy-install-${name}.conf"; nginx -t; systemctl reload nginx; ok "站点已删除。"; }
list(){ root_ubuntu; find /etc/nginx/sites-enabled -maxdepth 1 -type l -name 'easy-install-*.conf' -printf '%f -> %l\n' | sort; }
status(){ root_ubuntu; nginx -t; systemctl --no-pager --full status nginx || true; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 Nginx？" || die "已取消。"; systemctl disable --now nginx 2>/dev/null || true; apt-get purge -y nginx nginx-common nginx-core python3-certbot-nginx; if [[ "$KEEP_DATA" == true ]]; then warn "已保留站点文件与配置。"; else rm -rf "$MANAGED_DIR" "$WEB_ROOT_BASE" /etc/nginx/sites-available/easy-install-*.conf /etc/nginx/sites-enabled/easy-install-*.conf; fi; ok "Nginx 已卸载。"; }
main(){ parse "$@"; [[ "$COMMAND" == install ]] || validate; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_nginx;; add) add;; remove) remove;; list) list;; status) status;; uninstall) uninstall;; esac; }
main "$@"
