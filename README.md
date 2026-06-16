# Easy Install

为常用服务提供真正省心的一键部署脚本：新手一路回车即可完成，熟悉系统的用户也可以细调每个关键选项。

## Ubuntu 一键部署 Docker Engine

通过 Docker 官方 APT 仓库安装 Docker Engine、Buildx 和 Compose 插件：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/docker.sh
chmod +x docker.sh
sudo ./docker.sh
```

常用管理命令：

```bash
# 安装并允许指定用户运行 docker（docker 组等同 root 权限）
sudo ./docker.sh --yes --user ubuntu

# 自定义数据目录、日志轮转和 IPv6
sudo ./docker.sh --data-root /data/docker --log-size 20m --log-files 5 --ipv6

sudo ./docker.sh status
sudo ./docker.sh upgrade

# 默认保留镜像、容器和卷；明确指定后才删除数据
sudo ./docker.sh uninstall
sudo ./docker.sh uninstall --purge-data
```

脚本会配置容器 JSON 日志轮转和 `live-restore`，完成后运行官方
`hello-world` 镜像进行验证。Docker 发布端口可能绕过部分 UFW 规则；生产环境应把
自定义访问控制放在 `DOCKER-USER` 链中。

## Ubuntu 一键部署 Nginx

默认安装 Ubuntu 仓库中的 Nginx 并创建一个静态默认站点：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/nginx.sh
chmod +x nginx.sh
sudo ./nginx.sh
```

静态站点、反向代理和自动 HTTPS 示例：

```bash
# 静态站点
sudo ./nginx.sh add --domain www.example.com --root /var/www/example

# 反向代理 Web 应用
sudo ./nginx.sh add --domain app.example.com --proxy http://127.0.0.1:3000

# 使用 Certbot 申请 Let's Encrypt 证书并跳转 HTTPS
sudo ./nginx.sh add --domain app.example.com \
  --proxy http://127.0.0.1:3000 --tls --email admin@example.com --force

sudo ./nginx.sh list
sudo ./nginx.sh status
sudo ./nginx.sh remove --domain app.example.com
sudo ./nginx.sh uninstall
```

申请证书前，请确保域名已经解析到服务器，且云安全组和防火墙开放 TCP 80/443。
站点配置会在写入后执行 `nginx -t`，只有配置测试成功才会重新加载服务。

## Ubuntu 一键部署 PostgreSQL

默认安装 Ubuntu 仓库中的 PostgreSQL，并创建 `app` 数据库和独立登录用户：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/postgresql.sh
chmod +x postgresql.sh
sudo ./postgresql.sh
```

常用操作：

```bash
# 自定义数据库、用户和密码
sudo ./postgresql.sh --database production --user appuser \
  --password 'use-a-long-random-password'

# 创建更多数据库，或更新已有数据库所有者和用户密码
sudo ./postgresql.sh create --database analytics --user analyst
sudo ./postgresql.sh create --database production --user appuser \
  --password 'new-long-random-password' --force

# 生成 pg_dump custom-format 备份
sudo ./postgresql.sh backup --database production --backup-dir /srv/backups

sudo ./postgresql.sh list
sudo ./postgresql.sh status
sudo ./postgresql.sh uninstall
```

PostgreSQL 默认只监听本机。远程访问必须同时指定监听地址和允许的客户端 CIDR：

```bash
sudo ./postgresql.sh --listen '*' --allow-cidr 10.10.0.0/16
```

请同时使用云安全组或防火墙限制 TCP 5432，禁止向整个互联网开放数据库端口。
卸载默认保留数据库文件；只有 `--purge-data` 才会删除数据。

## Ubuntu 一键部署 Redis

默认只监听 `127.0.0.1` 和 `::1`，启用 protected mode、密码认证和 AOF：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/redis.sh
chmod +x redis.sh
sudo ./redis.sh
```

常用配置：

```bash
# 设置密码、内存上限和淘汰策略
sudo ./redis.sh --password 'a-long-random-secret' \
  --maxmemory 512mb --policy allkeys-lru

# 测试认证
sudo ./redis.sh test --password 'a-long-random-secret'
sudo ./redis.sh status --password 'a-long-random-secret'

# 默认保留数据；显式指定才删除
sudo ./redis.sh uninstall
sudo ./redis.sh uninstall --purge-data
```

不建议把 Redis 暴露到公网。如果确实需要远程访问，必须显式使用 `--remote` 和至少
16 字符密码，并通过云安全组或防火墙仅允许可信 CIDR 访问 TCP 6379：

```bash
sudo ./redis.sh --remote --password 'very-long-random-secret'
```


## Ubuntu 一键部署 MySQL

默认安装 Ubuntu 仓库中的 MySQL，创建 `app` 数据库和独立应用用户：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/mysql.sh
chmod +x mysql.sh
sudo ./mysql.sh
```

常用操作：

```bash
# 自定义数据库、用户和密码
sudo ./mysql.sh --database production --user appuser \
  --password 'use-a-long-random-password'

# 创建更多数据库，或更新已有用户密码
sudo ./mysql.sh create --database analytics --user analyst
sudo ./mysql.sh create --database production --user appuser \
  --password 'new-long-random-password' --force

# 备份为 gzip 压缩 SQL
sudo ./mysql.sh backup --database production --backup-dir /srv/backups/mysql

sudo ./mysql.sh list
sudo ./mysql.sh status
sudo ./mysql.sh uninstall
```

MySQL 默认只监听本机。若使用 `--bind 0.0.0.0` 开启远程访问，请务必配合云安全组
或 UFW 仅允许可信来源访问 TCP 3306。卸载默认保留 `/var/lib/mysql`，只有
`--purge-data` 才会删除数据。

## Ubuntu 一键部署 Node.js

使用 NodeSource APT 仓库安装 Node.js，并可为已有应用生成 systemd 服务：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/nodejs.sh
chmod +x nodejs.sh
sudo ./nodejs.sh --major 22
```

应用服务示例：

```bash
# 在 /srv/myapp 中运行 npm start，并注入 PORT=3000
sudo ./nodejs.sh service --app-dir /srv/myapp --user www-data \
  --service myapp --start-cmd 'npm start' --port 3000

sudo ./nodejs.sh status --service myapp
sudo journalctl -u myapp --no-pager -n 100
sudo ./nodejs.sh uninstall
```

生成的 systemd unit 默认启用 `NoNewPrivileges`、`PrivateTmp` 和 `ProtectSystem=full`。
建议把 Node.js 应用放在 Nginx/Caddy 反向代理之后，不要直接向公网暴露开发端口。

## Ubuntu 一键初始化 UFW 防火墙

适合在新服务器上快速建立“默认拒绝入站、允许出站、保留 SSH”的基础规则：

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/ufw.sh
chmod +x ufw.sh
sudo ./ufw.sh --ssh-port 22 --ports 80,443
```

常用操作：

```bash
# 放行多个服务端口，UDP 端口可带协议后缀
sudo ./ufw.sh allow --ports 5432,6379,51820/udp

sudo ./ufw.sh status
sudo ./ufw.sh reset
```

启用防火墙前请确认实际 SSH 端口正确，并尽量先在云厂商安全组中保留紧急访问方式。

## Ubuntu 一键部署 WireGuard

WireGuard 配置简单、性能优秀，特别适合手机、笔记本和服务器之间的日常 VPN
连接。脚本会自动配置密钥、转发、NAT 和 systemd 服务，并为每台设备生成独立配置
与二维码。

### 最懒安装方式

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/wireguard.sh
chmod +x wireguard.sh
sudo ./wireguard.sh
```

无人值守安装：

```bash
sudo ./wireguard.sh --yes --endpoint vpn.example.com --client phone
```

安装完成后会在当前目录生成 `phone.conf` 和 `phone.png`。可将 `.conf` 导入桌面
WireGuard 客户端，或用手机客户端扫描二维码图片。

> 请在云安全组和外部防火墙放行所选 UDP 端口，默认为 **UDP 51820**。服务器位于
> NAT 后方时，还需要把该 UDP 端口转发到服务器。

### 客户端管理

```bash
# 为每台设备创建独立配置和密钥
sudo ./wireguard.sh add --client laptop --output "$HOME"

# 列出或删除客户端
sudo ./wireguard.sh list
sudo ./wireguard.sh remove --client old-phone

# 重新导出配置，并在终端显示二维码
sudo ./wireguard.sh show --client phone --output "$HOME"

# 查看接口状态和最近握手
sudo ./wireguard.sh status

# 卸载；--keep-keys 可保留密钥和客户端资料
sudo ./wireguard.sh uninstall
```

每台设备必须使用独立配置。客户端文件包含私钥和预共享密钥，默认以 `0600` 权限
保存，不能通过公开聊天、网盘或邮件明文传输。

### 高级能力

执行 `./wireguard.sh --help` 查看全部选项。脚本支持：

- 自定义 UDP 端口、IPv4 VPN 网段、DNS、MTU 和 PersistentKeepalive。
- 默认接管 IPv4/IPv6 路由以避免 IPv6 泄漏，也可使用 `--split-tunnel` 或完全自定义 `--allowed-ips`。
- 可选 IPv6 ULA 地址池、IPv6 转发和 NAT66。
- 自动分配不重复的客户端 IPv4/IPv6 地址。
- 独立客户端私钥与额外预共享密钥，删除后立即同步运行中的接口。
- 配置文件、PNG 二维码和终端二维码导出。
- `--yes` 无人值守、`--dry-run` 演练、强制重装和密钥保留。

### WireGuard 文件位置

| 路径 | 用途 |
| --- | --- |
| `/etc/wireguard/wg0.conf` | WireGuard 服务端配置 |
| `/etc/wireguard/easy-install/server.key` | 服务端私钥 |
| `/etc/wireguard/easy-install/peers` | 客户端密钥、元数据和配置备份 |
| `/etc/wireguard/easy-install/settings.env` | 安装与管理参数 |
| `/etc/sysctl.d/99-easy-install-wireguard.conf` | IPv4/IPv6 转发设置 |

常用排错命令：

```bash
sudo wg show wg0
sudo systemctl status wg-quick@wg0
sudo journalctl -u wg-quick@wg0 --no-pager -n 100
sudo ss -lunp | grep 51820
```

## Ubuntu 一键部署 IKEv2/IPsec

IPsec 脚本使用 strongSwan 部署现代 IKEv2 VPN。Windows、macOS、iOS、Android
和 Linux 均可使用系统自带或常见的 IKEv2 客户端，不需要安装 OpenVPN 客户端。

### 最懒安装方式

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/ipsec.sh
chmod +x ipsec.sh
sudo ./ipsec.sh
```

脚本会自动探测公网 IPv4，安装 strongSwan，创建私有 CA 和服务端证书，配置
EAP-MSCHAPv2 用户认证、IPv4 转发、NAT 及持久化防火墙规则，并输出客户端连接资料
和需要安装的 CA 证书。

如果服务器使用域名，推荐明确指定域名，使服务端证书包含正确的身份：

```bash
sudo ./ipsec.sh --yes --endpoint vpn.example.com --user phone
```

> 请先在云安全组和外部防火墙放行 **UDP 500** 与 **UDP 4500**。服务器处于
> NAT 后方时，还需将这两个 UDP 端口转发到服务器。

### 账号管理

```bash
# 创建账号；不传 --password 时生成随机高强度密码
sudo ./ipsec.sh add --user laptop --output "$HOME"

# 显式设置或更新密码
sudo ./ipsec.sh add --user laptop --password 'long-random-password' --force

# 查看、删除账号
sudo ./ipsec.sh list
sudo ./ipsec.sh remove --user old-phone

# 重新导出某个账号的连接资料与 CA 证书
sudo ./ipsec.sh export --user laptop --output "$HOME"

# 状态与卸载
sudo ./ipsec.sh status
sudo ./ipsec.sh uninstall
```

每台设备应使用不同账号。账号密码和客户端连接资料均以 `0600` 权限保存；请通过
安全渠道传输，设备遗失后及时删除对应账号。更新密码或删除账号会重启 IPsec，
以便立即断开使用旧凭据的活动会话。

### 高级能力

执行 `./ipsec.sh --help` 查看完整参数。脚本支持：

- 自定义客户端 IPv4 地址池以及 Cloudflare、Google、Quad9、系统或自定义 DNS。
- 自定义 strongSwan IKE/ESP 加密提议和证书有效期。
- 默认全隧道，或通过 `--routes 10.0.0.0/8,192.168.0.0/16` 指定分流业务网段。
- 自动生成 RSA CA 和服务端证书，并根据入口类型写入 DNS 或 IP SAN。
- 账号添加、强制更新、删除、列表和客户端资料重新导出。
- 幂等 iptables 规则、MSS 调整、systemd 防火墙持久化和安全 sysctl。
- `--yes` 无人值守、`--dry-run` 演练和 `--keep-ca` 卸载保留。

客户端首次连接前必须安装并信任输出的 `easy-install-ikev2-ca.pem`，VPN 类型选择
IKEv2，认证方式选择用户名和密码，服务器地址与远程 ID 均填写安装时使用的入口。

### IPsec 文件位置

| 路径 | 用途 |
| --- | --- |
| `/etc/ipsec.conf` | strongSwan IKEv2 连接配置 |
| `/etc/ipsec.secrets` | 服务端私钥引用和 EAP 账号 |
| `/etc/ipsec.d/easy-install` | CA、服务端证书、账号数据库和安装设置 |
| `/usr/local/lib/easy-install/ipsec-firewall.sh` | IPsec 转发与 NAT 规则 |
| `/etc/systemd/system/easy-install-ipsec-firewall.service` | 防火墙持久化服务 |

常用排错命令：

```bash
sudo ipsec statusall
sudo journalctl -u strongswan-starter --no-pager -n 100
sudo ss -lunp | grep -E ':(500|4500)\b'
sudo /usr/local/lib/easy-install/ipsec-firewall.sh start
```

## Ubuntu 一键部署 OpenVPN

### 最懒安装方式

```bash
curl -fsSLO https://raw.githubusercontent.com/laman-heredia/Easy-Install/main/scripts/openvpn.sh
chmod +x openvpn.sh
sudo ./openvpn.sh
```

脚本会自动安装依赖、探测公网 IPv4、创建 PKI、配置转发与防火墙、启动 OpenVPN，并在当前目录生成可直接导入 OpenVPN Connect、Tunnelblick 或 NetworkManager 的 `client.ovpn`。

无人值守安装：

```bash
sudo ./openvpn.sh --yes --client phone --endpoint vpn.example.com
```

> 运行前请确认云厂商安全组/外部防火墙已放行 `1194/UDP`（或你通过参数选择的端口和协议）。容器或 VPS 还必须提供 `/dev/net/tun`。

### 日常管理

```bash
# 创建另一个独立客户端配置
sudo ./openvpn.sh add --client laptop --output "$HOME"

# 查看、吊销客户端
sudo ./openvpn.sh list
sudo ./openvpn.sh revoke --client old-phone

# 查看服务状态和关键配置
sudo ./openvpn.sh status

# 卸载（加 --keep-ca 可保留 PKI）
sudo ./openvpn.sh uninstall
```

每台设备应使用独立证书，避免多人共享同一个 `.ovpn`。客户端配置包含私钥，默认权限为 `0600`，请通过安全渠道传输。

### 可调选项

执行 `./openvpn.sh --help` 可查看完整参数。主要能力包括：

- Ubuntu 20.04、22.04、24.04 和 26.04 版本检测；其他 Ubuntu 版本会警告后尝试安装。
- UDP/TCP、监听端口、公网 IP/域名、VPN IPv4 网段与掩码。
- Cloudflare、Google、Quad9、系统或自定义 DNS。
- 默认 IPv4 全隧道并阻断隧道外 IPv6；启用 VPN IPv6 后同时接管 IPv4/IPv6 默认路由，也可使用 `--split-tunnel` 分流。
- `tls-crypt`（默认）或 `tls-auth`，可调整数据加密套件和认证摘要。
- 可选 IPv6 转发、自定义 IPv6 VPN 网段。
- 客户端添加、列出、吊销和 CRL 更新。
- 幂等的 systemd 防火墙规则、服务状态检查、卸载与 CA 保留。
- `--dry-run` 演练模式和 `--yes` 无人值守模式。

压缩因为存在 VORACLE 类风险而默认关闭；只有兼容旧客户端时才建议使用 `--compression`。

### 文件位置

| 路径 | 用途 |
| --- | --- |
| `/etc/openvpn/server/server.conf` | OpenVPN 服务配置 |
| `/etc/openvpn/easy-install/pki` | Easy-RSA PKI（高度敏感） |
| `/etc/openvpn/easy-install/clients` | 已生成客户端配置的受限备份 |
| `/etc/openvpn/easy-install/settings.env` | 脚本管理参数 |
| `/usr/local/lib/easy-install/openvpn-firewall.sh` | NAT/转发规则 |
| `/etc/systemd/system/easy-install-openvpn-firewall.service` | 防火墙规则持久化服务 |

### 排错

```bash
sudo systemctl status openvpn-server@server
sudo journalctl -u openvpn-server@server --no-pager -n 100
sudo ss -lunp | grep 1194
sudo /usr/local/lib/easy-install/openvpn-firewall.sh start
```

如果客户端连不上，依次检查：云安全组、服务器本机防火墙、域名解析、端口/协议是否一致，以及 VPS 是否启用了 TUN。客户端能连接但不能上网时，检查 `net.ipv4.ip_forward`、出口网卡和上游网络是否允许 NAT。

## 安全说明

脚本使用 Ubuntu 官方仓库中的 OpenVPN 与 Easy-RSA，默认启用 TLS 1.2 下限、独立客户端证书、证书吊销列表、`tls-crypt` 和 AEAD 数据加密套件。生产环境仍应定期更新 Ubuntu、保护 CA 私钥、为每台设备签发独立证书并及时吊销遗失设备。

## License

[MIT](LICENSE)
