#!/usr/bin/env bash
# Easy Install - Ubuntu WireGuard server installer
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly PROGRAM="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/etc/wireguard/easy-install"
readonly WG_CONF="/etc/wireguard/wg0.conf"
readonly SETTINGS_FILE="${CONFIG_DIR}/settings.env"
readonly PEERS_DIR="${CONFIG_DIR}/peers"
readonly SYSCTL_FILE="/etc/sysctl.d/99-easy-install-wireguard.conf"

COMMAND="install"
CLIENT_NAME="client"
ENDPOINT=""
PORT="51820"
VPN_SUBNET="10.66.66.0/24"
IPV6="false"
IPV6_SUBNET="fd42:42:42:66::/64"
DNS_MODE="cloudflare"
CUSTOM_DNS=""
OUTPUT_DIR="$PWD"
ALLOWED_IPS=""
ROUTE_ALL="true"
MTU="1420"
KEEPALIVE="25"
ASSUME_YES="false"
FORCE="false"
KEEP_KEYS="false"
DRY_RUN="false"
VERBOSE="false"

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run() { if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败，可使用 --verbose 查看详情。"' ERR

usage() {
  cat <<'USAGE'
Ubuntu WireGuard 一键部署与管理

用法：
  sudo ./wireguard.sh [install] [选项]  安装服务并创建首个客户端（默认）
  sudo ./wireguard.sh add [选项]        添加客户端
  sudo ./wireguard.sh remove [选项]     删除客户端
  sudo ./wireguard.sh list              列出客户端
  sudo ./wireguard.sh show [选项]       重新导出配置并显示二维码
  sudo ./wireguard.sh status            查看 WireGuard 状态
  sudo ./wireguard.sh uninstall         卸载配置

懒人用法：
  sudo ./wireguard.sh
  sudo ./wireguard.sh --yes --client phone --endpoint vpn.example.com
  sudo ./wireguard.sh add --client laptop
  sudo ./wireguard.sh show --client phone

常用选项：
  --client NAME              客户端名称（默认 client）
  --endpoint HOST            公网 IP 或域名（默认自动探测）
  --port PORT                UDP 监听端口（默认 51820）
  --subnet CIDR              WireGuard IPv4 网段（默认 10.66.66.0/24）
  --dns MODE                 cloudflare/google/quad9/system/custom
  --custom-dns IP[,IP]       自定义 DNS
  --output DIR               客户端配置输出目录（默认当前目录）
  -y, --yes                  无交互安装

高级选项：
  --ipv6                     启用 IPv6 和 NAT66
  --ipv6-subnet CIDR         IPv6 VPN 网段（默认 fd42:42:42:66::/64）
  --split-tunnel             客户端仅路由 VPN 网段
  --allowed-ips LIST         自定义客户端 AllowedIPs（逗号分隔）
  --mtu MTU                  接口 MTU（默认 1420）
  --keepalive SECONDS        客户端保活间隔（默认 25，0 为关闭）
  --force                    覆盖已有安装或同名客户端
  --keep-keys                卸载时保留密钥和客户端资料
  --dry-run                  仅展示安装命令，不修改系统
  --verbose                  显示详细执行过程
  -h, --help                 显示帮助
  -V, --version              显示版本

需在云安全组和外部防火墙放行所选 UDP 端口（默认 51820）。
USAGE
}

parse_args() {
  if [[ ${1:-} =~ ^(install|add|remove|list|show|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi
  while (($#)); do
    case "$1" in
      --client) CLIENT_NAME="${2:?--client 缺少参数}"; shift 2;;
      --endpoint) ENDPOINT="${2:?--endpoint 缺少参数}"; shift 2;;
      --port) PORT="${2:?--port 缺少参数}"; shift 2;;
      --subnet) VPN_SUBNET="${2:?--subnet 缺少参数}"; shift 2;;
      --dns) DNS_MODE="${2:?--dns 缺少参数}"; shift 2;;
      --custom-dns) CUSTOM_DNS="${2:?--custom-dns 缺少参数}"; shift 2;;
      --output) OUTPUT_DIR="${2:?--output 缺少参数}"; shift 2;;
      --ipv6) IPV6="true"; shift;;
      --ipv6-subnet) IPV6="true"; IPV6_SUBNET="${2:?--ipv6-subnet 缺少参数}"; shift 2;;
      --split-tunnel) ROUTE_ALL="false"; shift;;
      --allowed-ips) ALLOWED_IPS="${2:?--allowed-ips 缺少参数}"; shift 2;;
      --mtu) MTU="${2:?--mtu 缺少参数}"; shift 2;;
      --keepalive) KEEPALIVE="${2:?--keepalive 缺少参数}"; shift 2;;
      -y|--yes) ASSUME_YES="true"; shift;;
      --force) FORCE="true"; shift;;
      --keep-keys) KEEP_KEYS="true"; shift;;
      --dry-run) DRY_RUN="true"; shift;;
      --verbose) VERBOSE="true"; shift;;
      -h|--help) usage; exit 0;;
      -V|--version) echo "$SCRIPT_VERSION"; exit 0;;
      *) die "未知参数：$1（使用 --help 查看帮助）";;
    esac
  done
}

validate() {
  [[ "$CLIENT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die "客户端名格式无效，最长 64 字符。"
  [[ -z "$ENDPOINT" || "$ENDPOINT" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "公网入口只能是 IP 地址或域名。"
  if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then die "端口必须在 1-65535 之间。"; fi
  [[ "$VPN_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([8-9]|[12][0-9]|30)$ ]] || die "IPv4 网段必须是 /8 到 /30 的 CIDR。"
  [[ "$IPV6_SUBNET" =~ ^[A-Fa-f0-9:]+/([0-9]|[1-9][0-9]|1[01][0-9]|12[0-6])$ ]] || die "IPv6 网段必须是 /0 到 /126 的 CIDR。"
  [[ "$DNS_MODE" =~ ^(cloudflare|google|quad9|system|custom)$ ]] || die "不支持的 DNS 模式。"
  [[ "$DNS_MODE" != custom || -n "$CUSTOM_DNS" ]] || die "--dns custom 需要 --custom-dns。"
  [[ "$CUSTOM_DNS" =~ ^[A-Fa-f0-9:.,]*$ ]] || die "自定义 DNS 只能是逗号分隔的 IP 地址。"
  [[ -z "$ALLOWED_IPS" || "$ALLOWED_IPS" =~ ^[A-Fa-f0-9:.,/]+$ ]] || die "AllowedIPs 格式无效。"
  if [[ ! "$MTU" =~ ^[0-9]+$ ]] || ((MTU < 576 || MTU > 9000)); then die "MTU 必须在 576-9000 之间。"; fi
  if [[ ! "$KEEPALIVE" =~ ^[0-9]+$ ]] || ((KEEPALIVE < 0 || KEEPALIVE > 65535)); then die "保活间隔必须在 0-65535 秒之间。"; fi
}

require_root_ubuntu() {
  ((EUID == 0)) || die "请使用 root 权限运行：sudo $PROGRAM"
  [[ -r /etc/os-release ]] || die "无法识别操作系统。"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || die "当前仅支持 Ubuntu，检测到：${PRETTY_NAME:-未知系统}"
  case "${VERSION_ID:-}" in 20.04|22.04|24.04|26.04) ;; *) warn "Ubuntu ${VERSION_ID:-未知版本} 未经完整验证，将继续尝试。";; esac
}

confirm() { [[ "$ASSUME_YES" == true ]] && return 0; read -r -p "$1 [Y/n] " answer; [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; }

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

dns_value() {
  case "$DNS_MODE" in
    cloudflare) [[ "$IPV6" == true ]] && echo "1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001" || echo "1.1.1.1, 1.0.0.1";;
    google) [[ "$IPV6" == true ]] && echo "8.8.8.8, 8.8.4.4, 2001:4860:4860::8888, 2001:4860:4860::8844" || echo "8.8.8.8, 8.8.4.4";;
    quad9) [[ "$IPV6" == true ]] && echo "9.9.9.9, 149.112.112.112, 2620:fe::fe, 2620:fe::9" || echo "9.9.9.9, 149.112.112.112";;
    custom) echo "${CUSTOM_DNS//,/\, }";;
    system) awk '/^nameserver / && $2 !~ /^127\./ {a=a (a?", ":"") $2; if(++n==2) exit} END {print a}' /etc/resolv.conf;;
  esac
}

load_settings() {
  [[ -r "$SETTINGS_FILE" ]] || die "未找到安装配置，请先执行 install。"
  # shellcheck disable=SC1090
  source "$SETTINGS_FILE"
}

save_settings() {
  install -d -m 700 "$CONFIG_DIR" "$PEERS_DIR"
  cat >"$SETTINGS_FILE" <<EOF_SETTINGS
ENDPOINT=$(printf %q "$ENDPOINT")
PORT=$(printf %q "$PORT")
VPN_SUBNET=$(printf %q "$VPN_SUBNET")
IPV6=$(printf %q "$IPV6")
IPV6_SUBNET=$(printf %q "$IPV6_SUBNET")
DNS_MODE=$(printf %q "$DNS_MODE")
CUSTOM_DNS=$(printf %q "$CUSTOM_DNS")
ALLOWED_IPS=$(printf %q "$ALLOWED_IPS")
ROUTE_ALL=$(printf %q "$ROUTE_ALL")
MTU=$(printf %q "$MTU")
KEEPALIVE=$(printf %q "$KEEPALIVE")
EOF_SETTINGS
  chmod 600 "$SETTINGS_FILE"
}

install_packages() {
  log "安装 WireGuard、二维码和网络依赖…"
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -q
  run apt-get install -y --no-install-recommends wireguard-tools iptables curl ca-certificates qrencode python3
}

ipcalc() {
  python3 - "$@" <<'PY'
import ipaddress, sys
cmd, network = sys.argv[1], ipaddress.ip_network(sys.argv[2], strict=True)
if cmd == "server": print(network.network_address + 1)
elif cmd == "prefix": print(network.prefixlen)
elif cmd == "network": print(network.network_address)
elif cmd == "client":
    index = int(sys.argv[3])
    address = network.network_address + index
    if address >= network.broadcast_address: raise SystemExit("address pool exhausted")
    print(address)
PY
}

next_index() {
  local max=1 file value
  shopt -s nullglob
  for file in "$PEERS_DIR"/*.meta; do value="$(awk -F= '$1=="INDEX" {print $2}' "$file")"; ((value > max)) && max="$value"; done
  echo $((max + 1))
}

write_server_config() {
  local iface server4 prefix4 server6="" prefix6="" ip6_address="" ip6_up="" ip6_down=""
  iface="$(default_interface)"; [[ -n "$iface" ]] || die "无法检测默认出口网卡。"
  server4="$(ipcalc server "$VPN_SUBNET")"; prefix4="$(ipcalc prefix "$VPN_SUBNET")"
  if [[ "$IPV6" == true ]]; then
    server6="$(ipcalc server "$IPV6_SUBNET")"; prefix6="$(ipcalc prefix "$IPV6_SUBNET")"
    ip6_address=", ${server6}/${prefix6}"
    ip6_up="PostUp = ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -A FORWARD -o %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -s ${IPV6_SUBNET} -o ${iface} -j MASQUERADE"
    ip6_down="PostDown = ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -s ${IPV6_SUBNET} -o ${iface} -j MASQUERADE"
  fi
  cat >"$WG_CONF" <<EOF_CONF
# Managed by Easy Install. Use wireguard.sh to change peers.
[Interface]
Address = ${server4}/${prefix4}${ip6_address}
ListenPort = ${PORT}
PrivateKey = $(cat "$CONFIG_DIR/server.key")
MTU = ${MTU}
PostUp = iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT; iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -s ${VPN_SUBNET} -o ${iface} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${PORT} -j ACCEPT; iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -s ${VPN_SUBNET} -o ${iface} -j MASQUERADE
${ip6_up}
${ip6_down}
EOF_CONF
  shopt -s nullglob
  local meta name public_key address4 address6
  for meta in "$PEERS_DIR"/*.meta; do
    name=""; public_key=""; address4=""; address6=""
    # shellcheck disable=SC1090
    source "$meta"
    cat >>"$WG_CONF" <<EOF_PEER

# ${name}
[Peer]
PublicKey = ${public_key}
PresharedKey = $(cat "$PEERS_DIR/${name}.psk")
AllowedIPs = ${address4}/32$( [[ -n "$address6" ]] && printf ', %s/128' "$address6" )
EOF_PEER
  done
  sed -i '/^[[:space:]]*$/N;/^\n$/D' "$WG_CONF"
  chmod 600 "$WG_CONF"
}

sync_interface() {
  if systemctl is-active --quiet wg-quick@wg0; then run bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'; else run systemctl enable --now wg-quick@wg0; fi
}

create_client() {
  local meta="$PEERS_DIR/${CLIENT_NAME}.meta" index address4 address6="" private_key public_key client_allowed endpoint_value
  [[ ! -e "$meta" || "$FORCE" == true ]] || die "客户端 $CLIENT_NAME 已存在；换名称或使用 --force。"
  [[ ! -e "$meta" ]] || remove_client_files "$CLIENT_NAME"
  index="$(next_index)"
  address4="$(ipcalc client "$VPN_SUBNET" "$index")"
  [[ "$IPV6" == true ]] && address6="$(ipcalc client "$IPV6_SUBNET" "$index")"
  private_key="$(wg genkey)"; public_key="$(printf '%s' "$private_key" | wg pubkey)"
  printf '%s\n' "$private_key" >"$PEERS_DIR/${CLIENT_NAME}.key"
  wg genpsk >"$PEERS_DIR/${CLIENT_NAME}.psk"
  cat >"$meta" <<EOF_META
name=$(printf %q "$CLIENT_NAME")
INDEX=$(printf %q "$index")
public_key=$(printf %q "$public_key")
address4=$(printf %q "$address4")
address6=$(printf %q "$address6")
EOF_META
  chmod 600 "$PEERS_DIR/${CLIENT_NAME}.key" "$PEERS_DIR/${CLIENT_NAME}.psk" "$meta"
  write_server_config; sync_interface
  if [[ -n "$ALLOWED_IPS" ]]; then client_allowed="$ALLOWED_IPS"; elif [[ "$ROUTE_ALL" == true ]]; then client_allowed="0.0.0.0/0$( [[ "$IPV6" == true ]] && echo ', ::/0' )"; else client_allowed="$VPN_SUBNET$( [[ "$IPV6" == true ]] && printf ', %s' "$IPV6_SUBNET" )"; fi
  mkdir -p "$OUTPUT_DIR"
  endpoint_value="$ENDPOINT"
  [[ "$endpoint_value" == *:* && "$endpoint_value" != \\[*\\] ]] && endpoint_value="[$endpoint_value]"
  cat >"$OUTPUT_DIR/${CLIENT_NAME}.conf" <<EOF_CLIENT
[Interface]
PrivateKey = ${private_key}
Address = ${address4}/32$( [[ -n "$address6" ]] && printf ', %s/128' "$address6" )
DNS = $(dns_value)
MTU = ${MTU}

[Peer]
PublicKey = $(cat "$CONFIG_DIR/server.pub")
PresharedKey = $(cat "$PEERS_DIR/${CLIENT_NAME}.psk")
Endpoint = ${endpoint_value}:${PORT}
AllowedIPs = ${client_allowed}
$( ((KEEPALIVE > 0)) && echo "PersistentKeepalive = ${KEEPALIVE}" )
EOF_CLIENT
  chmod 600 "$OUTPUT_DIR/${CLIENT_NAME}.conf"
  qrencode -t PNG -o "$OUTPUT_DIR/${CLIENT_NAME}.png" -r "$OUTPUT_DIR/${CLIENT_NAME}.conf"
  chmod 600 "$OUTPUT_DIR/${CLIENT_NAME}.png"
  install -m 600 "$OUTPUT_DIR/${CLIENT_NAME}.conf" "$PEERS_DIR/${CLIENT_NAME}.conf"
  success "客户端配置：$OUTPUT_DIR/${CLIENT_NAME}.conf"
  success "二维码图片：$OUTPUT_DIR/${CLIENT_NAME}.png"
}

remove_client_files() { rm -f "$PEERS_DIR/$1.key" "$PEERS_DIR/$1.psk" "$PEERS_DIR/$1.meta" "$PEERS_DIR/$1.conf"; }

install_server() {
  require_root_ubuntu
  [[ ! -e "$SETTINGS_FILE" || "$FORCE" == true ]] || die "WireGuard 已安装；使用 add 添加客户端，或 --force 重装。"
  detect_endpoint; validate
  log "将安装 WireGuard：${ENDPOINT}:${PORT}/udp，网段 $VPN_SUBNET，客户端 $CLIENT_NAME"
  confirm "开始安装？" || die "已取消。"
  install_packages
  if [[ "$DRY_RUN" == true ]]; then success "演练完成，系统未被修改。"; return; fi
  if [[ -e "$SETTINGS_FILE" ]]; then systemctl disable --now wg-quick@wg0 2>/dev/null || true; rm -rf "$CONFIG_DIR"; fi
  save_settings
  wg genkey >"$CONFIG_DIR/server.key"; wg pubkey <"$CONFIG_DIR/server.key" >"$CONFIG_DIR/server.pub"
  chmod 600 "$CONFIG_DIR/server.key"; chmod 644 "$CONFIG_DIR/server.pub"
  cat >"$SYSCTL_FILE" <<EOF_SYSCTL
net.ipv4.ip_forward=1
$( [[ "$IPV6" == true ]] && echo 'net.ipv6.conf.all.forwarding=1' )
EOF_SYSCTL
  run sysctl --system
  create_client
  success "WireGuard 安装完成。请放行 UDP $PORT。"
}

add_client() { require_root_ubuntu; load_settings; create_client; }

remove_client() {
  require_root_ubuntu; load_settings
  [[ -e "$PEERS_DIR/${CLIENT_NAME}.meta" ]] || die "客户端 $CLIENT_NAME 不存在。"
  confirm "确定删除客户端 $CLIENT_NAME？" || die "已取消。"
  remove_client_files "$CLIENT_NAME"; write_server_config; sync_interface
  success "客户端 $CLIENT_NAME 已删除。"
}

list_clients() {
  require_root_ubuntu; load_settings
  printf '%-24s %-18s %s\n' "客户端" "IPv4" "IPv6"
  shopt -s nullglob
  local meta name address4 address6
  for meta in "$PEERS_DIR"/*.meta; do
    name=""; address4=""; address6=""
    # shellcheck disable=SC1090
    source "$meta"
    printf '%-24s %-18s %s\n' "$name" "$address4" "${address6:--}"
  done
}

show_client() {
  require_root_ubuntu; load_settings
  [[ -r "$PEERS_DIR/${CLIENT_NAME}.conf" ]] || die "客户端 $CLIENT_NAME 不存在。"
  mkdir -p "$OUTPUT_DIR"; install -m 600 "$PEERS_DIR/${CLIENT_NAME}.conf" "$OUTPUT_DIR/${CLIENT_NAME}.conf"
  qrencode -t PNG -o "$OUTPUT_DIR/${CLIENT_NAME}.png" -r "$PEERS_DIR/${CLIENT_NAME}.conf"; chmod 600 "$OUTPUT_DIR/${CLIENT_NAME}.png"
  qrencode -t ansiutf8 -r "$PEERS_DIR/${CLIENT_NAME}.conf"
  success "已导出到 $OUTPUT_DIR/${CLIENT_NAME}.conf"
}

show_status() { require_root_ubuntu; load_settings; wg show wg0 || true; systemctl --no-pager --full status wg-quick@wg0 || true; }

uninstall_server() {
  require_root_ubuntu; confirm "确定卸载 WireGuard 配置？" || die "已取消。"
  run systemctl disable --now wg-quick@wg0 || true
  rm -f "$WG_CONF" "$SYSCTL_FILE"
  if [[ "$KEEP_KEYS" == true ]]; then warn "已保留 $CONFIG_DIR。"; else rm -rf "$CONFIG_DIR"; fi
  run sysctl --system
  success "WireGuard 配置已卸载，软件包仍保留。"
}

main() {
  parse_args "$@"; validate
  [[ "$VERBOSE" == true ]] && set -x
  case "$COMMAND" in
    install) install_server;; add) add_client;; remove) remove_client;; list) list_clients;;
    show) show_client;; status) show_status;; uninstall) uninstall_server;;
  esac
}
main "$@"
