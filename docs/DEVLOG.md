# Mamaaz/D 开发日志

记录这个项目的演化、关键决策、设计取舍。给未来回来的自己 / 协作者看，
让任何人 clone 仓库都能在 5 分钟内理解"为什么是这样"。

> 配套的 [XSurge](https://github.com/Mamaaz/XSurge) 是 Mac 客户端，跨仓库
> 设计文档见 [docs/DESIGN.md](DESIGN.md)；部署细节见 [docs/DEPLOY.md](DEPLOY.md)。

---

## 项目定位

一行话：**Linux VPS 上一键部署多协议代理 (Snell+ShadowTLS / SS2022+ShadowTLS / VLESS-Reality / Hysteria2 / AnyTLS)，配套 HTTPS 订阅服务，配套 Mac 状态栏 app (XSurge) 让 Surge 用户能用 Reality**。

非目标（**故意**不做的事）：
- 多用户 / 面板 / Web UI
- 共享 :443 端口（v2ray-agent 那种 SNI fronting）— 每协议独立端口，故障隔离更清晰
- HA / 集群 — 单 VPS 自用 scope

---

## 整体架构

```
┌─ Linux VPS ────────────────────────────────────┐
│                                                │
│  /usr/local/bin/proxy-manager   ← 唯一 CLI     │
│       │                                        │
│       ├── 协议管理（install/uninstall/edit）   │
│       │     ├─ snell-server + shadow-tls (独立)│
│       │     ├─ sing-box (SS2022/Hy2/AnyTLS)    │
│       │     └─ xray-core   (VLESS Reality)     │
│       │                                        │
│       ├── 订阅服务（HTTPS daemon）              │
│       │     /var/lib/proxy-manager/autocert    │
│       │     /etc/proxy-manager/nodes.json      │
│       │     systemd: proxy-manager-subscribe   │
│       │                                        │
│       ├── 内核管理（kernel list/upgrade）       │
│       ├── SNI 工具（sni-test / sni-rank）       │
│       └── 一键诊断（doctor）                    │
│                                                │
└────────────────────────────────────────────────┘
                     ↑
                     │  HTTPS 订阅 URL
                     │
┌─ Mac (XSurge) ──────────────────────────────────┐
│                                                 │
│  状态栏 app                                     │
│       ├── 订阅管理（多 sub 自动同步）            │
│       ├── BridgeController                      │
│       │     └─ 启 launchd xray daemon (本地)    │
│       │        SOCKS5 :17890 ↔ VPS Reality      │
│       ├── SurgeProfileEditor                    │
│       │     └─ 自动写 Surge profile 管控块       │
│       ├── HealthChecker (30s SOCKS5 探测)       │
│       └── SNI 测试器 / 范围扫描器                │
│                                                 │
└─────────────────────────────────────────────────┘
                     ↑
                     │  socks5 127.0.0.1:17890
                     │
                  Surge.app
```

跨仓库设计的核心命题：**Reality 协议在 Surge 里没原生支持，XSurge 用本地 xray 桥接成 SOCKS5，Surge 当普通代理用**。已被实战验证（VPS tz.iooio.io）。

---

## 版本演化

| 版本 | 主题 | 关键 commit |
|---|---|---|
| v4.0.0 | 起点（旧 bash 脚本翻 Go） | — |
| v4.0.1 | subscribe service 启动失败修 + DEPLOY.md + Releases workflow | PR #11 |
| v4.0.2 | `sni-test` 子命令（VPS 视角验证候选 SNI） | PR #13 |
| v4.0.3 | `edit` 子命令（Reality MVP，无 reinstall 改字段） | PR #14 |
| v4.0.4 | `sni-rank` 批量打分（pipe RealiTLScanner CSV） | PR #15 |
| v4.0.5 | TUI 主菜单 #14 SNI 候选评估（粘 CSV 一键挑） | PR #16 |
| v4.0.6 | subscribe drop root + edit 扩到 Snell/SS2022 + DEPLOY sync | PR #17 |
| v4.0.7 | **Reality 内核切到 xray-core** | PR #18 |
| v4.0.8 | `kernel` 子命令（统一管理 list/upgrade） | PR #19 |
| v4.0.9 | TUI 服务状态表 reality SystemdName 跟上 v4.0.7 切换 | PR #21 |
| v4.0.10 | post-install 自动打印订阅 URL（5 种格式 + XSurge 提示）| PR #22 |
| v4.0.11 | `store.Save` 写完自动 chown 给 proxy-manager 用户 | PR #23 |
| v4.0.12 | post-install 末尾追加 json URL ASCII QR | PR #24 |
| v4.0.13 | 单节点 vless:// share URL + QR（不依赖订阅服务）| PR #25 |

每个版本都在 GitHub Releases 自动构建（amd64 + arm64 + checksums），
`bash <(curl -sL .../install.sh) update` 一键升级。

---

## 关键设计决策

### 1. 内核混合：sing-box (4 协议) + xray-core (Reality)

**为啥**：Reality 是 XTLS 团队的发明，新特性（vision-udp443 / 新 fingerprint /
未来的 MLKEM-768 后量子）先进 xray，sing-box 跟进通常滞后 1-3 周。其他协议
（Hysteria2/AnyTLS/ShadowTLS）xray 不支持，sing-box 是唯一选择。

**取舍**：多了一个 binary 要维护，但避免"等 sing-box 跟 Reality 上游"的痛苦。
迁移成本由 service-rebuild 自动吃掉（v4.0.6 → v4.0.7 用户毫无感知）。

**没切的**：MLKEM-768 后量子 — 客户端兼容性差（多数客户端没跟上），开了会
握手 fail 而不是优雅降级。留 edit 字段让用户按需 opt-in。

### 2. 订阅服务用 autocert 而非 acme.sh

**为啥**：autocert (golang.org/x/crypto/acme/autocert) 是 Go 标准 ACME 客户端，
和 proxy-manager binary 同进程，懒签 + 内存缓存 + 文件持久化，零外部依赖。

**取舍**：和 Hysteria2/AnyTLS 用的 acme.sh 抢 :80 — 必须按"先协议后订阅"顺序装。
DEPLOY.md §2 显式记下了这个顺序。

### 3. 节点存储统一 nodes.json + 兼容旧 .txt

**为啥**：早期版本用每协议一个 `.txt` 配置文件（key=value 风格）。v4.0.0 引入
`/etc/proxy-manager/nodes.json` 作为统一 source of truth，但保留 .txt 读路径
让旧部署平滑过渡。

**取舍**：双轨期短，但避免破坏现有用户。`store.LoadOrMigrate()` 头一次读会
把 .txt 内容转进 nodes.json，之后用 nodes.json 为准。

### 4. systemd 服务全部非 root + CAP_NET_BIND_SERVICE

**为啥**：默认安全，非 root + cap 让低端口绑定不需要 root，符合 systemd
现代 isolation 模型 (NoNewPrivileges, ProtectSystem=strict, ProtectHome)。

**实施时间**：协议服务在 PR3 / v4.0.0 时降权；subscribe 服务在 v4.0.6 才降。
旧部署升级时由 service-rebuild 自动迁移。

### 5. XSurge 改 Surge profile 不用 .sgmodule

**为啥**：尝试过 .sgmodule 模块文件，但 Surge Mac 的 Module → Add URL 只接
http(s)，file:// scheme 被当 HTTP 处理 404，本地模块无法订阅。改成直接维护
profile 里的 `# >>> XSurge BEGIN/END` 标记块，最终方案。

**取舍**：要读写用户 Surge profile（侵入性高），但能做到"重命名节点 → Surge
立刻看到新名"的实时同步体验。

### 6. SNI 评估三层：本地扫 / VPS 单点测 / VPS 批量打分

- **本地扫**（RealiTLScanner）：必须本地，VPS 扫会被云厂商风控当扫描器封机
- **VPS 单点测**（`sni-test`）：从 VPS 出口路径验证候选的延迟 + TLS 表现
- **VPS 批量打分**（`sni-rank`）：take CSV → 并发探测 → 自动按 Reality 适合度排序

打分透明：CDN -300、HTTP 5xx -500、隐版本 nginx +100、RTT 直接当负分。
TUI 主菜单 #14 把整个流程串起来一键完成。

### 7. 工具 fricial：Surge 增强模式拦截

实战发现：Surge 增强模式 + RealiTLScanner / openssl 出门会被 fake DNS 替换为
198.18.x.x，导致扫描结果失真。XSurge 测试器/扫描器 dialog 加了「直连规则」
按钮一键复制 PROCESS-NAME=DIRECT 规则。

### 8. nodes.json 文件 ownership：root 写 / proxy-manager 读

v4.0.6 把 subscribe service 降到 `User=proxy-manager` 后冒出新 bug：root 跑
install 写出 root-owned `/etc/proxy-manager/nodes.json`，subscribe service
读不到，全部订阅 URL 返 500 "store unavailable"。v4.0.11 修：`store.saveLocked`
写完后调 `os.Chown` best-effort 把文件 + 目录所有权改给 proxy-manager
（用户存在则改，不存在静默跳过——subscribe enable 时会自己创 + 全量 chown）。

### 9. Reality transport 选型：默认 TCP, 不用 XHTTP

xray 26.x 加了 XHTTP transport（mimic HTTP/2 fingerprint）。但默认仍用
`network: tcp` 因为：
- 客户端兼容性：sing-box / V2Box / NekoBox / Shadowrocket 多数对 XHTTP
  支持参差，TCP 是 Reality 全客户端通吃的最大公约数
- 协议成熟度：XHTTP 2024 合并，spec 改过几次；TCP 是 Reality 一开始就有的
- 抗审查实测：Reality 强度来自 TLS 1.3 mimic + X25519，transport 层差异小
未来如撞墙，加成 `proxy-manager edit reality --field transport --value xhttp`
opt-in（跟 MLKEM-768 同样策略），不动默认。

### 10. post-install QR：仅给 vless:// share，不给 json URL

v4.0.12 给 json URL 也打了 QR；v4.0.13 加了 vless:// share URL 的 QR。
后来发现：json URL 的 QR 没用——XSurge / Surge 的"添加订阅"输入框只接受
复制粘贴的 URL 字符串，扫不进去。手机扫码的真实场景是**单节点 share URL**
（vless://...），扫了之后客户端立刻有这一个节点。所以删掉 json QR 只保留
vless:// QR。

---

## 端到端验证

VPS：`tz.iooio.io` (193.32.150.191, Debian 12, 1G RAM)
- v4.0.0 → v4.0.8 全部测过升级
- sing-box → xray Reality 内核切换零停机迁移
- subscribe service 5 种格式 URL 全 HTTP 200
- 证书续期 routine 已排（2026-07-01 远程跑 doctor）

Mac (XSurge)：
- 真订阅 fetch + JSON decode（修过 Go 纳秒时间戳兼容性）
- xray 真起 + SOCKS5 :17890 → VPS Reality → 出口 IP 命中 VPS
- Surge profile 自动同步 + surge-cli reload
- HealthChecker 杀 xray 30s 内状态栏图标变橙

---

## 踩坑记录

实战回来加的"血泪条目"，写下来防同样的坑再被踩。

### shortid 必须严格 hex（v4.0.31 修）

**症状**：QX 加 VLESS Reality 节点报 "syntax error"，但同一份订阅里另一个节点能用。差别只在 `reality-hex-shortid` 字段：能用的全 0-9/a-f，报错的有 X/m/U 等大小写字母。

**根因**：`internal/install/reality.go generateShortID()` 主路径 `singbox generate rand --hex 8`，**fallback 走 `utils.GeneratePassword(8)` 而后者是 base64 字母表（含 A-Z/a-z/0-9/+）**，根本不是 hex。装 VLESS Reality 的机器很多没 sing-box（VLESS Reality 走 xray 内核，sing-box 不是必装依赖），fallback 直接命中，store 里写进的就是非 hex 串。

**为啥 xray server 还能起**：xray 解析 shortid 比较宽松，按字面字节读，自洽就行。但 QX 字段名叫 `reality-hex-shortid`，前缀 hex 是合约，校验失败直接拒。Surge 的 `short-id=` 同理理论上也该报错，实测看版本宽松度不一。

**修复**：直接 `crypto/rand` 读 8 字节 + `hex.EncodeToString`，无外部进程依赖，无 fallback 路径。

**对存量节点的影响**：v4.0.31 之前装出来、shortid 含非 hex 的节点继续在 nodes.json 里，xray 服务端能跑但 QX 不认。修了之后 `proxy-manager` 卸载 → 重装 VLESS Reality 即可生成正确 shortid。客户端订阅重导。

### 菜单"更新 Proxy Manager"（11/12）双层 bug（v4.0.30 修）

**症状**：v4.0.28 已合 PR #41 修 `proxy-manager update` 的 stdin EOF bug，但用户从 TUI 菜单触发更新仍报 `bash: line 1: 404:: command not found`。

**根因双层**：
1. `internal/ui/ui.go doUpdatePM()` 的 install.sh URL 写的是 monorepo 旧路径 `main/P/proxy_manager_go/scripts/install.sh`，早就 404。GitHub raw 直接返响应体 `404: Not Found`，被 `curl -sL` 透传 piped 进 `bash -s update`，bash 把第一行 `404:` 当命令名 → "command not found"。`-s` 只压进度，不压响应体。
2. PR #41 只修了 `cmd/proxy-manager/main.go` 的 `doUpdate()`，菜单是另一份独立逻辑（`doUpdatePM`），用 `curl ... | bash -s update` 老路径，stdin EOF bug 也没复用修复。

**修复**：`doUpdatePM` 改成 `os.Executable()` 自调 `<self> update`，菜单和 CLI 共用 cmd/main 的 `doUpdate`（download to tmpfile + 保留 stdin）。

**通用教训**：重复逻辑不只是审美问题，是单点修复扩散不到所有调用方的根源。fix bug 时 grep 一下相同 pattern。

---

## 已知限制 / 未来可做

不是"待办"，是"想清楚了不做或低优先级"：

- **Hysteria2/AnyTLS 的 edit**：域名改动涉及 ACME 重签，复杂度比 Reality 编辑翻倍。等真有人提 issue 再做
- **install.sh 版本号检测**：`grep` 子串导致 "vdev" 包含 "4.0.8" 误判已是最新。改 exact match 五分钟事，低优先级
- **VLESS 多变体（WS/gRPC/XHTTP/CDN）**：v2ray-agent 全都支持，但每个变体都要 install 流程 + LE 证书 + edit + doctor + 订阅生成器。除非 :443 被精准封，否则 Reality 已经够。**唯一有独立价值的是 WS+TLS+CDN**（藏 IP），等真撞墙再加
- **Reality transport=XHTTP**：xray 26.x 新特性，客户端兼容性差。同样按 opt-in edit field 加，不默认换
- **MLKEM-768 后量子**：xray 支持，但客户端兼容性差。同上策略
- **共享证书 + 多协议复用 :443**：v2ray-agent 那种 SNI fronting，工程量大，对单机自用 scope 没必要
- **nodes.json 自动 .bak**：rotate-token / install 之前自动备份。健壮性提升，没人踩坑过
- **DOH only / DoT 强制**：autocert 在某些 ISP 污染 DNS 的网络下可能 challenge 失败。当前 VPS 默认 DNS 已经够用
- **XSurge Settings panel (M2.5)**：现在 autoSyncMinutes 改要手动编辑 JSON。出真实需求再做
- **XSurge `latestNodesBySub` 持久化**：当前 in-memory only，重启清空（v4.0.12 修了泄漏 bug 后这个是 by-design）。如果真要 cache 持久也可以加

---

## 如何回来续做

1. `git pull --ff-only` Mamaaz/D + Mamaaz/XSurge
2. 看 `docs/DEPLOY.md` 知道当前用法
3. 看本文件知道当前架构 + 历史决策
4. `proxy-manager doctor` 看 VPS 状态
5. XSurge 的诊断面板看本地状态

存量资源：
- VPS tz.iooio.io 跑 v4.0.8 + Reality on xray
- nmem memory 里有 "Surge 增强模式拦截 TLS 探测" 这条 feedback 经验
- claude.ai 有 cert renewal check routine（2026-07-01 触发）
- XSurge 状态栏 app 跑在 Mac，`brew services` 不管它（用户启动）

---

## 致谢 / 参考

- [v2ray-agent](https://github.com/mack-a/v2ray-agent)：多内核架构思路启发
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)：Reality 协议实现
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)：其余 4 协议内核
- [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner)：本地范围扫描
- 所有 ChatGPT-style 编辑请去仔细查 commit 消息——里面常常写了"为什么"
