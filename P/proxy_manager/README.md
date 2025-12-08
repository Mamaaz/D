# Proxy Manager

多协议代理服务器一键管理脚本，支持 Snell、SS-2022、VLESS Reality、Hysteria2。

## 🚀 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)
```

安装时会询问是否同时安装 Agent 探针。

## 📋 支持协议

| 协议 | 说明 |
|------|------|
| Snell + Shadow-TLS | Surge 专用协议 |
| SS-2022 + Shadow-TLS | 最新 Shadowsocks 协议 |
| VLESS Reality | Xray 核心协议 |
| Hysteria2 | 基于 QUIC 的高速协议 |

## 🌐 多服务器管理

从一台 VPS 集中管理多台服务器的代理服务。

### 方式一：安装时选择
```bash
bash <(curl -sL .../install.sh)
# 安装完成后询问是否安装 Agent，选择 y
```

### 方式二：仅安装 Agent
```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh) agent
```

### 方式三：在管理器内安装
```bash
proxy-manager -> 选择 11 (多服务器管理) -> 选择 2 (安装 Agent)
```

### 功能
- 🔍 批量查看所有服务器状态
- 🔄 批量重启/卸载服务
- 🔐 Token 认证（不存储密码）
- 📡 支持多 IP 选择

## 🔧 常用命令

```bash
proxy-manager              # 运行管理脚本
proxy-manager update       # 更新脚本
```

## 📱 主菜单

```
安装服务
  1. Snell + Shadow-TLS
  2. Sing-box (SS-2022)
  3. VLESS Reality
  4. Hysteria2

管理服务
  5-8. 配置/日志/更新/卸载

证书管理
  9-10. 续签/查看证书

多服务器管理
  11. 多服务器管理

系统管理
  12. 更新 Proxy Manager
  13. 完全卸载 Proxy Manager
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
├── modules/               # 服务模块
└── agent/                 # 探针 Agent
```

## 📄 License

MIT
