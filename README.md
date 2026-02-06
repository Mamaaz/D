# Proxy Manager (Go)

多协议代理服务器一键管理工具 (Go 版本)

## 🚀 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)
```

## ✨ 特性

- 🎯 单二进制文件，无依赖
- 🖥️ 现代 TUI 界面 (基于 Bubbletea)
- 🔄 健康检查和自动重启
- 📦 支持多平台 (Linux amd64/arm64)
- 🔧 一键安装/更新/卸载
- 🔍 动态版本检查，自动获取最新版本

## 📋 支持的协议

| 协议 | 内核 | 说明 |
|------|------|------|
| Snell + Shadow-TLS | snell-server | Surge 专用协议 |
| SS-2022 + Shadow-TLS | sing-box | 通用 Shadowsocks |
| VLESS Reality | sing-box | 抗检测协议 |
| Hysteria2 | sing-box | 高速 QUIC 协议，支持混淆 |
| AnyTLS | sing-box | 抗 TLS 指纹检测，支持填充方案 |

> **统一架构**: 除 Snell 外，所有协议都使用 sing-box 内核

## 🛠️ 使用方法

```bash
# 运行交互式管理界面
proxy-manager

# 显示帮助信息
proxy-manager --help

# 显示版本信息
proxy-manager --version

# 使用 TUI 模式
proxy-manager --tui
```

## 📥 安装命令

```bash
# 安装
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)

# 更新
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh) update

# 卸载
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh) uninstall
```

## 🔧 本地构建

```bash
# 本地构建
make build

# 跨平台构建
make all

# 安装到系统
make install

# 创建发布包
make release
```

## 📁 项目结构

```
proxy-manager-go/
├── cmd/proxy-manager/     # 主入口
├── internal/
│   ├── config/           # 配置管理
│   ├── install/          # 安装模块 (snell/singbox/reality/hysteria2/anytls)
│   ├── services/         # 服务管理
│   ├── ui/               # TUI 界面
│   ├── utils/            # 工具函数 (版本检查等)
│   └── health/           # 健康检查
├── scripts/
│   └── install.sh        # 在线安装脚本
├── dist/                 # 编译输出
├── .github/workflows/    # CI/CD
├── Makefile              # 构建脚本
└── go.mod                # Go 模块
```

## 🔍 版本检查

安装时自动从官方源获取最新版本：

| 组件 | 版本源 |
|------|--------|
| Snell | [Surge KB](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) |
| Sing-box | [GitHub API](https://api.github.com/repos/SagerNet/sing-box/releases/latest) |
| Shadow-TLS | [GitHub API](https://api.github.com/repos/ihciah/shadow-tls/releases/latest) |

## 🏥 健康检查

安装后会自动配置健康检查定时器，每 5 分钟检查一次代理服务状态，自动重启异常服务。

```bash
# 查看健康检查状态
systemctl status proxy-health.timer

# 查看健康检查日志
tail -f /var/log/proxy-manager/health.log
```

## 📄 License

MIT
