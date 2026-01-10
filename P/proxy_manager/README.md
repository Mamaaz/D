# Proxy Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)

多协议代理服务器一键管理脚本，支持 Snell、SS-2022、VLESS Reality、Hysteria2、AnyTLS，以及高级分流管理。

## 🚀 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)
```

> 💡 **提示**: 需要 root 权限运行。推荐在全新的 VPS 上安装。

## 📋 系统要求

- **操作系统**: Linux (Debian/Ubuntu/CentOS/RHEL/Arch)
- **权限**: Root
- **架构**: x86_64 / arm64 / armv7
- **依赖**: curl, wget, jq (安装脚本会自动安装)

## ✨ 功能特性

### 代理服务管理
| 协议 | 说明 | 客户端支持 |
|------|------|----------|
| Snell v5 + Shadow-TLS | Surge 专用协议 | Surge |
| SS-2022 + Shadow-TLS | 最新 Shadowsocks 协议 | Surge, Clash |
| VLESS Reality | Xray 核心协议，抗检测 | V2Ray 系客户端 |
| Hysteria2 | 基于 QUIC 的高速协议 | Surge, Clash |
| AnyTLS | 抗 TLS 指纹检测协议 ⭐ 新增 | Surge, Clash |

### 🌐 高级分流管理

| 功能 | 说明 |
|------|------|
| 落地代理管理 | 支持 SS/Hysteria2/VLESS/HTTP/SOCKS5 落地配置 |
| 分流规则 | 灵活的域名/IP/GeoSite 规则配置 |
| 远程订阅 | 支持 Loyalsoldier 规则集自动更新 |
| GeoIP/GeoSite | 自动更新地理位置数据库 |
| 规则测试 | 交互式规则匹配测试 |

分流架构图：
```
客户端 (Surge/Clash)
    │
    └─────▶ VPS 入口 (Snell/SS/Hysteria2)
                │
                └─────▶ Sing-box 分流引擎
                            │
                ┌───────────┼───────────┐
                ▼           ▼           ▼
            美国落地     新加坡落地    日本落地
```

## 🖥️ 快速开始

### 安装完成后

```bash
# 运行管理脚本
proxy-manager

# 更新到最新版
proxy-manager update

# 显示帮助信息
proxy-manager --help
```

### 推荐安装顺序

1. 选择 **1. 安装 Snell + Shadow-TLS** - 作为主要入口协议
2. 进入 **12. 高级分流管理** - 配置落地代理和规则
3. 选择 **6. 应用配置** - 生效分流设置

## 📱 主菜单

```
安装服务
  1-5. Snell / Sing-box / Reality / Hysteria2 / AnyTLS

管理服务
  6-9. 配置 / 日志 / 更新 / 卸载

证书管理
  10-11. 续签 / 查看证书

分流管理 ⭐
  12. 高级分流管理 (落地代理/规则/订阅)

系统管理
  13. 更新 Proxy Manager
  14. 完全卸载 Proxy Manager
```

## 🌐 分流管理详情

### 落地代理支持
- **Shadowsocks** - SS-2022 加密，高兼容性
- **Hysteria2** - QUIC 协议，高速低延迟
- **VLESS** - 支持 Reality，抗检测能力强
- **HTTP** - 支持 ISP 静态代理 ⭐ 新增
- **SOCKS5** - 支持 ISP 静态代理 ⭐ 新增

## 🌍 使用 ISP 静态代理作为落地

> 适用于购买了静态住宅/ISP 代理（如 Proxy-Cheap、IPRoyal 等）的用户，让 VPS 的出口 IP 变为 ISP 代理的 IP。

### 使用场景

- 需要稳定的住宅 IP 访问特定服务
- 绕过基于 IP 的地区限制
- 多个 VPS 共享同一个 ISP 出口 IP

### 配置步骤

#### 1. 添加 SOCKS5 落地代理

```bash
proxy-manager
# 选择 12. 高级分流管理
# 选择 1. 落地代理管理
# 选择 6. 添加 SOCKS5 代理 (ISP代理)
```

输入您购买的 ISP 代理信息：
- **代理标签**: 自定义名称（如 `isp-us`）
- **服务器地址**: ISP 代理的 IP
- **端口**: SOCKS5 端口
- **用户名/密码**: 认证信息

#### 2. 设置默认出口

```bash
# 选择 0. 返回上级菜单
# 选择 2. 分流规则管理
# 选择 6. 设置默认出口 (final)
# 输入落地代理标签（如 isp-us）
```

#### 3. 应用配置

```bash
# 选择 0. 返回上级菜单
# 选择 6. 应用配置
# 选择 1. 应用到入口服务 (推荐)
# 确认重载服务
```

#### 4. 验证配置

使用 Surge 连接 VPS，访问 [ip.sb](https://ip.sb) 查看出口 IP 是否变为 ISP 代理的 IP。

### 配置架构

```
Surge/Clash ──▶ VPS (SS-2022/Snell) ──▶ ISP SOCKS5 代理 ──▶ 目标网站
                      │
               入口服务 + 分流引擎
                      │
              自动合并到 sing-box 配置
```

### 注意事项

1. **只有 sing-box 服务支持落地代理**：包括 SS-2022、VLESS Reality、Hysteria2。Snell 服务不支持。
2. **ISP 代理需可达**：确保 VPS 可以连接到 ISP 代理服务器。
3. **编辑代理**：代理过期后可使用 **7. 编辑代理** 快速更新 IP/端口/密码。
4. **多 VPS 共享**：可以在多个 VPS 上配置相同的 ISP 代理，实现多入口单出口。

### 规则集订阅 (Loyalsoldier)
| 规则集 | 用途 |
|--------|------|
| reject | 广告拦截 |
| proxy | 需代理域名 |
| direct | 直连域名 |
| gfw | GFW 列表 |
| telegram | Telegram IP |
| cncidr | 中国 IP 段 |

### GeoIP/GeoSite 数据源
- GeoIP: [SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip)
- GeoSite: [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite)
- 支持定时自动更新 (systemd timer)

## 📁 目录结构

```
/opt/proxy-manager/
├── proxy-manager.sh           # 主入口
├── lib/
│   ├── common.sh              # 通用函数
│   ├── config.sh              # 配置管理
│   ├── system.sh              # 系统函数
│   ├── validation.sh          # 输入验证
│   ├── routing.sh             # 分流规则
│   ├── outbound.sh            # 落地代理管理 ⭐
│   ├── geo-update.sh          # GeoIP/GeoSite 更新 ⭐
│   └── subscriptions.sh       # 订阅规则集 ⭐
└── modules/
    ├── snell.sh               # Snell 服务
    ├── singbox.sh             # Sing-box 服务
    ├── reality.sh             # VLESS Reality
    ├── hysteria2.sh           # Hysteria2 服务
    ├── anytls.sh              # AnyTLS 服务 ⭐
    ├── cert.sh                # 证书管理
    └── routing-menu.sh        # 分流管理菜单 ⭐

/etc/unified-singbox/          # 分流配置目录
├── outbounds.json             # 落地代理配置
├── rules.json                 # 分流规则
├── subscriptions.json         # 订阅配置
├── config.json                # 生成的完整配置
├── geoip.db                   # GeoIP 数据库
├── geosite.db                 # GeoSite 数据库
└── rulesets/                  # 订阅规则集文件
```

## 🔄 更新日志

### v3.6
- ✨ 新增 HTTP 代理落地支持（支持 ISP 静态代理）
- ✨ 新增 SOCKS5 代理落地支持（支持用户名密码认证）
- ✨ 新增编辑代理功能（快速修改 IP/端口/密码）
- ✨ 分流配置支持直接应用到入口服务（自动合并 inbounds）
- ✨ HTTP 代理支持 TLS 加密选项
- ✨ SOCKS 代理支持 UDP over TCP 选项
- ✨ Snell 更新至 v5 版本支持
- 🔧 修复 DNS 配置顺序问题

### v3.5
- 🔧 移除 AnyTLS Nginx Fallback 功能（Nginx TLS 终止会破坏 AnyTLS 抗指纹能力）
- 🔧 AnyTLS 默认端口改为 443（直接暴露以保留完整 TLS 指纹特征）
- 🐛 修复 grep -oP 在部分系统上的兼容性问题

### v3.4
- ✨ 新增 AnyTLS 协议支持（抗 TLS 指纹检测）
- ✨ AnyTLS 自动 Let's Encrypt 证书申请
- 🔧 Snell Shadow-TLS 默认端口改为 8444

### v3.3
- ✨ 新增高级分流管理模块
- ✨ 支持 SS/Hysteria2/VLESS 落地代理配置
- ✨ 支持 Loyalsoldier 远程订阅规则集
- ✨ GeoIP/GeoSite 自动更新功能
- ✨ 交互式规则测试功能
- ✨ 统一分流管理菜单

### v3.2
- 🔧 版本更新检查优化
- 🔧 服务状态缓存

### v3.0
- 🎉 模块化重构
- ✨ 支持多协议管理

## ❓ 常见问题

<details>
<summary><b>安装失败怎么办？</b></summary>

1. 确保使用 root 用户运行
2. 检查网络连接是否正常
3. 尝试重新运行安装命令

</details>

<details>
<summary><b>如何更新到最新版本？</b></summary>

```bash
proxy-manager update
# 或者重新运行安装命令
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)
```

</details>

<details>
<summary><b>服务启动失败？</b></summary>

查看服务日志：
```bash
journalctl -u snell -n 50 --no-pager
journalctl -u sing-box -n 50 --no-pager
```

</details>

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 License

MIT
