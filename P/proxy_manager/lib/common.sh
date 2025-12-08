#!/bin/bash
# =========================================
# Proxy Manager - Common Library
# 通用函数库：颜色、日志、错误处理、下载等
# =========================================

# 防止重复加载
[[ -n "${_COMMON_LOADED:-}" ]] && return 0
_COMMON_LOADED=1

# =========================================
# 终端颜色支持检测
# =========================================
setup_colors() {
    if [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && [[ "$TERM" != "dumb" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        CYAN='\033[0;36m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        RESET='\033[0m'
        BOLD='\033[1m'
    else
        RED='' GREEN='' YELLOW='' CYAN='' BLUE='' MAGENTA='' RESET='' BOLD=''
    fi
}

# 初始化颜色
setup_colors

# =========================================
# 路径常量
# =========================================
CONFIG_DIR="/etc/proxy-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOG_DIR="/var/log/proxy-manager"
BACKUP_DIR="/var/backups/proxy-configs"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# =========================================
# 版本常量
# =========================================
DEFAULT_SNELL_VERSION="5.0.1"
DEFAULT_SINGBOX_VERSION="v1.10.0"
DEFAULT_SHADOW_TLS_VERSION="v0.2.25"
DEFAULT_HYSTERIA2_VERSION="v2.6.1"

# =========================================
# 跨平台兼容函数
# =========================================

# 获取默认用户组（兼容不同发行版）
get_default_group() {
    if getent group nogroup >/dev/null 2>&1; then
        echo "nogroup"
    elif getent group nobody >/dev/null 2>&1; then
        echo "nobody"
    else
        echo "nogroup"
    fi
}

# =========================================
# 日志函数
# =========================================

# 日志轮转
rotate_log() {
    local log_file="${LOG_DIR}/install.log"
    
    if [ -f "$log_file" ]; then
        local size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$log_file" "${log_file}.old" 2>/dev/null || true
            gzip -f "${log_file}.old" 2>/dev/null || true
        fi
    fi
}

# 日志记录（写入文件并输出到终端）
log_message() {
    local level=$1
    local message=$2
    local log_file="${LOG_DIR}/install.log"
    
    # 确保日志目录存在
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    fi
    
    # 日志轮转
    rotate_log
    
    # 写入日志文件
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$log_file" 2>/dev/null || true
    
    # 根据级别输出到终端
    case $level in
        ERROR)
            echo -e "${RED}[ERROR] $message${RESET}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN] $message${RESET}" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS] $message${RESET}" >&2
            ;;
        INFO)
            # INFO 级别不输出到终端，只记录日志
            ;;
    esac
}

# =========================================
# 错误处理
# =========================================

# 统一的错误处理函数
handle_error() {
    local exit_code=$1
    local error_msg=$2
    local log_file=${3:-""}
    
    echo -e "${RED}❌ 错误: ${error_msg}${RESET}"
    
    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        echo -e "${YELLOW}最近的日志输出:${RESET}"
        tail -n 20 "$log_file" 2>/dev/null || true
    fi
    
    log_message "ERROR" "$error_msg"
    return $exit_code
}

# =========================================
# 服务验证函数
# =========================================

# 验证服务是否成功启动
verify_service_started() {
    local service=$1
    local max_wait=${2:-10}
    
    echo -e "${CYAN}正在验证服务 ${service} 启动状态...${RESET}"
    
    for ((i=1; i<=max_wait; i++)); do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}✓ 服务 ${service} 启动成功${RESET}"
            return 0
        fi
        sleep 1
    done
    
    echo -e "${RED}✗ 服务 ${service} 启动失败${RESET}"
    echo -e "${YELLOW}最近的日志:${RESET}"
    journalctl -u "$service" -n 10 --no-pager 2>/dev/null || true
    return 1
}

# =========================================
# 下载函数
# =========================================

# 通用下载函数（带重试和清理）
download_file() {
    local url=$1
    local output=$2
    local max_retries=${3:-3}
    local retry_delay=${4:-5}
    
    log_message "INFO" "下载: $url"
    
    # 确保目标目录存在
    local output_dir=$(dirname "$output")
    mkdir -p "$output_dir" 2>/dev/null || true
    
    for ((i=1; i<=max_retries; i++)); do
        echo -e "${CYAN}下载尝试 $i/$max_retries...${RESET}"
        
        if wget -q --show-progress --progress=bar:force:noscroll \
               --timeout=30 --tries=3 \
               "$url" -O "$output" 2>&1; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                log_message "SUCCESS" "下载成功: $output"
                return 0
            else
                log_message "WARN" "下载的文件为空或不存在"
                rm -f "$output" 2>/dev/null || true
            fi
        else
            log_message "WARN" "wget 下载失败（尝试 $i/$max_retries）"
            rm -f "$output" 2>/dev/null || true
        fi
        
        if [ $i -lt $max_retries ]; then
            echo -e "${YELLOW}下载失败，${retry_delay}秒后重试...${RESET}"
            sleep $retry_delay
        fi
    done
    
    # 清理失败的下载
    rm -f "$output" 2>/dev/null || true
    log_message "ERROR" "下载失败（已重试 $max_retries 次）: $url"
    return 1
}

# =========================================
# 临时文件管理
# =========================================

# 安全创建临时文件
create_temp_file() {
    local suffix=${1:-.tmp}
    local temp_file
    
    if [ -d "/var/tmp" ]; then
        temp_file=$(mktemp -p /var/tmp "proxy-XXXXXX${suffix}")
    else
        temp_file=$(mktemp "/tmp/proxy-XXXXXX${suffix}")
    fi
    
    chmod 600 "$temp_file"
    echo "$temp_file"
}

# 清理临时文件
cleanup_temp_files() {
    rm -f /var/tmp/proxy-* /tmp/proxy-* 2>/dev/null || true
}

# =========================================
# 版本获取函数
# =========================================

# 统一版本获取函数
get_latest_version() {
    local repo=$1
    local service=$2
    local default_version=$3
    
    local version=""
    
    case $service in
        snell)
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://manual.nssurge.com/others/snell.html" 2>/dev/null | \
                grep -oP 'snell-server-v?\K[0-9]+\.[0-9]+\.[0-9]+' | \
                sort -V | tail -n 1 || true)
            
            if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$version"
                return 0
            fi
            
            log_message "WARN" "无法获取 Snell 最新版本，使用默认版本: $default_version"
            echo "$default_version"
            ;;
        shadow-tls)
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" 2>/dev/null | \
                grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            echo "${version:-$default_version}"
            ;;
        sing-box)
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null | \
                grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            echo "${version:-$default_version}"
            ;;
        hysteria2)
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://api.github.com/repos/apernet/hysteria/releases/latest" 2>/dev/null | \
                grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            echo "${version:-$default_version}"
            ;;
        *)
            # 通用 GitHub releases
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
                grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            echo "${version:-$default_version}"
            ;;
    esac
}

# =========================================
# 版本检查与更新提示
# =========================================
declare -A VERSION_UPDATE_CACHE

check_version_updates() {
    echo -e "${CYAN}正在检查版本更新...${RESET}"
    
    local has_update=false
    
    # 检查 Snell
    if [ -f /etc/snell-proxy-config.txt ]; then
        local current=$(grep "^SNELL_VERSION=" /etc/snell-proxy-config.txt 2>/dev/null | cut -d'=' -f2)
        local latest=$(get_latest_version "" "snell" "$DEFAULT_SNELL_VERSION")
        if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
            VERSION_UPDATE_CACHE["snell"]="$current -> $latest"
            has_update=true
        fi
    fi
    
    # 检查 Shadow-TLS
    if [ -f /etc/snell-proxy-config.txt ]; then
        local current=$(grep "^SHADOW_TLS_VERSION=" /etc/snell-proxy-config.txt 2>/dev/null | cut -d'=' -f2)
        local latest=$(get_latest_version "" "shadow-tls" "$DEFAULT_SHADOW_TLS_VERSION")
        if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
            VERSION_UPDATE_CACHE["shadow-tls"]="$current -> $latest"
            has_update=true
        fi
    fi
    
    # 检查 Sing-box
    if [ -f /etc/singbox-proxy-config.txt ] || [ -f /etc/reality-proxy-config.txt ] || [ -f /etc/hysteria2-proxy-config.txt ]; then
        local current=""
        for cfg in /etc/singbox-proxy-config.txt /etc/reality-proxy-config.txt /etc/hysteria2-proxy-config.txt; do
            if [ -f "$cfg" ]; then
                current=$(grep "^SINGBOX_VERSION=" "$cfg" 2>/dev/null | cut -d'=' -f2)
                [ -n "$current" ] && break
            fi
        done
        local latest=$(get_latest_version "" "sing-box" "$DEFAULT_SINGBOX_VERSION")
        if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
            VERSION_UPDATE_CACHE["sing-box"]="$current -> $latest"
            has_update=true
        fi
    fi
    
    # 显示更新提示
    if [ "$has_update" = true ]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${YELLOW}║${RESET}  ${CYAN}发现可用更新${RESET}                                            ${YELLOW}║${RESET}"
        echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════╣${RESET}"
        for service in "${!VERSION_UPDATE_CACHE[@]}"; do
            printf "${YELLOW}║${RESET}  %-15s: ${GREEN}%s${RESET}                    ${YELLOW}║${RESET}\n" "$service" "${VERSION_UPDATE_CACHE[$service]}"
        done
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${RESET}"
        echo ""
    fi
}

# =========================================
# 通用 systemd 服务创建函数
# =========================================
create_systemd_service() {
    local name=$1
    local description=$2
    local user=$3
    local exec_start=$4
    local needs_cap=${5:-false}
    local after=${6:-"network-online.target"}
    local requires=${7:-""}
    
    local default_group=$(get_default_group)
    local cap_line=""
    local requires_line=""
    
    [ "$needs_cap" = true ] && cap_line="AmbientCapabilities=CAP_NET_BIND_SERVICE"
    [ -n "$requires" ] && requires_line="Requires=$requires"
    
    cat > "/lib/systemd/system/${name}.service" <<EOF
[Unit]
Description=$description
After=$after
$requires_line

[Service]
Type=simple
User=$user
Group=${default_group}
LimitNOFILE=65535
ExecStart=$exec_start
$cap_line
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置正确权限
    chmod 644 "/lib/systemd/system/${name}.service"
    systemctl daemon-reload
}

# =========================================
# 通用域名选择函数
# =========================================
select_tls_domain() {
    local title=${1:-"选择 TLS 伪装域名"}
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   $title${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${GREEN}推荐域名:${RESET}"
    echo -e "${YELLOW}1.${RESET}  gateway.icloud.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}2.${RESET}  www.microsoft.com"
    echo -e "${YELLOW}3.${RESET}  www.apple.com"
    echo -e "${YELLOW}4.${RESET}  cloudflare.com"
    echo -e "${YELLOW}5.${RESET}  www.amazon.com"
    echo -e "${YELLOW}6.${RESET}  www.google.com"
    echo ""
    echo -e "${YELLOW}0.${RESET}  自定义域名"
    echo ""
    
    while true; do
        read -p "请选择域名 [0-6] (默认: 1): " domain_choice
        domain_choice=${domain_choice:-1}
        
        case $domain_choice in
            1) TLS_DOMAIN="gateway.icloud.com"; break;;
            2) TLS_DOMAIN="www.microsoft.com"; break;;
            3) TLS_DOMAIN="www.apple.com"; break;;
            4) TLS_DOMAIN="cloudflare.com"; break;;
            5) TLS_DOMAIN="www.amazon.com"; break;;
            6) TLS_DOMAIN="www.google.com"; break;;
            0)
                read -p "请输入自定义域名: " TLS_DOMAIN
                [ -n "$TLS_DOMAIN" ] && break
                echo -e "${RED}域名不能为空${RESET}"
                ;;
            *) echo -e "${RED}无效的选择${RESET}" ;;
        esac
    done
    
    echo -e "${GREEN}已选择域名: ${TLS_DOMAIN}${RESET}"
}

# =========================================
# 配置文件权限设置
# =========================================
secure_config_file() {
    local file=$1
    if [ -f "$file" ]; then
        chmod 600 "$file"
        log_message "INFO" "设置配置文件权限: $file"
    fi
}
