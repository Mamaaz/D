# Proxy Manager

Linux VPS 一键多协议代理部署 + 订阅服务 + Reality SNI 工具，单 Go 二进制。

## 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)
```

## 支持的协议

| 协议 | 内核 | 备注 |
| --- | --- | --- |
| **VLESS Reality** | **`xray-core`** | XTLS 团队 Reality 实现 (v4.0.7+) |
| Hysteria2 | `sing-box` | LE 自动签证 |
| AnyTLS | `sing-box` | LE 自动签证 |
| AnyTLS + Reality | `sing-box` | Reality TLS 层，无需证书 (v4.0.25+) |

> v4.0.26 起删除 Snell+Shadow-TLS / SS-2022+Shadow-TLS：ShadowTLS v3 已被探测，
> Surge 用 AnyTLS 直连、其他客户端用 XSurge 桥接到 Reality 即可覆盖原场景。

每协议独立端口、独立 systemd unit、专属系统用户 + `CAP_NET_BIND_SERVICE`，
`ProtectSystem=strict` 硬化。

## TUI 主菜单

直接 `proxy-manager` 进交互菜单（推荐入口）：

| # | 功能 |
| --- | --- |
| 1-4 | 安装协议（Reality / Hysteria2 / AnyTLS / AnyTLS+Reality） |
| 5 | 查看服务配置（输出 Surge / Mihomo / QuantumultX 三种格式） |
| 6-8 | 查看日志 / 更新某协议 / 卸载协议 |
| 9-10 | 续签证书 / 查看证书状态 |
| 13 | Reality SNI 候选评估（粘扫描结果一键挑最佳） |
| **14** | **订阅服务管理（启用 / 停用 / 看 URL / 轮换 token）** |
| **15** | **一键升级所有内核（xray + sing-box）** |
| 11-12 | 升级 / 卸载 proxy-manager 本身 |

## 核心子命令（CLI）

```
proxy-manager                       # 默认菜单
proxy-manager doctor                # 一键诊断: 协议服务/证书/订阅服务状态
proxy-manager subscribe enable      # 启用 HTTPS 订阅服务 (autocert)
proxy-manager subscribe url         # 打印 7 种格式订阅 URL + ASCII QR
                                    # (surge/clash/mihomo/singbox/xray/qx/json)
proxy-manager sni-test <host>       # 单点验证 Reality SNI 候选
cat scan.csv | proxy-manager sni-rank  # 批量打分排序候选
proxy-manager edit reality --field sni --value www.apple.com  # 改配置无需重装
proxy-manager kernel list           # 列出已装内核 + 当前/最新版本
proxy-manager kernel upgrade --all  # 一键升级所有内核
proxy-manager service-rebuild       # 升级二进制后重写 systemd unit
proxy-manager update                # 升级 proxy-manager 自身到最新 release
```

## 跨仓库设计

服务端 ↔ Mac 客户端 配套：

- **Mamaaz/D (本仓)**: VPS 部署 + 订阅服务 + SNI 工具
- **[Mamaaz/XSurge](https://github.com/Mamaaz/XSurge)**: macOS 状态栏 app，通过本地 xray
  桥接 Reality 成 SOCKS5，让 Surge 这种不原生支持 Reality 的工具也能用

## 文档

- **[docs/DEPLOY.md](docs/DEPLOY.md)** — 部署 checklist：前置条件、协议安装顺序、
  升级路径、Reality SNI 评估流程、故障排查
- **[docs/DEVLOG.md](docs/DEVLOG.md)** — 开发日志：版本演化、架构图、关键设计
  决策、已知限制、回来续做指引
- **[docs/DESIGN.md](docs/DESIGN.md)** — 跨仓库设计

## 自动化

- CI: `.github/workflows/release.yml` 在 `git tag v*` push 时自动构建
  amd64 + arm64 binary + checksums，发布到 GitHub Releases
- Auto cert 续期: `subscribe enable` 后由 `golang.org/x/crypto/acme/autocert`
  懒签 + 持久化缓存到 `/var/lib/proxy-manager/autocert/`，无需手工续

## 本地构建

```bash
go build -ldflags "-s -w -X main.version=$(git describe --tags --always)" \
  -o proxy-manager ./cmd/proxy-manager

# 跨编 Linux
GOOS=linux GOARCH=amd64 go build -ldflags "..." -o proxy-manager-linux-amd64 ./cmd/proxy-manager
```

## License

MIT
