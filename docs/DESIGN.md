# 架构与开发计划

最后更新：2026-04-30

本文档跨越两个仓库：服务端 [`Mamaaz/D`](https://github.com/Mamaaz/D)
（本仓库）和客户端 [`Mamaaz/XSurge`](https://github.com/Mamaaz/XSurge)。
任何一边的设计变化要回来更新这份文档。

## 1. 项目目标

把"VPS 上一键部署多协议代理 + Mac 端图形化集成 Surge"做成一条可重复的流水线：

- **服务端 (Mamaaz/D)**: Linux VPS 上一键安装 Snell / SS2022+ShadowTLS / VLESS-Reality / Hysteria2 / AnyTLS 任意组合；通过 HTTPS 订阅服务把节点配置以多种格式（Surge / Clash / sing-box / xray / 原始 JSON）暴露给客户端
- **客户端 (XSurge)**: macOS 状态栏小工具，订阅服务端的 URL，把 Surge 不能原生消费的协议（VLESS-Reality）通过本地 xray 桥接成 SOCKS5，原生协议直接写入 Surge 配置；用户开/关桥接、看节点状态、切换订阅都在状态栏里完成

## 2. 数据流

```
┌──────────────────────────┐     ┌──────────────────────────┐
│  VPS (Mamaaz/D)          │     │  Mac (XSurge + Surge)    │
│                          │     │                          │
│  proxy-manager 安装协议  │     │  XSurge.app             │
│  ↓                       │     │  ↓                       │
│  /etc/proxy-manager/     │     │  ① GET /s/json/<token>  │
│    nodes.json            │     │  ② GET /s/xray/<token>  │
│  ↓                       │     │  ③ GET /s/surge/<token> │
│  proxy-manager-subscribe │ HTTP│  ↓                       │
│   :443 + :80 (ACME)      │ ─→  │  本地 xray 配置生成       │
│  /s/{format}/<token>     │     │  ↓                       │
└──────────────────────────┘     │  ~/Library/.../xray-     │
                                 │      config.json          │
                                 │  ↓                       │
                                 │  launchd 拉起 xray       │
                                 │  ↓                       │
                                 │  127.0.0.1:17890+ SOCKS5│
                                 │  ↓                       │
                                 │  Surge .conf [Proxy] 段  │
                                 │  managed 行注入          │
                                 │  ↓                       │
                                 │  surge-cli reload-all    │
                                 └──────────────────────────┘
```

## 3. 协议矩阵 + 路由策略

| 协议 | 服务端可装 | Surge 原生 | 走桥接 (xray) | 备注 |
|---|---|---|---|---|
| Snell + Shadow-TLS | ✅ | ✅ | — | Surge 团队亲生协议 |
| SS2022 + Shadow-TLS | ✅ | ✅ | — | Surge 5.x 加的 ShadowTLS 字段 |
| Hysteria2 | ✅ | ✅ | — | Surge 5.x 原生 |
| AnyTLS | ✅ | ✅ | — | Surge 最新 |
| VLESS + Reality | ✅ | ❌ | ✅ | xray-core 是 Reality 协议亲爹 |

**关键决策**：xray 桥接**只用于** VLESS+Reality。其他协议直接 Surge 配置即可，不绕一圈。

## 4. 仓库分工

### 4.1 Mamaaz/D（服务端，Go + bash 安装脚本）

```
.
├── cmd/proxy-manager/          # CLI 入口
│   ├── main.go                 # 子命令 dispatcher
│   ├── export.go               # export --format=<...>
│   └── subscribe.go            # subscribe enable/disable/status/url/rotate-token/serve
├── internal/
│   ├── install/                # 协议安装/卸载
│   │   ├── snell.go            # Snell + Shadow-TLS
│   │   ├── singbox.go          # SS2022 + Shadow-TLS（用 sing-box 内核）
│   │   ├── reality.go          # VLESS + Reality（用 sing-box 内核）
│   │   ├── hysteria2.go        # Hysteria2（用 sing-box 内核）
│   │   ├── anytls.go           # AnyTLS（用 sing-box 内核 ≥1.12）
│   │   ├── common.go           # systemd / acme.sh / 通用证书管理
│   │   └── storebridge.go      # 各协议安装后写入 nodes.json
│   ├── store/                  # PR1: 统一 nodes.json 存储
│   │   ├── nodes.go            # Load/Save/Upsert/RemoveByType + token rotation
│   │   └── migrate.go          # 旧 .txt 自动迁移
│   ├── format/                 # PR1: 五种协议 × 四种格式渲染
│   │   ├── format.go           # 入口 + 类型派发
│   │   ├── snell.go / ss2022.go / vless_reality.go / hysteria2.go / anytls.go
│   ├── subscribe/              # PR2: HTTPS 订阅服务
│   │   ├── server.go           # /s/{format}/{token} 路由 + 恒时 token 比较
│   │   ├── serve.go            # ACME autocert + HTTP-01 + HTTPS daemon
│   │   └── service.go          # systemd 单元生命周期 + URL 渲染
│   └── ui/, services/, utils/, health/, config/
└── scripts/install.sh
```

### 4.2 XSurge（客户端，Swift + AppKit）

```
.
├── Package.swift               # SwiftPM, macOS 13+
└── Sources/XSurge/
    ├── App/
    │   ├── main.swift          # accessory 模式启动（隐 Dock）
    │   ├── AppDelegate.swift
    │   └── StatusBarController.swift  # NSStatusItem + 三态白色云图标
    ├── UI/
    │   ├── MenuBuilder.swift           # 动态构建菜单（每次打开重建）
    │   └── AddSubscriptionDialog.swift # NSAlert + 双输入框
    ├── Models/
    │   ├── Node.swift          # 镜像服务端 store.Node + AnyCodable
    │   ├── Subscription.swift  # URL + lastSyncedAt + lastError
    │   ├── AppState.swift      # 单一 observable hub
    │   └── DemoData.swift      # 首次启动假数据
    ├── Services/
    │   ├── SubscriptionFetcher.swift   # URLSession async/await
    │   ├── SyncCoordinator.swift       # TaskGroup 并发同步多订阅
    │   ├── XrayConfigBuilder.swift     # 节点 → xray JSON
    │   ├── SurgeConfigWriter.swift     # 改 Surge .conf managed 段（M2.2 实装）
    │   ├── LaunchdManager.swift        # plist + launchctl load/kickstart
    │   └── HealthChecker.swift         # SOCKS5 端口探测（M2.2 实装）
    └── Resources/cloud-icon{,@2x,@3x}.png
```

## 5. 进度

### 5.1 服务端 Mamaaz/D

| 项 | 状态 | 说明 |
|---|---|---|
| 协议安装器 | ✅ 已落地 | 5 种协议都能装 |
| **PR1: 统一 nodes.json** | 🔄 [PR #1](https://github.com/Mamaaz/D/pull/1) | UUID fix + dist/ 移出 + nodes.json + format 渲染 + export 子命令 |
| **PR2: 订阅服务 + ACME** | 🔄 [PR #2](https://github.com/Mamaaz/D/pull/2) | HTTPS + autocert + token + 5 路由 |
| P2 修复 | 待办 | fmt.Scanln 替换 / 端口预检 / Reality 用户降权 / TLS_DOMAIN 必填 / 防火墙提示 |
| 进程合并 | 待办 | 多 sing-box 协议合并到一个 sing-box 进程 |
| 二维码输出 | 待办 | 订阅 URL 显示二维码（手机扫码导入）|
| 短别名 `pm` | 待办 | install.sh 软链 `/usr/local/bin/pm` |
| `proxy-manager doctor` | 待办 | 一键诊断所有服务/端口/订阅状态 |

### 5.2 客户端 XSurge

| 里程碑 | 状态 | 说明 |
|---|---|---|
| **M1: 脚手架** | ✅ 已 push | 状态栏壳子 + 模型 + 服务 stub |
| **M1.5: 假数据 + 白色云图标** | ✅ 已 push | 首启动 demo + 用户提供的图标，pre-rendered 白色 PNG |
| **M2.1: 订阅管理** | ✅ 已 push | 添加订阅 dialog / parallel fetch / 子菜单 / 错误展示 |
| **M2.1.5: 设置 / 诊断 / 日志菜单可点** | ✅ 已 push | 临时 NSAlert，含路径预览 + Finder 跳转 + 复制诊断 |
| M2.2: 真桥接 | 待办 | xray 配置写入 + launchd plist + Surge 配置注入 + surge-cli reload |
| M2.3: 设置窗 / 诊断面板 / 自动同步定时器 / 开机自启 | 待办 | SwiftUI |
| M3: 打 .app + 签名 / Sparkle 自动更新 | 待办 | 分发 |

## 6. 关键设计决策

### 6.1 订阅 URL 单 token，不做多用户

自用场景下"每用户独立 URL"是过度设计。单 token + 手动 `rotate-token`
（旧 URL 立即失效）足够。多设备共享同一 URL 无副作用。

### 6.2 双写过渡，不破坏老安装

PR1 让所有 install/uninstall 同时写老 `.txt` 和新 `nodes.json`；
ViewConfig / Update / RenewCert 这些只读老 `.txt` 的代码路径暂不改。
未来某个 PR 才把 `.txt` 完全淘汰，目前是可以双向兼容的状态。

### 6.3 服务端只服务 5 种协议格式，xray 输出仅 VLESS-Reality

`/s/xray/<token>` 在筛选时调用 `format.NeedsBridge(node)`，只把需要桥接的
节点（当前唯一是 VLESS-Reality）写进 outbounds。Mac 端拉这个 URL 时
天然只会拿到该桥接的节点，避免误把 Surge 原生协议也丢给 xray。

### 6.4 ACME HTTP-01 + Cloudflare 灰云

部署前提：

1. 一个解析到 VPS 的子域名（如 `sub.your-domain.com`），A 记录
2. **Cloudflare 用户必须用灰云**（DNS only），不能开橙云代理——否则 ACME challenge 永远到不了 VPS
3. VPS 80 端口空闲（ACME 续约也要）

### 6.5 XSurge 选 Swift + AppKit 而不是 Go + systray

- 100% native 体验，菜单/图标/对话框都最舒服
- 服务端已经把 format 渲染做完了（`/s/<format>/<token>`），客户端**不需要**复用 Go 包，直接 HTTP 消费即可
- 开发体验：Xcode 直接打开 `Package.swift` 就有完整 IDE

### 6.6 状态栏图标 = pre-rendered 白色 PNG

模板图 + `contentTintColor` 在某些 macOS 版本/外观下不稳定；干脆把 PNG
像素直接做成白色，关掉 `isTemplate`，所见即所得。状态变化用
`alphaValue` (disabled) 和 `contentTintColor` (degraded/error) 区分。

### 6.7 桥接路线 A：所有 VLESS 同时桥接，不做"切换"

xray 同时跑 N 个 SOCKS5 inbound（每个 VLESS 一个端口）；Surge 的
Proxy Group 自动 url-test 选最快。状态栏 app 不抢 Surge 的选路职责，
只负责保持桥接活着。

### 6.8 demo 数据持久化时被过滤

`AppState.persist()` 写盘前用 `[demo]` 标签过滤，所以重启后 demo 不会
"幽灵复活"挤占用户真订阅的位置。

## 7. 部署清单

服务端（VPS）：

```bash
# 一键安装 proxy-manager 二进制（待 PR1+PR2 合并）
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)

# 装协议
proxy-manager   # 进菜单选 1) Snell / 2) SS2022 / 3) VLESS Reality ...

# 启用订阅服务
proxy-manager subscribe enable --domain sub.your-domain.com --email you@example.com
# → 终端输出 5 个 URL（surge / clash / singbox / xray / json）

# 之后随时
proxy-manager subscribe status       # systemd is-active + 订阅信息
proxy-manager subscribe url          # 重打印 URL
proxy-manager subscribe rotate-token # 旧 URL 立即失效
proxy-manager export --format=json   # 离线 dump 给 SSH 拉
```

客户端（Mac）：

```bash
brew install xray-core               # M2.2 才会用到
brew install --cask surge            # 假定已装

# 拉 XSurge
git clone https://github.com/Mamaaz/XSurge.git
cd XSurge
swift run XSurge                     # 状态栏图标出现
# 或 open Package.swift 在 Xcode 里调试

# 状态栏 → 添加订阅...
# 名称: vps-hk-01
# URL:  https://sub.your-domain.com:38291/s/json/<token>
```

## 8. 测试策略

**离线 / 无 VPS 测试**：

- XSurge 首启动有 demo 数据
- 把样例 JSON 放在本地 `file:///tmp/xsurge-fixture.json` 当订阅 URL
- 服务端 `--staging` flag 切到 LE 测试 CA，避开生产 rate limit

**端到端测试**：

1. 拉 PR1+PR2 在 VPS 编译 `proxy-manager` 二进制
2. `proxy-manager` 装一个 VLESS-Reality 节点
3. `proxy-manager subscribe enable --staging` 验证 ACME 流程
4. `curl https://sub.your-domain.com:<port>/s/json/<token>` 看节点列表
5. Mac 上把订阅 URL 贴进 XSurge → demo 被替换为真节点
6. M2.2 完成后开桥接，xray 起，Surge 配置注入，端到端连通

## 9. 待解问题 / 后续方向

1. **PR1+PR2 合并节奏**：按目前顺序 PR1 → PR2（PR2 base 是 PR1 分支，PR1 合并后 GitHub 自动改 base）。决定先 review 还是一起合
2. **VLESS+Reality 在 Surge 5.x 里的真实支持情况**：reality.go 输出的 `Reality = vless,...` 实测能不能跑通？如果 Surge 已经原生支持，xray 桥接就不必做了；XSurge 直接订阅 `/s/surge/` 写入 Surge 即可
3. **订阅过期 / 多端同步**：长期可加一个"订阅最后健康时间"字段，UI 在订阅 N 天没同步时弹通知
4. **Mac 客户端分发**：自用阶段裸 binary OK；要给朋友用得先签 Apple Developer 证书 + notarize（$99/年）
5. **多 sing-box 协议合并到单进程**：现在 Reality / Hysteria2 / AnyTLS 各跑独立 sing-box，CPU 多耗一点，未来可以合并到一份配置

## 10. 名词表

- **桥接 (Bridge)**：在 Mac 本地起 xray 把 VLESS-Reality 转成 SOCKS5 让 Surge 消费
- **订阅 (Subscription)**：服务端 HTTPS 端点 `/s/<format>/<token>`
- **托管段 (Managed Block)**：Surge `.conf` 里 `# === XSurge managed BEGIN/END ===` 之间的行，由 XSurge 完全控制
- **Native 协议**：Surge 不需要桥接的协议（Snell / SS2022+STLS / Hy2 / AnyTLS）
- **桥接协议**：Surge 不能直接吃，需要 xray 转发的（VLESS+Reality）
