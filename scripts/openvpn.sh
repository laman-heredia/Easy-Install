#!/usr/bin/env bash
# Easy Install - Ubuntu OpenVPN server installer
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly PROGRAM="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/etc/openvpn/easy-install"
readonly SERVER_DIR="/etc/openvpn/server"
readonly SERVER_CONF="${SERVER_DIR}/server.conf"
readonly PKI_DIR="${CONFIG_DIR}/pki"
readonly CLIENT_DIR="${CONFIG_DIR}/clients"
readonly SETTINGS_FILE="${CONFIG_DIR}/settings.env"
readonly FIREWALL_SCRIPT="/usr/local/lib/easy-install/openvpn-firewall.sh"
readonly FIREWALL_SERVICE="/etc/systemd/system/easy-install-openvpn-firewall.service"
readonly SYSCTL_FILE="/etc/sysctl.d/99-easy-install-openvpn.conf"

COMMAND="install"
CLIENT_NAME="client"
ENDPOINT=""
PORT="1194"
PROTOCOL="udp"
VPN_SUBNET="10.8.0.0"
VPN_NETMASK="255.255.255.0"
DNS_MODE="cloudflare"
CUSTOM_DNS=""
OUTPUT_DIR="${PWD}"
CIPHER="AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305"
AUTH="SHA256"
TLS_MODE="tls-crypt"
IPV6="false"
IPV6_SUBNET="fd42:42:42:42::/64"
ROUTE_ALL="true"
COMPRESSION="false"
KEEP_CA="false"
ASSUME_YES="false"
FORCE="false"
VERBOSE="false"
DRY_RUN="false"

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run() {
  if [[ "$DRY_RUN" == "true" ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi
}
trap 'die "第 ${LINENO} 行执行失败。可使用 --verbose 查看详情。"' ERR

usage() {
  cat <<'USAGE'
Ubuntu OpenVPN 一键部署与管理

用法：
  sudo ./openvpn.sh [install] [选项]  安装服务并创建首个客户端（默认）
  sudo ./openvpn.sh add [选项]        添加客户端
  sudo ./openvpn.sh revoke [选项]     吊销客户端
  sudo ./openvpn.sh list              列出客户端证书
  sudo ./openvpn.sh status            查看服务状态与配置
  sudo ./openvpn.sh uninstall [选项]  卸载服务

懒人用法：
  sudo ./openvpn.sh
  sudo ./openvpn.sh --yes --client phone
  sudo ./openvpn.sh add --client laptop
  sudo ./openvpn.sh revoke --client old-phone

常用选项：
  --client NAME             客户端名称（默认 client）
  --endpoint HOST           公网 IP 或域名（默认自动探测）
  --port PORT               监听端口（默认 1194）
  --protocol udp|tcp        传输协议（默认 udp）
  --dns MODE                cloudflare/google/quad9/system/custom（默认 cloudflare）
  --custom-dns IP[,IP]      --dns custom 时使用
  --output DIR              .ovpn 输出目录（默认当前目录）
  -y, --yes                 无交互采用默认值

高级选项：
  --subnet NETWORK          IPv4 VPN 网段地址（默认 10.8.0.0）
  --netmask MASK            IPv4 VPN 掩码（默认 255.255.255.0）
  --cipher LIST             data-ciphers 列表
  --auth ALGORITHM          控制通道摘要（默认 SHA256）
  --tls-mode tls-crypt|tls-auth
  --ipv6                    启用 VPN IPv6
  --ipv6-subnet CIDR        VPN IPv6 网段（默认 fd42:42:42:42::/64）
  --split-tunnel            不将客户端默认路由导向 VPN
  --compression             启用兼容压缩（不推荐，有安全风险）
  --keep-ca                 卸载时保留 PKI 和客户端资料
  --force                   强制重装已有服务（不会覆盖同名客户端）
  --dry-run                 仅展示安装命令，不改动系统
  --verbose                 显示详细命令输出
  -h, --help                显示帮助
  -V, --version             显示版本
USAGE
}

parse_args() {
  if [[ ${1:-} =~ ^(install|add|revoke|list|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi
  while (($#)); do
    case "$1" in
      --client) CLIENT_NAME="${2:?--client 缺少参数}"; shift 2;;
      --endpoint) ENDPOINT="${2:?--endpoint 缺少参数}"; shift 2;;
      --port) PORT="${2:?--port 缺少参数}"; shift 2;;
      --protocol) PROTOCOL="${2:?--protocol 缺少参数}"; shift 2;;
      --dns) DNS_MODE="${2:?--dns 缺少参数}"; shift 2;;
      --custom-dns) CUSTOM_DNS="${2:?--custom-dns 缺少参数}"; shift 2;;
      --output) OUTPUT_DIR="${2:?--output 缺少参数}"; shift 2;;
      --subnet) VPN_SUBNET="${2:?--subnet 缺少参数}"; shift 2;;
      --netmask) VPN_NETMASK="${2:?--netmask 缺少参数}"; shift 2;;
      --cipher) CIPHER="${2:?--cipher 缺少参数}"; shift 2;;
      --auth) AUTH="${2:?--auth 缺少参数}"; shift 2;;
      --tls-mode) TLS_MODE="${2:?--tls-mode 缺少参数}"; shift 2;;
      --ipv6) IPV6="true"; shift;;
      --ipv6-subnet) IPV6="true"; IPV6_SUBNET="${2:?--ipv6-subnet 缺少参数}"; shift 2;;
      --split-tunnel) ROUTE_ALL="false"; shift;;
      --compression) COMPRESSION="true"; shift;;
      --keep-ca) KEEP_CA="true"; shift;;
      -y|--yes) ASSUME_YES="true"; shift;;
      --force) FORCE="true"; shift;;
      --dry-run) DRY_RUN="true"; shift;;
      --verbose) VERBOSE="true"; shift;;
      -h|--help) usage; exit 0;;
      -V|--version) echo "$SCRIPT_VERSION"; exit 0;;
      *) die "未知参数：$1（使用 --help 查看帮助）";;
    esac
  done
}

validate() {
  if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then die "端口必须在 1-65535 之间。"; fi
  [[ "$PROTOCOL" == "udp" || "$PROTOCOL" == "tcp" ]] || die "协议只能是 udp 或 tcp。"
  [[ "$TLS_MODE" == "tls-crypt" || "$TLS_MODE" == "tls-auth" ]] || die "TLS 模式只能是 tls-crypt 或 tls-auth。"
  [[ "$CLIENT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die "客户端名只能包含字母、数字、点、下划线和连字符，最长 64 字符。"
  python3 - "$VPN_SUBNET" "$VPN_NETMASK" <<'PY' || die "VPN 子网或掩码无效，且地址必须是网络地址。"
import ipaddress, sys
ipaddress.ip_network(f"{sys.argv[1]}/{sys.argv[2]}", strict=True)
PY
  python3 - "$IPV6_SUBNET" <<'PY' || die "IPv6 VPN 网段无效，且必须是网络地址。"
import ipaddress, sys
network = ipaddress.ip_network(sys.argv[1], strict=True)
assert network.version == 6 and network.prefixlen <= 126
PY
  [[ -z "$ENDPOINT" || "$ENDPOINT" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "公网入口只能是 IP 地址或域名。"
  [[ "$CIPHER" =~ ^[A-Za-z0-9_:-]+$ ]] || die "加密套件列表包含无效字符。"
  [[ "$AUTH" =~ ^[A-Za-z0-9_-]+$ ]] || die "认证摘要包含无效字符。"
  [[ "$CUSTOM_DNS" =~ ^[A-Fa-f0-9:.,]*$ ]] || die "自定义 DNS 只能包含以逗号分隔的 IP 地址。"
  [[ "$DNS_MODE" =~ ^(cloudflare|google|quad9|system|custom)$ ]] || die "不支持的 DNS 模式。"
  [[ "$DNS_MODE" != "custom" || -n "$CUSTOM_DNS" ]] || die "--dns custom 需要 --custom-dns。"
  if [[ "$COMPRESSION" == "true" ]]; then warn "压缩可能遭受 VORACLE 类攻击，仅应为兼容旧客户端启用。"; fi
}

ensure_bootstrap() {
  command -v python3 >/dev/null && command -v curl >/dev/null && return
  [[ "$DRY_RUN" != "true" ]] || die "演练模式需要预先安装 python3 和 curl。"
  log "安装参数校验和公网探测所需的基础工具…"
  apt-get update -q
  apt-get install -y --no-install-recommends python3-minimal curl ca-certificates
}

require_root_ubuntu() {
  ((EUID == 0)) || die "请使用 root 权限运行：sudo $PROGRAM"
  [[ -r /etc/os-release ]] || die "无法识别操作系统。"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "当前仅支持 Ubuntu，检测到：${PRETTY_NAME:-未知系统}"
  case "${VERSION_ID:-}" in 20.04|22.04|24.04|26.04) ;; *) warn "Ubuntu ${VERSION_ID:-未知版本} 未经完整验证，将继续尝试。";; esac
}

confirm() {
  [[ "$ASSUME_YES" == "true" ]] && return 0
  read -r -p "$1 [Y/n] " answer
  [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]
}

detect_endpoint() {
  [[ -n "$ENDPOINT" ]] && return
  local candidate=""
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    candidate="$(curl -4fsS --max-time 5 "$url" 2>/dev/null || true)"
    [[ "$candidate" =~ ^[0-9a-fA-F:.]+$ ]] && { ENDPOINT="$candidate"; break; }
  done
  if [[ -z "$ENDPOINT" && "$ASSUME_YES" != "true" ]]; then read -r -p "无法探测公网地址，请输入服务器 IP 或域名: " ENDPOINT; fi
  [[ -n "$ENDPOINT" ]] || die "无法探测公网地址，请通过 --endpoint 指定。"
}

default_interface() {
  ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'
}

dns_lines() {
  case "$DNS_MODE" in
    cloudflare) printf 'push "dhcp-option DNS 1.1.1.1"\npush "dhcp-option DNS 1.0.0.1"\n';;
    google) printf 'push "dhcp-option DNS 8.8.8.8"\npush "dhcp-option DNS 8.8.4.4"\n';;
    quad9) printf 'push "dhcp-option DNS 9.9.9.9"\npush "dhcp-option DNS 149.112.112.112"\n';;
    system) awk '/^nameserver / && $2 !~ /^127\./ {print "push \"dhcp-option DNS " $2 "\""}' /etc/resolv.conf | head -n 2;;
    custom) tr ',' '\n' <<<"$CUSTOM_DNS" | sed '/^$/d;s/^/push "dhcp-option DNS /;s/$/"/' ;;
  esac
}

save_settings() {
  install -d -m 700 "$CONFIG_DIR" "$CLIENT_DIR"
  cat >"$SETTINGS_FILE" <<EOF_SETTINGS
ENDPOINT=$(printf %q "$ENDPOINT")
PORT=$(printf %q "$PORT")
PROTOCOL=$(printf %q "$PROTOCOL")
VPN_SUBNET=$(printf %q "$VPN_SUBNET")
VPN_NETMASK=$(printf %q "$VPN_NETMASK")
DNS_MODE=$(printf %q "$DNS_MODE")
CUSTOM_DNS=$(printf %q "$CUSTOM_DNS")
CIPHER=$(printf %q "$CIPHER")
AUTH=$(printf %q "$AUTH")
TLS_MODE=$(printf %q "$TLS_MODE")
IPV6=$(printf %q "$IPV6")
IPV6_SUBNET=$(printf %q "$IPV6_SUBNET")
ROUTE_ALL=$(printf %q "$ROUTE_ALL")
COMPRESSION=$(printf %q "$COMPRESSION")
EOF_SETTINGS
  chmod 600 "$SETTINGS_FILE"
}

load_settings() {
  [[ -r "$SETTINGS_FILE" ]] || die "未找到安装配置，请先运行 install。"
  # shellcheck disable=SC1090
  source "$SETTINGS_FILE"
}

easyrsa() { EASYRSA_PKI="$PKI_DIR" /usr/share/easy-rsa/easyrsa --batch "$@"; }

install_packages() {
  log "安装 OpenVPN、Easy-RSA 和防火墙依赖…"
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -q
  run apt-get install -y --no-install-recommends openvpn easy-rsa iptables curl ca-certificates
}

create_pki() {
  log "创建证书机构和服务端证书…"
  install -d -m 700 "$CONFIG_DIR" "$SERVER_DIR" "$CLIENT_DIR"
  easyrsa init-pki
  EASYRSA_REQ_CN="Easy-Install OpenVPN CA" easyrsa build-ca nopass
  easyrsa build-server-full server nopass
  easyrsa gen-crl
  openvpn --genkey secret "${CONFIG_DIR}/${TLS_MODE}.key"
  install -m 600 "$PKI_DIR/private/server.key" "$SERVER_DIR/server.key"
  install -m 644 "$PKI_DIR/issued/server.crt" "$SERVER_DIR/server.crt"
  install -m 644 "$PKI_DIR/ca.crt" "$SERVER_DIR/ca.crt"
  install -m 644 "$PKI_DIR/crl.pem" "$SERVER_DIR/crl.pem"
  install -m 600 "${CONFIG_DIR}/${TLS_MODE}.key" "${SERVER_DIR}/${TLS_MODE}.key"
  chown nobody:nogroup "$SERVER_DIR/crl.pem"
}

write_server_config() {
  local proto="$PROTOCOL" tls_line compression_lines="" ipv6_lines="" redirect_line="" exit_notify=""
  [[ "$PROTOCOL" == "tcp" ]] && proto="tcp-server"
  [[ "$PROTOCOL" == "udp" ]] && exit_notify="explicit-exit-notify 1"
  [[ "$TLS_MODE" == "tls-crypt" ]] && tls_line="tls-crypt ${TLS_MODE}.key" || tls_line=$'tls-auth tls-auth.key 0\nkey-direction 0'
  [[ "$COMPRESSION" == "true" ]] && compression_lines=$'compress lz4-v2\npush "compress lz4-v2"'
  if [[ "$IPV6" == "true" ]]; then
    ipv6_lines="server-ipv6 ${IPV6_SUBNET}"
  elif [[ "$ROUTE_ALL" == "true" ]]; then
    ipv6_lines='push "block-ipv6"'
  fi
  if [[ "$ROUTE_ALL" == "true" ]]; then
    redirect_line='push "redirect-gateway def1 bypass-dhcp"'
    [[ "$IPV6" == "true" ]] && redirect_line+=$'\npush "redirect-gateway ipv6"'
  fi
  cat >"$SERVER_CONF" <<EOF_SERVER
port ${PORT}
proto ${proto}
dev tun
topology subnet
server ${VPN_SUBNET} ${VPN_NETMASK}
${ipv6_lines}
ca ca.crt
cert server.crt
key server.key
crl-verify crl.pem
${tls_line}
tls-version-min 1.2
data-ciphers ${CIPHER}
data-ciphers-fallback AES-256-GCM
auth ${AUTH}
dh none
ecdh-curve prime256v1
${redirect_line}
$(dns_lines)
${compression_lines}
user nobody
group nogroup
persist-key
persist-tun
keepalive 10 120
${exit_notify}
client-to-client
status /run/openvpn/server.status
verb 3
EOF_SERVER
  sed -i '/^[[:space:]]*$/d' "$SERVER_CONF"
  chmod 600 "$SERVER_CONF"
}

write_network_config() {
  local iface
  iface="$(default_interface)"
  [[ -n "$iface" ]] || die "无法检测默认出口网卡。"
  cat >"$SYSCTL_FILE" <<EOF_SYSCTL
net.ipv4.ip_forward=1
$( [[ "$IPV6" == "true" ]] && echo 'net.ipv6.conf.all.forwarding=1' )
EOF_SYSCTL
  install -d -m 755 "$(dirname "$FIREWALL_SCRIPT")"
  cat >"$FIREWALL_SCRIPT" <<EOF_FW
#!/usr/bin/env bash
set -euo pipefail
ACTION="\${1:-start}"
IPT="\$(command -v iptables)"
IPT6="\$(command -v ip6tables)"
rule() { "\$IPT" "\$@"; }
rule6() { "\$IPT6" "\$@"; }
add() { local table="\$1" chain="\$2"; shift 2; rule -t "\$table" -C "\$chain" "\$@" 2>/dev/null || rule -t "\$table" -I "\$chain" 1 "\$@"; }
del() { local table="\$1" chain="\$2"; shift 2; while rule -t "\$table" -C "\$chain" "\$@" 2>/dev/null; do rule -t "\$table" -D "\$chain" "\$@"; done; }
add6() { local table="\$1" chain="\$2"; shift 2; rule6 -t "\$table" -C "\$chain" "\$@" 2>/dev/null || rule6 -t "\$table" -I "\$chain" 1 "\$@"; }
del6() { local table="\$1" chain="\$2"; shift 2; while rule6 -t "\$table" -C "\$chain" "\$@" 2>/dev/null; do rule6 -t "\$table" -D "\$chain" "\$@"; done; }
if [[ "\$ACTION" == start ]]; then
  add filter INPUT -p ${PROTOCOL} --dport ${PORT} -j ACCEPT
  add filter FORWARD -s ${VPN_SUBNET}/${VPN_NETMASK} -j ACCEPT
  add filter FORWARD -d ${VPN_SUBNET}/${VPN_NETMASK} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  add nat POSTROUTING -s ${VPN_SUBNET}/${VPN_NETMASK} -o ${iface} -j MASQUERADE
$(if [[ "$IPV6" == "true" ]]; then cat <<EOF_IPV6_START
  add6 filter FORWARD -s ${IPV6_SUBNET} -j ACCEPT
  add6 filter FORWARD -d ${IPV6_SUBNET} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  add6 nat POSTROUTING -s ${IPV6_SUBNET} -o ${iface} -j MASQUERADE
EOF_IPV6_START
fi)
else
  del filter INPUT -p ${PROTOCOL} --dport ${PORT} -j ACCEPT
  del filter FORWARD -s ${VPN_SUBNET}/${VPN_NETMASK} -j ACCEPT
  del filter FORWARD -d ${VPN_SUBNET}/${VPN_NETMASK} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  del nat POSTROUTING -s ${VPN_SUBNET}/${VPN_NETMASK} -o ${iface} -j MASQUERADE
$(if [[ "$IPV6" == "true" ]]; then cat <<EOF_IPV6_STOP
  del6 filter FORWARD -s ${IPV6_SUBNET} -j ACCEPT
  del6 filter FORWARD -d ${IPV6_SUBNET} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  del6 nat POSTROUTING -s ${IPV6_SUBNET} -o ${iface} -j MASQUERADE
EOF_IPV6_STOP
fi)
fi
EOF_FW
  chmod 700 "$FIREWALL_SCRIPT"
  cat >"$FIREWALL_SERVICE" <<EOF_UNIT
[Unit]
Description=Easy Install OpenVPN firewall rules
Before=openvpn-server@server.service
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
  run systemctl enable --now easy-install-openvpn-firewall.service
}

create_client() {
  local cert="${PKI_DIR}/issued/${CLIENT_NAME}.crt" key="${PKI_DIR}/private/${CLIENT_NAME}.key"
  [[ ! -e "$cert" ]] || die "客户端 ${CLIENT_NAME} 已存在。为避免先吊销后签发失败，请使用新名称轮换证书。"
  log "签发客户端证书：${CLIENT_NAME}"
  easyrsa build-client-full "$CLIENT_NAME" nopass
  install -m 600 "$PKI_DIR/crl.pem" "$SERVER_DIR/crl.pem"
  chown nobody:nogroup "$SERVER_DIR/crl.pem"
  generate_profile "$cert" "$key"
}

generate_profile() {
  local cert="$1" key="$2" output temp_output tls_inline proto="$PROTOCOL"
  mkdir -p "$OUTPUT_DIR"
  output="${OUTPUT_DIR%/}/${CLIENT_NAME}.ovpn"
  temp_output="$(mktemp "${OUTPUT_DIR%/}/.${CLIENT_NAME}.ovpn.XXXXXX")"
  trap 'rm -f "${temp_output:-}"' RETURN
  [[ "$PROTOCOL" == "tcp" ]] && proto="tcp-client"
  if [[ "$TLS_MODE" == "tls-crypt" ]]; then
    tls_inline="<tls-crypt>$(printf '\n'; cat "${CONFIG_DIR}/tls-crypt.key")</tls-crypt>"
  else
    tls_inline="key-direction 1
<tls-auth>$(printf '\n'; cat "${CONFIG_DIR}/tls-auth.key")</tls-auth>"
  fi
  cat >"$temp_output" <<EOF_CLIENT
client
dev tun
proto ${proto}
remote ${ENDPOINT} ${PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name server name
tls-version-min 1.2
data-ciphers ${CIPHER}
auth ${AUTH}
verb 3
$( [[ "$COMPRESSION" == "true" ]] && echo 'compress lz4-v2' )
<ca>
$(cat "$PKI_DIR/ca.crt")
</ca>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$p' "$cert")
</cert>
<key>
$(cat "$key")
</key>
${tls_inline}
EOF_CLIENT
  sed -i '/^[[:space:]]*$/d' "$temp_output"
  chmod 600 "$temp_output"
  mv -f "$temp_output" "$output"
  install -m 600 "$output" "$CLIENT_DIR/${CLIENT_NAME}.ovpn"
  trap - RETURN
  success "客户端配置已生成：${output}"
}

install_server() {
  require_root_ubuntu
  ensure_bootstrap
  validate
  [[ -c /dev/net/tun ]] || die "未发现 /dev/net/tun；请先在宿主机或 VPS 控制台启用 TUN。"
  if [[ -e "$SETTINGS_FILE" && "$FORCE" != "true" ]]; then die "OpenVPN 已由本脚本安装。使用 add 添加客户端，或用 --force 重装。"; fi
  detect_endpoint
  validate
  local summary="公网入口 ${ENDPOINT}:${PORT}/${PROTOCOL}，客户端 ${CLIENT_NAME}，DNS ${DNS_MODE}"
  log "$summary"
  confirm "开始安装？" || die "已取消。"
  install_packages
  if [[ "$DRY_RUN" == "true" ]]; then success "演练完成，系统未被修改。"; return; fi
  if [[ -e "$SETTINGS_FILE" && "$FORCE" == "true" ]]; then
    systemctl disable --now easy-install-openvpn-firewall.service 2>/dev/null || true
    if [[ -x "$FIREWALL_SCRIPT" ]]; then "$FIREWALL_SCRIPT" stop || true; fi
    systemctl disable --now openvpn-server@server.service 2>/dev/null || true
    rm -rf "$CONFIG_DIR" "$SERVER_DIR"
  fi
  create_pki
  write_server_config
  save_settings
  write_network_config
  run systemctl enable --now openvpn-server@server.service
  create_client
  success "OpenVPN 安装完成。"
  log "服务状态：systemctl status openvpn-server@server"
}

add_client() { require_root_ubuntu; load_settings; create_client; }

revoke_client() {
  require_root_ubuntu; load_settings
  [[ -e "$PKI_DIR/issued/${CLIENT_NAME}.crt" ]] || die "客户端 ${CLIENT_NAME} 不存在。"
  confirm "确定永久吊销客户端 ${CLIENT_NAME}？" || die "已取消。"
  easyrsa revoke "$CLIENT_NAME"
  easyrsa gen-crl
  install -m 600 "$PKI_DIR/crl.pem" "$SERVER_DIR/crl.pem"
  chown nobody:nogroup "$SERVER_DIR/crl.pem"
  rm -f "$CLIENT_DIR/${CLIENT_NAME}.ovpn"
  run systemctl reload-or-restart openvpn-server@server.service
  success "客户端 ${CLIENT_NAME} 已吊销。"
}

list_clients() {
  require_root_ubuntu; load_settings
  printf '%-28s %-12s %s\n' "客户端" "状态" "到期时间"
  awk -F'\t' '$1=="V" || $1=="R" {split($NF,a,"/"); printf "%-28s %-12s %s\n", a[length(a)], ($1=="V"?"有效":"已吊销"), $2}' "$PKI_DIR/index.txt"
}

show_status() {
  require_root_ubuntu; load_settings
  printf '入口: %s:%s/%s\nVPN 网段: %s %s\nDNS: %s\n配置: %s\n\n' "$ENDPOINT" "$PORT" "$PROTOCOL" "$VPN_SUBNET" "$VPN_NETMASK" "$DNS_MODE" "$SERVER_CONF"
  systemctl --no-pager --full status openvpn-server@server.service || true
}

uninstall_server() {
  require_root_ubuntu
  confirm "确定卸载 OpenVPN 服务？" || die "已取消。"
  run systemctl disable --now openvpn-server@server.service || true
  run systemctl disable --now easy-install-openvpn-firewall.service || true
  if [[ -x "$FIREWALL_SCRIPT" ]]; then run "$FIREWALL_SCRIPT" stop || true; fi
  rm -f "$SERVER_CONF" "$SYSCTL_FILE" "$FIREWALL_SCRIPT" "$FIREWALL_SERVICE"
  if [[ "$KEEP_CA" == "true" ]]; then warn "已按要求保留 ${CONFIG_DIR}。"; else rm -rf "$CONFIG_DIR" "$SERVER_DIR"; fi
  run systemctl daemon-reload
  run sysctl --system
  success "OpenVPN 配置已卸载。软件包仍保留，可用 apt purge openvpn easy-rsa 手动移除。"
}

main() {
  parse_args "$@"
  [[ "$DRY_RUN" != "true" || "$COMMAND" == install ]] || die "--dry-run 当前仅支持 install，避免管理命令意外修改证书。"
  [[ "$COMMAND" == install ]] || validate
  [[ "$VERBOSE" == "true" ]] && set -x
  case "$COMMAND" in
    install) install_server;; add) add_client;; revoke) revoke_client;;
    list) list_clients;; status) show_status;; uninstall) uninstall_server;;
  esac
}
main "$@"
