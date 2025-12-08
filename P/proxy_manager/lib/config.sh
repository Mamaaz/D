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

# 保存单个配置项（使用 --arg 防止注入）
save_config() {
    local service=$1
    local key=$2
    local value=$3
    
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE" 2>/dev/null
        chmod 600 "$CONFIG_FILE" 2>/dev/null
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        chmod 600 "$temp_file"
        
        # 使用 --arg 安全传递参数，防止 jq 注入
        if jq --arg svc "$service" --arg k "$key" --arg v "$value" \
              'if .[$svc] then .[$svc][$k] = $v else . + {($svc): {($k): $v}} end' \
              "$CONFIG_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$CONFIG_FILE" 2>/dev/null
            chmod 600 "$CONFIG_FILE" 2>/dev/null
        else
            rm -f "$temp_file"
            log_message "ERROR" "保存配置失败: $service.$key"
        fi
    fi
}

# 读取配置（使用 --arg 防止注入）
get_config() {
    local service=$1
    local key=$2
    
    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        # 使用 --arg 安全传递参数
        jq -r --arg svc "$service" --arg k "$key" '.[$svc][$k] // empty' "$CONFIG_FILE" 2>/dev/null || true
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
        log_message "WARN" "配置文件不存在: $config_file"
        return 1
    fi
    
    # 验证文件权限
    local perms=$(stat -c%a "$config_file" 2>/dev/null || stat -f%Lp "$config_file" 2>/dev/null)
    if [ -n "$perms" ] && [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        log_message "WARN" "配置文件权限不安全: $config_file ($perms)"
    fi
    
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # 跳过注释和空行
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        # 清理空白字符
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # 验证 key 只包含安全字符
        if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            declare -g "$key=$value" 2>/dev/null || true
        else
            log_message "WARN" "跳过不安全的配置键: $key"
        fi
    done < "$config_file"
    
    return 0
}

# 保存完整服务配置（使用 --arg 防止注入）
save_service_config() {
    local service=$1
    shift
    local -n config_array=$1
    
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE" 2>/dev/null
        chmod 600 "$CONFIG_FILE" 2>/dev/null
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        chmod 600 "$temp_file"
        trap "rm -f '$temp_file'" RETURN
        
        # 构建 jq 参数数组
        local jq_args=(--arg svc "$service")
        for key in "${!config_array[@]}"; do
            jq_args+=(--arg "val_$key" "${config_array[$key]}")
        done
        
        # 构建 jq 表达式
        local jq_expr='. + {($svc): {'
        local first=true
        for key in "${!config_array[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                jq_expr+=','
            fi
            jq_expr+="\"$key\": \$val_$key"
        done
        jq_expr+='}}'
        
        if jq "${jq_args[@]}" "$jq_expr" "$CONFIG_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$CONFIG_FILE" 2>/dev/null
            chmod 600 "$CONFIG_FILE" 2>/dev/null
        else
            rm -f "$temp_file"
            log_message "ERROR" "保存配置失败: $service"
        fi
    fi
}

# 安全保存配置到文本文件
save_config_txt() {
    local config_file=$1
    shift
    
    # 创建临时文件
    local temp_file=$(mktemp)
    chmod 600 "$temp_file"
    
    # 写入配置
    for arg in "$@"; do
        echo "$arg" >> "$temp_file"
    done
    
    # 移动到目标位置
    mv "$temp_file" "$config_file" 2>/dev/null
    chmod 600 "$config_file" 2>/dev/null
    
    log_message "INFO" "配置已保存: $config_file"
}
