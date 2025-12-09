#!/bin/bash
# =========================================
# Proxy Manager - 在线安装脚本
# 一行命令安装: bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)
# =========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# GitHub 仓库信息
GITHUB_USER="Mamaaz"
GITHUB_REPO="D"
BRANCH="main"
SUBDIR="P/proxy_manager"
INSTALL_DIR="/opt/proxy-manager"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/refs/heads/${BRANCH}/${SUBDIR}"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}       ${GREEN}Proxy Manager 在线安装${RESET}                              ${CYAN}║${RESET}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${RESET}"
    exit 1
fi

# 检测包管理器并安装依赖
install_deps() {
    echo -e "${CYAN}正在检查依赖...${RESET}"
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq git curl wget jq
    elif command -v yum &> /dev/null; then
        yum install -y -q git curl wget jq
    elif command -v dnf &> /dev/null; then
        dnf install -y -q git curl wget jq
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm git curl wget jq
    fi
}

# 下载文件函数
download_file() {
    local url=$1
    local output=$2
    
    if curl -sL "$url" -o "$output" 2>/dev/null; then
        # 检查文件是否为空或过小（可能是404页面）
        local size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo 0)
        if [ "$size" -lt 100 ]; then
            echo -e "${YELLOW}警告: $output 文件过小，可能下载失败${RESET}"
            return 1
        fi
        return 0
    else
        echo -e "${RED}下载失败: $url${RESET}"
        return 1
    fi
}

# 安装
install_proxy_manager() {
    echo -e "${CYAN}正在安装 Proxy Manager...${RESET}"
    
    # 如果已存在，先备份
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}检测到已有安装，正在备份...${RESET}"
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 创建目录结构
    mkdir -p "$INSTALL_DIR"/{lib,modules,config}
    
    echo -e "${CYAN}正在下载文件...${RESET}"
    
    # 下载主文件
    download_file "${RAW_URL}/proxy-manager.sh" "$INSTALL_DIR/proxy-manager.sh"
    download_file "${RAW_URL}/install.sh" "$INSTALL_DIR/install.sh"
    
    # 下载 lib 目录 - 基础库
    for f in common.sh config.sh system.sh validation.sh routing.sh; do
        download_file "${RAW_URL}/lib/${f}" "$INSTALL_DIR/lib/${f}"
    done
    
    # 下载 lib 目录 - 分流管理库 (v3.3 新增)
    for f in outbound.sh geo-update.sh subscriptions.sh; do
        download_file "${RAW_URL}/lib/${f}" "$INSTALL_DIR/lib/${f}"
    done
    
    # 下载 modules 目录 - 服务模块
    for f in snell.sh singbox.sh reality.sh hysteria2.sh cert.sh; do
        download_file "${RAW_URL}/modules/${f}" "$INSTALL_DIR/modules/${f}"
    done
    
    # 下载 modules 目录 - 分流菜单 (v3.3 新增)
    download_file "${RAW_URL}/modules/routing-menu.sh" "$INSTALL_DIR/modules/routing-menu.sh"
    
    # 设置权限
    chmod +x "$INSTALL_DIR/proxy-manager.sh"
    chmod +x "$INSTALL_DIR/lib/"*.sh 2>/dev/null || true
    chmod +x "$INSTALL_DIR/modules/"*.sh 2>/dev/null || true
    
    # 创建软链接
    ln -sf "$INSTALL_DIR/proxy-manager.sh" /usr/local/bin/proxy-manager
    
    echo -e "${GREEN}✓ Proxy Manager 安装完成！${RESET}"
    echo ""
    echo -e "${CYAN}使用方法:${RESET}"
    echo -e "  ${YELLOW}proxy-manager${RESET}        # 运行管理脚本"
    echo -e "  ${YELLOW}proxy-manager update${RESET} # 更新到最新版"
    echo ""
}

# 更新功能
update_proxy_manager() {
    echo -e "${CYAN}正在更新 Proxy Manager...${RESET}"
    
    # 重新下载所有文件
    rm -rf "$INSTALL_DIR"
    install_proxy_manager
    
    echo -e "${GREEN}✓ 更新完成！${RESET}"
}

# 主逻辑
case "${1:-install}" in
    update)
        update_proxy_manager
        ;;
    uninstall)
        echo -e "${YELLOW}正在卸载 Proxy Manager...${RESET}"
        rm -f /usr/local/bin/proxy-manager
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}✓ 卸载完成${RESET}"
        ;;
    *)
        install_deps
        install_proxy_manager
        ;;
esac
