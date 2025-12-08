#!/bin/bash

# =========================================
# Snell/Sing-box + Shadow-TLS 一键安装脚本
# 支持同时安装多个代理服务和自动更新
# 已集成安全配置和自动断联修复
# 新增 VLESS Reality 支持
# 新增 Hysteria2 支持（Let's Encrypt 证书 + 自动续签）
# 支持 IPv4/IPv6 选择
# 版本: 2.3 (完整修复版)
# =========================================

# 🚀 性能优化：启用管道错误检测
set -o pipefail
set -u  # 只保留未定义变量检测

# 定义颜色代码（在 trap 之前定义，避免错误处理函数中未定义）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# 配置文件路径（统一管理）
CONFIG_DIR="/etc/proxy-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOG_DIR="/var/log/proxy-manager"
BACKUP_DIR="/var/backups/proxy-configs"

# 🚀 集中定义默认版本号（便于维护）
DEFAULT_SNELL_VERSION="5.0.1"
DEFAULT_SINGBOX_VERSION="v1.10.0"
DEFAULT_SHADOW_TLS_VERSION="v0.2.25"

# 🚀 获取默认用户组（跨平台兼容）
get_default_group() {
    if getent group nogroup >/dev/null 2>&1; then
        echo "nogroup"
    elif getent group nobody >/dev/null 2>&1; then
        echo "nobody"
    else
        echo "nogroup"  # 回退默认值
    fi
}

# =========================================
# 错误处理
# =========================================

# 脚本错误处理函数（修复版 - 避免依赖未定义变量）
handle_script_error() {
    trap - ERR  # 禁用 ERR trap，防止无限循环
    local exit_code=$1
    local line_no=$2
    
    # 直接使用 ANSI 颜色码，避免依赖变量
    echo -e "\033[0;31m[ERROR] 脚本在第 ${line_no} 行出错，退出码: ${exit_code}\033[0m" >&2
    
    # 尝试记录日志（不触发新错误）
    if declare -f log_message > /dev/null 2>&1; then
        log_message "ERROR" "脚本在第 ${line_no} 行出错，退出码: ${exit_code}" 2>/dev/null || true
    fi
}

trap 'handle_script_error $? $LINENO' ERR

# =========================================
# 工具函数
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

# 日志记录函数（优化版）
log_message() {
    local level=$1
    local message=$2
    local log_file="${LOG_DIR}/install.log"
    
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$log_file" 2>/dev/null || true
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR] $message${RESET}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN] $message${RESET}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS] $message${RESET}"
            ;;
    esac
}

# 🚀 新增：通用下载函数（修复版 - 移除 || false）
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

# 🚀 新增：安全创建临时文件（使用 trap 自动清理）
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

# 🚀 新增：统一版本获取函数（修复版 - 增加验证）
get_latest_version() {
    local repo=$1  # 格式: owner/repo
    local service=$2  # snell/singbox/reality/hysteria2
    local default_version=$3
    
    local version=""
    
    case $service in
        snell)
            # 尝试多个来源
            local sources=(
                "https://kb.nssurge.com/surge-knowledge-base/release-notes/snell"
                "https://manual.nssurge.com/others/snell.html"
            )
            
            for source in "${sources[@]}"; do
                version=$(curl -s --connect-timeout 3 --max-time 5 "$source" 2>/dev/null | \
                    grep -oP 'snell-server-v?\K[0-9]+\.[0-9]+\.[0-9]+' | \
                    sort -V | tail -n 1 || true)
                
                if [ -n "$version" ]; then
                    # 验证版本号格式
                    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        # 验证下载链接是否存在（使用 amd64 作为测试）
                        local test_url="https://dl.nssurge.com/snell/snell-server-v${version}-linux-amd64.zip"
                        if curl -s --head --connect-timeout 2 --max-time 3 "$test_url" 2>/dev/null | grep -q "200 OK"; then
                            echo "$version"
                            return 0
                        fi
                    fi
                fi
            done
            
            # 如果所有方法都失败，使用默认版本
            log_message "WARN" "无法获取 Snell 最新版本，使用默认版本: $default_version"
            echo "$default_version"
            ;;
        *)
            # GitHub releases
            version=$(curl -s --connect-timeout 3 --max-time 5 \
                "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
                grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            
            if [ -z "$version" ]; then
                # 备用方法：从 releases 页面抓取
                version=$(curl -s --connect-timeout 3 --max-time 5 \
                    "https://github.com/${repo}/releases/latest" 2>/dev/null | \
                    grep -oP '/releases/tag/\K[^"]+' | head -n 1 || true)
            fi
            
            echo "${version:-$default_version}"
            ;;
    esac
}

# 配置文件管理函数
save_config() {
    local service=$1
    local key=$2
    local value=$3
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE" 2>/dev/null
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq ".${service}.${key} = \"${value}\"" "$CONFIG_FILE" > "$temp_file" 2>/dev/null || {
            jq ". + {\"${service}\": {\"${key}\": \"${value}\"}}" "$CONFIG_FILE" > "$temp_file"
        }
        mv "$temp_file" "$CONFIG_FILE" 2>/dev/null
    fi
}

# 读取配置
get_config() {
    local service=$1
    local key=$2
    
    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        jq -r ".${service}.${key} // empty" "$CONFIG_FILE" 2>/dev/null || true
    else
        local legacy_config="/etc/${service}-proxy-config.txt"
        if [ -f "$legacy_config" ]; then
            grep "^${key}=" "$legacy_config" 2>/dev/null | cut -d'=' -f2- || true
        fi
    fi
}

# 🚀 安全加载配置文件（避免执行任意代码）
safe_source_config() {
    local config_file=$1
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # 使用 while 循环安全读取键值对
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # 跳过注释和空行
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        # 去除首尾空格
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # 使用 declare -g 设置全局变量
        declare -g "$key=$value" 2>/dev/null || true
    done < "$config_file"
    
    return 0
}

# 保存完整服务配置（修复版 - 使用 jq 的 --arg 避免手动转义）
save_service_config() {
    local service=$1
    shift
    local -n config_array=$1
    
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE" 2>/dev/null
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        trap "rm -f '$temp_file'" RETURN
        
        # 使用 jq 的 --arg 避免手动转义
        local jq_args=()
        for key in "${!config_array[@]}"; do
            jq_args+=(--arg "$key" "${config_array[$key]}")
        done
        
        # 构建 jq 表达式
        local jq_expr=". + {\"${service}\": {"
        local first=true
        for key in "${!config_array[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                jq_expr+=","
            fi
            jq_expr+="\"${key}\": \$${key}"
        done
        jq_expr+="}}"
        
        if jq "${jq_args[@]}" "$jq_expr" "$CONFIG_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$CONFIG_FILE" 2>/dev/null
        else
            rm -f "$temp_file"
            log_message "ERROR" "保存配置失败"
        fi
    fi
}

# 🚀 优化：批量获取服务状态（修复版 - 避免并发写入问题）
declare -A SERVICE_STATUS_CACHE
declare -g STATUS_CACHE_TIME=0

get_all_service_status() {
    local current_time=$(date +%s)
    
    # 检查缓存是否有效
    if [ $((current_time - STATUS_CACHE_TIME)) -lt 5 ]; then
        return
    fi
    
    local services=("snell" "shadow-tls-snell" "sing-box" "sing-box-reality" "hysteria2")
    
    # 一次性获取所有已安装的服务
    local installed_services=$(systemctl list-unit-files 2>/dev/null | grep -E "^(snell|shadow-tls-snell|sing-box|sing-box-reality|hysteria2)\.service" | awk '{print $1}' | sed 's/\.service$//')
    
    # 使用临时文件避免并发写入问题
    local temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN
    
    for service in "${services[@]}"; do
        {
            if echo "$installed_services" | grep -q "^${service}$"; then
                local status=$(systemctl is-active "$service" 2>/dev/null || echo "未运行")
                echo "$status" > "$temp_dir/$service"
            else
                echo "未安装" > "$temp_dir/$service"
            fi
        } &
    done
    wait
    
    # 从临时文件读取结果到缓存
    for service in "${services[@]}"; do
        if [ -f "$temp_dir/$service" ]; then
            SERVICE_STATUS_CACHE[$service]=$(cat "$temp_dir/$service")
        fi
    done
    
    STATUS_CACHE_TIME=$current_time
}

# 获取单个服务状态
get_service_status() {
    local service=$1
    
    if [ -z "${SERVICE_STATUS_CACHE[$service]:-}" ]; then
        SERVICE_STATUS_CACHE[$service]=$(systemctl is-active "$service" 2>/dev/null || echo "未运行")
    fi
    
    echo "${SERVICE_STATUS_CACHE[$service]}"
}

# 清除状态缓存
clear_status_cache() {
    # 清空关联数组的所有键值
    for key in "${!SERVICE_STATUS_CACHE[@]}"; do
        unset SERVICE_STATUS_CACHE[$key]
    done
    STATUS_CACHE_TIME=0
}
# =========================================
# 输入验证函数
# =========================================

# 🚀 新增：输入验证函数
validate_port() {
    local port=$1
    local service_name=${2:-"服务"}
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}错误: 端口必须在 1-65535 之间${RESET}"
        return 1
    fi
    
    if check_port "$port"; then
        echo -e "${RED}错误: 端口 $port 已被占用${RESET}"
        echo -e "${YELLOW}占用进程信息:${RESET}"
        ss -tulpn 2>/dev/null | grep ":$port " || netstat -tulpn 2>/dev/null | grep ":$port "
        return 1
    fi
    
    # 检查是否为特权端口
    if [ "$port" -lt 1024 ] && [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}警告: 端口 $port 是特权端口，需要 root 权限${RESET}"
    fi
    
    return 0
}

validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}错误: 域名格式不正确${RESET}"
        return 1
    fi
    return 0
}

validate_ipv4() {
    local ip=$1
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done
    return 0
}

# 🚀 新增：IPv6 验证函数（修复版 - 支持压缩格式）
validate_ipv6() {
    local ip=$1
    # 匹配完整和压缩的 IPv6 地址
    if [[ "$ip" =~ ^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$ ]]; then
        return 0
    fi
    return 1
}

# 🚀 新增：邮箱验证函数（修复版 - 增强安全性）
validate_email() {
    local email=$1
    
    # 基本格式检查
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    
    # 提取本地部分和域名部分
    local local_part="${email%@*}"
    local domain_part="${email#*@}"
    
    # 检查本地部分
    if [[ "$local_part" =~ ^\.|\.$ ]]; then
        echo -e "${RED}邮箱本地部分不能以点开头或结尾${RESET}"
        return 1
    fi
    
    if [[ "$local_part" =~ \.\. ]]; then
        echo -e "${RED}邮箱本地部分不能包含连续的点${RESET}"
        return 1
    fi
    
    # 检查域名部分
    if [[ "$domain_part" =~ ^\.|\.$ ]]; then
        echo -e "${RED}邮箱域名部分格式不正确${RESET}"
        return 1
    fi
    
    if [[ "$domain_part" =~ \.\. ]]; then
        echo -e "${RED}邮箱域名部分不能包含连续的点${RESET}"
        return 1
    fi
    
    # 检查是否为示例域名
    if [[ "$domain_part" =~ (example\.(com|org|net)|test\.com|localhost)$ ]]; then
        echo -e "${RED}不能使用示例域名或本地域名${RESET}"
        return 1
    fi
    
    # 可选：DNS 验证（检查 MX 记录）
    if command -v dig &> /dev/null; then
        if ! dig +short MX "$domain_part" 2>/dev/null | grep -q .; then
            echo -e "${YELLOW}警告: 域名 $domain_part 没有 MX 记录，可能无法接收邮件${RESET}"
            read -p "是否继续？(y/n): " continue_anyway
            if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

# =========================================
# 备份功能
# =========================================

# 🚀 新增：备份功能
create_restore_point() {
    local service=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${service}_${timestamp}.tar.gz"
    
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    
    echo -e "${CYAN}创建备份...${RESET}"
    
    tar -czf "$backup_file" \
        "/etc/${service}"* \
        "/usr/local/bin/${service}"* \
        "/lib/systemd/system/${service}"* 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "$backup_file" > "$BACKUP_DIR/${service}_latest.txt"
        log_message "SUCCESS" "备份创建成功: $backup_file"
        echo -e "${GREEN}✓ 备份已创建${RESET}"
        
        find "$BACKUP_DIR" -name "${service}_*.tar.gz" -mtime +30 -delete 2>/dev/null
        
        return 0
    fi
    
    return 1
}

restore_from_backup() {
    local service=$1
    local backup_file
    
    if [ -f "$BACKUP_DIR/${service}_latest.txt" ]; then
        backup_file=$(cat "$BACKUP_DIR/${service}_latest.txt")
    else
        backup_file=$(ls -t "$BACKUP_DIR/${service}_"*.tar.gz 2>/dev/null | head -n 1)
    fi
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        echo -e "${RED}未找到备份文件${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}从备份恢复: $backup_file${RESET}"
    
    systemctl stop "$service" 2>/dev/null
    tar -xzf "$backup_file" -C / 2>/dev/null
    
    if [ $? -eq 0 ]; then
        systemctl daemon-reload
        systemctl start "$service"
        log_message "SUCCESS" "从备份恢复成功"
        echo -e "${GREEN}✓ 恢复成功${RESET}"
        return 0
    fi
    
    return 1
}

# =========================================
# 系统检查函数
# =========================================

# 检查是否为 root 用户（优化版）
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

# 检查服务是否已安装
check_service_installed() {
    local service=$1
    
    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        if jq -e ".${service}" "$CONFIG_FILE" &> /dev/null; then
            return 0
        fi
    fi
    
    if [ -f "/etc/${service}-proxy-config.txt" ]; then
        return 0
    fi
    
    return 1
}

check_snell_installed() {
    check_service_installed "snell"
}

check_singbox_installed() {
    check_service_installed "singbox"
}

check_reality_installed() {
    check_service_installed "reality"
}

check_hysteria2_installed() {
    check_service_installed "hysteria2"
}

# 🚀 优化：网络检测（修复版 - 改进 IPv6 检测）
get_server_ip() {
    log_message "INFO" "正在检测服务器 IP 地址..."
    
    echo -e "${CYAN}正在检测 IPv4...${RESET}"
    IPV4=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1 || true)
    
    if [ -z "$IPV4" ]; then
        IPV4=$(curl -4 -s --connect-timeout 2 --max-time 3 ifconfig.me 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || true)
    fi
    
    if [ -z "$IPV4" ]; then
        IPV4=$(curl -4 -s --connect-timeout 2 --max-time 3 ip.sb 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || true)
    fi
    
    echo -e "${CYAN}正在检测 IPv6...${RESET}"
    IPV6=$(ip -6 addr show 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1 || true)
    
    if [ -z "$IPV6" ]; then
        local ipv6_raw=$(curl -6 -s --connect-timeout 2 --max-time 3 ifconfig.me 2>/dev/null || true)
        if validate_ipv6 "$ipv6_raw"; then
            IPV6="$ipv6_raw"
        fi
    fi
    
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
                1)
                    SERVER_IP=$IPV4
                    IP_VERSION="IPv4"
                    break
                    ;;
                2)
                    SERVER_IP=$IPV6
                    IP_VERSION="IPv6"
                    break
                    ;;
                3)
                    read -p "请输入服务器 IP 地址: " SERVER_IP
                    if [ -n "$SERVER_IP" ]; then
                        if validate_ipv4 "$SERVER_IP"; then
                            IP_VERSION="IPv4"
                        elif validate_ipv6 "$SERVER_IP"; then
                            IP_VERSION="IPv6"
                        else
                            IP_VERSION="Unknown"
                        fi
                        break
                    else
                        echo -e "${RED}IP 地址不能为空${RESET}"
                    fi
                    ;;
                *)
                    echo -e "${RED}无效的选择，请重新输入${RESET}"
                    ;;
            esac
        done
    elif [ "$has_ipv4" = true ]; then
        SERVER_IP=$IPV4
        IP_VERSION="IPv4"
        echo -e "${GREEN}自动使用 IPv4: ${YELLOW}${SERVER_IP}${RESET}"
    elif [ "$has_ipv6" = true ]; then
        SERVER_IP=$IPV6
        IP_VERSION="IPv6"
        echo -e "${YELLOW}仅检测到 IPv6: ${SERVER_IP}${RESET}"
        echo ""
        read -p "是否使用此 IPv6 地址？(y/n，默认: y): " use_ipv6
        use_ipv6=${use_ipv6:-y}
        if [ "$use_ipv6" != "y" ] && [ "$use_ipv6" != "Y" ]; then
            read -p "请手动输入服务器 IP 地址: " SERVER_IP
            if validate_ipv4 "$SERVER_IP"; then
                IP_VERSION="IPv4"
            elif validate_ipv6 "$SERVER_IP"; then
                IP_VERSION="IPv6"
            else
                IP_VERSION="Unknown"
            fi
        fi
    else
        log_message "ERROR" "无法自动检测 IP 地址"
        echo -e "${RED}无法自动检测 IP 地址${RESET}"
        read -p "请手动输入服务器 IP 地址: " SERVER_IP
        if [ -z "$SERVER_IP" ]; then
            log_message "ERROR" "IP 地址不能为空"
            echo -e "${RED}IP 地址不能为空，退出安装${RESET}"
            exit 1
        fi
        if validate_ipv4 "$SERVER_IP"; then
            IP_VERSION="IPv4"
        elif validate_ipv6 "$SERVER_IP"; then
            IP_VERSION="IPv6"
        else
            IP_VERSION="Unknown"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}已选择 IP 地址: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "SUCCESS" "IP 地址选择完成: $SERVER_IP ($IP_VERSION)"
    sleep 1
}

# 日志轮转设置
setup_log_rotation() {
    log_message "INFO" "配置日志轮转..."
    
    cat > /etc/logrotate.d/proxy-manager <<EOF
${LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF
    
    log_message "SUCCESS" "日志轮转配置完成"
}

# 检查端口占用
check_port() {
    local port=$1
    
    if [ -z "$port" ] || [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    if ss -tulpn 2>/dev/null | grep -q ":$port " || netstat -tulpn 2>/dev/null | grep -q ":$port "; then
        return 0
    else
        return 1
    fi
}
# =========================================
# 依赖安装和系统检测
# =========================================

# 🚀 优化：检测包管理器
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

# 依赖检查优化（修复版 - 支持多种包管理器，修复 cron/cronie 问题）
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
    
    # 🚀 修复：根据不同系统选择正确的 cron 包名
    local cron_package=""
    case $pkg_manager in
        apt)
            cron_package="cron"
            ;;
        yum|dnf)
            cron_package="cronie"
            ;;
        pacman)
            cron_package="cronie"
            ;;
    esac
    
    # 检查 cron 是否已安装
    if ! command -v crontab &> /dev/null && [ -n "$cron_package" ]; then
        missing_packages+=("$cron_package")
    fi
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${CYAN}需要安装以下软件包: ${YELLOW}${missing_packages[*]}${RESET}"
        log_message "INFO" "使用 $pkg_manager 安装软件包: ${missing_packages[*]}"
        
        case $pkg_manager in
            apt)
                echo -e "${CYAN}正在更新软件包列表...${RESET}"
                if ! apt-get update -qq 2>&1 | tee -a "${LOG_DIR}/apt-update.log"; then
                    handle_error $? "apt-get update 失败" "${LOG_DIR}/apt-update.log"
                    return 1
                fi
                
                echo -e "${CYAN}正在安装依赖包...${RESET}"
                if ! apt-get install -y -qq "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/apt-install.log"; then
                    handle_error $? "软件包安装失败" "${LOG_DIR}/apt-install.log"
                    return 1
                fi
                ;;
            yum)
                echo -e "${CYAN}正在安装依赖包...${RESET}"
                if ! yum install -y -q "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/yum-install.log"; then
                    handle_error $? "软件包安装失败" "${LOG_DIR}/yum-install.log"
                    return 1
                fi
                ;;
            dnf)
                echo -e "${CYAN}正在安装依赖包...${RESET}"
                if ! dnf install -y -q "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/dnf-install.log"; then
                    handle_error $? "软件包安装失败" "${LOG_DIR}/dnf-install.log"
                    return 1
                fi
                ;;
            pacman)
                echo -e "${CYAN}正在安装依赖包...${RESET}"
                if ! pacman -Sy --noconfirm "${missing_packages[@]}" 2>&1 | tee -a "${LOG_DIR}/pacman-install.log"; then
                    handle_error $? "软件包安装失败" "${LOG_DIR}/pacman-install.log"
                    return 1
                fi
                ;;
            *)
                echo -e "${RED}不支持的包管理器，请手动安装依赖${RESET}"
                echo -e "${YELLOW}需要安装: ${missing_packages[*]}${RESET}"
                log_message "ERROR" "不支持的包管理器"
                return 1
                ;;
        esac
        
        log_message "SUCCESS" "依赖安装完成"
        echo -e "${GREEN}✓ 依赖安装完成${RESET}"
    else
        echo -e "${GREEN}✓ 所有依赖已安装${RESET}"
        log_message "INFO" "所有依赖已满足"
    fi
    
    # 确保 cron 服务运行
    if command -v crontab &> /dev/null; then
        if systemctl list-unit-files 2>/dev/null | grep -qE "^(cron|cronie)\.service"; then
            local cron_service=$(systemctl list-unit-files 2>/dev/null | grep -oE "^(cron|cronie)\.service" | head -n 1 | sed 's/\.service$//')
            if ! systemctl is-active --quiet "$cron_service" 2>/dev/null; then
                echo -e "${CYAN}正在启动 cron 服务...${RESET}"
                systemctl enable "$cron_service" 2>/dev/null
                systemctl start "$cron_service" 2>/dev/null
                echo -e "${GREEN}✓ cron 服务已启动${RESET}"
            fi
        fi
    fi
    
    setup_log_rotation
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
}

# =========================================
# 下载函数
# =========================================

# 🚀 优化：下载 Shadow-TLS（使用新的下载函数和 trap 清理）
download_shadow_tls() {
    if [ ! -f /usr/local/bin/shadow-tls ]; then
        log_message "INFO" "开始下载 Shadow-TLS..."
        echo -e "${GREEN}正在下载 Shadow-TLS...${RESET}"

        echo -e "${CYAN}正在获取最新的 Shadow-TLS 版本...${RESET}"
        SHADOW_TLS_VERSION=$(get_latest_version "ihciah/shadow-tls" "github" "$DEFAULT_SHADOW_TLS_VERSION")

        log_message "INFO" "Shadow-TLS 版本: $SHADOW_TLS_VERSION"
        echo -e "${GREEN}最新 Shadow-TLS 版本: ${SHADOW_TLS_VERSION}${RESET}"

        SHADOW_TLS_DOWNLOAD_URL="https://github.com/ihciah/shadow-tls/releases/download/${SHADOW_TLS_VERSION}/shadow-tls-${SHADOW_TLS_ARCH}"

        echo -e "${CYAN}正在下载 Shadow-TLS...${RESET}"
        log_message "INFO" "下载地址: $SHADOW_TLS_DOWNLOAD_URL"
        
        local temp_file=$(create_temp_file)
        trap "rm -f '$temp_file'" RETURN
        
        if ! download_file "$SHADOW_TLS_DOWNLOAD_URL" "$temp_file" 3 5; then
            handle_error 1 "下载 Shadow-TLS 失败" "${LOG_DIR}/shadow-tls-download.log"
            return 1
        fi

        mv "$temp_file" /usr/local/bin/shadow-tls
        chmod +x /usr/local/bin/shadow-tls
        
        log_message "SUCCESS" "Shadow-TLS 下载成功"
        echo -e "${GREEN}✓ Shadow-TLS 安装成功${RESET}"
    else
        echo -e "${GREEN}Shadow-TLS 已安装，跳过下载${RESET}"
        SHADOW_TLS_VERSION=$(shadow-tls --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' || echo "已安装")
        log_message "INFO" "Shadow-TLS 已存在: $SHADOW_TLS_VERSION"
    fi
}

# 下载 Sing-box (如果未安装)
download_singbox() {
    if [ ! -f /usr/local/bin/sing-box ]; then
        log_message "INFO" "开始下载 Sing-box..."
        echo -e "${GREEN}正在下载 Sing-box...${RESET}"
        
        detect_architecture
        
        echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
        SINGBOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '\"tag_name\":' | sed -E 's/.*\"([^\"]+)\".*/\1/')

        if [ -z "$SINGBOX_VERSION" ]; then
            log_message "WARN" "无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION"
            echo -e "${YELLOW}无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION${RESET}"
            SINGBOX_VERSION="$DEFAULT_SINGBOX_VERSION"
        fi

        log_message "INFO" "Sing-box 版本: $SINGBOX_VERSION"
        echo -e "${GREEN}最新 Sing-box 版本: ${SINGBOX_VERSION}${RESET}"

        SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"

        echo -e "${CYAN}正在从以下地址下载 Sing-box: ${SINGBOX_DOWNLOAD_URL}${RESET}"
        log_message "INFO" "下载地址: $SINGBOX_DOWNLOAD_URL"
        
        cd /tmp || { log_message "ERROR" "无法进入 /tmp 目录"; return 1; }
        if ! wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz 2>"${LOG_DIR}/singbox-download.log"; then
            handle_error $? "下载 Sing-box 失败" "${LOG_DIR}/singbox-download.log"
            return 1
        fi

        if ! tar -xzf sing-box.tar.gz 2>"${LOG_DIR}/singbox-extract.log"; then
            rm -rf /tmp/sing-box*
            handle_error $? "解压 Sing-box 失败" "${LOG_DIR}/singbox-extract.log"
            return 1
        fi
        
        SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
        if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
            mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
            chmod +x /usr/local/bin/sing-box
            log_message "SUCCESS" "Sing-box 安装成功"
        else
            rm -rf /tmp/sing-box*
            log_message "ERROR" "未找到 sing-box 二进制文件"
            echo -e "${RED}未找到 sing-box 二进制文件${RESET}"
            return 1
        fi
        
        rm -rf /tmp/sing-box*
        
        echo -e "${GREEN}Sing-box 安装成功${RESET}"
        log_message "SUCCESS" "Sing-box 安装成功"
    else
        echo -e "${GREEN}Sing-box 已安装，跳过下载${RESET}"
        SINGBOX_VERSION=$(/usr/local/bin/sing-box version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "已安装")
        log_message "INFO" "Sing-box 已存在: $SINGBOX_VERSION"
    fi
}

# =========================================
# Reality 和 Hysteria2 辅助函数
# =========================================

# 生成 Reality 密钥对（修复版 - 增强错误处理和验证）
generate_reality_keypair() {
    log_message "INFO" "生成 Reality 密钥对..."
    echo -e "${CYAN}正在生成 Reality 密钥对...${RESET}"
    
    # 确保 sing-box 已安装
    if ! download_singbox; then
        log_message "ERROR" "Sing-box 安装失败"
        return 1
    fi
    
    # 验证 sing-box 版本是否支持 reality
    local singbox_version=$(/usr/local/bin/sing-box version 2>/dev/null | grep -oP 'version \K[0-9.]+' || echo "0.0.0")
    local min_version="1.3.0"
    
    if ! printf '%s\n%s\n' "$min_version" "$singbox_version" | sort -V -C; then
        log_message "ERROR" "Sing-box 版本过低，需要 >= $min_version"
        echo -e "${RED}Sing-box 版本过低（当前: $singbox_version，需要: >= $min_version）${RESET}"
        return 1
    fi
    
    # 生成密钥对
    local keypair_output
    local temp_log=$(mktemp)
    trap "rm -f '$temp_log'" RETURN
    
    if ! keypair_output=$(/usr/local/bin/sing-box generate reality-keypair 2>"$temp_log"); then
        log_message "ERROR" "生成密钥对失败"
        cat "$temp_log" >> "${LOG_DIR}/reality-keygen.log"
        handle_error 1 "生成密钥对失败" "${LOG_DIR}/reality-keygen.log"
        return 1
    fi
    
    # 解析密钥（更健壮的方法）
    REALITY_PRIVATE_KEY=$(echo "$keypair_output" | grep -i "PrivateKey" | sed -E 's/.*PrivateKey[: ]+([A-Za-z0-9_-]+).*/\1/' | tr -d '[:space:]')
    REALITY_PUBLIC_KEY=$(echo "$keypair_output" | grep -i "PublicKey" | sed -E 's/.*PublicKey[: ]+([A-Za-z0-9_-]+).*/\1/' | tr -d '[:space:]')
    
    # 验证密钥格式
    if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
        log_message "ERROR" "无法解析密钥对"
        echo -e "${RED}无法解析密钥对${RESET}"
        echo -e "${YELLOW}原始输出:${RESET}"
        echo "$keypair_output"
        return 1
    fi
    
    # 验证密钥长度（Reality 使用 X25519，密钥应为 base64 编码，约 43-44 字符）
    local private_len=${#REALITY_PRIVATE_KEY}
    local public_len=${#REALITY_PUBLIC_KEY}
    
    if [ "$private_len" -lt 40 ] || [ "$private_len" -gt 50 ] || \
       [ "$public_len" -lt 40 ] || [ "$public_len" -gt 50 ]; then
        log_message "ERROR" "密钥长度异常（Private: $private_len, Public: $public_len）"
        echo -e "${RED}密钥长度异常，可能生成失败${RESET}"
        return 1
    fi
    
    log_message "SUCCESS" "密钥对生成成功（Private: ${private_len} chars, Public: ${public_len} chars）"
    echo -e "${GREEN}✓ 密钥对生成成功${RESET}"
    echo -e "${CYAN}  Private Key: ${YELLOW}${REALITY_PRIVATE_KEY:0:20}...${RESET}"
    echo -e "${CYAN}  Public Key:  ${YELLOW}${REALITY_PUBLIC_KEY:0:20}...${RESET}"
    
    return 0
}

# 生成短 ID
generate_short_id() {
    openssl rand -hex 8
}

# =========================================
# acme.sh 和证书管理
# =========================================

# 安装 acme.sh（修复版 - 要求输入真实邮箱，使用改进的验证函数）
install_acme() {
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        log_message "INFO" "开始安装 acme.sh..."
        echo -e "${CYAN}正在安装 acme.sh...${RESET}"
        echo ""
        echo -e "${YELLOW}=========================================${RESET}"
        echo -e "${YELLOW}   配置 Let's Encrypt 账户${RESET}"
        echo -e "${YELLOW}=========================================${RESET}"
        echo ""
        echo -e "${CYAN}Let's Encrypt 需要一个有效的邮箱地址用于：${RESET}"
        echo -e "  - 证书到期提醒"
        echo -e "  - 重要的账户通知"
        echo -e "  - 紧急安全公告"
        echo ""
        echo -e "${YELLOW}请输入您的邮箱地址:${RESET}"
        
        while true; do
            read -p "邮箱: " ACME_EMAIL
            
            if [ -z "$ACME_EMAIL" ]; then
                echo -e "${RED}邮箱不能为空，请重新输入${RESET}"
                continue
            fi
            
            if validate_email "$ACME_EMAIL"; then
                echo ""
                echo -e "${CYAN}您输入的邮箱是: ${YELLOW}${ACME_EMAIL}${RESET}"
                read -p "确认无误？(y/n): " confirm
                if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                    break
                fi
                echo ""
            fi
        done
        
        echo ""
        echo -e "${CYAN}正在安装 acme.sh...${RESET}"
        log_message "INFO" "使用邮箱安装 acme.sh: $ACME_EMAIL"
        
        # 使用正确的参数格式安装 acme.sh
        if ! curl https://get.acme.sh | sh -s email="$ACME_EMAIL" 2>"${LOG_DIR}/acme-install.log"; then
            handle_error $? "acme.sh 安装失败" "${LOG_DIR}/acme-install.log"
            return 1
        fi
        
        # 等待安装完成
        sleep 2
        
        # 验证 acme.sh 是否安装成功
        if [ ! -f ~/.acme.sh/acme.sh ]; then
            log_message "ERROR" "acme.sh 安装失败：文件不存在"
            echo -e "${RED}acme.sh 安装失败，请检查网络连接或手动安装${RESET}"
            echo -e "${YELLOW}手动安装命令: curl https://get.acme.sh | sh -s email=${ACME_EMAIL}${RESET}"
            return 1
        fi
        
        # 重新加载 shell 环境（确保 acme.sh 可用）
        source ~/.acme.sh/acme.sh.env 2>/dev/null || true
        
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        
        log_message "SUCCESS" "acme.sh 安装成功，邮箱: $ACME_EMAIL"
        echo -e "${GREEN}✓ acme.sh 安装成功${RESET}"
        echo -e "${GREEN}✓ 邮箱: ${ACME_EMAIL}${RESET}"
        echo ""
    else
        echo -e "${GREEN}acme.sh 已安装${RESET}"
        log_message "INFO" "acme.sh 已存在"
        
        if [ -f ~/.acme.sh/ca/acme-v02.api.letsencrypt.org/directory/account.json ]; then
            REGISTERED_EMAIL=$(grep -oP '"contact":\["mailto:\K[^"]+' ~/.acme.sh/ca/acme-v02.api.letsencrypt.org/directory/account.json 2>/dev/null || echo "未知")
            echo -e "${GREEN}已注册邮箱: ${YELLOW}${REGISTERED_EMAIL}${RESET}"
            log_message "INFO" "已注册邮箱: $REGISTERED_EMAIL"
        fi
    fi
}

# 申请 Let's Encrypt 证书（修复版 - 改进端口冲突处理和错误提示）
issue_letsencrypt_cert() {
    local domain=$1
    local stopped_services=()
    
    log_message "INFO" "开始为域名 $domain 申请证书..."
    echo -e "${CYAN}正在为域名 ${YELLOW}${domain}${CYAN} 申请 Let's Encrypt 证书...${RESET}"
    
    # 检查 80 端口
    if check_port 80; then
        log_message "WARN" "80 端口已被占用"
        echo -e "${YELLOW}警告: 80 端口已被占用${RESET}"
        echo ""
        echo -e "${CYAN}选择处理方式:${RESET}"
        echo -e "${YELLOW}1.${RESET} 自动停止占用服务（推荐）"
        echo -e "${YELLOW}2.${RESET} 使用 DNS 验证（需要手动添加 DNS 记录）"
        echo -e "${YELLOW}3.${RESET} 取消申请"
        echo ""
        
        read -p "请选择 [1-3]: " port_choice
        
        case $port_choice in
            1)
                echo -e "${CYAN}正在尝试停止可能占用 80 端口的服务...${RESET}"
                
                for service in nginx apache2 httpd lighttpd caddy hysteria2; do
                    if systemctl is-active --quiet $service 2>/dev/null; then
                        log_message "INFO" "停止服务: $service"
                        echo -e "${YELLOW}停止服务: $service${RESET}"
                        if systemctl stop $service 2>/dev/null; then
                            stopped_services+=("$service")
                        fi
                    fi
                done
                
                sleep 2
                
                if check_port 80; then
                    log_message "ERROR" "80 端口仍被占用"
                    echo -e "${RED}80 端口仍被占用，无法申请证书${RESET}"
                    echo -e "${YELLOW}占用进程信息：${RESET}"
                    ss -tulpn 2>/dev/null | grep ":80 " || netstat -tulpn 2>/dev/null | grep ":80 "
                    
                    # 恢复已停止的服务
                    for service in "${stopped_services[@]}"; do
                        systemctl start "$service" 2>/dev/null
                    done
                    
                    return 1
                fi
                ;;
            2)
                echo -e "${CYAN}使用 DNS 验证模式...${RESET}"
                echo -e "${YELLOW}请按照提示添加 DNS TXT 记录${RESET}"
                
                if ! ~/.acme.sh/acme.sh --issue -d "$domain" --dns --keylength ec-256 --force 2>"${LOG_DIR}/acme-issue-${domain}.log"; then
                    log_message "ERROR" "DNS 验证失败"
                    echo -e "${RED}证书申请失败${RESET}"
                    return 1
                fi
                
                log_message "SUCCESS" "证书申请成功: $domain"
                echo -e "${GREEN}✓ 证书申请成功${RESET}"
                return 0
                ;;
            3)
                echo -e "${CYAN}取消证书申请${RESET}"
                return 1
                ;;
            *)
                echo -e "${RED}无效的选择${RESET}"
                return 1
                ;;
        esac
    fi
    
    # 使用 standalone 模式申请证书
    log_message "INFO" "使用 standalone 模式申请证书..."
    if ! ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --keylength ec-256 --force 2>"${LOG_DIR}/acme-issue-${domain}.log"; then
        log_message "ERROR" "证书申请失败"
        echo -e "${RED}证书申请失败${RESET}"
        echo -e "${YELLOW}请确保:${RESET}"
        echo -e "  1. 域名 ${domain} 已正确解析到此服务器 (${SERVER_IP})"
        echo -e "  2. 防火墙已开放 80 端口"
        echo -e "  3. 没有其他服务占用 80 端口"
        echo ""
        echo -e "${CYAN}调试命令:${RESET}"
        echo -e "  检查域名解析: ${YELLOW}nslookup ${domain}${RESET}"
        echo -e "  检查端口占用: ${YELLOW}netstat -tulpn | grep :80${RESET}"
        echo -e "  查看详细日志: ${YELLOW}cat ${LOG_DIR}/acme-issue-${domain}.log${RESET}"
        
        # 恢复已停止的服务
        for service in "${stopped_services[@]}"; do
            systemctl start "$service" 2>/dev/null
        done
        
        return 1
    fi
    
    # 恢复已停止的服务
    if [ ${#stopped_services[@]} -gt 0 ]; then
        echo ""
        echo -e "${CYAN}正在恢复已停止的服务...${RESET}"
        for service in "${stopped_services[@]}"; do
            echo -e "${YELLOW}启动服务: $service${RESET}"
            systemctl start "$service" 2>/dev/null
        done
    fi
    
    log_message "SUCCESS" "证书申请成功: $domain"
    echo -e "${GREEN}✓ 证书申请成功${RESET}"
    return 0
}

# 安装证书到 Hysteria2（改进版 - 增加错误处理）
install_cert_to_hysteria2() {
    local domain=$1
    
    log_message "INFO" "开始安装证书到 Hysteria2..."
    echo -e "${CYAN}正在安装证书到 Hysteria2...${RESET}"
    
    mkdir -p /etc/hysteria2
    
    if ! id -u hysteria2 > /dev/null 2>&1; then
        log_message "INFO" "创建 hysteria2 用户..."
        echo -e "${YELLOW}hysteria2 用户不存在，正在创建...${RESET}"
        useradd -r -s /usr/sbin/nologin hysteria2
    fi
    
    log_message "INFO" "安装证书文件..."
    local default_group=$(get_default_group)
    if ! ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
        --key-file /etc/hysteria2/server.key \
        --fullchain-file /etc/hysteria2/server.crt \
        --reloadcmd "chown hysteria2:${default_group} /etc/hysteria2/server.key /etc/hysteria2/server.crt && chmod 600 /etc/hysteria2/server.key && chmod 644 /etc/hysteria2/server.crt && systemctl restart hysteria2 2>/dev/null || true" \
        2>"${LOG_DIR}/acme-install-cert-${domain}.log"; then
        handle_error $? "证书安装失败" "${LOG_DIR}/acme-install-cert-${domain}.log"
        return 1
    fi
    
    chown hysteria2:$(get_default_group) /etc/hysteria2/server.key /etc/hysteria2/server.crt 2>/dev/null
    chmod 600 /etc/hysteria2/server.key
    chmod 644 /etc/hysteria2/server.crt
    
    if [ ! -f /etc/hysteria2/server.key ] || [ ! -f /etc/hysteria2/server.crt ]; then
        log_message "ERROR" "证书文件不存在"
        echo -e "${RED}证书文件不存在${RESET}"
        return 1
    fi
    
    log_message "SUCCESS" "证书安装成功"
    echo -e "${GREEN}✓ 证书安装成功${RESET}"
    return 0
}
# =========================================
# 配置文件生成函数（使用 jq 确保 JSON 有效）
# =========================================

# 创建 Sing-box 配置（使用 jq 生成，确保 JSON 有效）
create_singbox_config() {
    local config_file=$1
    local ss_port=$2
    local ss_method=$3
    local ss_password=$4
    local shadow_tls_port=$5
    local shadow_tls_password=$6
    local tls_domain=$7
    
    # 使用 jq 生成配置，自动处理转义
    jq -n \
        --arg ss_port "$ss_port" \
        --arg ss_method "$ss_method" \
        --arg ss_password "$ss_password" \
        --arg shadow_tls_port "$shadow_tls_port" \
        --arg shadow_tls_password "$shadow_tls_password" \
        --arg tls_domain "$tls_domain" \
        '{
            "log": {
                "level": "info",
                "timestamp": true
            },
            "inbounds": [
                {
                    "type": "shadowsocks",
                    "tag": "ss-in",
                    "listen": "127.0.0.1",
                    "listen_port": ($ss_port | tonumber),
                    "method": $ss_method,
                    "password": $ss_password,
                    "tcp_fast_open": true,
                    "udp_fragment": true
                },
                {
                    "type": "shadowtls",
                    "tag": "st-in",
                    "listen": "::",
                    "listen_port": ($shadow_tls_port | tonumber),
                    "version": 3,
                    "users": [
                        {
                            "name": "user1",
                            "password": $shadow_tls_password
                        }
                    ],
                    "handshake": {
                        "server": $tls_domain,
                        "server_port": 443
                    },
                    "strict_mode": true,
                    "detour": "ss-in"
                }
            ],
            "outbounds": [
                {
                    "type": "direct",
                    "tag": "direct"
                }
            ],
            "route": {
                "rules": [],
                "final": "direct"
            }
        }' > "$config_file"
    
    # 验证 JSON 格式
    if ! jq empty "$config_file" 2>/dev/null; then
        log_message "ERROR" "生成的配置文件 JSON 格式无效"
        return 1
    fi
    
    # 使用 sing-box 验证配置
    if command -v sing-box &> /dev/null; then
        if ! /usr/local/bin/sing-box check -c "$config_file" 2>&1 | tee -a "${LOG_DIR}/singbox-config-check.log"; then
            log_message "ERROR" "Sing-box 配置验证失败"
            return 1
        fi
    fi
    
    return 0
}

# 创建 Hysteria2 配置（统一函数，修复版 - 正确处理布尔值）
create_hysteria2_config() {
    local config_file=$1
    local port=$2
    local password=$3
    local domain=$4
    local enable_obfs=$5
    local obfs_password=$6
    
    # 构建基础配置
    local config=$(jq -n \
        --arg port "$port" \
        --arg password "$password" \
        --arg domain "$domain" \
        '{
            "log": {
                "level": "info",
                "timestamp": true
            },
            "inbounds": [
                {
                    "type": "hysteria2",
                    "tag": "hy2-in",
                    "listen": "::",
                    "listen_port": ($port | tonumber),
                    "users": [
                        {
                            "name": "user1",
                            "password": $password
                        }
                    ],
                    "tls": {
                        "enabled": true,
                        "server_name": $domain,
                        "key_path": "/etc/hysteria2/server.key",
                        "certificate_path": "/etc/hysteria2/server.crt"
                    }
                }
            ],
            "outbounds": [
                {
                    "type": "direct",
                    "tag": "direct"
                }
            ]
        }')
    
    # 如果启用混淆，添加混淆配置
    if [ "$enable_obfs" = "true" ] || [ "$enable_obfs" = true ]; then
        config=$(echo "$config" | jq \
            --arg obfs_password "$obfs_password" \
            '.inbounds[0].obfs = {
                "type": "salamander",
                "password": $obfs_password
            }')
    fi
    
    # 写入配置文件
    echo "$config" > "$config_file"
    
    # 验证 JSON 格式
    if ! jq empty "$config_file" 2>/dev/null; then
        log_message "ERROR" "生成的配置文件 JSON 格式无效"
        return 1
    fi
    
    # 使用 sing-box 验证配置
    if command -v sing-box &> /dev/null; then
        if ! /usr/local/bin/sing-box check -c "$config_file" 2>&1 | tee -a "${LOG_DIR}/hysteria2-config-check.log"; then
            log_message "ERROR" "Hysteria2 配置验证失败"
            return 1
        fi
    fi
    
    return 0
}

# =========================================
# 健康检查脚本
# =========================================

# 创建健康检查脚本（修复版 - 改进日志轮转逻辑）
create_healthcheck_script() {
    log_message "INFO" "创建健康检查脚本..."
    echo -e "${CYAN}正在创建健康检查脚本...${RESET}"
    
    cat <<'EOF' > /usr/local/bin/proxy-healthcheck.sh
#!/bin/bash

LOG_FILE="/var/log/proxy-manager/healthcheck.log"
MAX_LOG_SIZE=10485760  # 10MB
MAX_OLD_LOGS=5  # 保留最多 5 个旧日志

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 日志轮转函数
rotate_log() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi
    
    # 跨平台获取文件大小
    local file_size=0
    if command -v stat &> /dev/null; then
        # Linux
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    elif [ -f "$LOG_FILE" ]; then
        # 备用方法：使用 wc
        file_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    if [ "$file_size" -gt $MAX_LOG_SIZE ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local old_log="${LOG_FILE}.${timestamp}"
        
        # 移动并压缩
        if mv "$LOG_FILE" "$old_log" 2>/dev/null; then
            if gzip "$old_log" 2>/dev/null; then
                log "日志已轮转: ${old_log}.gz"
            else
                # 如果压缩失败，至少保留未压缩的文件
                log "日志已轮转（未压缩）: $old_log"
            fi
        fi
        
        # 清理旧日志（保留最新的 N 个）
        local log_dir=$(dirname "$LOG_FILE")
        local log_name=$(basename "$LOG_FILE")
        ls -t "${log_dir}/${log_name}".*.gz 2>/dev/null | tail -n +$((MAX_OLD_LOGS + 1)) | xargs -r rm -f
    fi
}

# 执行日志轮转
rotate_log

# 检查服务函数
check_service() {
    local service=$1
    local port=$2
    local listen_addr=$3
    
    # 检查服务是否已安装
    if ! systemctl list-unit-files 2>/dev/null | grep -q "^${service}.service"; then
        return
    fi
    
    # 检查服务是否运行
    if ! systemctl is-active --quiet $service; then
        log "[$service] 服务已停止，正在重启..."
        if systemctl restart $service 2>&1 | head -n 5 >> "$LOG_FILE"; then
            sleep 3
            if systemctl is-active --quiet $service; then
                log "[$service] 服务重启成功"
            else
                log "[$service] 服务重启失败"
                # 记录失败原因
                systemctl status $service --no-pager -l 2>&1 | tail -n 10 >> "$LOG_FILE"
            fi
        else
            log "[$service] 服务重启命令执行失败"
        fi
    fi
    
    # 检查端口监听（如果指定）
    if [ -n "$port" ] && [ -n "$listen_addr" ]; then
        local port_check=false
        if command -v ss &> /dev/null; then
            ss -tulpn 2>/dev/null | grep -q "${listen_addr}:${port}" && port_check=true
        elif command -v netstat &> /dev/null; then
            netstat -tulpn 2>/dev/null | grep -q "${listen_addr}:${port}" && port_check=true
        fi
        
        if ! $port_check; then
            log "[$service] 端口 ${listen_addr}:${port} 未监听，重启服务..."
            systemctl restart $service 2>&1 | head -n 5 >> "$LOG_FILE"
        fi
    fi
}

# 检查各个服务
check_service "snell" "30622" "127.0.0.1"

if systemctl list-unit-files 2>/dev/null | grep -q "shadow-tls-snell.service"; then
    SHADOW_PORT=$(grep "ExecStart" /etc/systemd/system/shadow-tls-snell.service 2>/dev/null | grep -oP '::0:\K\d+' | head -1)
    check_service "shadow-tls-snell" "$SHADOW_PORT" "0.0.0.0"
fi

check_service "sing-box" "" ""
check_service "sing-box-reality" "" ""
check_service "hysteria2" "" ""

# 清理超过 7 天的旧日志
find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE").*.gz" -mtime +7 -delete 2>/dev/null

log "健康检查完成"
EOF

    chmod +x /usr/local/bin/proxy-healthcheck.sh
    
    # 添加 cron 任务
    if ! crontab -l 2>/dev/null | grep -q "proxy-healthcheck.sh"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/proxy-healthcheck.sh") | crontab -
        log_message "SUCCESS" "已添加健康检查 cron 任务"
        echo -e "${GREEN}✓ 已添加健康检查 cron 任务 (每5分钟执行一次)${RESET}"
    else
        log_message "INFO" "健康检查 cron 任务已存在"
        echo -e "${YELLOW}健康检查 cron 任务已存在${RESET}"
    fi
}

# =========================================
# 菜单和选择函数
# =========================================

# 选择 TLS 域名
select_tls_domain() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择 Shadow-TLS SNI 伪装域名${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${GREEN}国际知名域名:${RESET}"
    echo -e "${YELLOW}1.${RESET}  gateway.icloud.com ${GREEN}(推荐 - Apple iCloud)${RESET}"
    echo -e "${YELLOW}2.${RESET}  www.microsoft.com ${GREEN}(推荐 - 微软)${RESET}"
    echo -e "${YELLOW}3.${RESET}  www.apple.com ${GREEN}(推荐 - 苹果官网)${RESET}"
    echo -e "${YELLOW}4.${RESET}  itunes.apple.com ${GREEN}(推荐 - Apple iTunes)${RESET}"
    echo ""
    echo -e "${GREEN}国内常用域名:${RESET}"
    echo -e "${YELLOW}5.${RESET}  mp.weixin.qq.com (微信公众号)"
    echo -e "${YELLOW}6.${RESET}  www.qq.com (腾讯)"
    echo -e "${YELLOW}7.${RESET}  www.taobao.com (淘宝)"
    echo -e "${YELLOW}8.${RESET}  www.jd.com (京东)"
    echo -e "${YELLOW}9.${RESET}  www.baidu.com (百度)"
    echo -e "${YELLOW}10.${RESET} www.163.com (网易)"
    echo ""
    echo -e "${GREEN}CDN 与云服务:${RESET}"
    echo -e "${YELLOW}11.${RESET} cloudflare.com ${GREEN}(推荐 - Cloudflare)${RESET}"
    echo -e "${YELLOW}12.${RESET} www.cloudflare.com ${GREEN}(推荐 - Cloudflare)${RESET}"
    echo -e "${YELLOW}13.${RESET} aws.amazon.com ${GREEN}(推荐 - AWS)${RESET}"
    echo -e "${YELLOW}14.${RESET} azure.microsoft.com ${GREEN}(推荐 - Azure)${RESET}"
    echo -e "${YELLOW}15.${RESET} cloud.google.com ${GREEN}(推荐 - Google Cloud)${RESET}"
    echo ""
    echo -e "${YELLOW}0.${RESET}  自定义域名 (手动输入)"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    
    while true; do
        read -p "请选择域名 [0-15]: " domain_choice
        
        case $domain_choice in
            1) TLS_DOMAIN="gateway.icloud.com"; break;;
            2) TLS_DOMAIN="www.microsoft.com"; break;;
            3) TLS_DOMAIN="www.apple.com"; break;;
            4) TLS_DOMAIN="itunes.apple.com"; break;;
            5) TLS_DOMAIN="mp.weixin.qq.com"; break;;
            6) TLS_DOMAIN="www.qq.com"; break;;
            7) TLS_DOMAIN="www.taobao.com"; break;;
            8) TLS_DOMAIN="www.jd.com"; break;;
            9) TLS_DOMAIN="www.baidu.com"; break;;
            10) TLS_DOMAIN="www.163.com"; break;;
            11) TLS_DOMAIN="cloudflare.com"; break;;
            12) TLS_DOMAIN="www.cloudflare.com"; break;;
            13) TLS_DOMAIN="aws.amazon.com"; break;;
            14) TLS_DOMAIN="azure.microsoft.com"; break;;
            15) TLS_DOMAIN="cloud.google.com"; break;;
            0)
                read -p "请输入自定义域名 (例如: www.example.com): " TLS_DOMAIN
                if [ -n "$TLS_DOMAIN" ]; then
                    break
                else
                    echo -e "${RED}域名不能为空${RESET}"
                fi
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done
    
    log_message "INFO" "已选择 TLS 域名: $TLS_DOMAIN"
    echo -e "${GREEN}已选择域名: ${TLS_DOMAIN}${RESET}"
}

# 选择 Reality 目标网站
select_reality_dest() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择 Reality 目标网站${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${BLUE}提示: Reality 会伪装成访问这些网站${RESET}"
    echo ""
    echo -e "${GREEN}推荐网站 (支持 TLS 1.3 和 HTTP/2):${RESET}"
    echo -e "${YELLOW}1.${RESET}  www.microsoft.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}2.${RESET}  www.apple.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}3.${RESET}  www.cloudflare.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}4.${RESET}  www.amazon.com"
    echo -e "${YELLOW}5.${RESET}  www.google.com"
    echo -e "${YELLOW}6.${RESET}  www.github.com"
    echo -e "${YELLOW}7.${RESET}  www.yahoo.com"
    echo -e "${YELLOW}8.${RESET}  www.nginx.com"
    echo ""
    echo -e "${YELLOW}0.${RESET}  自定义域名 (手动输入)"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    
    while true; do
        read -p "请选择目标网站 [0-8]: " dest_choice
        
        case $dest_choice in
            1) REALITY_DEST="www.microsoft.com"; break;;
            2) REALITY_DEST="www.apple.com"; break;;
            3) REALITY_DEST="www.cloudflare.com"; break;;
            4) REALITY_DEST="www.amazon.com"; break;;
            5) REALITY_DEST="www.google.com"; break;;
            6) REALITY_DEST="www.github.com"; break;;
            7) REALITY_DEST="www.yahoo.com"; break;;
            8) REALITY_DEST="www.nginx.com"; break;;
            0)
                read -p "请输入自定义域名 (例如: www.example.com): " REALITY_DEST
                if [ -n "$REALITY_DEST" ]; then
                    break
                else
                    echo -e "${RED}域名不能为空${RESET}"
                fi
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done
    
    log_message "INFO" "已选择 Reality 目标网站: $REALITY_DEST"
    echo -e "${GREEN}已选择目标网站: ${REALITY_DEST}${RESET}"
}

# 选择 Shadowsocks 加密方法
select_ss_method() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择 Shadowsocks 加密方式${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${GREEN}SS-2022 加密方式 (推荐):${RESET}"
    echo -e "${YELLOW}1.${RESET} 2022-blake3-aes-256-gcm ${GREEN}(推荐 - 最强安全性)${RESET}"
    echo -e "${YELLOW}2.${RESET} 2022-blake3-aes-128-gcm ${GREEN}(推荐 - 平衡性能)${RESET}"
    echo -e "${YELLOW}3.${RESET} 2022-blake3-chacha20-poly1305 (ChaCha20)"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${BLUE}提示: SS-2022 加密方式提供更好的安全性和性能${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    while true; do
        read -p "请选择加密方式 [1-3] (默认: 1): " method_choice
        method_choice=${method_choice:-1}
        
        case $method_choice in
            1)
                SS_METHOD="2022-blake3-aes-256-gcm"
                SS_PASSWORD=$(openssl rand -base64 32)
                break
                ;;
            2)
                SS_METHOD="2022-blake3-aes-128-gcm"
                SS_PASSWORD=$(openssl rand -base64 16)
                break
                ;;
            3)
                SS_METHOD="2022-blake3-chacha20-poly1305"
                SS_PASSWORD=$(openssl rand -base64 32)
                break
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done
    
    log_message "INFO" "已选择加密方式: $SS_METHOD"
    echo -e "${GREEN}已选择加密方式: ${SS_METHOD}${RESET}"
}

# =========================================
# 显示菜单
# =========================================

# 🚀 优化：显示主菜单（延迟加载状态，加快启动速度）
show_menu() {
    clear
    
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${GREEN}   代理 + Shadow-TLS 一键安装脚本${RESET}"
    echo -e "${GREEN}   v2.3 - 完整修复版${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    echo -e "${CYAN}已安装的服务:${RESET}"
    
    local has_service=false
    
    if check_snell_installed; then
        echo -e "${GREEN}  ✓${RESET} Snell + Shadow-TLS"
        has_service=true
    fi
    
    if check_singbox_installed; then
        echo -e "${GREEN}  ✓${RESET} Sing-box (SS-2022 + Shadow-TLS)"
        has_service=true
    fi
    
    if check_reality_installed; then
        echo -e "${GREEN}  ✓${RESET} VLESS Reality"
        has_service=true
    fi
    
    if check_hysteria2_installed; then
        CERT_TYPE=$(get_config "hysteria2" "CERT_TYPE")
        if [ "$CERT_TYPE" == "letsencrypt" ]; then
            echo -e "${GREEN}  ✓${RESET} Hysteria2 ${GREEN}[Let's Encrypt]${RESET}"
        else
            echo -e "${GREEN}  ✓${RESET} Hysteria2"
        fi
        has_service=true
    fi
    
    if [ "$has_service" = false ]; then
        echo -e "${YELLOW}  (无已安装服务)${RESET}"
    fi
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${YELLOW}安装选项:${RESET}"
    echo -e "${YELLOW}1.${RESET}  安装 Snell + Shadow-TLS"
    echo -e "${YELLOW}2.${RESET}  安装 Sing-box (SS-2022 + Shadow-TLS)"
    echo -e "${YELLOW}3.${RESET}  安装 VLESS Reality"
    echo -e "${YELLOW}4.${RESET}  安装 Hysteria2 ${GREEN}(Let's Encrypt 证书)${RESET}"
    echo ""
    echo -e "${YELLOW}更新选项:${RESET}"
    echo -e "${YELLOW}5.${RESET}  更新 Snell 到最新版本"
    echo -e "${YELLOW}6.${RESET}  更新 Sing-box 到最新版本"
    echo -e "${YELLOW}7.${RESET}  更新 Reality 到最新版本"
    echo -e "${YELLOW}8.${RESET}  更新 Hysteria2 到最新版本"
    echo -e "${YELLOW}9.${RESET}  更新所有服务"
    echo ""
    echo -e "${YELLOW}管理选项:${RESET}"
    echo -e "${YELLOW}10.${RESET} 查看服务状态 ${CYAN}(实时)${RESET}"
    echo -e "${YELLOW}11.${RESET} 卸载 Snell + Shadow-TLS"
    echo -e "${YELLOW}12.${RESET} 卸载 Sing-box"
    echo -e "${YELLOW}13.${RESET} 卸载 VLESS Reality"
    echo -e "${YELLOW}14.${RESET} 卸载 Hysteria2"
    echo -e "${YELLOW}15.${RESET} 卸载所有服务"
    echo ""
    echo -e "${YELLOW}查看选项:${RESET}"
    echo -e "${YELLOW}16.${RESET} 查看 Snell 配置"
    echo -e "${YELLOW}17.${RESET} 查看 Sing-box 配置"
    echo -e "${YELLOW}18.${RESET} 查看 VLESS Reality 配置"
    echo -e "${YELLOW}19.${RESET} 查看 Hysteria2 配置"
    echo -e "${YELLOW}20.${RESET} 查看所有配置"
    echo -e "${YELLOW}21.${RESET} 查看服务日志"
    echo ""
    echo -e "${YELLOW}证书管理:${RESET}"
    echo -e "${YELLOW}22.${RESET} 手动续签 Hysteria2 证书"
    echo -e "${YELLOW}23.${RESET} 查看 Hysteria2 证书状态"
    echo ""
    echo -e "${YELLOW}0.${RESET}  退出脚本"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
}

# 🆕 新增：查看服务实时状态（单独菜单项）
view_service_status() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   服务实时状态${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    clear_status_cache
    get_all_service_status
    
    local has_service=false
    
    if check_snell_installed; then
        has_service=true
        SNELL_STATUS="${SERVICE_STATUS_CACHE[snell]:-未运行}"
        SNELL_SHADOW_STATUS="${SERVICE_STATUS_CACHE[shadow-tls-snell]:-未运行}"
        
        if [ "$SNELL_STATUS" == "active" ]; then
            STATUS_ICON="${GREEN}●${RESET}"
        else
            STATUS_ICON="${RED}●${RESET}"
        fi
        
        echo -e "${STATUS_ICON} Snell: ${YELLOW}${SNELL_STATUS}${RESET}"
        
        if [ "$SNELL_SHADOW_STATUS" == "active" ]; then
            STATUS_ICON="${GREEN}●${RESET}"
        else
            STATUS_ICON="${RED}●${RESET}"
        fi
        
        echo -e "${STATUS_ICON} Shadow-TLS (Snell): ${YELLOW}${SNELL_SHADOW_STATUS}${RESET}"
        
        if [ -f /etc/snell/snell-server.conf ]; then
            SNELL_LISTEN=$(grep "listen" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')
            if [[ $SNELL_LISTEN == 127.0.0.1:* ]]; then
                echo -e "  ${GREEN}✓ 安全配置: 仅本地监听${RESET}"
            else
                echo -e "  ${RED}⚠ 警告: 公网可访问${RESET}"
            fi
        fi
        echo ""
    fi
    
    if check_singbox_installed; then
        has_service=true
        SINGBOX_STATUS="${SERVICE_STATUS_CACHE[sing-box]:-未运行}"
        
        if [ "$SINGBOX_STATUS" == "active" ]; then
            STATUS_ICON="${GREEN}●${RESET}"
        else
            STATUS_ICON="${RED}●${RESET}"
        fi
        
        echo -e "${STATUS_ICON} Sing-box: ${YELLOW}${SINGBOX_STATUS}${RESET}"
        echo ""
    fi
    
    if check_reality_installed; then
        has_service=true
        REALITY_STATUS="${SERVICE_STATUS_CACHE[sing-box-reality]:-未运行}"
        
        if [ "$REALITY_STATUS" == "active" ]; then
            STATUS_ICON="${GREEN}●${RESET}"
        else
            STATUS_ICON="${RED}●${RESET}"
        fi
        
        echo -e "${STATUS_ICON} VLESS Reality: ${YELLOW}${REALITY_STATUS}${RESET}"
        echo ""
    fi
    
    if check_hysteria2_installed; then
        has_service=true
        HYSTERIA2_STATUS="${SERVICE_STATUS_CACHE[hysteria2]:-未运行}"
        
        if [ "$HYSTERIA2_STATUS" == "active" ]; then
            STATUS_ICON="${GREEN}●${RESET}"
        else
            STATUS_ICON="${RED}●${RESET}"
        fi
        
        echo -e "${STATUS_ICON} Hysteria2: ${YELLOW}${HYSTERIA2_STATUS}${RESET}"
        
        CERT_TYPE=$(get_config "hysteria2" "CERT_TYPE")
        if [ "$CERT_TYPE" == "letsencrypt" ]; then
            echo -e "  ${GREEN}✓ 证书: Let's Encrypt (自动续签)${RESET}"
        fi
        echo ""
    fi
    
    if [ "$has_service" = false ]; then
        echo -e "${YELLOW}没有已安装的服务${RESET}"
    else
        echo -e "${CYAN}提示: 使用 ${YELLOW}systemctl status <服务名>${CYAN} 查看详细状态${RESET}"
    fi
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
}
# =========================================
# 服务安装函数
# =========================================

# 安装 Snell Server（优化版 - 修复下载链接和使用 trap 清理）
install_snell() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 Snell + Shadow-TLS${RESET}"
    echo -e "${GREEN}   (已集成安全配置和断联修复)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始安装 Snell + Shadow-TLS"

    if check_snell_installed; then
        echo -e "${YELLOW}检测到 Snell 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            log_message "INFO" "用户取消重新安装 Snell"
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        create_restore_point "snell"
        uninstall_snell
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    # ==================== Snell Server 部分 ====================
    log_message "INFO" "开始安装 Snell Server..."
    echo -e "${GREEN}正在安装 Snell Server...${RESET}"

    echo -e "${CYAN}正在获取最新的 Snell 版本...${RESET}"
    SNELL_VERSION=$(get_latest_version "" "snell" "$DEFAULT_SNELL_VERSION")

    log_message "INFO" "Snell 版本: v$SNELL_VERSION"
    echo -e "${GREEN}最新 Snell 版本: v${SNELL_VERSION}${RESET}"

    SNELL_DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"

    local temp_file=$(create_temp_file ".zip")
    trap "rm -f '$temp_file'" RETURN
    
    if ! download_file "$SNELL_DOWNLOAD_URL" "$temp_file" 3 5; then
        handle_error 1 "下载 Snell Server 失败" "${LOG_DIR}/snell-download.log"
        return 1
    fi

    if ! unzip -o "$temp_file" -d /usr/local/bin 2>"${LOG_DIR}/snell-extract.log"; then
        handle_error $? "解压 Snell Server 失败" "${LOG_DIR}/snell-extract.log"
        return 1
    fi

    chmod +x /usr/local/bin/snell-server
    
    echo -e "${GREEN}✓ Snell Server 安装成功${RESET}"

    mkdir -p /etc/snell

    log_message "INFO" "生成 Snell 配置文件..."
    echo -e "${CYAN}正在生成 Snell 配置文件...${RESET}"
    echo "y" | /usr/local/bin/snell-server --wizard -c /etc/snell/snell-server.conf 2>"${LOG_DIR}/snell-wizard.log"

    log_message "INFO" "应用安全配置（仅监听本地 127.0.0.1）..."
    echo -e "${CYAN}正在应用安全配置（仅监听本地 127.0.0.1）...${RESET}"
    sed -i 's/listen = 0.0.0.0:/listen = 127.0.0.1:/' /etc/snell/snell-server.conf

    SNELL_PORT=$(grep "listen" /etc/snell/snell-server.conf | cut -d ':' -f 2 | tr -d ' ')
    SNELL_PSK=$(grep "psk" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')

    log_message "INFO" "Snell 配置: 端口=$SNELL_PORT"

    if ! id -u snell > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin snell
        log_message "INFO" "创建 snell 用户"
    fi

    log_message "INFO" "创建 Snell systemd 服务..."
    cat <<EOF > /lib/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=snell
Group=$(get_default_group)
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable snell
    log_message "INFO" "已启用 Snell 开机自启"

    # ==================== Shadow-TLS 部分 (Snell) ====================
    download_shadow_tls

    SNELL_SHADOW_TLS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    select_tls_domain
    SNELL_TLS_DOMAIN=$TLS_DOMAIN

    while true; do
        read -p "请输入 Shadow-TLS 监听端口 (默认: 8443): " SNELL_SHADOW_TLS_PORT
        SNELL_SHADOW_TLS_PORT=${SNELL_SHADOW_TLS_PORT:-8443}
        
        if validate_port "$SNELL_SHADOW_TLS_PORT"; then
            break
        fi
        echo -e "${YELLOW}请重新输入有效端口${RESET}"
    done

    log_message "INFO" "Shadow-TLS 配置: 端口=$SNELL_SHADOW_TLS_PORT, 域名=$SNELL_TLS_DOMAIN"

    log_message "INFO" "创建 Shadow-TLS systemd 服务..."
    cat <<EOF > /etc/systemd/system/shadow-tls-snell.service
[Unit]
Description=Shadow-TLS Server Service for Snell
Documentation=man:sstls-server
After=network-online.target snell.service
Wants=network-online.target
Requires=snell.service

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen ::0:$SNELL_SHADOW_TLS_PORT --server 127.0.0.1:$SNELL_PORT --tls $SNELL_TLS_DOMAIN --password $SNELL_SHADOW_TLS_PASSWORD
StandardOutput=journal
StandardError=journal
SyslogIdentifier=shadow-tls-snell

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

# 防止频繁重启
RestartPreventExitStatus=SIGKILL

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${CYAN}正在重载 Systemd 守护进程...${RESET}"
    systemctl daemon-reload

    echo -e "${CYAN}正在设置 Shadow-TLS 开机自启...${RESET}"
    systemctl enable shadow-tls-snell.service
    log_message "INFO" "已启用 Shadow-TLS 开机自启"

    echo -e "${CYAN}正在启动服务...${RESET}"
    log_message "INFO" "启动 Snell 和 Shadow-TLS 服务..."
    systemctl start snell
    systemctl start shadow-tls-snell.service

    sleep 2

    clear_status_cache
    get_all_service_status

    SNELL_STATUS="${SERVICE_STATUS_CACHE[snell]:-未运行}"
    SNELL_SHADOW_TLS_STATUS="${SERVICE_STATUS_CACHE[shadow-tls-snell]:-未运行}"

    create_healthcheck_script

    declare -A snell_config=(
        ["TYPE"]="snell"
        ["SERVER_IP"]="$SERVER_IP"
        ["IP_VERSION"]="$IP_VERSION"
        ["SNELL_VERSION"]="$SNELL_VERSION"
        ["SNELL_PORT"]="$SNELL_PORT"
        ["SNELL_PSK"]="$SNELL_PSK"
        ["SHADOW_TLS_VERSION"]="$SHADOW_TLS_VERSION"
        ["SHADOW_TLS_PORT"]="$SNELL_SHADOW_TLS_PORT"
        ["SHADOW_TLS_PASSWORD"]="$SNELL_SHADOW_TLS_PASSWORD"
        ["TLS_DOMAIN"]="$SNELL_TLS_DOMAIN"
        ["INSTALL_DATE"]="$(date '+%Y-%m-%d %H:%M:%S')"
    )
    save_service_config "snell" snell_config

    cat <<EOF > /etc/snell-proxy-config.txt
TYPE=snell
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SNELL_VERSION=$SNELL_VERSION
SNELL_PORT=$SNELL_PORT
SNELL_PSK=$SNELL_PSK
SHADOW_TLS_VERSION=$SHADOW_TLS_VERSION
SHADOW_TLS_PORT=$SNELL_SHADOW_TLS_PORT
SHADOW_TLS_PASSWORD=$SNELL_SHADOW_TLS_PASSWORD
TLS_DOMAIN=$SNELL_TLS_DOMAIN
EOF

    log_message "SUCCESS" "Snell + Shadow-TLS 安装完成"

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Snell 配置:${RESET}"
    echo -e "  版本: ${YELLOW}v${SNELL_VERSION}${RESET}"
    echo -e "  监听地址: ${GREEN}127.0.0.1:${SNELL_PORT}${RESET} ${GREEN}(仅本地，安全)${RESET}"
    echo -e "  PSK: ${YELLOW}${SNELL_PSK}${RESET}"
    echo -e "  状态: ${YELLOW}${SNELL_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SHADOW_TLS_VERSION}${RESET}"
    echo -e "  外部端口: ${YELLOW}${SNELL_SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${SNELL_SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "  伪装域名: ${YELLOW}${SNELL_TLS_DOMAIN}${RESET}"
    echo -e "  状态: ${YELLOW}${SNELL_SHADOW_TLS_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置 (Snell v4):${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SNELL_SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=4, reuse=true, tfo=true, shadow-tls-password=${SNELL_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SNELL_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置 (Snell v5):${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SNELL_SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SNELL_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SNELL_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - 安全配置: Snell 仅监听本地 (127.0.0.1)${RESET}"
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}  - 服务依赖管理${RESET}"
    echo -e "${GREEN}  - 配置自动备份${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if [ "$SNELL_STATUS" != "active" ] || [ "$SNELL_SHADOW_TLS_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: 部分服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看 Snell 日志: ${CYAN}journalctl -u snell -f${RESET}"
        echo -e "  2. 查看 Shadow-TLS 日志: ${CYAN}journalctl -u shadow-tls-snell -f${RESET}"
        echo -e "  3. 检查端口占用: ${CYAN}netstat -tulpn | grep ${SNELL_SHADOW_TLS_PORT}${RESET}"
        echo -e "  4. 查看详细日志: ${CYAN}cat ${LOG_DIR}/install.log${RESET}"
        echo ""
    fi
}

# 安装 Sing-box (SS-2022 + Shadow-TLS）优化版
install_singbox() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 Sing-box (SS-2022 + Shadow-TLS)${RESET}"
    echo -e "${GREEN}   (已集成安全配置和断联修复)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始安装 Sing-box (SS-2022 + Shadow-TLS)"

    if check_singbox_installed; then
        echo -e "${YELLOW}检测到 Sing-box 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            log_message "INFO" "用户取消重新安装 Sing-box"
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        create_restore_point "singbox"
        uninstall_singbox
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    download_singbox

    select_ss_method

    while true; do
        read -p "请输入 Shadowsocks 监听端口 (默认: 8388): " SS_PORT
        SS_PORT=${SS_PORT:-8388}
        
        if validate_port "$SS_PORT"; then
            break
        fi
        echo -e "${YELLOW}请重新输入有效端口${RESET}"
    done

    select_tls_domain
    SINGBOX_TLS_DOMAIN=$TLS_DOMAIN

    read -p "请输入 Shadow-TLS 监听端口 (默认: 9443): " SINGBOX_SHADOW_TLS_PORT
    SINGBOX_SHADOW_TLS_PORT=${SINGBOX_SHADOW_TLS_PORT:-9443}

    SINGBOX_SHADOW_TLS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    log_message "INFO" "Sing-box 配置: SS端口=$SS_PORT, Shadow-TLS端口=$SINGBOX_SHADOW_TLS_PORT"

    mkdir -p /etc/sing-box

    log_message "INFO" "创建 Sing-box 配置文件..."
    echo -e "${CYAN}正在创建 Sing-box 配置文件...${RESET}"
    
    if ! create_singbox_config \
        "/etc/sing-box/config.json" \
        "$SS_PORT" \
        "$SS_METHOD" \
        "$SS_PASSWORD" \
        "$SINGBOX_SHADOW_TLS_PORT" \
        "$SINGBOX_SHADOW_TLS_PASSWORD" \
        "$SINGBOX_TLS_DOMAIN"; then
        echo -e "${RED}配置文件创建失败${RESET}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 配置文件已创建并验证${RESET}"

    if ! id -u sing-box > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin sing-box
        log_message "INFO" "创建 sing-box 用户"
    fi

    log_message "INFO" "创建 Sing-box systemd 服务..."
    cat <<EOF > /lib/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=sing-box
Group=$(get_default_group)
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sing-box

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable sing-box
    log_message "INFO" "已启用 Sing-box 开机自启"

    echo -e "${CYAN}正在启动服务...${RESET}"
    log_message "INFO" "启动 Sing-box 服务..."
    systemctl start sing-box

    sleep 2

    clear_status_cache
    get_all_service_status

    SINGBOX_STATUS="${SERVICE_STATUS_CACHE[sing-box]:-未运行}"

    if [ "$SINGBOX_STATUS" != "active" ]; then
        log_message "ERROR" "Sing-box 服务启动失败"
        echo -e "${RED}Sing-box 服务启动失败${RESET}"
        echo -e "${YELLOW}查看详细日志:${RESET}"
        journalctl -u sing-box -n 30 --no-pager
    fi

    create_healthcheck_script

    declare -A singbox_config=(
        ["TYPE"]="singbox"
        ["SERVER_IP"]="$SERVER_IP"
        ["IP_VERSION"]="$IP_VERSION"
        ["SINGBOX_VERSION"]="$SINGBOX_VERSION"
        ["SS_PORT"]="$SS_PORT"
        ["SS_PASSWORD"]="$SS_PASSWORD"
        ["SS_METHOD"]="$SS_METHOD"
        ["SHADOW_TLS_PORT"]="$SINGBOX_SHADOW_TLS_PORT"
        ["SHADOW_TLS_PASSWORD"]="$SINGBOX_SHADOW_TLS_PASSWORD"
        ["TLS_DOMAIN"]="$SINGBOX_TLS_DOMAIN"
        ["INSTALL_DATE"]="$(date '+%Y-%m-%d %H:%M:%S')"
    )
    save_service_config "singbox" singbox_config

    cat <<EOF > /etc/singbox-proxy-config.txt
TYPE=singbox
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
SS_PORT=$SS_PORT
SS_PASSWORD=$SS_PASSWORD
SS_METHOD=$SS_METHOD
SHADOW_TLS_PORT=$SINGBOX_SHADOW_TLS_PORT
SHADOW_TLS_PASSWORD=$SINGBOX_SHADOW_TLS_PASSWORD
TLS_DOMAIN=$SINGBOX_TLS_DOMAIN
EOF

    log_message "SUCCESS" "Sing-box 安装完成"

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${SINGBOX_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadowsocks-2022 配置:${RESET}"
    echo -e "  内部端口: ${YELLOW}${SS_PORT}${RESET} ${GREEN}(仅本地，安全)${RESET}"
    echo -e "  密码: ${YELLOW}${SS_PASSWORD}${RESET}"
    echo -e "  加密方式: ${YELLOW}${SS_METHOD}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  外部端口: ${YELLOW}${SINGBOX_SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${SINGBOX_SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "  伪装域名: ${YELLOW}${SINGBOX_TLS_DOMAIN}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = ss, ${SERVER_IP}, ${SINGBOX_SHADOW_TLS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${SINGBOX_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SINGBOX_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - 安全配置: Shadowsocks 仅监听本地 (127.0.0.1)${RESET}"
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}  - 配置自动备份${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if [ "$SINGBOX_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: Sing-box 服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看日志: ${CYAN}journalctl -u sing-box -f${RESET}"
        echo -e "  2. 检查配置: ${CYAN}cat /etc/sing-box/config.json${RESET}"
        echo -e "  3. 测试配置: ${CYAN}/usr/local/bin/sing-box check -c /etc/sing-box/config.json${RESET}"
        echo -e "  4. 查看详细日志: ${CYAN}cat ${LOG_DIR}/install.log${RESET}"
        echo ""
    fi
}
# 安装 VLESS Reality（优化版）
install_reality() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 VLESS Reality${RESET}"
    echo -e "${GREEN}   (已集成安全配置和断联修复)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始安装 VLESS Reality"

    if check_reality_installed; then
        echo -e "${YELLOW}检测到 VLESS Reality 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            log_message "INFO" "用户取消重新安装 Reality"
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        create_restore_point "reality"
        uninstall_reality
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    download_singbox

    generate_reality_keypair

    REALITY_UUID=$(cat /proc/sys/kernel/random/uuid)

    REALITY_SHORT_ID=$(generate_short_id)

    select_reality_dest

    while true; do
        read -p "请输入 VLESS Reality 监听端口 (默认: 443): " REALITY_PORT
        REALITY_PORT=${REALITY_PORT:-443}
        
        if validate_port "$REALITY_PORT"; then
            break
        fi
        echo -e "${YELLOW}请重新输入有效端口${RESET}"
    done

    log_message "INFO" "Reality 配置: 端口=$REALITY_PORT, 目标=$REALITY_DEST"

    mkdir -p /etc/sing-box-reality
    
    log_message "INFO" "创建 Reality 配置文件"

    cat <<EOF > /etc/sing-box-reality/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $REALITY_PORT,
      "users": [
        {
          "uuid": "$REALITY_UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_DEST",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$REALITY_DEST",
            "server_port": 443
          },
          "private_key": "$REALITY_PRIVATE_KEY",
          "short_id": [
            "$REALITY_SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${GREEN}配置文件已创建: /etc/sing-box-reality/config.json${RESET}"

    if ! id -u sing-box-reality > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin sing-box-reality
        log_message "INFO" "创建 sing-box-reality 用户"
    fi

    log_message "INFO" "创建 Reality systemd 服务..."
    cat <<EOF > /lib/systemd/system/sing-box-reality.service
[Unit]
Description=Sing-box Reality Service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=sing-box-reality
Group=$(get_default_group)
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box-reality/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sing-box-reality

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable sing-box-reality
    log_message "INFO" "已启用 Reality 开机自启"

    echo -e "${CYAN}正在启动服务...${RESET}"
    log_message "INFO" "启动 Reality 服务..."
    systemctl start sing-box-reality

    sleep 2

    clear_status_cache
    get_all_service_status

    REALITY_STATUS="${SERVICE_STATUS_CACHE[sing-box-reality]:-未运行}"

    if [ "$REALITY_STATUS" != "active" ]; then
        log_message "ERROR" "Reality 服务启动失败"
        echo -e "${RED}Reality 服务启动失败${RESET}"
        echo -e "${YELLOW}查看详细日志:${RESET}"
        journalctl -u sing-box-reality -n 30 --no-pager
    fi

    create_healthcheck_script

    declare -A reality_config=(
        ["TYPE"]="reality"
        ["SERVER_IP"]="$SERVER_IP"
        ["IP_VERSION"]="$IP_VERSION"
        ["SINGBOX_VERSION"]="$SINGBOX_VERSION"
        ["REALITY_PORT"]="$REALITY_PORT"
        ["REALITY_UUID"]="$REALITY_UUID"
        ["REALITY_PUBLIC_KEY"]="$REALITY_PUBLIC_KEY"
        ["REALITY_SHORT_ID"]="$REALITY_SHORT_ID"
        ["REALITY_DEST"]="$REALITY_DEST"
        ["INSTALL_DATE"]="$(date '+%Y-%m-%d %H:%M:%S')"
    )
    save_service_config "reality" reality_config

    cat <<EOF > /etc/reality-proxy-config.txt
TYPE=reality
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
REALITY_PORT=$REALITY_PORT
REALITY_UUID=$REALITY_UUID
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
REALITY_DEST=$REALITY_DEST
EOF

    log_message "SUCCESS" "Reality 安装完成"

    REALITY_LINK="vless://${REALITY_UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-${SERVER_IP}"

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${REALITY_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}VLESS Reality 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${REALITY_PORT}${RESET}"
    echo -e "  UUID: ${YELLOW}${REALITY_UUID}${RESET}"
    echo -e "  Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${RESET}"
    echo -e "  Short ID: ${YELLOW}${REALITY_SHORT_ID}${RESET}"
    echo -e "  目标网站: ${YELLOW}${REALITY_DEST}${RESET}"
    echo -e "  Flow: ${YELLOW}xtls-rprx-vision${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${REALITY_LINK}${RESET}"
    echo ""
    echo -e "${CYAN}二维码:${RESET}"
    qrencode -t ANSIUTF8 "$REALITY_LINK"
    echo ""
    echo -e "${CYAN}客户端配置提示:${RESET}"
    echo -e "  请使用支持 VLESS Reality 的客户端"
    echo -e "  推荐客户端: v2rayN, Shadowrocket, Surge (5.0+), Clash Meta"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - Reality 协议 (抗审查能力强)${RESET}"
    echo -e "${GREEN}  - XTLS Vision 流控${RESET}"
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}  - 配置自动备份${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if [ "$REALITY_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: Reality 服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看日志: ${CYAN}journalctl -u sing-box-reality -f${RESET}"
        echo -e "  2. 检查配置: ${CYAN}cat /etc/sing-box-reality/config.json${RESET}"
        echo -e "  3. 测试配置: ${CYAN}/usr/local/bin/sing-box check -c /etc/sing-box-reality/config.json${RESET}"
        echo -e "  4. 查看详细日志: ${CYAN}cat ${LOG_DIR}/install.log${RESET}"
        echo ""
    fi
}

# 安装 Hysteria2（优化版 - 基于 sing-box 内核 + Let's Encrypt 证书）
install_hysteria2() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 Hysteria2 (Sing-box 内核)${RESET}"
    echo -e "${GREEN}   (Let's Encrypt 证书 + 自动续签)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始安装 Hysteria2"

    if check_hysteria2_installed; then
        echo -e "${YELLOW}检测到 Hysteria2 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            log_message "INFO" "用户取消重新安装 Hysteria2"
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        create_restore_point "hysteria2"
        uninstall_hysteria2
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    download_singbox

    HYSTERIA2_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    while true; do
        read -p "请输入 Hysteria2 监听端口 (默认: 443): " HYSTERIA2_PORT
        HYSTERIA2_PORT=${HYSTERIA2_PORT:-443}
        
        if validate_port "$HYSTERIA2_PORT"; then
            break
        fi
        echo -e "${YELLOW}请重新输入有效端口${RESET}"
    done

    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   配置混淆 (Salamander)${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${YELLOW}是否启用混淆？${RESET}"
    echo -e "  混淆可以进一步提高隐蔽性，防止流量特征被识别"
    echo ""
    read -p "启用混淆？(y/n，默认: n): " enable_obfs
    enable_obfs=${enable_obfs:-n}
    
    if [ "$enable_obfs" == "y" ] || [ "$enable_obfs" == "Y" ]; then
        ENABLE_OBFS=true
        OBFS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
        echo -e "${GREEN}✓ 已启用混淆${RESET}"
        echo -e "${CYAN}混淆密码: ${YELLOW}${OBFS_PASSWORD}${RESET}"
    else
        ENABLE_OBFS=false
        echo -e "${YELLOW}未启用混淆${RESET}"
    fi
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   配置域名和证书${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${YELLOW}请输入您的域名 (必须已解析到此服务器):${RESET}"
    
    while true; do
        read -p "域名: " HYSTERIA2_DOMAIN
        
        if [ -z "$HYSTERIA2_DOMAIN" ]; then
            echo -e "${RED}域名不能为空${RESET}"
            continue
        fi
        
        if validate_domain "$HYSTERIA2_DOMAIN"; then
            break
        fi
        echo -e "${YELLOW}请输入有效的域名格式${RESET}"
    done
    
    echo ""
    echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo -e "${YELLOW}请确保域名已正确解析到: ${GREEN}${SERVER_IP}${RESET}"
    echo ""
    read -p "确认继续？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_message "INFO" "用户取消安装"
        echo -e "${CYAN}取消安装${RESET}"
        return
    fi

    log_message "INFO" "Hysteria2 配置: 端口=$HYSTERIA2_PORT, 域名=$HYSTERIA2_DOMAIN, 混淆=$ENABLE_OBFS"

    echo ""
    echo -e "${CYAN}正在准备安装环境...${RESET}"
    
    mkdir -p /etc/hysteria2
    echo -e "${GREEN}✓ 已创建配置目录${RESET}"

    if ! id -u hysteria2 > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin hysteria2
        log_message "INFO" "创建 hysteria2 用户"
        echo -e "${GREEN}✓ 已创建 hysteria2 用户${RESET}"
    else
        echo -e "${GREEN}✓ hysteria2 用户已存在${RESET}"
    fi

    install_acme

    if ! issue_letsencrypt_cert "$HYSTERIA2_DOMAIN"; then
        echo -e "${RED}证书申请失败，安装终止${RESET}"
        return
    fi

    if ! install_cert_to_hysteria2 "$HYSTERIA2_DOMAIN"; then
        echo -e "${RED}证书安装失败，安装终止${RESET}"
        return
    fi

    chown hysteria2:$(get_default_group) /etc/hysteria2/server.key /etc/hysteria2/server.crt
    chmod 600 /etc/hysteria2/server.key
    chmod 644 /etc/hysteria2/server.crt
    echo -e "${GREEN}✓ 证书权限设置完成${RESET}"

    echo ""
    echo -e "${CYAN}正在创建 Hysteria2 配置文件...${RESET}"
    
    if ! create_hysteria2_config \
        "/etc/hysteria2/config.json" \
        "$HYSTERIA2_PORT" \
        "$HYSTERIA2_PASSWORD" \
        "$HYSTERIA2_DOMAIN" \
        "$ENABLE_OBFS" \
        "${OBFS_PASSWORD:-}"; then
        echo -e "${RED}配置文件创建失败${RESET}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 配置文件已创建并验证${RESET}"

    echo ""
    echo -e "${CYAN}正在创建 Systemd 服务...${RESET}"
    
    cat <<EOF > /lib/systemd/system/hysteria2.service
[Unit]
Description=Hysteria2 Service (Sing-box)
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=hysteria2
Group=$(get_default_group)
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/hysteria2/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hysteria2

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✓ Systemd 服务文件已创建${RESET}"

    systemctl daemon-reload

    systemctl enable hysteria2
    log_message "INFO" "已启用 Hysteria2 开机自启"
    echo -e "${GREEN}✓ 已设置开机自启${RESET}"

    echo ""
    echo -e "${CYAN}正在启动 Hysteria2 服务...${RESET}"
    systemctl start hysteria2

    sleep 3

    clear_status_cache
    get_all_service_status

    HYSTERIA2_STATUS="${SERVICE_STATUS_CACHE[hysteria2]:-未运行}"

    if [ "$HYSTERIA2_STATUS" != "active" ]; then
        echo -e "${RED}Hysteria2 服务启动失败${RESET}"
        echo -e "${YELLOW}查看详细日志:${RESET}"
        journalctl -u hysteria2 -n 30 --no-pager
        echo ""
        echo -e "${YELLOW}可能的原因:${RESET}"
        echo -e "  1. 端口 $HYSTERIA2_PORT 已被占用"
        echo -e "  2. 证书文件权限不正确"
        echo -e "  3. 配置文件格式错误"
        echo ""
        echo -e "${CYAN}调试命令:${RESET}"
        echo -e "  查看端口占用: ${YELLOW}netstat -tulpn | grep $HYSTERIA2_PORT${RESET}"
        echo -e "  检查证书权限: ${YELLOW}ls -la /etc/hysteria2/${RESET}"
        echo -e "  测试配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/hysteria2/config.json${RESET}"
        echo ""
    fi

    create_healthcheck_script

    if [ "$ENABLE_OBFS" = true ]; then
        declare -A hysteria2_config=(
            ["TYPE"]="hysteria2"
            ["SERVER_IP"]="$SERVER_IP"
            ["IP_VERSION"]="$IP_VERSION"
            ["SINGBOX_VERSION"]="$SINGBOX_VERSION"
            ["HYSTERIA2_PORT"]="$HYSTERIA2_PORT"
            ["HYSTERIA2_PASSWORD"]="$HYSTERIA2_PASSWORD"
            ["HYSTERIA2_DOMAIN"]="$HYSTERIA2_DOMAIN"
            ["CERT_TYPE"]="letsencrypt"
            ["ENABLE_OBFS"]="true"
            ["OBFS_PASSWORD"]="$OBFS_PASSWORD"
            ["INSTALL_DATE"]="$(date '+%Y-%m-%d %H:%M:%S')"
        )
    else
        declare -A hysteria2_config=(
            ["TYPE"]="hysteria2"
            ["SERVER_IP"]="$SERVER_IP"
            ["IP_VERSION"]="$IP_VERSION"
            ["SINGBOX_VERSION"]="$SINGBOX_VERSION"
            ["HYSTERIA2_PORT"]="$HYSTERIA2_PORT"
            ["HYSTERIA2_PASSWORD"]="$HYSTERIA2_PASSWORD"
            ["HYSTERIA2_DOMAIN"]="$HYSTERIA2_DOMAIN"
            ["CERT_TYPE"]="letsencrypt"
            ["ENABLE_OBFS"]="false"
            ["INSTALL_DATE"]="$(date '+%Y-%m-%d %H:%M:%S')"
        )
    fi
    save_service_config "hysteria2" hysteria2_config

    if [ "$ENABLE_OBFS" = true ]; then
        cat <<EOF > /etc/hysteria2-proxy-config.txt
TYPE=hysteria2
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
HYSTERIA2_PORT=$HYSTERIA2_PORT
HYSTERIA2_PASSWORD=$HYSTERIA2_PASSWORD
HYSTERIA2_DOMAIN=$HYSTERIA2_DOMAIN
CERT_TYPE=letsencrypt
ENABLE_OBFS=true
OBFS_PASSWORD=$OBFS_PASSWORD
EOF
    else
        cat <<EOF > /etc/hysteria2-proxy-config.txt
TYPE=hysteria2
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
HYSTERIA2_PORT=$HYSTERIA2_PORT
HYSTERIA2_PASSWORD=$HYSTERIA2_PASSWORD
HYSTERIA2_DOMAIN=$HYSTERIA2_DOMAIN
CERT_TYPE=letsencrypt
ENABLE_OBFS=false
EOF
    fi

    log_message "SUCCESS" "Hysteria2 安装完成"

    if [ "$ENABLE_OBFS" = true ]; then
        HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
    else
        HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
    fi

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo -e "  域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${HYSTERIA2_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Hysteria2 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${HYSTERIA2_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${HYSTERIA2_PASSWORD}${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "  混淆: ${GREEN}已启用 (salamander)${RESET}"
        echo -e "  混淆密码: ${YELLOW}${OBFS_PASSWORD}${RESET}"
    else
        echo -e "  混淆: ${YELLOW}未启用${RESET}"
    fi
    echo -e "  TLS: ${GREEN}Let's Encrypt 证书 (自动续签)${RESET}"
    echo ""
    
    if [ -f /etc/hysteria2/server.crt ]; then
        CERT_EXPIRY=$(openssl x509 -in /etc/hysteria2/server.crt -noout -enddate | cut -d= -f2)
        echo -e "${CYAN}证书信息:${RESET}"
        echo -e "  颁发者: ${GREEN}Let's Encrypt${RESET}"
        echo -e "  到期时间: ${YELLOW}${CERT_EXPIRY}${RESET}"
        echo ""
    fi
    
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${HYSTERIA2_LINK}${RESET}"
    echo ""
    echo -e "${CYAN}二维码:${RESET}"
    qrencode -t ANSIUTF8 "$HYSTERIA2_LINK" 2>/dev/null || echo -e "${YELLOW}qrencode 未安装，无法显示二维码${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
    else
        echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}${RESET}"
    fi
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - Hysteria2 协议 (高速、抗丢包)${RESET}"
    echo -e "${GREEN}  - Let's Encrypt 证书 (自动续签)${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "${GREEN}  - Salamander 混淆 (增强抗审查)${RESET}"
    fi
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}  - 配置自动备份${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if [ "$HYSTERIA2_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: Hysteria2 服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看日志: ${CYAN}journalctl -u hysteria2 -f${RESET}"
        echo -e "  2. 检查配置: ${CYAN}cat /etc/hysteria2/config.json${RESET}"
        echo -e "  3. 测试配置: ${CYAN}/usr/local/bin/sing-box check -c /etc/hysteria2/config.json${RESET}"
        echo -e "  4. 检查证书权限: ${CYAN}ls -la /etc/hysteria2/${RESET}"
        echo -e "  5. 检查端口占用: ${CYAN}netstat -tulpn | grep ${HYSTERIA2_PORT}${RESET}"
        echo -e "  6. 查看详细日志: ${CYAN}cat ${LOG_DIR}/install.log${RESET}"
        echo ""
    else
        echo -e "${GREEN}🎉 Hysteria2 安装成功并正常运行！${RESET}"
        echo ""
        echo -e "${CYAN}证书管理提示:${RESET}"
        echo -e "  - 证书有效期: ${YELLOW}90 天${RESET}"
        echo -e "  - 自动续签: ${GREEN}已启用 (到期前 30 天自动续签)${RESET}"
        echo -e "  - 查看证书状态: ${YELLOW}选择菜单选项 23${RESET}"
        echo -e "  - 手动续签: ${YELLOW}选择菜单选项 22${RESET}"
        echo ""
    fi
}

# =========================================
# 证书管理函数
# =========================================

# 手动续签证书
renew_hysteria2_cert() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装${RESET}"
        return
    fi
    
    local domain=$(get_config "hysteria2" "HYSTERIA2_DOMAIN")
    local cert_type=$(get_config "hysteria2" "CERT_TYPE")
    
    if [ "$cert_type" != "letsencrypt" ]; then
        echo -e "${RED}当前使用的不是 Let's Encrypt 证书，无需续签${RESET}"
        return
    fi
    
    log_message "INFO" "开始手动续签证书: $domain"
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在续签 Hysteria2 证书${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    echo -e "${CYAN}域名: ${YELLOW}${domain}${RESET}"
    echo ""
    
    echo -e "${CYAN}正在停止 Hysteria2 服务...${RESET}"
    systemctl stop hysteria2
    
    log_message "INFO" "执行证书续签..."
    if ~/.acme.sh/acme.sh --renew -d "$domain" --ecc --force 2>"${LOG_DIR}/acme-renew-${domain}.log"; then
        log_message "SUCCESS" "证书续签成功"
        echo -e "${GREEN}✓ 证书续签成功${RESET}"
        
        install_cert_to_hysteria2 "$domain"
        
        systemctl start hysteria2
        
        sleep 2
        clear_status_cache
        get_all_service_status
        if [ "${SERVICE_STATUS_CACHE[hysteria2]:-未运行}" == "active" ]; then
            log_message "SUCCESS" "Hysteria2 服务已重启"
            echo -e "${GREEN}✓ Hysteria2 服务已重启${RESET}"
        else
            log_message "ERROR" "Hysteria2 服务启动失败"
            echo -e "${RED}Hysteria2 服务启动失败${RESET}"
            journalctl -u hysteria2 -n 20 --no-pager
        fi
    else
        log_message "ERROR" "证书续签失败"
        handle_error $? "证书续签失败" "${LOG_DIR}/acme-renew-${domain}.log"
        systemctl start hysteria2
    fi
}

# 查看证书状态
view_cert_status() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装${RESET}"
        return
    fi
    
    local domain=$(get_config "hysteria2" "HYSTERIA2_DOMAIN")
    local cert_type=$(get_config "hysteria2" "CERT_TYPE")
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Hysteria2 证书状态${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if [ "$cert_type" == "letsencrypt" ]; then
        echo -e "${CYAN}证书类型: ${GREEN}Let's Encrypt${RESET}"
        echo -e "${CYAN}域名: ${YELLOW}${domain}${RESET}"
        echo ""
        
        if [ -f /etc/hysteria2/server.crt ]; then
            echo -e "${CYAN}证书信息:${RESET}"
            openssl x509 -in /etc/hysteria2/server.crt -noout -dates -subject
            echo ""
            
            EXPIRY_DATE=$(openssl x509 -in /etc/hysteria2/server.crt -noout -enddate | cut -d= -f2)
            EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null)
            CURRENT_EPOCH=$(date +%s)
            DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
            
            if [ $DAYS_LEFT -gt 30 ]; then
                echo -e "${GREEN}剩余有效期: ${DAYS_LEFT} 天${RESET}"
            elif [ $DAYS_LEFT -gt 7 ]; then
                echo -e "${YELLOW}剩余有效期: ${DAYS_LEFT} 天 (建议续签)${RESET}"
            else
                echo -e "${RED}剩余有效期: ${DAYS_LEFT} 天 (请立即续签)${RESET}"
            fi
        else
            echo -e "${RED}证书文件不存在${RESET}"
        fi
        
        echo ""
        echo -e "${CYAN}自动续签状态:${RESET}"
        if crontab -l 2>/dev/null | grep -q "acme.sh.*--cron"; then
            echo -e "${GREEN}✓ 已启用 (每天自动检查)${RESET}"
        else
            echo -e "${RED}✗ 未启用${RESET}"
        fi
    else
        echo -e "${CYAN}证书类型: ${YELLOW}自签名证书${RESET}"
        echo ""
        
        if [ -f /etc/hysteria2/server.crt ]; then
            echo -e "${CYAN}证书信息:${RESET}"
            openssl x509 -in /etc/hysteria2/server.crt -noout -dates -subject
        else
            echo -e "${RED}证书文件不存在${RESET}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
}
# =========================================
# 更新函数（修复版 - 完整的回滚机制）
# =========================================

# 更新 Snell（修复版 - 完整回滚机制）
update_snell() {
    if ! check_snell_installed; then
        echo -e "${RED}Snell 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Snell${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始更新 Snell"

    # 获取当前版本
    CURRENT_VERSION=$(get_config "snell" "SNELL_VERSION")
    if [ -z "$CURRENT_VERSION" ]; then
        if [ -f /etc/snell-proxy-config.txt ]; then
            safe_source_config /etc/snell-proxy-config.txt
            CURRENT_VERSION=$SNELL_VERSION
        else
            CURRENT_VERSION="未知"
        fi
    fi

    echo -e "${CYAN}当前版本: ${YELLOW}${CURRENT_VERSION}${RESET}"

    detect_architecture

    echo -e "${CYAN}正在获取最新的 Snell 版本...${RESET}"
    LATEST_VERSION=$(get_latest_version "" "snell" "$DEFAULT_SNELL_VERSION")

    if [ -z "$LATEST_VERSION" ]; then
        log_message "WARN" "无法获取最新版本"
        echo -e "${YELLOW}无法获取最新版本${RESET}"
        return 1
    fi

    log_message "INFO" "最新版本: v$LATEST_VERSION"
    echo -e "${CYAN}最新版本: ${YELLOW}v${LATEST_VERSION}${RESET}"
    echo ""

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        log_message "INFO" "Snell 已是最新版本"
        echo -e "${GREEN}✓ 已经是最新版本，无需更新${RESET}"
        return 0
    fi

    echo -e "${YELLOW}发现新版本: ${CURRENT_VERSION} -> ${LATEST_VERSION}${RESET}"
    read -p "是否继续更新？(y/n): " confirm_update
    if [ "$confirm_update" != "y" ] && [ "$confirm_update" != "Y" ]; then
        echo -e "${CYAN}取消更新${RESET}"
        return 0
    fi

    # 创建完整备份
    echo ""
    echo -e "${CYAN}正在创建备份...${RESET}"
    local backup_success=false
    if create_restore_point "snell"; then
        backup_success=true
        echo -e "${GREEN}✓ 备份创建成功${RESET}"
    else
        echo -e "${YELLOW}警告: 备份创建失败${RESET}"
        read -p "是否继续更新？(y/n): " continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            echo -e "${CYAN}取消更新${RESET}"
            return 1
        fi
    fi

    # 停止相关服务
    echo ""
    echo -e "${CYAN}正在停止服务...${RESET}"
    local services_stopped=()
    
    if systemctl is-active --quiet shadow-tls-snell 2>/dev/null; then
        systemctl stop shadow-tls-snell
        services_stopped+=("shadow-tls-snell")
        echo -e "${YELLOW}已停止: shadow-tls-snell${RESET}"
    fi
    
    if systemctl is-active --quiet snell 2>/dev/null; then
        systemctl stop snell
        services_stopped+=("snell")
        echo -e "${YELLOW}已停止: snell${RESET}"
    fi

    # 备份二进制文件
    local binary_backup="/tmp/snell-server.bak.$$"
    if [ -f /usr/local/bin/snell-server ]; then
        cp /usr/local/bin/snell-server "$binary_backup"
    fi

    # 备份配置版本信息
    local config_backup="/tmp/snell-config.bak.$$"
    if [ -f /etc/snell-proxy-config.txt ]; then
        cp /etc/snell-proxy-config.txt "$config_backup"
    fi

    # 下载新版本
    echo ""
    echo -e "${CYAN}正在下载 Snell v${LATEST_VERSION}...${RESET}"
    SNELL_DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v${LATEST_VERSION}-linux-${SNELL_ARCH}.zip"
    
    local temp_file=$(create_temp_file ".zip")
    local download_success=false
    
    if download_file "$SNELL_DOWNLOAD_URL" "$temp_file" 3 5; then
        echo -e "${GREEN}✓ 下载成功${RESET}"
        
        # 解压
        echo -e "${CYAN}正在解压...${RESET}"
        if unzip -o "$temp_file" -d /usr/local/bin 2>"${LOG_DIR}/snell-extract.log"; then
            chmod +x /usr/local/bin/snell-server
            download_success=true
            echo -e "${GREEN}✓ 解压成功${RESET}"
        else
            echo -e "${RED}解压失败${RESET}"
            cat "${LOG_DIR}/snell-extract.log"
        fi
    else
        echo -e "${RED}下载失败${RESET}"
    fi
    
    rm -f "$temp_file"

    # 如果下载或解压失败，回滚
    if [ "$download_success" = false ]; then
        echo ""
        echo -e "${RED}更新失败，正在回滚...${RESET}"
        
        if [ -f "$binary_backup" ]; then
            mv "$binary_backup" /usr/local/bin/snell-server
            chmod +x /usr/local/bin/snell-server
            echo -e "${GREEN}✓ 已恢复旧版本二进制文件${RESET}"
        fi
        
        if [ -f "$config_backup" ]; then
            mv "$config_backup" /etc/snell-proxy-config.txt
            echo -e "${GREEN}✓ 已恢复配置文件${RESET}"
        fi
        
        # 重启服务
        for service in "${services_stopped[@]}"; do
            systemctl start "$service"
        done
        
        log_message "ERROR" "Snell 更新失败"
        return 1
    fi

    # 更新配置文件中的版本信息
    echo ""
    echo -e "${CYAN}正在更新配置...${RESET}"
    save_config "snell" "SNELL_VERSION" "$LATEST_VERSION"
    if [ -f /etc/snell-proxy-config.txt ]; then
        sed -i "s/SNELL_VERSION=.*/SNELL_VERSION=$LATEST_VERSION/" /etc/snell-proxy-config.txt
    fi

    # 启动服务
    echo ""
    echo -e "${CYAN}正在启动服务...${RESET}"
    
    local start_success=true
    for service in "${services_stopped[@]}"; do
        echo -e "${YELLOW}启动: $service${RESET}"
        if systemctl start "$service"; then
            sleep 1
            if systemctl is-active --quiet "$service"; then
                echo -e "${GREEN}✓ $service 启动成功${RESET}"
            else
                echo -e "${RED}✗ $service 启动失败${RESET}"
                start_success=false
            fi
        else
            echo -e "${RED}✗ $service 启动命令失败${RESET}"
            start_success=false
        fi
    done

    # 验证服务状态
    sleep 2
    clear_status_cache
    get_all_service_status

    SNELL_STATUS="${SERVICE_STATUS_CACHE[snell]:-未运行}"
    SHADOW_STATUS="${SERVICE_STATUS_CACHE[shadow-tls-snell]:-未运行}"

    echo ""
    if [ "$SNELL_STATUS" == "active" ] && [ "$SHADOW_STATUS" == "active" ]; then
        log_message "SUCCESS" "Snell 更新成功: $CURRENT_VERSION -> $LATEST_VERSION"
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${GREEN}   ✓ 更新成功！${RESET}"
        echo -e "${GREEN}=========================================${RESET}"
        echo ""
        echo -e "${CYAN}版本: ${YELLOW}${CURRENT_VERSION}${RESET} -> ${GREEN}${LATEST_VERSION}${RESET}"
        echo -e "${CYAN}Snell 状态: ${GREEN}${SNELL_STATUS}${RESET}"
        echo -e "${CYAN}Shadow-TLS 状态: ${GREEN}${SHADOW_STATUS}${RESET}"
        echo ""
        
        # 清理备份文件
        rm -f "$binary_backup" "$config_backup"
        
        return 0
    else
        log_message "ERROR" "Snell 服务启动失败"
        echo -e "${RED}=========================================${RESET}"
        echo -e "${RED}   ✗ 服务启动失败，正在回滚...${RESET}"
        echo -e "${RED}=========================================${RESET}"
        echo ""
        
        # 停止失败的服务
        systemctl stop shadow-tls-snell 2>/dev/null
        systemctl stop snell 2>/dev/null
        
        # 恢复备份
        if [ -f "$binary_backup" ]; then
            mv "$binary_backup" /usr/local/bin/snell-server
            chmod +x /usr/local/bin/snell-server
            echo -e "${GREEN}✓ 已恢复旧版本二进制文件${RESET}"
        fi
        
        if [ -f "$config_backup" ]; then
            mv "$config_backup" /etc/snell-proxy-config.txt
            echo -e "${GREEN}✓ 已恢复配置文件${RESET}"
        fi
        
        # 重启服务
        echo ""
        echo -e "${CYAN}正在重启服务...${RESET}"
        for service in "${services_stopped[@]}"; do
            systemctl start "$service"
            sleep 1
        done
        
        # 验证回滚后的状态
        sleep 2
        clear_status_cache
        get_all_service_status
        
        SNELL_STATUS="${SERVICE_STATUS_CACHE[snell]:-未运行}"
        SHADOW_STATUS="${SERVICE_STATUS_CACHE[shadow-tls-snell]:-未运行}"
        
        if [ "$SNELL_STATUS" == "active" ] && [ "$SHADOW_STATUS" == "active" ]; then
            echo -e "${GREEN}✓ 已成功回滚到旧版本${RESET}"
            echo -e "${CYAN}Snell 状态: ${GREEN}${SNELL_STATUS}${RESET}"
            echo -e "${CYAN}Shadow-TLS 状态: ${GREEN}${SHADOW_STATUS}${RESET}"
        else
            echo -e "${RED}✗ 回滚后服务仍未正常运行${RESET}"
            echo ""
            echo -e "${YELLOW}请尝试以下操作:${RESET}"
            echo -e "  1. 查看日志: ${CYAN}journalctl -u snell -n 50${RESET}"
            echo -e "  2. 查看日志: ${CYAN}journalctl -u shadow-tls-snell -n 50${RESET}"
            echo -e "  3. 手动重启: ${CYAN}systemctl restart snell shadow-tls-snell${RESET}"
            
            if [ "$backup_success" = true ]; then
                echo -e "  4. 从完整备份恢复: ${CYAN}选择菜单中的恢复选项${RESET}"
            fi
        fi
        
        echo ""
        return 1
    fi
}

# 更新 Sing-box (简化版，逻辑类似)
update_singbox() {
    if ! check_singbox_installed; then
        echo -e "${RED}Sing-box 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Sing-box${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始更新 Sing-box"

    CURRENT_VERSION=$(get_config "singbox" "SINGBOX_VERSION")
    if [ -z "$CURRENT_VERSION" ]; then
        if [ -f /etc/singbox-proxy-config.txt ]; then
            safe_source_config /etc/singbox-proxy-config.txt
            CURRENT_VERSION=$SINGBOX_VERSION
        fi
    fi

    detect_architecture

    echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '\"tag_name\":' | sed -E 's/.*\"([^\"]+)\".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        log_message "WARN" "无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION"
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION${RESET}"
        LATEST_VERSION="$DEFAULT_SINGBOX_VERSION"
    fi

    log_message "INFO" "Sing-box 版本: $LATEST_VERSION"
    echo -e "${GREEN}最新 Sing-box 版本: ${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        log_message "INFO" "Sing-box 已是最新版本"
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    log_message "INFO" "发现新版本，开始更新..."
    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    create_restore_point "singbox"

    systemctl stop sing-box

    if [ -f /usr/local/bin/sing-box ]; then
        cp /usr/local/bin/sing-box /usr/local/bin/sing-box.bak
    fi

    SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
    echo -e "${CYAN}正在下载: ${SINGBOX_DOWNLOAD_URL}${RESET}"
    log_message "INFO" "下载地址: $SINGBOX_DOWNLOAD_URL"
    
    cd /tmp || { log_message "ERROR" "无法进入 /tmp 目录"; systemctl start sing-box; return 1; }
    if ! wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz 2>"${LOG_DIR}/singbox-download.log"; then
        handle_error $? "下载 Sing-box 失败" "${LOG_DIR}/singbox-download.log"
        systemctl start sing-box
        return 1
    fi

    if ! tar -xzf sing-box.tar.gz 2>"${LOG_DIR}/singbox-extract.log"; then
        rm -rf /tmp/sing-box*
        handle_error $? "解压 Sing-box 失败" "${LOG_DIR}/singbox-extract.log"
        systemctl start sing-box
        return 1
    fi
    
    SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
    if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
        mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
    else
        echo -e "${RED}未找到 sing-box 二进制文件${RESET}"
        systemctl start sing-box
        return 1
    fi
    
    rm -rf /tmp/sing-box*

    save_config "singbox" "SINGBOX_VERSION" "$LATEST_VERSION"
    sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$LATEST_VERSION/" /etc/singbox-proxy-config.txt 2>/dev/null

    systemctl start sing-box
    
    sleep 2
    
    clear_status_cache
    get_all_service_status
    
    SINGBOX_STATUS="${SERVICE_STATUS_CACHE[sing-box]}"
    
    if [ "$SINGBOX_STATUS" == "active" ]; then
        log_message "SUCCESS" "Sing-box 更新成功"
        echo -e "${GREEN}Sing-box 更新成功！当前版本: ${LATEST_VERSION}${RESET}"
    else
        log_message "ERROR" "Sing-box 服务启动失败"
        echo -e "${RED}Sing-box 服务启动失败，正在回滚...${RESET}"
        if [ -f /usr/local/bin/sing-box.bak ]; then
            mv /usr/local/bin/sing-box.bak /usr/local/bin/sing-box
            systemctl start sing-box
            echo -e "${YELLOW}已回滚到旧版本${RESET}"
        fi
    fi
}

# 更新 Reality（逻辑同 Sing-box）
update_reality() {
    if ! check_reality_installed; then
        echo -e "${RED}Reality 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Reality${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始更新 Reality"

    CURRENT_VERSION=$(get_config "reality" "SINGBOX_VERSION")
    if [ -z "$CURRENT_VERSION" ]; then
        if [ -f /etc/reality-proxy-config.txt ]; then
            safe_source_config /etc/reality-proxy-config.txt
            CURRENT_VERSION=$SINGBOX_VERSION
        fi
    fi

    detect_architecture

    echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '\"tag_name\":' | sed -E 's/.*\"([^\"]+)\".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        log_message "WARN" "无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION"
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION${RESET}"
        LATEST_VERSION="$DEFAULT_SINGBOX_VERSION"
    fi

    log_message "INFO" "Sing-box 版本: $LATEST_VERSION"
    echo -e "${GREEN}最新 Sing-box 版本: ${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        log_message "INFO" "Reality 已是最新版本"
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    log_message "INFO" "发现新版本，开始更新..."
    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    create_restore_point "reality"

    systemctl stop sing-box-reality

    if [ -f /usr/local/bin/sing-box ]; then
        cp /usr/local/bin/sing-box /usr/local/bin/sing-box.bak
    fi

    SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
    echo -e "${CYAN}正在下载: ${SINGBOX_DOWNLOAD_URL}${RESET}"
    log_message "INFO" "下载地址: $SINGBOX_DOWNLOAD_URL"
    
    cd /tmp || { log_message "ERROR" "无法进入 /tmp 目录"; systemctl start sing-box-reality; return 1; }
    if ! wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz 2>"${LOG_DIR}/singbox-download.log"; then
        handle_error $? "下载 Sing-box 失败" "${LOG_DIR}/singbox-download.log"
        systemctl start sing-box-reality
        return 1
    fi

    if ! tar -xzf sing-box.tar.gz 2>"${LOG_DIR}/singbox-extract.log"; then
        rm -rf /tmp/sing-box*
        handle_error $? "解压 Sing-box 失败" "${LOG_DIR}/singbox-extract.log"
        systemctl start sing-box-reality
        return 1
    fi
    
    SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
    if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
        mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
    else
        echo -e "${RED}未找到 sing-box 二进制文件${RESET}"
        systemctl start sing-box-reality
        return 1
    fi
    
    rm -rf /tmp/sing-box*

    save_config "reality" "SINGBOX_VERSION" "$LATEST_VERSION"
    sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$LATEST_VERSION/" /etc/reality-proxy-config.txt 2>/dev/null

    systemctl start sing-box-reality
    
    sleep 2
    
    clear_status_cache
    get_all_service_status
    
    REALITY_STATUS="${SERVICE_STATUS_CACHE[sing-box-reality]}"
    
    if [ "$REALITY_STATUS" == "active" ]; then
        log_message "SUCCESS" "Reality 更新成功"
        echo -e "${GREEN}Reality 更新成功！当前版本: ${LATEST_VERSION}${RESET}"
    else
        log_message "ERROR" "Reality 服务启动失败"
        echo -e "${RED}Reality 服务启动失败，正在回滚...${RESET}"
        if [ -f /usr/local/bin/sing-box.bak ]; then
            mv /usr/local/bin/sing-box.bak /usr/local/bin/sing-box
            systemctl start sing-box-reality
            echo -e "${YELLOW}已回滚到旧版本${RESET}"
        fi
    fi
}

# 更新 Hysteria2（逻辑同上）
update_hysteria2() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Hysteria2${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始更新 Hysteria2"

    CURRENT_VERSION=$(get_config "hysteria2" "SINGBOX_VERSION")
    if [ -z "$CURRENT_VERSION" ]; then
        if [ -f /etc/hysteria2-proxy-config.txt ]; then
            safe_source_config /etc/hysteria2-proxy-config.txt
            CURRENT_VERSION=$SINGBOX_VERSION
        fi
    fi

    detect_architecture

    echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '\"tag_name\":' | sed -E 's/.*\"([^\"]+)\".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        log_message "WARN" "无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION"
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 $DEFAULT_SINGBOX_VERSION${RESET}"
        LATEST_VERSION="$DEFAULT_SINGBOX_VERSION"
    fi

    log_message "INFO" "Sing-box 版本: $LATEST_VERSION"
    echo -e "${GREEN}最新 Sing-box 版本: ${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        log_message "INFO" "Hysteria2 已是最新版本"
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    log_message "INFO" "发现新版本，开始更新..."
    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    create_restore_point "hysteria2"

    systemctl stop hysteria2

    if [ -f /usr/local/bin/sing-box ]; then
        cp /usr/local/bin/sing-box /usr/local/bin/sing-box.bak
    fi

    SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
    echo -e "${CYAN}正在下载: ${SINGBOX_DOWNLOAD_URL}${RESET}"
    log_message "INFO" "下载地址: $SINGBOX_DOWNLOAD_URL"
    
    cd /tmp || { log_message "ERROR" "无法进入 /tmp 目录"; systemctl start hysteria2; return 1; }
    if ! wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz 2>"${LOG_DIR}/singbox-download.log"; then
        handle_error $? "下载 Sing-box 失败" "${LOG_DIR}/singbox-download.log"
        systemctl start hysteria2
        return 1
    fi

    if ! tar -xzf sing-box.tar.gz 2>"${LOG_DIR}/singbox-extract.log"; then
        rm -rf /tmp/sing-box*
        handle_error $? "解压 Sing-box 失败" "${LOG_DIR}/singbox-extract.log"
        systemctl start hysteria2
        return 1
    fi
    
    SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
    if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
        mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
    else
        echo -e "${RED}未找到 sing-box 二进制文件${RESET}"
        systemctl start hysteria2
        return 1
    fi
    
    rm -rf /tmp/sing-box*

    save_config "hysteria2" "SINGBOX_VERSION" "$LATEST_VERSION"
    sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$LATEST_VERSION/" /etc/hysteria2-proxy-config.txt 2>/dev/null

    systemctl start hysteria2
    
    sleep 2
    
    clear_status_cache
    get_all_service_status
    
    HYSTERIA2_STATUS="${SERVICE_STATUS_CACHE[hysteria2]}"
    
    if [ "$HYSTERIA2_STATUS" == "active" ]; then
        log_message "SUCCESS" "Hysteria2 更新成功"
        echo -e "${GREEN}Hysteria2 更新成功！当前版本: ${LATEST_VERSION}${RESET}"
    else
        log_message "ERROR" "Hysteria2 服务启动失败"
        echo -e "${RED}Hysteria2 服务启动失败，正在回滚...${RESET}"
        if [ -f /usr/local/bin/sing-box.bak ]; then
            mv /usr/local/bin/sing-box.bak /usr/local/bin/sing-box
            systemctl start hysteria2
            echo -e "${YELLOW}已回滚到旧版本${RESET}"
        fi
    fi
}

# 更新所有服务
update_all() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新所有服务${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始更新所有服务"

    if check_snell_installed; then
        update_snell
        echo ""
    fi

    if check_singbox_installed; then
        update_singbox
        echo ""
    fi

    if check_reality_installed; then
        update_reality
        echo ""
    fi

    if check_hysteria2_installed; then
        update_hysteria2
        echo ""
    fi

    if ! check_snell_installed && ! check_singbox_installed && ! check_reality_installed && ! check_hysteria2_installed; then
        echo -e "${RED}没有已安装的服务${RESET}"
    else
        log_message "SUCCESS" "所有服务更新完成"
        echo -e "${GREEN}✓ 所有服务已更新到最新版本${RESET}"
    fi
}
# =========================================
# 卸载函数（修复版 - 完善的依赖处理和清理）
# =========================================

# 卸载 Snell + Shadow-TLS（修复版）
uninstall_snell() {
    echo -e "${YELLOW}正在卸载 Snell + Shadow-TLS...${RESET}"
    log_message "INFO" "开始卸载 Snell + Shadow-TLS"
    
    # 检查是否有依赖此服务的其他服务
    local dependent_services=$(systemctl list-dependencies --reverse snell.service 2>/dev/null | grep -v "snell.service" | grep ".service" || true)
    if [ -n "$dependent_services" ]; then
        echo -e "${YELLOW}警告: 以下服务依赖 Snell:${RESET}"
        echo "$dependent_services"
        read -p "是否继续卸载？(y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo -e "${CYAN}取消卸载${RESET}"
            return
        fi
    fi
    
    # 停止服务
    echo -e "${CYAN}停止服务...${RESET}"
    systemctl stop shadow-tls-snell 2>/dev/null
    systemctl stop snell 2>/dev/null
    
    # 等待服务完全停止
    sleep 2
    
    # 禁用服务
    systemctl disable shadow-tls-snell 2>/dev/null
    systemctl disable snell 2>/dev/null
    
    # 删除 systemd 服务文件
    rm -f /lib/systemd/system/snell.service
    rm -f /etc/systemd/system/shadow-tls-snell.service
    
    # 删除二进制文件
    rm -f /usr/local/bin/snell-server
    
    # 删除配置文件
    rm -rf /etc/snell
    rm -f /etc/snell-proxy-config.txt
    
    # 从统一配置中删除
    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq 'del(.snell)' "$CONFIG_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$CONFIG_FILE"
    fi
    
    # 清理日志文件
    echo -e "${CYAN}清理日志文件...${RESET}"
    rm -f "${LOG_DIR}/snell-"*.log
    journalctl --vacuum-time=1s --unit=snell 2>/dev/null
    journalctl --vacuum-time=1s --unit=shadow-tls-snell 2>/dev/null
    
    # 检查并删除用户
    if id -u snell > /dev/null 2>&1; then
        # 检查是否有属于该用户的运行进程
        if ps -u snell > /dev/null 2>&1; then
            echo -e "${YELLOW}警告: 检测到 snell 用户仍有运行的进程${RESET}"
            ps -u snell
            echo -e "${CYAN}正在强制终止...${RESET}"
            pkill -u snell 2>/dev/null
            sleep 1
        fi
        
        userdel snell 2>/dev/null
        echo -e "${GREEN}✓ 已删除 snell 用户${RESET}"
    fi
    
    # 重载 systemd
    systemctl daemon-reload
    
    # 更新健康检查脚本（移除 Snell 相关检查）
    if [ -f /usr/local/bin/proxy-healthcheck.sh ]; then
        echo -e "${CYAN}更新健康检查脚本...${RESET}"
        sed -i '/check_service "snell"/d' /usr/local/bin/proxy-healthcheck.sh
        sed -i '/shadow-tls-snell/d' /usr/local/bin/proxy-healthcheck.sh
    fi
    
    # 清除状态缓存
    clear_status_cache
    
    log_message "SUCCESS" "Snell + Shadow-TLS 卸载完成"
    echo -e "${GREEN}✓ Snell + Shadow-TLS 已成功卸载！${RESET}"
    echo ""
    echo -e "${CYAN}已清理的内容:${RESET}"
    echo -e "  - 服务文件"
    echo -e "  - 二进制文件"
    echo -e "  - 配置文件"
    echo -e "  - 日志文件"
    echo -e "  - 系统用户"
    echo -e "  - 健康检查配置"
    echo ""
}

# 卸载 Sing-box
uninstall_singbox() {
    echo -e "${YELLOW}正在卸载 Sing-box...${RESET}"
    log_message "INFO" "开始卸载 Sing-box"

    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null

    rm -f /lib/systemd/system/sing-box.service

    rm -rf /etc/sing-box
    rm -f /etc/singbox-proxy-config.txt

    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq 'del(.singbox)' "$CONFIG_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$CONFIG_FILE"
    fi

    rm -f "${LOG_DIR}/singbox-"*.log
    journalctl --vacuum-time=1s --unit=sing-box 2>/dev/null

    if id -u sing-box > /dev/null 2>&1; then
        if ps -u sing-box > /dev/null 2>&1; then
            pkill -u sing-box 2>/dev/null
            sleep 1
        fi
        userdel sing-box 2>/dev/null
    fi

    systemctl daemon-reload

    if [ -f /usr/local/bin/proxy-healthcheck.sh ]; then
        sed -i '/check_service "sing-box"/d' /usr/local/bin/proxy-healthcheck.sh
    fi

    clear_status_cache

    log_message "SUCCESS" "Sing-box 卸载完成"
    echo -e "${GREEN}✓ Sing-box 已成功卸载！${RESET}"
}

# 卸载 Reality
uninstall_reality() {
    echo -e "${YELLOW}正在卸载 VLESS Reality...${RESET}"
    log_message "INFO" "开始卸载 VLESS Reality"

    systemctl stop sing-box-reality 2>/dev/null
    systemctl disable sing-box-reality 2>/dev/null

    rm -f /lib/systemd/system/sing-box-reality.service

    rm -rf /etc/sing-box-reality
    rm -f /etc/reality-proxy-config.txt

    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq 'del(.reality)' "$CONFIG_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$CONFIG_FILE"
    fi

    rm -f "${LOG_DIR}/reality-"*.log
    journalctl --vacuum-time=1s --unit=sing-box-reality 2>/dev/null

    if id -u sing-box-reality > /dev/null 2>&1; then
        if ps -u sing-box-reality > /dev/null 2>&1; then
            pkill -u sing-box-reality 2>/dev/null
            sleep 1
        fi
        userdel sing-box-reality 2>/dev/null
    fi

    systemctl daemon-reload

    if [ -f /usr/local/bin/proxy-healthcheck.sh ]; then
        sed -i '/check_service "sing-box-reality"/d' /usr/local/bin/proxy-healthcheck.sh
    fi

    clear_status_cache

    log_message "SUCCESS" "Reality 卸载完成"
    echo -e "${GREEN}✓ VLESS Reality 已成功卸载！${RESET}"
}

# 卸载 Hysteria2
uninstall_hysteria2() {
    echo -e "${YELLOW}正在卸载 Hysteria2...${RESET}"
    log_message "INFO" "开始卸载 Hysteria2"

    if [ -f /etc/hysteria2-proxy-config.txt ]; then
        safe_source_config /etc/hysteria2-proxy-config.txt
        
        if [ "$CERT_TYPE" == "letsencrypt" ]; then
            echo ""
            read -p "是否同时删除 Let's Encrypt 证书？(y/n): " remove_cert
            if [ "$remove_cert" == "y" ] || [ "$remove_cert" == "Y" ]; then
                if [ -n "$HYSTERIA2_DOMAIN" ]; then
                    echo -e "${CYAN}正在删除域名 ${YELLOW}${HYSTERIA2_DOMAIN}${CYAN} 的证书...${RESET}"
                    ~/.acme.sh/acme.sh --remove -d "$HYSTERIA2_DOMAIN" --ecc 2>/dev/null
                    echo -e "${GREEN}✓ 证书已删除${RESET}"
                fi
            fi
        fi
    fi

    systemctl stop hysteria2 2>/dev/null
    systemctl disable hysteria2 2>/dev/null

    rm -f /lib/systemd/system/hysteria2.service

    rm -rf /etc/hysteria2
    rm -f /etc/hysteria2-proxy-config.txt

    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq 'del(.hysteria2)' "$CONFIG_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$CONFIG_FILE"
    fi

    rm -f "${LOG_DIR}/hysteria2-"*.log
    journalctl --vacuum-time=1s --unit=hysteria2 2>/dev/null

    if id -u hysteria2 > /dev/null 2>&1; then
        if ps -u hysteria2 > /dev/null 2>&1; then
            pkill -u hysteria2 2>/dev/null
            sleep 1
        fi
        userdel hysteria2 2>/dev/null
    fi

    systemctl daemon-reload

    if [ -f /usr/local/bin/proxy-healthcheck.sh ]; then
        sed -i '/check_service "hysteria2"/d' /usr/local/bin/proxy-healthcheck.sh
    fi

    clear_status_cache

    log_message "SUCCESS" "Hysteria2 卸载完成"
    echo -e "${GREEN}✓ Hysteria2 已成功卸载！${RESET}"
}

# 卸载所有服务（修复版 - 增加备份选项）
uninstall_all() {
    echo -e "${YELLOW}正在卸载所有服务...${RESET}"
    log_message "INFO" "开始卸载所有服务"
    
    echo -e "${RED}警告: 这将删除所有已安装的代理服务和相关配置${RESET}"
    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${CYAN}取消卸载${RESET}"
        return
    fi
    
    # 按依赖顺序卸载
    local services_to_uninstall=()
    
    if check_snell_installed; then
        services_to_uninstall+=("snell")
    fi
    
    if check_singbox_installed; then
        services_to_uninstall+=("singbox")
    fi
    
    if check_reality_installed; then
        services_to_uninstall+=("reality")
    fi
    
    if check_hysteria2_installed; then
        services_to_uninstall+=("hysteria2")
    fi
    
    if [ ${#services_to_uninstall[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有已安装的服务${RESET}"
        return
    fi
    
    echo -e "${CYAN}将卸载以下服务: ${YELLOW}${services_to_uninstall[*]}${RESET}"
    echo ""
    
    # 创建备份
    echo -e "${CYAN}是否创建配置备份？(y/n): ${RESET}"
    read -p "" create_backup
    if [ "$create_backup" == "y" ] || [ "$create_backup" == "Y" ]; then
        local backup_file="/tmp/proxy-config-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        echo -e "${CYAN}正在创建备份: $backup_file${RESET}"
        tar -czf "$backup_file" \
            /etc/snell* \
            /etc/sing-box* \
            /etc/reality* \
            /etc/hysteria2* \
            "$CONFIG_FILE" \
            2>/dev/null || true
        echo -e "${GREEN}✓ 备份已创建: $backup_file${RESET}"
        echo ""
    fi
    
    # 依次卸载
    for service in "${services_to_uninstall[@]}"; do
        case $service in
            snell)
                uninstall_snell
                ;;
            singbox)
                uninstall_singbox
                ;;
            reality)
                uninstall_reality
                ;;
            hysteria2)
                uninstall_hysteria2
                ;;
        esac
        echo ""
    done
    
    # 清理共享资源
    echo -e "${CYAN}清理共享资源...${RESET}"
    
    # 删除共享二进制文件
    if ! check_snell_installed && ! check_singbox_installed && ! check_reality_installed && ! check_hysteria2_installed; then
        rm -f /usr/local/bin/shadow-tls
        rm -f /usr/local/bin/sing-box
        echo -e "${GREEN}✓ 已删除共享二进制文件${RESET}"
        
        # 删除健康检查
        rm -f /usr/local/bin/proxy-healthcheck.sh
        crontab -l 2>/dev/null | grep -v "proxy-healthcheck.sh" | crontab - 2>/dev/null
        echo -e "${GREEN}✓ 已删除健康检查脚本${RESET}"
        
        # 清理日志目录
        rm -rf "${LOG_DIR}"
        echo -e "${GREEN}✓ 已清理日志目录${RESET}"
        
        # 清理配置目录
        rm -rf "${CONFIG_DIR}"
        echo -e "${GREEN}✓ 已清理配置目录${RESET}"
        
        # 清理备份目录
        if [ -d "$BACKUP_DIR" ]; then
            echo -e "${YELLOW}备份目录: $BACKUP_DIR${RESET}"
            read -p "是否删除备份目录？(y/n): " remove_backup
            if [ "$remove_backup" == "y" ] || [ "$remove_backup" == "Y" ]; then
                rm -rf "$BACKUP_DIR"
                echo -e "${GREEN}✓ 已删除备份目录${RESET}"
            fi
        fi
        
        # 询问是否卸载 acme.sh
        if [ -d ~/.acme.sh ]; then
            echo ""
            read -p "是否卸载 acme.sh？(y/n): " remove_acme
            if [ "$remove_acme" == "y" ] || [ "$remove_acme" == "Y" ]; then
                ~/.acme.sh/acme.sh --uninstall 2>/dev/null
                rm -rf ~/.acme.sh
                echo -e "${GREEN}✓ acme.sh 已卸载${RESET}"
            fi
        fi
    fi
    
    log_message "SUCCESS" "所有服务卸载完成"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   所有服务已成功卸载！${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
}

# =========================================
# 查看配置函数（修复版 - 增加安全性）
# =========================================

# 密码显示控制函数
mask_sensitive_info() {
    local value=$1
    local show_full=${2:-false}
    
    if [ "$show_full" = true ]; then
        echo "$value"
    else
        local len=${#value}
        if [ $len -le 8 ]; then
            echo "****"
        else
            echo "${value:0:4}****${value: -4}"
        fi
    fi
}

# 查看 Snell 配置（修复版 - 增加安全性）
view_snell_config() {
    if [ ! -f /etc/snell-proxy-config.txt ]; then
        echo -e "${RED}未找到 Snell 配置文件。请先安装 Snell 服务。${RESET}"
        return
    fi

    # 安全地读取配置
    local SERVER_IP SNELL_VERSION SNELL_PORT SNELL_PSK SHADOW_TLS_PORT SHADOW_TLS_PASSWORD TLS_DOMAIN IP_VERSION
    
    while IFS='=' read -r key value; do
        case $key in
            SERVER_IP) SERVER_IP=$value ;;
            SNELL_VERSION) SNELL_VERSION=$value ;;
            SNELL_PORT) SNELL_PORT=$value ;;
            SNELL_PSK) SNELL_PSK=$value ;;
            SHADOW_TLS_PORT) SHADOW_TLS_PORT=$value ;;
            SHADOW_TLS_PASSWORD) SHADOW_TLS_PASSWORD=$value ;;
            TLS_DOMAIN) TLS_DOMAIN=$value ;;
            IP_VERSION) IP_VERSION=$value ;;
        esac
    done < /etc/snell-proxy-config.txt

    # 获取服务状态
    SNELL_STATUS=$(systemctl is-active snell 2>/dev/null || echo "未运行")
    SHADOW_TLS_STATUS=$(systemctl is-active shadow-tls-snell 2>/dev/null || echo "未运行")

    # 检查安全配置
    if [ -f /etc/snell/snell-server.conf ]; then
        SNELL_LISTEN=$(grep "listen" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')
        if [[ $SNELL_LISTEN == 127.0.0.1:* ]]; then
            SECURITY_INFO="${GREEN}(仅本地，安全)${RESET}"
        else
            SECURITY_INFO="${RED}(公网可访问，不安全！)${RESET}"
        fi
    else
        SECURITY_INFO=""
    fi

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}      Snell + Shadow-TLS 配置信息        ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Snell 配置:${RESET}"
    echo -e "  版本: ${YELLOW}v${SNELL_VERSION}${RESET}"
    echo -e "  监听地址: ${YELLOW}${SNELL_LISTEN:-未知}${RESET} ${SECURITY_INFO}"
    echo -e "  PSK: ${YELLOW}$(mask_sensitive_info "$SNELL_PSK")${RESET}"
    echo -e "  状态: ${YELLOW}${SNELL_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  外部端口: ${YELLOW}${SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}$(mask_sensitive_info "$SHADOW_TLS_PASSWORD")${RESET}"
    echo -e "  伪装域名: ${YELLOW}${TLS_DOMAIN}${RESET}"
    echo -e "  状态: ${YELLOW}${SHADOW_TLS_STATUS}${RESET}"
    echo ""
    
    # 询问是否显示完整信息
    echo -e "${YELLOW}提示: 敏感信息已隐藏${RESET}"
    read -p "是否显示完整配置（包括密码）？(y/n): " show_full
    
    if [ "$show_full" == "y" ] || [ "$show_full" == "Y" ]; then
        echo ""
        echo -e "${RED}=========================================${RESET}"
        echo -e "${RED}   完整配置信息（包含敏感数据）${RESET}"
        echo -e "${RED}=========================================${RESET}"
        echo ""
        echo -e "${CYAN}Snell PSK:${RESET}"
        echo -e "${YELLOW}${SNELL_PSK}${RESET}"
        echo ""
        echo -e "${CYAN}Shadow-TLS 密码:${RESET}"
        echo -e "${YELLOW}${SHADOW_TLS_PASSWORD}${RESET}"
        echo ""
        echo -e "${CYAN}Surge 配置 (Snell v4):${RESET}"
        echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=4, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
        echo ""
        echo -e "${CYAN}Surge 配置 (Snell v5):${RESET}"
        echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
        echo ""
        
        # 提供复制到剪贴板的选项（如果支持）
        if command -v xclip &> /dev/null || command -v pbcopy &> /dev/null; then
            read -p "是否复制 Surge 配置到剪贴板？(y/n): " copy_config
            if [ "$copy_config" == "y" ] || [ "$copy_config" == "Y" ]; then
                local surge_config="Proxy = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3"
                
                if command -v xclip &> /dev/null; then
                    echo "$surge_config" | xclip -selection clipboard
                    echo -e "${GREEN}✓ 已复制到剪贴板${RESET}"
                elif command -v pbcopy &> /dev/null; then
                    echo "$surge_config" | pbcopy
                    echo -e "${GREEN}✓ 已复制到剪贴板${RESET}"
                fi
            fi
        fi
        
        # 安全提示
        echo ""
        echo -e "${RED}⚠️  安全提示:${RESET}"
        echo -e "${YELLOW}  - 请勿在不安全的环境中显示此信息${RESET}"
        echo -e "${YELLOW}  - 请勿截图或录屏包含密码的内容${RESET}"
        echo -e "${YELLOW}  - 如果怀疑密码泄露，请立即更换${RESET}"
        echo ""
    fi
    
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Snell 状态: ${YELLOW}systemctl status snell${RESET}"
    echo -e "  重启 Snell: ${YELLOW}systemctl restart snell${RESET}"
    echo -e "  查看 Snell 日志: ${YELLOW}journalctl -u snell -f${RESET}"
    echo -e "  查看 Shadow-TLS 状态: ${YELLOW}systemctl status shadow-tls-snell${RESET}"
    echo -e "  重启 Shadow-TLS: ${YELLOW}systemctl restart shadow-tls-snell${RESET}"
    echo -e "  查看 Shadow-TLS 日志: ${YELLOW}journalctl -u shadow-tls-snell -f${RESET}"
    echo ""
}

# 查看 Sing-box 配置（简化版，逻辑类似）
view_singbox_config() {
    if [ ! -f /etc/singbox-proxy-config.txt ]; then
        echo -e "${RED}未找到 Sing-box 配置文件。请先安装 Sing-box 服务。${RESET}"
        return
    fi

    safe_source_config /etc/singbox-proxy-config.txt

    SINGBOX_STATUS=$(systemctl is-active sing-box 2>/dev/null || echo "未运行")

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Sing-box (SS-2022 + Shadow-TLS) 配置信息   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${SINGBOX_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadowsocks-2022 配置:${RESET}"
    echo -e "  内部端口: ${YELLOW}${SS_PORT}${RESET} ${GREEN}(仅本地，安全)${RESET}"
    echo -e "  密码: ${YELLOW}$(mask_sensitive_info "$SS_PASSWORD")${RESET}"
    echo -e "  加密方式: ${YELLOW}${SS_METHOD}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  外部端口: ${YELLOW}${SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}$(mask_sensitive_info "$SHADOW_TLS_PASSWORD")${RESET}"
    echo -e "  伪装域名: ${YELLOW}${TLS_DOMAIN}${RESET}"
    echo ""
    
    echo -e "${YELLOW}提示: 敏感信息已隐藏${RESET}"
    read -p "是否显示完整配置（包括密码）？(y/n): " show_full
    
    if [ "$show_full" == "y" ] || [ "$show_full" == "Y" ]; then
        echo ""
        echo -e "${CYAN}Surge 配置:${RESET}"
        echo -e "${GREEN}Proxy = ss, ${SERVER_IP}, ${SHADOW_TLS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
        echo ""
    fi
    
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Sing-box 状态: ${YELLOW}systemctl status sing-box${RESET}"
    echo -e "  重启 Sing-box: ${YELLOW}systemctl restart sing-box${RESET}"
    echo -e "  查看 Sing-box 日志: ${YELLOW}journalctl -u sing-box -f${RESET}"
    echo -e "  检查配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/sing-box/config.json${RESET}"
    echo ""
}

# 查看 Reality 配置（简化版）
view_reality_config() {
    if [ ! -f /etc/reality-proxy-config.txt ]; then
        echo -e "${RED}未找到 Reality 配置文件。请先安装 Reality 服务。${RESET}"
        return
    fi

    safe_source_config /etc/reality-proxy-config.txt

    REALITY_STATUS=$(systemctl is-active sing-box-reality 2>/dev/null || echo "未运行")

    REALITY_LINK="vless://${REALITY_UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-${SERVER_IP}"

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}      VLESS Reality 配置信息        ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${REALITY_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}VLESS Reality 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${REALITY_PORT}${RESET}"
    echo -e "  UUID: ${YELLOW}${REALITY_UUID}${RESET}"
    echo -e "  Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${RESET}"
    echo -e "  Short ID: ${YELLOW}${REALITY_SHORT_ID}${RESET}"
    echo -e "  目标网站: ${YELLOW}${REALITY_DEST}${RESET}"
    echo -e "  Flow: ${YELLOW}xtls-rprx-vision${RESET}"
    echo ""
    
    read -p "是否显示分享链接和二维码？(y/n): " show_share
    
    if [ "$show_share" == "y" ] || [ "$show_share" == "Y" ]; then
        echo ""
        echo -e "${CYAN}分享链接:${RESET}"
        echo -e "${GREEN}${REALITY_LINK}${RESET}"
        echo ""
        echo -e "${CYAN}二维码:${RESET}"
        qrencode -t ANSIUTF8 "$REALITY_LINK" 2>/dev/null || echo -e "${YELLOW}qrencode 未安装，无法显示二维码${RESET}"
        echo ""
    fi
    
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Reality 状态: ${YELLOW}systemctl status sing-box-reality${RESET}"
    echo -e "  重启 Reality: ${YELLOW}systemctl restart sing-box-reality${RESET}"
    echo -e "  查看 Reality 日志: ${YELLOW}journalctl -u sing-box-reality -f${RESET}"
    echo -e "  检查配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/sing-box-reality/config.json${RESET}"
    echo ""
}
# 查看 Hysteria2 配置
view_hysteria2_config() {
    if [ ! -f /etc/hysteria2-proxy-config.txt ]; then
        echo -e "${RED}未找到 Hysteria2 配置文件。请先安装 Hysteria2 服务。${RESET}"
        return
    fi

    safe_source_config /etc/hysteria2-proxy-config.txt

    HYSTERIA2_STATUS=$(systemctl is-active hysteria2 2>/dev/null || echo "未运行")

    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        if [ "$ENABLE_OBFS" = "true" ]; then
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
        else
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
        fi
    else
        if [ "$ENABLE_OBFS" = "true" ]; then
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${SERVER_IP}:${HYSTERIA2_PORT}?insecure=1&obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=bing.com#Hysteria2-${SERVER_IP}"
        else
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${SERVER_IP}:${HYSTERIA2_PORT}?insecure=1&sni=bing.com#Hysteria2-${SERVER_IP}"
        fi
    fi

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}      Hysteria2 配置信息        ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo -e "  域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    fi
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${HYSTERIA2_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Hysteria2 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${HYSTERIA2_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}$(mask_sensitive_info "$HYSTERIA2_PASSWORD")${RESET}"
    if [ "$ENABLE_OBFS" = "true" ]; then
        echo -e "  混淆: ${GREEN}已启用 (salamander)${RESET}"
        echo -e "  混淆密码: ${YELLOW}$(mask_sensitive_info "$OBFS_PASSWORD")${RESET}"
    else
        echo -e "  混淆: ${YELLOW}未启用${RESET}"
    fi
    
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo -e "  TLS: ${GREEN}Let's Encrypt 证书 (自动续签)${RESET}"
    else
        echo -e "  TLS: ${YELLOW}自签名证书${RESET}"
    fi
    echo ""
    
    echo -e "${YELLOW}提示: 敏感信息已隐藏${RESET}"
    read -p "是否显示完整配置（包括密码和分享链接）？(y/n): " show_full
    
    if [ "$show_full" == "y" ] || [ "$show_full" == "Y" ]; then
        echo ""
        echo -e "${RED}=========================================${RESET}"
        echo -e "${RED}   完整配置信息（包含敏感数据）${RESET}"
        echo -e "${RED}=========================================${RESET}"
        echo ""
        echo -e "${CYAN}Hysteria2 密码:${RESET}"
        echo -e "${YELLOW}${HYSTERIA2_PASSWORD}${RESET}"
        echo ""
        if [ "$ENABLE_OBFS" = "true" ]; then
            echo -e "${CYAN}混淆密码:${RESET}"
            echo -e "${YELLOW}${OBFS_PASSWORD}${RESET}"
            echo ""
        fi
        echo -e "${CYAN}分享链接:${RESET}"
        echo -e "${GREEN}${HYSTERIA2_LINK}${RESET}"
        echo ""
        echo -e "${CYAN}二维码:${RESET}"
        qrencode -t ANSIUTF8 "$HYSTERIA2_LINK" 2>/dev/null || echo -e "${YELLOW}qrencode 未安装，无法显示二维码${RESET}"
        echo ""
        echo -e "${CYAN}Surge 配置:${RESET}"
        if [ "$CERT_TYPE" == "letsencrypt" ]; then
            if [ "$ENABLE_OBFS" = "true" ]; then
                echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
            else
                echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}${RESET}"
            fi
        else
            if [ "$ENABLE_OBFS" = "true" ]; then
                echo -e "${GREEN}Proxy = hysteria2, ${SERVER_IP}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, skip-cert-verify=true, sni=bing.com, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
            else
                echo -e "${GREEN}Proxy = hysteria2, ${SERVER_IP}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, skip-cert-verify=true, sni=bing.com${RESET}"
            fi
        fi
        echo ""
        
        # 安全提示
        echo -e "${RED}⚠️  安全提示:${RESET}"
        echo -e "${YELLOW}  - 请勿在不安全的环境中显示此信息${RESET}"
        echo -e "${YELLOW}  - 请勿截图或录屏包含密码的内容${RESET}"
        echo -e "${YELLOW}  - 如果怀疑密码泄露，请立即更换${RESET}"
        echo ""
    fi
    
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Hysteria2 状态: ${YELLOW}systemctl status hysteria2${RESET}"
    echo -e "  重启 Hysteria2: ${YELLOW}systemctl restart hysteria2${RESET}"
    echo -e "  查看 Hysteria2 日志: ${YELLOW}journalctl -u hysteria2 -f${RESET}"
    echo -e "  检查配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/hysteria2/config.json${RESET}"
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo ""
        echo -e "${CYAN}证书管理命令:${RESET}"
        echo -e "  查看证书状态: ${YELLOW}选择菜单选项 23${RESET}"
        echo -e "  手动续签证书: ${YELLOW}选择菜单选项 22${RESET}"
    fi
    echo ""
}

# 查看所有配置
view_all_config() {
    local has_config=false
    
    if check_snell_installed; then
        view_snell_config
        has_config=true
    fi
    
    if check_singbox_installed; then
        if [ "$has_config" = true ]; then
            echo ""
            echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        view_singbox_config
        has_config=true
    fi
    
    if check_reality_installed; then
        if [ "$has_config" = true ]; then
            echo ""
            echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        view_reality_config
        has_config=true
    fi
    
    if check_hysteria2_installed; then
        if [ "$has_config" = true ]; then
            echo ""
            echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        view_hysteria2_config
        has_config=true
    fi
    
    if [ "$has_config" = false ]; then
        echo -e "${RED}未找到任何配置文件。请先安装代理服务。${RESET}"
    fi
}

# 查看服务日志
view_logs() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择要查看的日志${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    local options=()
    local services=()
    
    if check_snell_installed; then
        options+=("1. Snell 服务日志")
        services+=("snell")
        options+=("2. Shadow-TLS (Snell) 服务日志")
        services+=("shadow-tls-snell")
    fi
    
    if check_singbox_installed; then
        local num=$((${#options[@]} + 1))
        options+=("$num. Sing-box 服务日志")
        services+=("sing-box")
    fi
    
    if check_reality_installed; then
        local num=$((${#options[@]} + 1))
        options+=("$num. Reality 服务日志")
        services+=("sing-box-reality")
    fi
    
    if check_hysteria2_installed; then
        local num=$((${#options[@]} + 1))
        options+=("$num. Hysteria2 服务日志")
        services+=("hysteria2")
    fi
    
    if [ ${#options[@]} -eq 0 ]; then
        echo -e "${RED}没有已安装的服务${RESET}"
        return
    fi
    
    for opt in "${options[@]}"; do
        echo -e "${YELLOW}$opt${RESET}"
    done
    
    local health_num=$((${#options[@]} + 1))
    echo -e "${YELLOW}$health_num. 健康检查日志${RESET}"
    echo -e "${YELLOW}0. 返回主菜单${RESET}"
    echo ""
    
    read -p "请选择 [0-$health_num]: " log_choice
    
    case $log_choice in
        0)
            return
            ;;
        $health_num)
            if [ -f /var/log/proxy-manager/healthcheck.log ]; then
                echo -e "${CYAN}显示最近 50 行健康检查日志 (Ctrl+C 退出):${RESET}"
                tail -n 50 /var/log/proxy-manager/healthcheck.log
            else
                echo -e "${RED}健康检查日志文件不存在${RESET}"
            fi
            ;;
        *)
            if [ "$log_choice" -ge 1 ] && [ "$log_choice" -le ${#services[@]} ]; then
                local service="${services[$((log_choice-1))]}"
                echo -e "${CYAN}显示 $service 服务日志 (Ctrl+C 退出):${RESET}"
                journalctl -u "$service" -n 50 --no-pager
                echo ""
                read -p "是否实时查看日志？(y/n): " realtime
                if [ "$realtime" == "y" ] || [ "$realtime" == "Y" ]; then
                    journalctl -u "$service" -f
                fi
            else
                echo -e "${RED}无效的选择${RESET}"
            fi
            ;;
    esac
}

# =========================================
# 主程序和菜单输入处理
# =========================================

# 🆕 新增：输入验证函数
read_menu_choice() {
    local prompt=$1
    local min=$2
    local max=$3
    local timeout=${4:-0}  # 0 表示无超时
    
    local choice
    
    while true; do
        if [ $timeout -gt 0 ]; then
            read -t $timeout -p "$prompt" choice
            local read_status=$?
            
            if [ $read_status -eq 142 ]; then
                # 超时
                echo ""
                echo -e "${YELLOW}输入超时，返回主菜单${RESET}"
                return 255
            elif [ $read_status -ne 0 ]; then
                # 读取错误
                return 1
            fi
        else
            read -p "$prompt" choice
        fi
        
        # 处理空输入
        if [ -z "$choice" ]; then
            echo -e "${YELLOW}输入不能为空，请重新输入${RESET}"
            continue
        fi
        
        # 验证是否为数字
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}无效输入，请输入数字 [$min-$max]${RESET}"
            continue
        fi
        
        # 验证范围
        if [ "$choice" -lt "$min" ] || [ "$choice" -gt "$max" ]; then
            echo -e "${RED}输入超出范围，请输入 [$min-$max]${RESET}"
            continue
        fi
        
        echo "$choice"
        return 0
    done
}

# 信号处理
cleanup_on_exit() {
    local exit_code=$?
    
    echo ""
    echo -e "${YELLOW}正在清理...${RESET}"
    
    # 清理临时文件
    rm -f /tmp/snell-*.bak.$$ 2>/dev/null
    rm -f /tmp/proxy-*.tmp.$$ 2>/dev/null
    
    # 如果有未完成的安装，提示用户
    if [ -f /tmp/.proxy-install-in-progress ]; then
        echo -e "${RED}检测到未完成的安装${RESET}"
        echo -e "${YELLOW}建议检查服务状态：systemctl status snell sing-box hysteria2${RESET}"
        rm -f /tmp/.proxy-install-in-progress
    fi
    
    log_message "INFO" "脚本退出，退出码: $exit_code"
    
    exit $exit_code
}

# 中断信号处理
handle_interrupt() {
    echo ""
    echo -e "${YELLOW}检测到中断信号 (Ctrl+C)${RESET}"
    
    # 如果正在安装，询问是否继续
    if [ -f /tmp/.proxy-install-in-progress ]; then
        echo -e "${RED}警告: 安装过程被中断${RESET}"
        read -t 10 -p "是否要清理并退出？(y/n，10秒后自动退出): " cleanup_choice
        
        if [ "$cleanup_choice" == "y" ] || [ "$cleanup_choice" == "Y" ] || [ -z "$cleanup_choice" ]; then
            cleanup_on_exit
        else
            echo -e "${YELLOW}继续运行...${RESET}"
            return
        fi
    else
        cleanup_on_exit
    fi
}

# 初始化全局变量
init_global_vars() {
    # 系统信息
    declare -g SERVER_IP=""
    declare -g IP_VERSION=""
    declare -g ARCH=""
    
    # Snell 相关
    declare -g SNELL_VERSION=""
    declare -g SNELL_PORT=""
    declare -g SNELL_PSK=""
    declare -g SNELL_ARCH=""
    
    # Shadow-TLS 相关
    declare -g SHADOW_TLS_VERSION=""
    declare -g SNELL_SHADOW_TLS_PORT=""
    declare -g SNELL_SHADOW_TLS_PASSWORD=""
    declare -g SNELL_TLS_DOMAIN=""
    declare -g SHADOW_TLS_ARCH=""
    
    # Sing-box 相关
    declare -g SINGBOX_VERSION=""
    declare -g SINGBOX_ARCH=""
    declare -g SS_PORT=""
    declare -g SS_METHOD=""
    declare -g SS_PASSWORD=""
    declare -g SINGBOX_SHADOW_TLS_PORT=""
    declare -g SINGBOX_SHADOW_TLS_PASSWORD=""
    declare -g SINGBOX_TLS_DOMAIN=""
    
    # Reality 相关
    declare -g REALITY_PORT=""
    declare -g REALITY_UUID=""
    declare -g REALITY_PRIVATE_KEY=""
    declare -g REALITY_PUBLIC_KEY=""
    declare -g REALITY_SHORT_ID=""
    declare -g REALITY_DEST=""
    
    # Hysteria2 相关
    declare -g HYSTERIA2_PORT=""
    declare -g HYSTERIA2_PASSWORD=""
    declare -g HYSTERIA2_DOMAIN=""
    declare -g HYSTERIA2_ARCH=""
    declare -g ENABLE_OBFS=false
    declare -g OBFS_PASSWORD=""
}

# 主程序
main() {
    # 设置信号处理
    trap handle_interrupt INT TERM
    trap cleanup_on_exit EXIT
    
    # 初始化全局变量
    init_global_vars
    
    # 检查 root 权限
    check_root
    
    # 显示欢迎信息
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   代理服务管理脚本 v2.3${RESET}"
    echo -e "${GREEN}   (完整修复版 - 已修复 cron/cronie 问题)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    # 检查系统兼容性
    if ! command -v systemctl &> /dev/null; then
        echo -e "${RED}错误: 此脚本需要 systemd 支持${RESET}"
        exit 1
    fi
    
    # 主循环
    local consecutive_errors=0
    local max_errors=3
    
    while true; do
        show_menu
        
        local choice
        choice=$(read_menu_choice "请选择操作 [0-23]: " 0 23)
        local read_status=$?
        
        if [ $read_status -eq 255 ]; then
            # 超时，继续循环
            continue
        elif [ $read_status -ne 0 ]; then
            # 读取错误
            consecutive_errors=$((consecutive_errors + 1))
            if [ $consecutive_errors -ge $max_errors ]; then
                echo -e "${RED}连续读取错误，退出脚本${RESET}"
                exit 1
            fi
            continue
        fi
        
        # 重置错误计数
        consecutive_errors=0
        
        case $choice in
            0)
                echo ""
                echo -e "${GREEN}感谢使用，再见！${RESET}"
                exit 0
                ;;
            1)
                touch /tmp/.proxy-install-in-progress
                install_snell
                rm -f /tmp/.proxy-install-in-progress
                ;;
            2)
                touch /tmp/.proxy-install-in-progress
                install_singbox
                rm -f /tmp/.proxy-install-in-progress
                ;;
            3)
                touch /tmp/.proxy-install-in-progress
                install_reality
                rm -f /tmp/.proxy-install-in-progress
                ;;
            4)
                touch /tmp/.proxy-install-in-progress
                install_hysteria2
                rm -f /tmp/.proxy-install-in-progress
                ;;
            5)
                update_snell
                ;;
            6)
                update_singbox
                ;;
            7)
                update_reality
                ;;
            8)
                update_hysteria2
                ;;
            9)
                update_all
                ;;
            10)
                view_service_status
                ;;
            11)
                if ! check_snell_installed; then
                    echo -e "${RED}Snell 未安装${RESET}"
                else
                    echo ""
                    echo -e "${YELLOW}警告: 即将卸载 Snell + Shadow-TLS${RESET}"
                    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
                    if [ "$confirm" == "yes" ]; then
                        uninstall_snell
                    else
                        echo -e "${CYAN}取消卸载${RESET}"
                    fi
                fi
                ;;
            12)
                if ! check_singbox_installed; then
                    echo -e "${RED}Sing-box 未安装${RESET}"
                else
                    echo ""
                    echo -e "${YELLOW}警告: 即将卸载 Sing-box${RESET}"
                    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
                    if [ "$confirm" == "yes" ]; then
                        uninstall_singbox
                    else
                        echo -e "${CYAN}取消卸载${RESET}"
                    fi
                fi
                ;;
            13)
                if ! check_reality_installed; then
                    echo -e "${RED}Reality 未安装${RESET}"
                else
                    echo ""
                    echo -e "${YELLOW}警告: 即将卸载 VLESS Reality${RESET}"
                    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
                    if [ "$confirm" == "yes" ]; then
                        uninstall_reality
                    else
                        echo -e "${CYAN}取消卸载${RESET}"
                    fi
                fi
                ;;
            14)
                if ! check_hysteria2_installed; then
                    echo -e "${RED}Hysteria2 未安装${RESET}"
                else
                    echo ""
                    echo -e "${YELLOW}警告: 即将卸载 Hysteria2${RESET}"
                    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
                    if [ "$confirm" == "yes" ]; then
                        uninstall_hysteria2
                    else
                        echo -e "${CYAN}取消卸载${RESET}"
                    fi
                fi
                ;;
            15)
                echo ""
                echo -e "${RED}警告: 即将卸载所有服务${RESET}"
                read -p "确定要继续吗？(输入 'YES' 确认): " confirm
                if [ "$confirm" == "YES" ]; then
                    uninstall_all
                else
                    echo -e "${CYAN}取消卸载${RESET}"
                fi
                ;;
            16)
                view_snell_config
                ;;
            17)
                view_singbox_config
                ;;
            18)
                view_reality_config
                ;;
            19)
                view_hysteria2_config
                ;;
            20)
                view_all_config
                ;;
            21)
                view_logs
                ;;
            22)
                renew_hysteria2_cert
                ;;
            23)
                view_cert_status
                ;;
            *)
                echo -e "${RED}无效的选项${RESET}"
                ;;
        esac
        
        echo ""
        read -t 30 -p "按回车键继续（30秒后自动继续）..." || true
        echo ""
    done
}

# 运行主程序
main "$@"
