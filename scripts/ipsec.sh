#!/usr/bin/env bash
# Easy Install - Ubuntu IKEv2/IPsec server installer
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly PROGRAM="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/etc/ipsec.d/easy-install"
readonly SETTINGS_FILE="${CONFIG_DIR}/settings.env"
readonly USERS_FILE="${CONFIG_DIR}/users.tsv"
readonly IPSEC_CONF="/etc/ipsec.conf"
readonly IPSEC_SECRETS="/etc/ipsec.secrets"
readonly FIREWALL_SCRIPT="/usr/local/lib/easy-install/ipsec-firewall.sh"
readonly FIREWALL_SERVICE="/etc/systemd/system/easy-install-ipsec-firewall.service"
readonly SYSCTL_FILE="/etc/sysctl.d/99-easy-install-ipsec.conf"

COMMAND="install"
USERNAME="vpnuser"
PASSWORD=""
ENDPOINT=""
VPN_POOL="10.10.10.0/24"
DNS_MODE="cloudflare"
CUSTOM_DNS=""
OUTPUT_DIR="$PWD"
IKE_PROPOSALS="aes256gcm16-aes128gcm16-prfsha384-prfsha256-ecp384-ecp256,aes256-sha256-modp2048"
ESP_PROPOSALS="aes256gcm16-aes128gcm16-ecp384-ecp256,aes256-sha256"
CERT_DAYS="3650"
ROUTE_ALL="true"
ASSUME_YES="false"
FORCE="false"
KEEP_CA="false"
DRY_RUN="false"
VERBOSE="false"

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run() { if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败，可加 --verbose 查看详情。"' ERR

usage() {
  cat <<'USAGE'
Ubuntu IKEv2/IPsec 一键部署与管理（strongSwan）

用法：
  sudo ./ipsec.sh [install] [选项]  安装服务并创建首个账号（默认）
  sudo ./ipsec.sh add [选项]        添加或更新账号
  sudo ./ipsec.sh remove [选项]     删除账号
  sudo ./ipsec.sh list              列出账号（不显示密码）
  sudo ./ipsec.sh status            查看服务状态
  sudo ./ipsec.sh export [选项]     重新导出客户端资料
  sudo ./ipsec.sh uninstall         卸载配置

懒人用法：
  sudo ./ipsec.sh
  sudo ./ipsec.sh --yes --endpoint vpn.example.com
  sudo ./ipsec.sh add --user phone
  sudo ./ipsec.sh remove --user old-phone

常用选项：
  --user NAME                VPN 用户名（默认 vpnuser）
  --password PASSWORD        密码（默认生成高强度随机密码）
  --endpoint HOST            公网 IP 或域名（默认自动探测）
  --pool CIDR                客户端 IPv4 地址池（默认 10.10.10.0/24）
  --dns MODE                 cloudflare/google/quad9/system/custom
  --custom-dns IP[,IP]       自定义 DNS
  --output DIR               客户端资料输出目录（默认当前目录）
  -y, --yes                  无交互安装

高级选项：
  --ike PROPOSALS            strongSwan IKE 加密提议
  --esp PROPOSALS            strongSwan ESP 加密提议
  --cert-days DAYS           CA/服务端证书有效天数（默认 3650）
  --split-tunnel             只路由 VPN 地址池（需客户端另配业务路由）
  --force                    覆盖已有安装或更新同名账号
  --keep-ca                  卸载时保留 CA、账号和导出资料
  --dry-run                  展示安装命令，不修改系统
  --verbose                  输出详细执行过程
  -h, --help                 显示帮助
  -V, --version              显示版本

协议：IKEv2 + EAP-MSCHAPv2；服务端使用私有 CA 签发的证书。
需在云安全组和外部防火墙放行 UDP 500、UDP 4500。
USAGE
}

parse_args() {
  if [[ ${1:-} =~ ^(install|add|remove|list|status|export|uninstall)$ ]]; then COMMAND="$1"; shift; fi
  while (($#)); do
    case "$1" in
      --user) USERNAME="${2:?--user 缺少参数}"; shift 2;;
      --password) PASSWORD="${2:?--password 缺少参数}"; shift 2;;
      --endpoint) ENDPOINT="${2:?--endpoint 缺少参数}"; shift 2;;
      --pool) VPN_POOL="${2:?--pool 缺少参数}"; shift 2;;
      --dns) DNS_MODE="${2:?--dns 缺少参数}"; shift 2;;
      --custom-dns) CUSTOM_DNS="${2:?--custom-dns 缺少参数}"; shift 2;;
      --output) OUTPUT_DIR="${2:?--output 缺少参数}"; shift 2;;
      --ike) IKE_PROPOSALS="${2:?--ike 缺少参数}"; shift 2;;
      --esp) ESP_PROPOSALS="${2:?--esp 缺少参数}"; shift 2;;
      --cert-days) CERT_DAYS="${2:?--cert-days 缺少参数}"; shift 2;;
      --split-tunnel) ROUTE_ALL="false"; shift;;
      -y|--yes) ASSUME_YES="true"; shift;;
      --force) FORCE="true"; shift;;
      --keep-ca) KEEP_CA="true"; shift;;
      --dry-run) DRY_RUN="true"; shift;;
      --verbose) VERBOSE="true"; shift;;
      -h|--help) usage; exit 0;;
      -V|--version) echo "$SCRIPT_VERSION"; exit 0;;
      *) die "未知参数：$1（使用 --help 查看帮助）";;
    esac
  done
}

validate() {
  [[ "$USERNAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}$ ]] || die "用户名格式无效，最长 64 字符。"
  [[ -z "$ENDPOINT" || "$ENDPOINT" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "公网入口只能是 IP 地址或域名。"
  [[ "$VPN_POOL" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([8-9]|[12][0-9]|3[0-0])$ ]] || die "地址池必须是 /8 到 /30 的 IPv4 CIDR。"
  [[ "$DNS_MODE" =~ ^(cloudflare|google|quad9|system|custom)$ ]] || die "不支持的 DNS 模式。"
  [[ "$DNS_MODE" != custom || -n "$CUSTOM_DNS" ]] || die "--dns custom 需要 --custom-dns。"
  [[ "$CUSTOM_DNS" =~ ^[A-Fa-f0-9:.,]*$ ]] || die "自定义 DNS 只能是逗号分隔的 IP 地址。"
  [[ "$IKE_PROPOSALS" =~ ^[A-Za-z0-9_+!,.-]+$ ]] || die "IKE 提议包含无效字符。"
  [[ "$ESP_PROPOSALS" =~ ^[A-Za-z0-9_+!,.-]+$ ]] || die "ESP 提议包含无效字符。"
  if [[ ! "$CERT_DAYS" =~ ^[0-9]+$ ]] || ((CERT_DAYS < 30 || CERT_DAYS > 36500)); then die "证书有效期必须为 30-36500 天。"; fi
  [[ "$PASSWORD" != *$'\n'* && "$PASSWORD" != *$'\t'* && "$PASSWORD" != *'"'* && "$PASSWORD" != *\\* ]] || die "密码不能包含换行、制表符、双引号或反斜杠。"
}

require_root_ubuntu() {
  ((EUID == 0)) || die "请使用 root 权限运行：sudo $PROGRAM"
  [[ -r /etc/os-release ]] || die "无法识别操作系统。"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || die "当前仅支持 Ubuntu，检测到：${PRETTY_NAME:-未知系统}"
  case "${VERSION_ID:-}" in 20.04|22.04|24.04|26.04) ;; *) warn "Ubuntu ${VERSION_ID:-未知版本} 未经完整验证，将继续尝试。";; esac
}

confirm() {
  [[ "$ASSUME_YES" == true ]] && return 0
  read -r -p "$1 [Y/n] " answer
  [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]
}

detect_endpoint() {
  [[ -n "$ENDPOINT" ]] && return
  local candidate="" url
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    candidate="$(curl -4fsS --max-time 5 "$url" 2>/dev/null || true)"
    [[ "$candidate" =~ ^[0-9.]+$ ]] && { ENDPOINT="$candidate"; break; }
  done
  if [[ -z "$ENDPOINT" && "$ASSUME_YES" != true ]]; then read -r -p "请输入服务器公网 IP 或域名: " ENDPOINT; fi
  [[ -n "$ENDPOINT" ]] || die "无法探测公网地址，请使用 --endpoint 指定。"
}

default_interface() { ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'; }

pool_network() { printf '%s' "${VPN_POOL%/*}"; }

dns_value() {
  case "$DNS_MODE" in
    cloudflare) echo "1.1.1.1,1.0.0.1";;
    google) echo "8.8.8.8,8.8.4.4";;
    quad9) echo "9.9.9.9,149.112.112.112";;
    custom) echo "$CUSTOM_DNS";;
    system) awk '/^nameserver / && $2 !~ /^127\./ {a=a (a?",":"") $2; if(++n==2) exit} END {print a}' /etc/resolv.conf;;
  esac
}

load_settings() {
  [[ -r "$SETTINGS_FILE" ]] || die "未找到安装配置，请先执行 install。"
  # shellcheck disable=SC1090
  source "$SETTINGS_FILE"
}

save_settings() {
  install -d -m 700 "$CONFIG_DIR"
  cat >"$SETTINGS_FILE" <<EOF_SETTINGS
ENDPOINT=$(printf %q "$ENDPOINT")
VPN_POOL=$(printf %q "$VPN_POOL")
DNS_MODE=$(printf %q "$DNS_MODE")
CUSTOM_DNS=$(printf %q "$CUSTOM_DNS")
IKE_PROPOSALS=$(printf %q "$IKE_PROPOSALS")
ESP_PROPOSALS=$(printf %q "$ESP_PROPOSALS")
CERT_DAYS=$(printf %q "$CERT_DAYS")
ROUTE_ALL=$(printf %q "$ROUTE_ALL")
EOF_SETTINGS
  chmod 600 "$SETTINGS_FILE"
  touch "$USERS_FILE"; chmod 600 "$USERS_FILE"
}

install_packages() {
  log "安装 strongSwan、PKI 和 EAP 插件…"
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -q
  run apt-get install -y --no-install-recommends strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins iptables curl ca-certificates openssl
}

create_certificates() {
  install -d -m 700 "$CONFIG_DIR/private" "$CONFIG_DIR/cacerts" "$CONFIG_DIR/certs" "$CONFIG_DIR/export"
  log "创建私有 CA 和 IKEv2 服务端证书…"
  pki --gen --type rsa --size 4096 --outform pem >"$CONFIG_DIR/private/ca-key.pem"
  pki --self --ca --lifetime "$CERT_DAYS" --in "$CONFIG_DIR/private/ca-key.pem" --type rsa \
    --dn "CN=Easy Install IKEv2 CA" --outform pem >"$CONFIG_DIR/cacerts/ca-cert.pem"
  pki --gen --type rsa --size 3072 --outform pem >"$CONFIG_DIR/private/server-key.pem"
  pki --pub --in "$CONFIG_DIR/private/server-key.pem" --type rsa | pki --issue --lifetime "$CERT_DAYS" \
    --cacert "$CONFIG_DIR/cacerts/ca-cert.pem" --cakey "$CONFIG_DIR/private/ca-key.pem" \
    --dn "CN=$ENDPOINT" --san "$ENDPOINT" --flag serverAuth --flag ikeIntermediate \
    --outform pem >"$CONFIG_DIR/certs/server-cert.pem"
  install -m 600 "$CONFIG_DIR/private/server-key.pem" /etc/ipsec.d/private/easy-install-server-key.pem
  install -m 644 "$CONFIG_DIR/cacerts/ca-cert.pem" /etc/ipsec.d/cacerts/easy-install-ca-cert.pem
  install -m 644 "$CONFIG_DIR/certs/server-cert.pem" /etc/ipsec.d/certs/easy-install-server-cert.pem
}

write_ipsec_config() {
  local remote_ts="0.0.0.0/0"
  [[ "$ROUTE_ALL" == false ]] && remote_ts="$VPN_POOL"
  [[ -f "$IPSEC_CONF" && ! -f "${IPSEC_CONF}.easy-install.bak" ]] && cp -a "$IPSEC_CONF" "${IPSEC_CONF}.easy-install.bak"
  [[ -f "$IPSEC_SECRETS" && ! -f "${IPSEC_SECRETS}.easy-install.bak" ]] && cp -a "$IPSEC_SECRETS" "${IPSEC_SECRETS}.easy-install.bak"
  cat >"$IPSEC_CONF" <<EOF_CONF
config setup
    uniqueids=no

conn easy-install-ikev2
    auto=add
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=30s
    rekey=no
    left=%any
    leftid=${ENDPOINT}
    leftcert=easy-install-server-cert.pem
    leftsendcert=always
    leftsubnet=${remote_ts}
    leftfirewall=no
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=${VPN_POOL}
    rightdns=$(dns_value)
    rightsendcert=never
    eap_identity=%identity
    ike=${IKE_PROPOSALS}
    esp=${ESP_PROPOSALS}
EOF_CONF
  cat >"$IPSEC_SECRETS" <<EOF_SECRETS
: RSA easy-install-server-key.pem
# Easy Install managed EAP users follow. Do not edit manually.
EOF_SECRETS
  chmod 600 "$IPSEC_SECRETS"
}

write_network_config() {
  local iface
  iface="$(default_interface)"
  [[ -n "$iface" ]] || die "无法检测默认出口网卡。"
  cat >"$SYSCTL_FILE" <<EOF_SYSCTL
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF_SYSCTL
  install -d -m 755 "$(dirname "$FIREWALL_SCRIPT")"
  cat >"$FIREWALL_SCRIPT" <<EOF_FW
#!/usr/bin/env bash
set -euo pipefail
ACTION="\${1:-start}"
IPT="\$(command -v iptables)"
has() { "\$IPT" "\$@" 2>/dev/null; }
add() { has -C "\$@" || "\$IPT" -A "\$@"; }
del() { while has -C "\$@"; do "\$IPT" -D "\$@"; done; }
if [[ "\$ACTION" == start ]]; then
  add INPUT -p udp --dport 500 -j ACCEPT
  add INPUT -p udp --dport 4500 -j ACCEPT
  add FORWARD -s ${VPN_POOL} -m policy --dir in --pol ipsec -j ACCEPT
  add FORWARD -d ${VPN_POOL} -m policy --dir out --pol ipsec -j ACCEPT
  add FORWARD -s ${VPN_POOL} -o ${iface} -j ACCEPT
  add FORWARD -d ${VPN_POOL} -i ${iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  add POSTROUTING -t nat -s ${VPN_POOL} -o ${iface} -m policy --dir out --pol none -j MASQUERADE
  add FORWARD -s ${VPN_POOL} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
else
  del INPUT -p udp --dport 500 -j ACCEPT
  del INPUT -p udp --dport 4500 -j ACCEPT
  del FORWARD -s ${VPN_POOL} -m policy --dir in --pol ipsec -j ACCEPT
  del FORWARD -d ${VPN_POOL} -m policy --dir out --pol ipsec -j ACCEPT
  del FORWARD -s ${VPN_POOL} -o ${iface} -j ACCEPT
  del FORWARD -d ${VPN_POOL} -i ${iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  del POSTROUTING -t nat -s ${VPN_POOL} -o ${iface} -m policy --dir out --pol none -j MASQUERADE
  del FORWARD -s ${VPN_POOL} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
fi
EOF_FW
  chmod 700 "$FIREWALL_SCRIPT"
  cat >"$FIREWALL_SERVICE" <<EOF_UNIT
[Unit]
Description=Easy Install IPsec firewall rules
Before=strongswan-starter.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${FIREWALL_SCRIPT} start
ExecStop=${FIREWALL_SCRIPT} stop

[Install]
WantedBy=multi-user.target
EOF_UNIT
  run sysctl --system
  run systemctl daemon-reload
  run systemctl enable --now easy-install-ipsec-firewall.service
}

generate_password() { openssl rand -base64 24 | tr -d '\n'; }

rebuild_secrets() {
  {
    printf ': RSA easy-install-server-key.pem\n'
    printf '# Easy Install managed EAP users follow. Do not edit manually.\n'
    while IFS=$'\t' read -r user password; do
      [[ -n "$user" ]] && printf '%s : EAP "%s"\n' "$user" "$password"
    done <"$USERS_FILE"
  } >"$IPSEC_SECRETS"
  chmod 600 "$IPSEC_SECRETS"
}

upsert_user() {
  [[ -n "$PASSWORD" ]] || PASSWORD="$(generate_password)"
  (( ${#PASSWORD} >= 12 )) || warn "密码短于 12 个字符，建议改用自动生成的高强度密码。"
  if awk -F'\t' -v user="$USERNAME" '$1==user {found=1} END {exit !found}' "$USERS_FILE"; then
    [[ "$FORCE" == true ]] || die "账号 $USERNAME 已存在；使用 --force 更新密码。"
    awk -F'\t' -v user="$USERNAME" '$1!=user' "$USERS_FILE" >"${USERS_FILE}.tmp"
    mv "${USERS_FILE}.tmp" "$USERS_FILE"
  fi
  printf '%s\t%s\n' "$USERNAME" "$PASSWORD" >>"$USERS_FILE"
  chmod 600 "$USERS_FILE"
  rebuild_secrets
  run ipsec rereadsecrets
  export_client
  success "IPsec 账号已创建：$USERNAME"
}

export_client() {
  local dir="$OUTPUT_DIR" profile="$OUTPUT_DIR/ipsec-${USERNAME}.txt"
  mkdir -p "$dir"
  install -m 644 "$CONFIG_DIR/cacerts/ca-cert.pem" "$dir/easy-install-ikev2-ca.pem"
  cat >"$profile" <<EOF_PROFILE
Easy Install IKEv2/IPsec 客户端资料
==================================
服务器: ${ENDPOINT}
VPN 类型: IKEv2
远程 ID / 服务器 ID: ${ENDPOINT}
用户名: ${USERNAME}
密码: ${PASSWORD:-（请使用创建账号时保存的密码）}
CA 证书: easy-install-ikev2-ca.pem

连接前必须在客户端安装并信任 CA 证书。Windows、macOS、iOS、Android
和 Linux 均可使用系统 IKEv2 客户端；认证方式选择「用户名和密码」。
EOF_PROFILE
  chmod 600 "$profile"
  success "客户端资料：$profile"
  log "CA 证书：$dir/easy-install-ikev2-ca.pem"
}

install_server() {
  require_root_ubuntu
  [[ ! -e "$SETTINGS_FILE" || "$FORCE" == true ]] || die "IPsec 已安装；使用 add 管理账号，或 --force 重装。"
  detect_endpoint; validate
  log "将安装 IKEv2/IPsec：入口 $ENDPOINT，地址池 $VPN_POOL，首个账号 $USERNAME"
  confirm "开始安装？" || die "已取消。"
  install_packages
  if [[ "$DRY_RUN" == true ]]; then success "演练完成，系统未被修改。"; return; fi
  if [[ -e "$SETTINGS_FILE" ]]; then
    systemctl disable --now easy-install-ipsec-firewall.service 2>/dev/null || true
    if [[ -x "$FIREWALL_SCRIPT" ]]; then "$FIREWALL_SCRIPT" stop || true; fi
    rm -rf "$CONFIG_DIR"
  fi
  save_settings; create_certificates; write_ipsec_config; write_network_config
  run systemctl enable --now strongswan-starter.service
  upsert_user
  run ipsec restart
  success "IKEv2/IPsec 安装完成。请放行 UDP 500 和 UDP 4500。"
}

add_user() { require_root_ubuntu; load_settings; upsert_user; }

remove_user() {
  require_root_ubuntu; load_settings
  awk -F'\t' -v user="$USERNAME" '$1==user {found=1} END {exit !found}' "$USERS_FILE" || die "账号 $USERNAME 不存在。"
  confirm "确定删除账号 $USERNAME？" || die "已取消。"
  awk -F'\t' -v user="$USERNAME" '$1!=user' "$USERS_FILE" >"${USERS_FILE}.tmp"; mv "${USERS_FILE}.tmp" "$USERS_FILE"
  rebuild_secrets
  run ipsec rereadsecrets
  success "账号 $USERNAME 已删除。"
}

list_users() { require_root_ubuntu; load_settings; printf 'IPsec 账号\n'; cut -f1 "$USERS_FILE" | sed '/^$/d;s/^/  - /'; }

show_status() { require_root_ubuntu; load_settings; printf '入口: %s\n地址池: %s\nDNS: %s\n\n' "$ENDPOINT" "$VPN_POOL" "$DNS_MODE"; ipsec statusall || true; }

export_existing() {
  require_root_ubuntu; load_settings
  if [[ -z "$PASSWORD" ]]; then PASSWORD="$(awk -F'\t' -v user="$USERNAME" '$1==user {print $2; exit}' "$USERS_FILE")"; fi
  [[ -n "$PASSWORD" ]] || die "账号 $USERNAME 不存在。"
  export_client
}

uninstall_server() {
  require_root_ubuntu
  confirm "确定卸载 IKEv2/IPsec 配置？" || die "已取消。"
  run systemctl disable --now easy-install-ipsec-firewall.service || true
  if [[ -x "$FIREWALL_SCRIPT" ]]; then run "$FIREWALL_SCRIPT" stop || true; fi
  run systemctl disable --now strongswan-starter.service || true
  rm -f "$FIREWALL_SCRIPT" "$FIREWALL_SERVICE" "$SYSCTL_FILE"
  rm -f /etc/ipsec.d/private/easy-install-server-key.pem /etc/ipsec.d/cacerts/easy-install-ca-cert.pem /etc/ipsec.d/certs/easy-install-server-cert.pem
  if [[ -f "${IPSEC_CONF}.easy-install.bak" ]]; then mv "${IPSEC_CONF}.easy-install.bak" "$IPSEC_CONF"; else rm -f "$IPSEC_CONF"; fi
  if [[ -f "${IPSEC_SECRETS}.easy-install.bak" ]]; then mv "${IPSEC_SECRETS}.easy-install.bak" "$IPSEC_SECRETS"; else rm -f "$IPSEC_SECRETS"; fi
  if [[ "$KEEP_CA" == true ]]; then warn "已保留 $CONFIG_DIR。"; else rm -rf "$CONFIG_DIR"; fi
  run systemctl daemon-reload; run sysctl --system
  success "IPsec 配置已卸载，软件包仍保留。"
}

main() {
  parse_args "$@"; validate
  [[ "$VERBOSE" == true ]] && set -x
  case "$COMMAND" in
    install) install_server;; add) add_user;; remove) remove_user;; list) list_users;;
    status) show_status;; export) export_existing;; uninstall) uninstall_server;;
  esac
}
main "$@"
