# Proxy Manager (Go)

多协议代理服务器一键管理工具 (Go 版本)

## 🚀 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh)
```

## ✨ 特性

- 🎯 单二进制文件，无依赖
- 🖥️ 现代 TUI 界面 (基于 Bubbletea)
- 🔄 健康检查和自动重启
- 📦 支持多平台 (Linux amd64/arm64)
- 🔧 一键安装/更新/卸载

## 📋 支持的协议

| 协议 | 说明 |
|------|------|
| Snell + Shadow-TLS | Surge 专用协议 |
| SS-2022 + Shadow-TLS | 通用 Shadowsocks |
| VLESS Reality | 抗检测协议 |
| Hysteria2 | 高速 QUIC 协议 |
| AnyTLS | 抗 TLS 指纹检测 |

## 🛠️ 使用方法

```bash
# 运行交互式管理界面
proxy-manager

# 显示帮助信息
proxy-manager --help

# 显示版本信息
proxy-manager --version

# 更新到最新版
proxy-manager update
```

## 📥 安装命令

```bash
# 安装
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh)

# 更新
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh) update

# 卸载
bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh) uninstall
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
│   ├── services/         # 服务管理
│   ├── ui/               # TUI 界面
│   └── health/           # 健康检查
├── scripts/
│   └── install.sh        # 安装脚本
├── .github/workflows/    # CI/CD
├── Makefile              # 构建脚本
└── go.mod                # Go 模块
```

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
