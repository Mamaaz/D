# Proxy Manager

多协议代理服务器一键管理脚本，支持 Snell、SS-2022、VLESS Reality、Hysteria2，以及高级分流管理。

## 🚀 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)
```

## ✨ 功能特性

### 代理服务管理
| 协议 | 说明 |
|------|------|
| Snell + Shadow-TLS | Surge 专用协议 |
| SS-2022 + Shadow-TLS | 最新 Shadowsocks 协议 |
| VLESS Reality | Xray 核心协议，抗检测 |
| Hysteria2 | 基于 QUIC 的高速协议 |

### 🌐 高级分流管理 (v3.3 新增)

| 功能 | 说明 |
|------|------|
| 落地代理管理 | 支持 SS/Hysteria2/VLESS 落地配置 |
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

## 🖥️ 常用命令

```bash
proxy-manager              # 运行管理脚本
proxy-manager update       # 更新脚本
proxy-manager --help       # 显示帮助
```

## 📱 主菜单

```
安装服务
  1-4. Snell / Sing-box / Reality / Hysteria2

管理服务
  5-8. 配置 / 日志 / 更新 / 卸载

证书管理
  9-10. 续签 / 查看证书

分流管理 ⭐ 新增
  11. 高级分流管理 (落地代理/规则/订阅)

系统管理
  12. 更新 Proxy Manager
  13. 完全卸载 Proxy Manager
```

## 🌐 分流管理详情

### 落地代理支持
- **Shadowsocks** - SS-2022 加密，高兼容性
- **Hysteria2** - QUIC 协议，高速低延迟
- **VLESS** - 支持 Reality，抗检测能力强

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

## 📦 系统要求

- Linux (Debian/Ubuntu/CentOS/RHEL)
- Root 权限
- x86_64 / arm64 / armv7

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

## 📄 License

MIT
