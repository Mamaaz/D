#!/bin/bash
# =========================================
# Proxy Manager - Validation Library
# 输入验证函数库
# =========================================

# 防止重复加载
[[ -n "${_VALIDATION_LOADED:-}" ]] && return 0
_VALIDATION_LOADED=1

# =========================================
# 端口验证
# =========================================
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
    
    if [ "$port" -lt 1024 ] && [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}警告: 端口 $port 是特权端口，需要 root 权限${RESET}"
    fi
    
    return 0
}

# 检查端口是否占用
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
# 域名验证
# =========================================
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}错误: 域名格式不正确${RESET}"
        return 1
    fi
    return 0
}

# =========================================
# IP 验证
# =========================================
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

validate_ipv6() {
    local ip=$1
    if [[ "$ip" =~ ^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:))$ ]]; then
        return 0
    fi
    return 1
}

# =========================================
# 邮箱验证
# =========================================
validate_email() {
    local email=$1
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    
    local local_part="${email%@*}"
    local domain_part="${email#*@}"
    
    if [[ "$local_part" =~ ^\.|\.$  ]] || [[ "$local_part" =~ \.\. ]]; then
        return 1
    fi
    
    if [[ "$domain_part" =~ ^\.|\.$  ]] || [[ "$domain_part" =~ \.\. ]]; then
        return 1
    fi
    
    return 0
}

# =========================================
# 注意: 函数通过 source 加载，无需 export -f
# =========================================
