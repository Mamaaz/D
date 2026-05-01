# 部署 Checklist

本文档基于一次真实部署 (Debian 12 / 1G RAM / 20G 盘) 编写，覆盖前置条件、步骤顺序、遇到过的失败场景与排查方法。

## 0. 前置条件

| 项 | 要求 | 为什么 |
| --- | --- | --- |
| OS | Debian 11+ / Ubuntu 20.04+ (x86_64 或 arm64) | systemd + 现代 glibc，sing-box / xray 二进制可直接跑 |
| 内存 | ≥ 512MB | sing-box 启动约 10MB，autocert 内存可忽略；512 留给系统 |
| 端口 80 | 空闲且对公网可达 | autocert HTTP-01 challenge 必须 |
| 端口 443 | 可选（如装 Hysteria2/AnyTLS） | 这两个协议默认占 443；与 subscribe 端口分开 |
| 域名 | 已 A 记录到 VPS IP | `dig +short <domain>` 必须直接返回 VPS IP |
| Cloudflare | **关橙云（DNS only / 灰云）** | 橙云会代理 :80，autocert 拿不到真实 challenge 应答 |
| 出口 | 能直连 GitHub | 下载 sing-box / xray 二进制 + 后续 update |

DNS 验证：

```bash
dig +short <your-domain> @1.1.1.1
# 必须直接返回 VPS IP，如返回 CF anycast IP (104.21.x.x / 172.67.x.x) 说明橙云没关
```

## 1. 安装

### 在线安装（推荐）

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)
```

install.sh 从 GitHub Releases 拉对应平台 (linux/amd64 或 linux/arm64) 的预编译
二进制。CI（`.github/workflows/release.yml`）在 `git tag v*` push 时自动触发，
产出 binary + checksums 上传到 release。

### 离线 / 调试：本地交叉编译 + scp

```bash
# 本地（macOS/Linux）
cd /path/to/Mamaaz/D
GOOS=linux GOARCH=amd64 go build \
  -ldflags "-s -w -X main.version=$(git describe --tags --always)" \
  -o /tmp/proxy-manager ./cmd/proxy-manager
scp /tmp/proxy-manager root@<vps>:/usr/local/bin/proxy-manager

# VPS 上
ssh root@<vps>
chmod +x /usr/local/bin/proxy-manager
ln -sf /usr/local/bin/proxy-manager /usr/local/bin/pm
proxy-manager --version
```

## 2. 选择部署顺序

> 关键决定：**先装协议，后装订阅服务**？还是相反？

| 协议 | 是否要 LE 证书 | 用什么拿证书 | 与 subscribe 服务的冲突 |
| --- | --- | --- | --- |
| Snell + ShadowTLS | 否 | — | 无 |
| SS2022 + ShadowTLS | 否 | — | 无 |
| VLESS Reality | 否 | — | 无 |
| Hysteria2 | 是 | acme.sh standalone (:80) | 与 subscribe 的 autocert 抢 :80 |
| AnyTLS | 是 | acme.sh standalone (:80) | 与 subscribe 的 autocert 抢 :80 |

**推荐顺序**：

1. 先装无证书协议（Reality / Snell / SS2022）—— 不抢 :80
2. 再装 Hysteria2 / AnyTLS（如需）—— 一次拿好证书，自动续期由 acme.sh 后台 cron 接手
3. 最后启用 subscribe 服务 —— autocert 这时拿到 :80，签订阅域名证书

如果反过来（subscribe 先），后续装 Hysteria2/AnyTLS 时 acme.sh standalone 会撞 :80。

## 3. 安装协议

### VLESS Reality（无证书，最简单）

```bash
proxy-manager --action install_reality
# 交互：
#   端口（默认 443，建议改 8443/12345 等避免与 subscribe 冲突）
#   选 SNI 目标（推荐 1 = www.apple.com）
```

完成后 `nodes.json` 落库，`sing-box-reality.service` 启动。

### Hysteria2

```bash
proxy-manager --action install_hysteria2
# 交互：端口 / 是否启用 obfs / 域名 / 邮箱
```

域名必须有效——acme.sh 会向 LE 申请证书；CF 橙云需关闭。

### Snell + ShadowTLS

```bash
proxy-manager --action install_snell
# 交互：Snell 端口 / Snell 密码 / ShadowTLS 端口 / SNI
```

## 4. 启用订阅服务

```bash
proxy-manager subscribe enable \
  --domain sub.example.com \
  --email you@example.com \
  --port 18443
```

- `--port` 不填会随机 10000-65000；显式指定方便防火墙记录
- 首次 HTTPS 请求触发 autocert 实际签证（懒签），约 5-10s
- 证书缓存在 `/var/lib/proxy-manager/autocert/`

启用后立即测：

```bash
curl -I https://<domain>:<port>/s/json/<token>
# HTTP/1.1 405 Method Not Allowed  ← HEAD 不支持，说明 TLS 已通
curl https://<domain>:<port>/s/surge/<token>
# 输出实际 Surge 配置行
```

## 5. 健康检查

```bash
proxy-manager doctor
```

输出示例：

```
[Protocols]
  ✓ VLESS-Reality          sing-box-reality         active       :8443

[Subscribe service]
  ✓ active
    Domain: sub.example.com
    Port:   18443
    证书: 89 天后过期

[General]
  Config:  /etc/proxy-manager/nodes.json (1 nodes)
```

证书 < 14 天会标黄，过期标红。

## 6. 升级（已部署机）

```bash
proxy-manager update
# 内部走 install.sh update 路径，自动调 service-rebuild
```

`service-rebuild` 会：
- 读 `nodes.json` 列出已装协议
- 逐个重写 systemd unit（拿到 PR3 的 User= 降权 + v4.0.6 的 subscribe 服务降权）
- v4.0.7+ 自动迁移旧 sing-box-reality.service → xray-reality.service（详见 §7-X）
- daemon-reload + restart

老部署只升级二进制不会自动改 unit；必须跑一次 `service-rebuild` 或 `update`。

### 6-X 内核管理（v4.0.8+）

```bash
proxy-manager kernel               # 列出所有内核 + 当前/最新版本
proxy-manager kernel upgrade       # 交互选要升的内核
proxy-manager kernel upgrade --all # 一键全升
proxy-manager kernel upgrade xray-core
```

输出范例：

```
Kernel       Current    Latest      Status   Used by
xray-core    26.3.27    v26.3.27    ✓ 最新    VLESS Reality
sing-box     1.13.11    v1.13.12    可升级    SS-2022, Hysteria2, AnyTLS
```

升级会自动 stop services → backup binary → download → start services。失败回滚。

## 7. Reality 内核：xray-core（v4.0.7+）

从 v4.0.7 起 Reality 协议跑在 **xray-core**（之前是 sing-box）。理由：Reality 是
XTLS 团队的发明，新特性（vision-udp443 / 新 fingerprint / 未来的 MLKEM-768 后量子）
先进 xray，sing-box 跟进通常滞后 1-3 周。

**其他协议保持 sing-box** —— 它们不是 xray 的强项（xray 不支持 Hysteria2 / AnyTLS / ShadowTLS）。

| 协议 | 内核 |
|---|---|
| Snell + ShadowTLS | snell-server + shadow-tls (独立 binary) |
| SS-2022 + ShadowTLS | sing-box |
| **VLESS Reality** | **xray-core** |
| Hysteria2 | sing-box |
| AnyTLS | sing-box |

**升级路径**：v4.0.6 → v4.0.7 部署后跑 `proxy-manager service-rebuild`，自动迁移：
- 卸 sing-box-reality.service + 删 /etc/sing-box-reality/
- 下载 xray binary
- 用现有 keypair / UUID / shortID / SNI 重建 xray config（客户端无感知）
- 起 xray-reality.service

**没默认开的 Reality 新特性**：MLKEM-768 后量子 — 客户端兼容性问题（多数客户端 v2box/NekoBox/sing-box 还没跟上）。需要时手动改 config 启用。

## 8. Reality SNI 候选评估（v4.0.5+）

Reality 协议要选一个 TLS 1.3 + X25519 + h2 + 证书可信 的 SNI 目标做仿冒。
完整流程：

1. **本地扫描**（Mac/Linux）：用 RealiTLScanner 对一段 IP 发起 TLS 握手，
   筛出 Reality 兼容的 host。**必须本地，VPS 扫会被云厂商风控当扫描器封机**。
   ```bash
   ./RealiTLScanner -addr 193.32.150.0/24 -thread 8 -timeout 5 -out scan.csv
   ```
2. **VPS 视角打分**：把 CSV 上传到 VPS，跑 sni-rank 并发探测 + 自动排序：
   ```bash
   cat scan.csv | proxy-manager sni-rank --top 10
   ```
   或在交互菜单选 #14「Reality SNI 候选评估」直接粘 CSV，看 ranked 表 +
   一键应用推荐。
3. **应用**：
   ```bash
   proxy-manager edit reality --field sni --value <推荐 host>
   ```

打分规则透明：TLS<1.3 / 证书无效直接淘汰；HTTP 200 加分；CDN (cloudflare/
akamai/...) 减 300 分；隐版本 nginx 加分；TLS RTT 直接当负分。

> ⚠️ Surge / Clash 增强模式用户：扫描器和 openssl 都会被 fake DNS 拦截，
> 必须在代理配置 [Rule] 顶部加 `PROCESS-NAME,RealiTLScanner,DIRECT` +
> `PROCESS-NAME,openssl,DIRECT`，否则结果会被反代后端污染。

## 9. 修改协议配置（无需 reinstall，v4.0.3+）

```bash
proxy-manager edit                           # 全交互
proxy-manager edit reality --field sni --value www.apple.com
proxy-manager edit snell --field shadowtls-password --value <new>
proxy-manager edit ss2022 --field tls-domain --value <new>
```

支持的字段：

| 协议 | 可改字段 |
| --- | --- |
| reality | port / uuid / short-id / sni |
| snell | snell-port / snell-psk / shadowtls-port / shadowtls-password / tls-domain |
| ss2022 | ss-port / ss-password / shadowtls-port / shadowtls-password / tls-domain |
| Hysteria2 / AnyTLS | (暂不支持，涉及 ACME 重签——请用 install 重装) |

故意不暴露的字段：Reality 的 private/public key、SS-2022 的 encrypt method
——改了等于 invalidate 所有客户端，重装表达更清楚。

## 10. 卸载

```bash
proxy-manager --action uninstall_service       # 卸某个协议（交互选）
proxy-manager subscribe disable                # 停订阅服务（保留 token，可恢复）
proxy-manager --action uninstall_pm            # 卸 proxy-manager 本身
```

`subscribe disable` 不会删 token；下次 `enable` 会沿用同一 token 即所有旧 URL 立刻失效请用 `rotate-token`。

## 故障排查

### 订阅服务启动后立即失败 (status=226/NAMESPACE)

**症状**：

```
proxy-manager-subscribe.service: Failed to set up mount namespacing:
/run/systemd/unit-root/var/lib/proxy-manager: No such file or directory
```

**原因**：unit 用 `ProtectSystem=full` + `ReadWritePaths=/var/lib/proxy-manager`，
systemd 在 namespace 阶段要 bind-mount 这些路径，路径不存在直接挂。

**修复**：v4.0.1+ 已在 `Install()` 里 `mkdir -p /var/lib/proxy-manager/autocert`。
旧版手工补：

```bash
mkdir -p /var/lib/proxy-manager/autocert
chmod 700 /var/lib/proxy-manager/autocert
systemctl restart proxy-manager-subscribe
```

### autocert 签证超时

**症状**：第一次 curl HTTPS 卡 30s+ 后 timeout，journalctl 显示 acme challenge 失败。

**排查**：

```bash
# 1. 80 端口公网可达？
curl -I http://<domain>/   # 从 Mac 直连，要返回 404 或 308 (autocert 会重定向 well-known)
# 不通 → 检查云厂商安全组、iptables、ISP 是否封 80

# 2. CF 橙云未关？
dig +short <domain> @1.1.1.1   # 要返回 VPS IP，不是 104.21.x.x

# 3. autocert 自身日志
journalctl -u proxy-manager-subscribe -n 50 | grep -i acme
```

### 订阅 URL 返回 404

- 路径错误：必须是 `/s/<format>/<token>`，format ∈ {surge,clash,singbox,xray,json}
- token 错误：404 而非 403，对扫描器不透明（这是 by-design）
- 服务没起：`systemctl is-active proxy-manager-subscribe`

### Surge 订阅了但 Reality 节点连不上

**预期行为**：Surge 不支持 VLESS-Reality 协议；订阅 URL 输出的 `Reality = vless,...`
是给 XSurge（Mac 状态栏 app）解析后通过本地 xray 桥接用的，不能直接给 Surge 用。

如要全 Surge 原生连接，只用 Snell / SS2022+ShadowTLS / Hysteria2 / AnyTLS 协议。

### 协议服务启动后立刻退出

```bash
systemctl status sing-box-reality   # 看 Active: failed (Result: exit-code)
journalctl -u sing-box-reality -n 30
# 常见：端口被占 / 配置 JSON 语法错 / sing-box 二进制版本不兼容
```

`/etc/sing-box-reality/config.json` 改完后必须 `systemctl restart`。

### 升级后老协议 unit User=root 没改

PR3 把 sing-box / snell 等服务的 `User=` 从 root 降到协议用户；v4.0.6 把
subscribe 服务也降到 `User=proxy-manager` (CAP_NET_BIND_SERVICE bind :80)。
旧 unit 文件不会自动改写（早期 install 已写过文件，update 只换二进制）。

```bash
proxy-manager service-rebuild   # 强制重写所有协议 + subscribe unit + restart
```

## 已知限制

| 限制 | 影响 | 改进方向 |
| --- | --- | --- |
| ~~没有 GitHub Releases~~ | ~~install.sh 在线安装当前不可用~~ | ✅ 已修：`.github/workflows/release.yml` |
| ~~subscribe 服务跑 root~~ | ~~权限过大~~ | ✅ v4.0.6 改 `User=proxy-manager` + `CAP_NET_BIND_SERVICE` |
| ~~Reality 在 sing-box 上落后于 xray 新特性~~ | ~~vision-udp443/PQ 等等不到~~ | ✅ v4.0.7 切到 xray-core |
| ~~多内核升级要逐协议跑~~ | ~~散在 5 个 UpdateXxx~~ | ✅ v4.0.8 加 `proxy-manager kernel upgrade` |
| acme.sh vs autocert 抢 :80 | 必须按"先协议后订阅"顺序装 | 后续可改 webroot 方式共享 :80 |
| systemd unit 落 `/lib/systemd/system/` | 非惯例（应在 `/etc/`），但工作正常 | 一行常量改动，低优先级 |
| Hysteria2/AnyTLS 不支持 edit | 改这俩协议得重装 | ACME 重签复杂，等真有需求再加 |
| install.sh 版本号检测匹子串 | "vdev" 含 "4.0.8" 子串误判"已是最新" | exact match 比较，低优先级 |
| 单机部署，无 HA / 集群 | 单点故障 | 当前 scope 不需要 |
