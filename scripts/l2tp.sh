#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'; umask 077
readonly SCRIPT_VERSION="1.0.0"; readonly STATE_DIR="/etc/xl2tpd/easy-install"; readonly SETTINGS="$STATE_DIR/settings.env"; readonly FIREWALL="/usr/local/lib/easy-install/l2tp-firewall.sh"; readonly FIREWALL_UNIT="/etc/systemd/system/easy-install-l2tp-firewall.service"
COMMAND="install"; ENDPOINT=""; PSK=""; USER_NAME="vpn"; USER_PASSWORD=""; VPN_CIDR="10.20.30.0/24"; LOCAL_IP="10.20.30.1"; CLIENT_POOL="10.20.30.10-10.20.30.250"; DNS="1.1.1.1,8.8.8.8"; MTU="1280"; INTERFACE=""; ASSUME_YES="false"; FORCE="false"; KEEP_CONFIG="false"; DRY_RUN="false"; VERBOSE="false"
log(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }; warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }; die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
run(){ if [[ "$DRY_RUN" == true ]]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
trap 'die "第 ${LINENO} 行执行失败。"' ERR
usage(){ cat <<'USAGE'
Ubuntu L2TP/IPsec 一键部署与用户管理
用法：
  sudo ./l2tp.sh [install] [选项]  安装 strongSwan + xl2tpd（默认）
  sudo ./l2tp.sh add [选项]        添加或更新 PPP 用户
  sudo ./l2tp.sh revoke --user U   删除 PPP 用户
  sudo ./l2tp.sh list              列出 PPP 用户
  sudo ./l2tp.sh status            查看服务状态
  sudo ./l2tp.sh uninstall         卸载 L2TP/IPsec
选项：
  --endpoint HOST       公网 IP 或域名（默认自动探测 IPv4）
  --psk VALUE           IPsec 预共享密钥（默认随机生成，至少 16 字符）
  --user NAME           VPN 用户名（默认 vpn）
  --password VALUE      VPN 密码（默认随机生成，至少 12 字符）
  --vpn-cidr CIDR       VPN IPv4 网段（默认 10.20.30.0/24）
  --local-ip IP         L2TP 服务端内网 IP（默认 10.20.30.1）
  --client-pool A-B     客户端地址池（默认 10.20.30.10-10.20.30.250）
  --dns A,B             DNS 服务器（默认 1.1.1.1,8.8.8.8）
  --mtu MTU             PPP MTU/MRU（默认 1280）
  --interface IFACE     出口网卡（默认自动探测）
  --force               覆盖已有配置或用户密码
  --keep-config         卸载时保留配置
  -y, --yes             无交互执行
  --dry-run             仅演练 install
  --verbose             显示详细命令
  -h, --help            显示帮助
  -V, --version         显示版本
USAGE
}
parse(){ if [[ ${1:-} =~ ^(install|add|revoke|list|status|uninstall)$ ]]; then COMMAND="$1"; shift; fi; while (($#)); do case "$1" in --endpoint) ENDPOINT="${2:?缺少 endpoint}"; shift 2;; --psk) PSK="${2:?缺少 PSK}"; shift 2;; --user) USER_NAME="${2:?缺少用户名}"; shift 2;; --password) USER_PASSWORD="${2:?缺少密码}"; shift 2;; --vpn-cidr) VPN_CIDR="${2:?缺少 CIDR}"; shift 2;; --local-ip) LOCAL_IP="${2:?缺少 IP}"; shift 2;; --client-pool) CLIENT_POOL="${2:?缺少地址池}"; shift 2;; --dns) DNS="${2:?缺少 DNS}"; shift 2;; --mtu) MTU="${2:?缺少 MTU}"; shift 2;; --interface) INTERFACE="${2:?缺少网卡}"; shift 2;; --force) FORCE="true"; shift;; --keep-config) KEEP_CONFIG="true"; shift;; -y|--yes) ASSUME_YES="true"; shift;; --dry-run) DRY_RUN="true"; shift;; --verbose) VERBOSE="true"; shift;; -h|--help) usage; exit 0;; -V|--version) echo "$SCRIPT_VERSION"; exit 0;; *) die "未知参数：$1";; esac; done; }
valid_net(){ python3 - "$1" <<'PY'
import ipaddress, sys
ipaddress.ip_network(sys.argv[1], strict=False)
PY
}
valid_ip(){ python3 - "$1" <<'PY'
import ipaddress, sys
ipaddress.ip_address(sys.argv[1])
PY
}
valid_dns(){ python3 - "$1" <<'PY'
import ipaddress, sys
for item in sys.argv[1].split(','):
    if not item: raise SystemExit(1)
    ipaddress.ip_address(item)
PY
}
validate(){ [[ -z "$ENDPOINT" || "$ENDPOINT" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "endpoint 格式无效。"; [[ -z "$PSK" || ${#PSK} -ge 16 ]] || die "PSK 至少 16 字符。"; [[ -z "$PSK" || "$PSK" =~ ^[A-Za-z0-9_.:@%+=,-]+$ ]] || die "PSK 包含不安全字符。"; [[ "$USER_NAME" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || die "用户名格式无效。"; [[ -z "$USER_PASSWORD" || ${#USER_PASSWORD} -ge 12 ]] || die "密码至少 12 字符。"; [[ -z "$USER_PASSWORD" || "$USER_PASSWORD" =~ ^[A-Za-z0-9_.:@%+=,-]+$ ]] || die "密码包含不安全字符。"; valid_net "$VPN_CIDR" || die "VPN CIDR 无效。"; valid_ip "$LOCAL_IP" || die "local-ip 无效。"; [[ "$CLIENT_POOL" =~ ^[0-9.]+-[0-9.]+$ ]] || die "client-pool 格式无效。"; valid_ip "${CLIENT_POOL%-*}" && valid_ip "${CLIENT_POOL#*-}" || die "client-pool IP 无效。"; valid_dns "$DNS" || die "DNS 无效。"; if [[ ! "$MTU" =~ ^[0-9]+$ ]] || ((MTU<576||MTU>1460)); then die "MTU 必须在 576-1460。"; fi; [[ -z "$INTERFACE" || "$INTERFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "网卡名无效。"; }
root_ubuntu(){ ((EUID==0)) || die "请使用 sudo。"; source /etc/os-release; [[ ${ID:-} == ubuntu ]] || die "仅支持 Ubuntu。"; }
ensure_bootstrap(){ command -v python3 >/dev/null && command -v openssl >/dev/null && return; [[ "$DRY_RUN" != true ]] || die "演练模式需要预先安装 python3 和 openssl。"; apt-get update -q; apt-get install -y --no-install-recommends python3-minimal openssl; }
confirm(){ [[ "$ASSUME_YES" == true ]] && return; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy]$ ]]; }
random_secret(){ openssl rand -base64 "$1" | tr -d '=+/\n' | cut -c1-32; }
detect_endpoint(){ [[ -n "$ENDPOINT" ]] && return; ENDPOINT="$(curl -4fsS --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')"; [[ -n "$ENDPOINT" ]] || die "无法自动探测公网 IPv4，请使用 --endpoint。"; }
detect_iface(){ [[ -n "$INTERFACE" ]] && return; INTERFACE="$(ip route show default 0.0.0.0/0 | awk '{print $5; exit}')"; [[ -n "$INTERFACE" ]] || die "无法自动探测出口网卡，请使用 --interface。"; }
load_settings(){ [[ -f "$SETTINGS" ]] || return; # shellcheck disable=SC1090
source "$SETTINGS"; }
save_settings(){ install -d -m 700 "$STATE_DIR"; cat >"$SETTINGS" <<EOF_SETTINGS
ENDPOINT='$ENDPOINT'
VPN_CIDR='$VPN_CIDR'
LOCAL_IP='$LOCAL_IP'
CLIENT_POOL='$CLIENT_POOL'
DNS='$DNS'
MTU='$MTU'
INTERFACE='$INTERFACE'
EOF_SETTINGS
chmod 600 "$SETTINGS"; }
write_ipsec(){ cat >/etc/ipsec.conf <<EOF_IPSEC
config setup
  uniqueids=no

conn easy-install-l2tp
  auto=add
  keyexchange=ikev1
  authby=secret
  type=transport
  left=%any
  leftprotoport=17/1701
  right=%any
  rightprotoport=17/%any
  ike=aes256-sha1-modp2048,aes128-sha1-modp2048!
  esp=aes256-sha1,aes128-sha1!
EOF_IPSEC
printf '%%any %%any : PSK "%s"\n' "$PSK" >/etc/ipsec.secrets; chmod 600 /etc/ipsec.secrets; }
write_xl2tp(){ cat >/etc/xl2tpd/xl2tpd.conf <<EOF_XL2TP
[global]
port = 1701

[lns default]
ip range = ${CLIENT_POOL}
local ip = ${LOCAL_IP}
require chap = yes
refuse pap = yes
require authentication = yes
name = easy-install-l2tp
ppp debug = no
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF_XL2TP
cat >/etc/ppp/options.xl2tpd <<EOF_PPP
ipcp-accept-local
ipcp-accept-remote
ms-dns ${DNS%%,*}
ms-dns ${DNS#*,}
asyncmap 0
auth
crtscts
lock
hide-password
modem
mtu ${MTU}
mru ${MTU}
nodefaultroute
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
EOF_PPP
chmod 600 /etc/ppp/options.xl2tpd; }
write_firewall(){ install -d -m 755 /usr/local/lib/easy-install; cat >"$FIREWALL" <<EOF_FW
#!/usr/bin/env bash
set -Eeuo pipefail
iptables -C INPUT -p udp --dport 500 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -C INPUT -p udp --dport 4500 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -C INPUT -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
iptables -C FORWARD -s ${VPN_CIDR} -j ACCEPT 2>/dev/null || iptables -A FORWARD -s ${VPN_CIDR} -j ACCEPT
iptables -t nat -C POSTROUTING -s ${VPN_CIDR} -o ${INTERFACE} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${VPN_CIDR} -o ${INTERFACE} -j MASQUERADE
EOF_FW
chmod 755 "$FIREWALL"; cat >"$FIREWALL_UNIT" <<EOF_UNIT
[Unit]
Description=Easy Install L2TP firewall rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${FIREWALL}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_UNIT
}
write_sysctl(){ cat >/etc/sysctl.d/99-easy-install-l2tp.conf <<'EOF_SYSCTL'
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
EOF_SYSCTL
sysctl --system >/dev/null; }
set_user(){ local file="/etc/ppp/chap-secrets"; touch "$file"; chmod 600 "$file"; if grep -Eq "^${USER_NAME}[[:space:]]+" "$file"; then [[ "$FORCE" == true ]] || die "用户已存在；使用 --force 更新密码。"; grep -Ev "^${USER_NAME}[[:space:]]+" "$file" >"$file.tmp"; mv "$file.tmp" "$file"; fi; printf '%s * %s *\n' "$USER_NAME" "$USER_PASSWORD" >>"$file"; }
install_l2tp(){ root_ubuntu; ensure_bootstrap; validate; confirm "安装 L2TP/IPsec？" || die "已取消。"; export DEBIAN_FRONTEND=noninteractive; run apt-get update -q; run apt-get install -y strongswan xl2tpd ppp iptables curl openssl python3-minimal; [[ "$DRY_RUN" == true ]] && { ok "演练完成。"; return; }; detect_endpoint; detect_iface; [[ -n "$PSK" ]] || PSK="$(random_secret 32)"; [[ -n "$USER_PASSWORD" ]] || USER_PASSWORD="$(random_secret 24)"; save_settings; write_ipsec; write_xl2tp; set_user; write_firewall; write_sysctl; systemctl daemon-reload; systemctl enable --now strongswan-starter xl2tpd easy-install-l2tp-firewall.service; systemctl restart strongswan-starter xl2tpd; ok "L2TP/IPsec 已安装。服务器：$ENDPOINT；PSK：$PSK；用户：$USER_NAME；密码：$USER_PASSWORD"; warn "L2TP/IPsec 兼容性好但安全性弱于 WireGuard/IKEv2；请优先使用更现代的 VPN。"; }
add_user(){ root_ubuntu; load_settings; validate; [[ "$DRY_RUN" != true ]] || die "add 不支持 --dry-run。"; [[ -n "$USER_PASSWORD" ]] || USER_PASSWORD="$(random_secret 24)"; set_user; systemctl restart xl2tpd; ok "用户已添加/更新：$USER_NAME；密码：$USER_PASSWORD"; }
revoke(){ root_ubuntu; validate; [[ "$DRY_RUN" != true ]] || die "revoke 不支持 --dry-run。"; local file="/etc/ppp/chap-secrets"; [[ -f "$file" ]] || die "找不到用户文件。"; grep -Ev "^${USER_NAME}[[:space:]]+" "$file" >"$file.tmp"; mv "$file.tmp" "$file"; chmod 600 "$file"; systemctl restart xl2tpd; ok "用户已删除：$USER_NAME"; }
list_users(){ root_ubuntu; awk '!/^#/ && NF>=4 {print $1}' /etc/ppp/chap-secrets 2>/dev/null | sort -u; }
status(){ root_ubuntu; systemctl --no-pager --full status strongswan-starter xl2tpd || true; ss -lunp | grep -E ':(500|4500|1701)\b' || true; }
uninstall(){ root_ubuntu; [[ "$DRY_RUN" != true ]] || die "uninstall 不支持 --dry-run。"; confirm "确定卸载 L2TP/IPsec？" || die "已取消。"; systemctl disable --now xl2tpd strongswan-starter easy-install-l2tp-firewall.service 2>/dev/null || true; apt-get purge -y xl2tpd strongswan ppp; rm -f "$FIREWALL" "$FIREWALL_UNIT" /etc/sysctl.d/99-easy-install-l2tp.conf; [[ "$KEEP_CONFIG" == true ]] || rm -rf "$STATE_DIR" /etc/xl2tpd/xl2tpd.conf /etc/ppp/options.xl2tpd; sysctl --system >/dev/null || true; ok "L2TP/IPsec 已卸载。"; }
main(){ parse "$@"; [[ "$DRY_RUN" != true || "$COMMAND" == install ]] || die "--dry-run 仅支持 install。"; [[ "$VERBOSE" == true ]] && set -x; case "$COMMAND" in install) install_l2tp;; add) add_user;; revoke) revoke;; list) list_users;; status) status;; uninstall) uninstall;; esac; }
main "$@"
