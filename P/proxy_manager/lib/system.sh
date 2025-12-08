#!/bin/bash
# =========================================
# Proxy Manager - System Library
# 系统检测和依赖安装函数库
# =========================================

# 防止重复加载
[[ -n "${_SYSTEM_LOADED:-}" ]] && return 0
_SYSTEM_LOADED=1

# =========================================
# 服务状态缓存
# =========================================
declare -A SERVICE_STATUS_CACHE
declare -g STATUS_CACHE_TIME=0

# =========================================
# 系统检测函数
# =========================================

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "需要 root 权限运行此脚本"
        echo -e "${RED}请使用 root 用户运行此脚本或使用 sudo${RESET}"
        exit 1
    fi
    
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR" 2>/dev/null || {
        echo -e "${YELLOW}警告: 无法创建配置目录，某些功能可能不可用${RESET}"
    }
    
    touch "${LOG_DIR}/install.log" 2>/dev/null || {
        echo -e "${YELLOW}警告: 无法创建日志文件${RESET}"
    }
}

# 检测包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# 检测体系结构
detect_architecture() {
    ARCH="$(uname -m)"
    log_message "INFO" "检测到系统架构: $ARCH"
    echo -e "${CYAN}检测到系统架构: ${ARCH}${RESET}"

    case "$ARCH" in
        x86_64)
            SNELL_ARCH="amd64"
            SINGBOX_ARCH="amd64"
            SHADOW_TLS_ARCH="x86_64-unknown-linux-musl"
            HYSTERIA2_ARCH="amd64"
            ;;
        aarch64)
            SNELL_ARCH="aarch64"
            SINGBOX_ARCH="arm64"
            SHADOW_TLS_ARCH="aarch64-unknown-linux-musl"
            HYSTERIA2_ARCH="arm64"
            ;;
        armv7l)
            SNELL_ARCH="armv7l"
            SINGBOX_ARCH="armv7"
            SHADOW_TLS_ARCH="armv7-unknown-linux-musleabihf"
            HYSTERIA2_ARCH="armv7"
            ;;
        *)
            log_message "ERROR" "不支持的系统架构: $ARCH"
            echo -e "${RED}不支持的系统架构: $ARCH${RESET}"
            exit 1
            ;;
    esac
    
    # 导出为全局变量
    export ARCH SNELL_ARCH SINGBOX_ARCH SHADOW_TLS_ARCH HYSTERIA2_ARCH
}

# 安装依赖
install_dependencies() {
    log_message "INFO" "检查并安装必要的依赖..."
    
    local required_packages=(
        "curl" "wget" "unzip" "jq" 
        "net-tools" "qrencode" "openssl" 
        "socat" "tar" "gzip"
    )
    
    local pkg_manager=$(detect_package_manager)
    local missing_packages=()
    
    for pkg in "${required_packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done
    
    # 检查 cron
    local cron_package=""
    case $pkg_manager in
        apt) cron_package="cron" ;;
        yum|dnf) cron_package="cronie" ;;
        pacman) cron_package="cronie" ;;
    esac
    
    if ! command -v crontab &> /dev/null && [ -n "$cron_package" ]; then
        missing_packages+=("$cron_package")
    fi
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${CYAN}需要安装以下软件包: ${YELLOW}${missing_packages[*]}${RESET}"
        log_message "INFO" "使用 $pkg_manager 安装软件包: ${missing_packages[*]}"
        
        case $pkg_manager in
            apt)
                apt-get update -qq 2>&1 | tee -a "${LOG_DIR}/apt-update.log"
                apt-get install -y -qq "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/apt-install.log"
                ;;
            yum)
                yum install -y -q "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/yum-install.log"
                ;;
            dnf)
                dnf install -y -q "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/dnf-install.log"
                ;;
            pacman)
                pacman -Sy --noconfirm "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/pacman-install.log"
                ;;
            *)
                echo -e "${RED}不支持的包管理器，请手动安装依赖${RESET}"
                echo -e "${YELLOW}需要安装: ${missing_packages[*]}${RESET}"
                return 1
                ;;
        esac
        
        echo -e "${GREEN}✓ 依赖安装完成${RESET}"
    else
        echo -e "${GREEN}✓ 所有依赖已安装${RESET}"
    fi
    
    # 确保 cron 服务运行
    if command -v crontab &> /dev/null; then
        if systemctl list-unit-files 2>/dev/null | grep -qE "^(cron|cronie)\.service"; then
            local cron_service=$(systemctl list-unit-files 2>/dev/null | grep -oE "^(cron|cronie)\.service" | head -n 1 | sed 's/\.service$//')
            if ! systemctl is-active --quiet "$cron_service" 2>/dev/null; then
                systemctl enable "$cron_service" 2>/dev/null
                systemctl start "$cron_service" 2>/dev/null
            fi
        fi
    fi
}

# =========================================
# IP 检测函数
# =========================================

# 获取服务器 IP
get_server_ip() {
    log_message "INFO" "正在检测服务器 IP 地址..."
    
    echo -e "${CYAN}正在检测 IPv4...${RESET}"
    IPV4=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1 || true)
    
    if [ -z "$IPV4" ]; then
        IPV4=$(curl -4 -s --connect-timeout 2 --max-time 3 ifconfig.me 2>/dev/null || true)
    fi
    
    echo -e "${CYAN}正在检测 IPv6...${RESET}"
    IPV6=$(ip -6 addr show 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1 || true)
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   检测到的 IP 地址${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    
    local has_ipv4=false
    local has_ipv6=false
    
    if [ -n "$IPV4" ]; then
        echo -e "${GREEN}IPv4: ${YELLOW}${IPV4}${RESET}"
        has_ipv4=true
    else
        echo -e "${RED}IPv4: 未检测到${RESET}"
    fi
    
    if [ -n "$IPV6" ]; then
        echo -e "${GREEN}IPv6: ${YELLOW}${IPV6}${RESET}"
        has_ipv6=true
    else
        echo -e "${RED}IPv6: 未检测到${RESET}"
    fi
    
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    # IP 选择逻辑
    if [ "$has_ipv4" = true ] && [ "$has_ipv6" = true ]; then
        echo -e "${YELLOW}检测到 IPv4 和 IPv6，请选择使用哪个:${RESET}"
        echo -e "${YELLOW}1.${RESET} 使用 IPv4 ${GREEN}(推荐)${RESET} - ${YELLOW}${IPV4}${RESET}"
        echo -e "${YELLOW}2.${RESET} 使用 IPv6 - ${YELLOW}${IPV6}${RESET}"
        echo -e "${YELLOW}3.${RESET} 手动输入"
        echo ""
        
        while true; do
            read -p "请选择 [1-3] (默认: 1): " ip_choice
            ip_choice=${ip_choice:-1}
            
            case $ip_choice in
                1) SERVER_IP=$IPV4; IP_VERSION="IPv4"; break ;;
                2) SERVER_IP=$IPV6; IP_VERSION="IPv6"; break ;;
                3)
                    read -p "请输入服务器 IP 地址: " SERVER_IP
                    if [ -n "$SERVER_IP" ]; then
                        IP_VERSION="Manual"
                        break
                    fi
                    ;;
                *) echo -e "${RED}无效的选择${RESET}" ;;
            esac
        done
    elif [ "$has_ipv4" = true ]; then
        SERVER_IP=$IPV4
        IP_VERSION="IPv4"
    elif [ "$has_ipv6" = true ]; then
        SERVER_IP=$IPV6
        IP_VERSION="IPv6"
    else
        read -p "请手动输入服务器 IP 地址: " SERVER_IP
        IP_VERSION="Manual"
    fi
    
    echo -e "${GREEN}已选择 IP 地址: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    export SERVER_IP IP_VERSION
}

# =========================================
# 服务状态函数
# =========================================

# 批量获取服务状态
get_all_service_status() {
    local current_time=$(date +%s)
    
    if [ $((current_time - STATUS_CACHE_TIME)) -lt 5 ]; then
        return
    fi
    
    local services=("snell" "shadow-tls-snell" "sing-box" "sing-box-reality" "hysteria2")
    local installed_services=$(systemctl list-unit-files 2>/dev/null | grep -E "^(snell|shadow-tls-snell|sing-box|sing-box-reality|hysteria2)\.service" | awk '{print $1}' | sed 's/\.service$//')
    
    for service in "${services[@]}"; do
        if echo "$installed_services" | grep -q "^${service}$"; then
            SERVICE_STATUS_CACHE[$service]=$(systemctl is-active "$service" 2>/dev/null || echo "未运行")
        else
            SERVICE_STATUS_CACHE[$service]="未安装"
        fi
    done
    
    STATUS_CACHE_TIME=$current_time
}

# 清除状态缓存
clear_status_cache() {
    for key in "${!SERVICE_STATUS_CACHE[@]}"; do
        unset SERVICE_STATUS_CACHE[$key]
    done
    STATUS_CACHE_TIME=0
}

# =========================================
# 注意: 函数通过 source 加载，无需 export -f
# =========================================
