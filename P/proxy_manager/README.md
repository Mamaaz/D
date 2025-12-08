# Proxy Manager

多协议代理服务器一键管理脚本，支持 Snell、SS-2022、VLESS Reality、Hysteria2。

## 🚀 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)
```

安装后使用 `proxy-manager` 命令即可运行。

## 📋 支持协议

| 协议 | 说明 |
|------|------|
| Snell + Shadow-TLS | Surge 专用协议 |
| SS-2022 + Shadow-TLS | 最新 Shadowsocks 协议 |
| VLESS Reality | Xray 核心协议 |
| Hysteria2 | 基于 QUIC 的高速协议 |

## 🔧 常用命令

```bash
proxy-manager              # 运行管理脚本
proxy-manager update       # 更新到最新版
```

## 📦 系统要求

- Linux (Debian/Ubuntu/CentOS/RHEL)
- Root 权限
- x86_64 / arm64 / armv7

## 📁 目录结构

```
/opt/proxy-manager/
├── proxy-manager.sh       # 主入口
├── lib/                   # 通用库
│   ├── common.sh
│   ├── config.sh
│   ├── system.sh
│   └── validation.sh
└── modules/               # 服务模块
    ├── snell.sh
    ├── singbox.sh
    ├── reality.sh
    ├── hysteria2.sh
    └── cert.sh
```

## 📄 License

MIT
