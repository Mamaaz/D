#!/bin/bash
# =========================================
# Proxy Manager - Config Library
# 配置读写函数库
# =========================================

# 防止重复加载
[[ -n "${_CONFIG_LOADED:-}" ]] && return 0
_CONFIG_LOADED=1

# =========================================
# 配置读写函数
# =========================================

# 保存单个配置项
save_config() {
    local service=$1
    local key=$2
    local value=$3
    
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
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

# 安全加载配置文件（避免执行任意代码）
safe_source_config() {
    local config_file=$1
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    while IFS='=' read -r key value || [ -n "$key" ]; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        declare -g "$key=$value" 2>/dev/null || true
    done < "$config_file"
    
    return 0
}

# 保存完整服务配置
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
        
        local jq_args=()
        for key in "${!config_array[@]}"; do
            jq_args+=(--arg "$key" "${config_array[$key]}")
        done
        
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

# =========================================
# 导出函数
# =========================================
export -f save_config
export -f get_config
export -f safe_source_config
export -f save_service_config
