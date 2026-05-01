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

## 已知限制 / 未来可做

不是"待办"，是"想清楚了不做或低优先级"：

- **Hysteria2/AnyTLS 的 edit**：域名改动涉及 ACME 重签，复杂度比 Reality 编辑翻倍。等真有人提 issue 再做
- **install.sh 版本号检测**：`grep` 子串导致 "vdev" 包含 "4.0.8" 误判已是最新。改 exact match 五分钟事，低优先级
- **共享证书 + 多协议复用 :443**：v2ray-agent 那种 SNI fronting，工程量大，对单机自用 scope 没必要
- **nodes.json 自动 .bak**：rotate-token / install 之前自动备份。健壮性提升，没人踩坑过
- **DOH only / DoT 强制**：autocert 在某些 ISP 污染 DNS 的网络下可能 challenge 失败。当前 VPS 默认 DNS 已经够用
- **XSurge Settings panel (M2.5)**：现在 autoSyncMinutes 改要手动编辑 JSON。出真实需求再做

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
