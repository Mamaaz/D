#!/bin/bash
# =========================================
# Proxy Manager (Go) - 在线安装脚本
# 一行命令安装: bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/install.sh)
# =========================================

set -e

# 版本配置
VERSION="4.0.0"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="proxy-manager"
CONFIG_DIR="/etc/proxy-manager"
LOG_DIR="/var/log/proxy-manager"

# GitHub 配置
GITHUB_USER="Mamaaz"
GITHUB_REPO="D"
BRANCH="main"
SUBDIR="P/proxy_manager_go"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/${SUBDIR}"
RELEASE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/latest/download"

# 颜色定义
setup_colors() {
    if [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && [[ "$TERM" != "dumb" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        CYAN='\033[0;36m'
        RESET='\033[0m'
    else
        RED='' GREEN='' YELLOW='' CYAN='' RESET=''
    fi
}

setup_colors

# =========================================
# 辅助函数
# =========================================

print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}       ${GREEN}Proxy Manager (Go) v${VERSION}${RESET}                          ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}       多协议代理服务器一键管理工具                         ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

log_info() {
    echo -e "${CYAN}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        echo ""
        echo "  sudo bash <(curl -sL ${RAW_URL}/scripts/install.sh)"
        echo ""
        exit 1
    fi
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    log_info "检测到架构: ${ARCH}"
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    else
        log_error "不支持的操作系统: $OSTYPE"
        log_info "此工具仅支持 Linux 系统"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    local missing=()
    
    for cmd in curl wget; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_info "正在安装依赖: ${missing[*]}"
        
        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y -qq "${missing[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y -q "${missing[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y -q "${missing[@]}"
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm "${missing[@]}"
        fi
    fi
}

# 获取最新版本号
get_latest_version() {
    local api_url="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/latest"
    local latest=$(curl -s --connect-timeout 5 "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')
    
    if [ -n "$latest" ]; then
        echo "$latest"
    else
        echo "$VERSION"
    fi
}

# 获取当前安装版本
get_installed_version() {
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        "${INSTALL_DIR}/${BINARY_NAME}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    else
        echo ""
    fi
}

# =========================================
# 安装函数
# =========================================

# 下载二进制文件
download_binary() {
    local version=${1:-$VERSION}
    local temp_file=$(mktemp)
    
    # 尝试从 GitHub Releases 下载
    local download_url="${RELEASE_URL}/${BINARY_NAME}-${OS}-${ARCH}"
    
    log_info "正在下载 ${BINARY_NAME} v${version} (${OS}-${ARCH})..."
    
    if curl -sL --fail "$download_url" -o "$temp_file" 2>/dev/null; then
        # 验证文件大小
        local size=$(stat -f%z "$temp_file" 2>/dev/null || stat -c%s "$temp_file" 2>/dev/null || echo 0)
        if [ "$size" -gt 1000000 ]; then  # 至少 1MB
            mv "$temp_file" "${INSTALL_DIR}/${BINARY_NAME}"
            chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
            log_success "二进制文件下载成功"
            return 0
        fi
    fi
    
    rm -f "$temp_file"
    
    # 尝试备用下载地址 (raw.githubusercontent.com)
    log_warn "主下载源失败，尝试备用源..."
    local alt_url="${RAW_URL}/dist/${BINARY_NAME}-${OS}-${ARCH}"
    
    if curl -sL --fail "$alt_url" -o "$temp_file" 2>/dev/null; then
        local size=$(stat -f%z "$temp_file" 2>/dev/null || stat -c%s "$temp_file" 2>/dev/null || echo 0)
        if [ "$size" -gt 1000000 ]; then
            mv "$temp_file" "${INSTALL_DIR}/${BINARY_NAME}"
            chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
            log_success "二进制文件下载成功 (备用源)"
            return 0
        fi
    fi
    
    rm -f "$temp_file"
    log_error "下载失败，请检查网络连接"
    return 1
}

# 创建目录
create_directories() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
}

# 安装健康检查服务
install_health_timer() {
    log_info "正在安装健康检查定时器..."
    
    # 下载健康检查脚本
    local health_script="${CONFIG_DIR}/health-check.sh"
    cat > "$health_script" << 'HEALTH_SCRIPT'
#!/bin/bash
# Proxy Manager - 健康检查脚本

LOG_FILE="/var/log/proxy-manager/health.log"
MAX_LOG_SIZE=$((5 * 1024 * 1024))  # 5MB

log_rotate() {
    if [ -f "$LOG_FILE" ]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            gzip -f "${LOG_FILE}.old" 2>/dev/null || true
        fi
    fi
}

log() {
    log_rotate
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        return 0
    else
        log "服务 $service 未运行，正在重启..."
        systemctl restart "$service" 2>/dev/null
        sleep 2
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "服务 $service 重启成功"
        else
            log "服务 $service 重启失败"
        fi
    fi
}

# 检查所有代理服务
for service in snell shadow-tls sing-box hysteria2; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        check_service "$service"
    fi
done

log "健康检查完成"
HEALTH_SCRIPT
    chmod +x "$health_script"
    
    # 创建 systemd service
    cat > /etc/systemd/system/proxy-health.service << EOF
[Unit]
Description=Proxy Manager Health Check

[Service]
Type=oneshot
ExecStart=${health_script}
EOF
    
    # 创建 systemd timer
    cat > /etc/systemd/system/proxy-health.timer << EOF
[Unit]
Description=Proxy Manager Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
    
    # 启用 timer
    systemctl daemon-reload
    systemctl enable proxy-health.timer 2>/dev/null || true
    systemctl start proxy-health.timer 2>/dev/null || true
    
    log_success "健康检查定时器已安装 (每5分钟检查一次)"
}

# 主安装函数
do_install() {
    print_banner
    check_root
    detect_os
    detect_arch
    check_dependencies
    
    local current_version=$(get_installed_version)
    if [ -n "$current_version" ]; then
        log_warn "检测到已安装版本: v${current_version}"
        echo ""
        read -p "是否继续安装/更新？(y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "安装已取消"
            exit 0
        fi
        echo ""
    fi
    
    create_directories
    download_binary || exit 1
    install_health_timer
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}       ${CYAN}安装完成！${RESET}                                          ${GREEN}║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${CYAN}使用方法:${RESET}"
    echo -e "  ${YELLOW}proxy-manager${RESET}              # 运行交互式管理界面"
    echo -e "  ${YELLOW}proxy-manager --help${RESET}       # 显示帮助信息"
    echo -e "  ${YELLOW}proxy-manager --version${RESET}    # 显示版本信息"
    echo ""
    echo -e "${CYAN}更新命令:${RESET}"
    echo -e "  ${YELLOW}bash <(curl -sL ${RAW_URL}/scripts/install.sh) update${RESET}"
    echo ""
}

# =========================================
# 更新函数
# =========================================

do_update() {
    print_banner
    check_root
    detect_os
    detect_arch
    
    local current_version=$(get_installed_version)
    local latest_version=$(get_latest_version)
    
    echo -e "${CYAN}当前版本:${RESET} ${current_version:-未安装}"
    echo -e "${CYAN}最新版本:${RESET} ${latest_version}"
    echo ""
    
    if [ "$current_version" = "$latest_version" ]; then
        log_success "已是最新版本，无需更新"
        return 0
    fi
    
    if [ -z "$current_version" ]; then
        log_warn "未检测到已安装版本，将执行全新安装"
        do_install
        return
    fi
    
    read -p "确认更新？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "更新已取消"
        exit 0
    fi
    
    # 备份旧版本
    cp "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak" 2>/dev/null || true
    
    if download_binary "$latest_version"; then
        rm -f "${INSTALL_DIR}/${BINARY_NAME}.bak"
        log_success "更新成功: v${current_version} -> v${latest_version}"
    else
        # 回滚
        mv "${INSTALL_DIR}/${BINARY_NAME}.bak" "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null || true
        log_error "更新失败，已回滚到 v${current_version}"
        exit 1
    fi
}

# =========================================
# 卸载函数
# =========================================

do_uninstall() {
    print_banner
    check_root
    
    echo -e "${YELLOW}即将卸载 Proxy Manager...${RESET}"
    echo ""
    echo "这将删除:"
    echo "  - ${INSTALL_DIR}/${BINARY_NAME}"
    echo "  - ${CONFIG_DIR}/"
    echo "  - 健康检查定时器"
    echo ""
    echo -e "${RED}注意: 这不会删除已安装的代理服务 (Snell, Sing-box 等)${RESET}"
    echo ""
    
    read -p "确认卸载？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "卸载已取消"
        exit 0
    fi
    
    # 停止并删除健康检查 timer
    systemctl stop proxy-health.timer 2>/dev/null || true
    systemctl disable proxy-health.timer 2>/dev/null || true
    rm -f /etc/systemd/system/proxy-health.service
    rm -f /etc/systemd/system/proxy-health.timer
    systemctl daemon-reload
    
    # 删除二进制文件和配置
    rm -f "${INSTALL_DIR}/${BINARY_NAME}"
    rm -rf "${CONFIG_DIR}"
    
    log_success "Proxy Manager 已卸载"
}

# =========================================
# 主入口
# =========================================

case "${1:-install}" in
    install)
        do_install
        ;;
    update)
        do_update
        ;;
    uninstall|remove)
        do_uninstall
        ;;
    --help|-h)
        echo "Proxy Manager 安装脚本"
        echo ""
        echo "用法: bash install.sh [命令]"
        echo ""
        echo "命令:"
        echo "  install     安装 Proxy Manager (默认)"
        echo "  update      更新到最新版本"
        echo "  uninstall   卸载 Proxy Manager"
        echo ""
        ;;
    *)
        log_error "未知命令: $1"
        echo "使用 --help 查看帮助"
        exit 1
        ;;
esac
