#!/bin/bash
# =========================================
# Proxy Manager - Common Library
# 通用函数库：颜色、日志、错误处理、下载等
# =========================================

# 防止重复加载
[[ -n "${_COMMON_LOADED:-}" ]] && return 0
_COMMON_LOADED=1

# =========================================
# 颜色定义
# =========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# =========================================
# 路径常量
# =========================================
CONFIG_DIR="/etc/proxy-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOG_DIR="/var/log/proxy-manager"
BACKUP_DIR="/var/backups/proxy-configs"

# =========================================
# 版本常量
# =========================================
DEFAULT_SNELL_VERSION="5.0.1"
DEFAULT_SINGBOX_VERSION="v1.10.0"
DEFAULT_SHADOW_TLS_VERSION="v0.2.25"

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

# 日志记录（写入文件并输出到终端）
log_message() {
    local level=$1
    local message=$2
    local log_file="${LOG_DIR}/install.log"
    
    # 确保日志目录存在
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    fi
    
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
# 下载函数
# =========================================

# 通用下载函数（带重试）
download_file() {
    local url=$1
    local output=$2
    local max_retries=${3:-3}
    local retry_delay=${4:-5}
    
    log_message "INFO" "下载: $url"
    
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
        fi
        
        if [ $i -lt $max_retries ]; then
            echo -e "${YELLOW}下载失败，${retry_delay}秒后重试...${RESET}"
            sleep $retry_delay
        fi
    done
    
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
            local sources=(
                "https://manual.nssurge.com/others/snell.html"
            )
            
            for source in "${sources[@]}"; do
                version=$(curl -s --connect-timeout 3 --max-time 5 "$source" 2>/dev/null | \
                    grep -oP 'snell-server-v?\K[0-9]+\.[0-9]+\.[0-9]+' | \
                    sort -V | tail -n 1 || true)
                
                if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo "$version"
                    return 0
                fi
            done
            
            log_message "WARN" "无法获取 Snell 最新版本，使用默认版本: $default_version"
            echo "$default_version"
            ;;
        *)
            # GitHub releases
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
                grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            
            echo "${version:-$default_version}"
            ;;
    esac
}

# =========================================
# 导出函数供其他模块使用
# =========================================
export -f get_default_group
export -f log_message
export -f handle_error
export -f download_file
export -f create_temp_file
export -f get_latest_version
