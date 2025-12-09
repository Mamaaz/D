#!/bin/bash
# =========================================
# Proxy Manager - Outbound Library
# 落地代理管理：SS/Hysteria2/VLESS 配置
# =========================================

# 防止重复加载
[[ -n "${_OUTBOUND_LOADED:-}" ]] && return 0
_OUTBOUND_LOADED=1

# =========================================
# 配置路径
# =========================================
UNIFIED_CONFIG_DIR="${UNIFIED_CONFIG_DIR:-/etc/unified-singbox}"
OUTBOUNDS_FILE="$UNIFIED_CONFIG_DIR/outbounds.json"

# =========================================
# 初始化出口配置文件
# =========================================
init_outbounds_file() {
    if [ ! -f "$OUTBOUNDS_FILE" ]; then
        mkdir -p "$UNIFIED_CONFIG_DIR"
        cat > "$OUTBOUNDS_FILE" <<'EOF'
{
  "outbounds": [
    {"tag": "direct", "type": "direct"},
    {"tag": "block", "type": "block"}
  ],
  "auto_select": {
    "tag": "auto-select",
    "type": "urltest",
    "outbounds": [],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "3m",
    "tolerance": 50
  }
}
EOF
        chmod 600 "$OUTBOUNDS_FILE"
        log_message "INFO" "初始化出口配置文件: $OUTBOUNDS_FILE"
    fi
}

# =========================================
# 列出所有落地代理
# =========================================
list_outbounds() {
    init_outbounds_file
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}                              📡 落地代理列表                                          ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═════╦════════════════╦═══════════════╦═══════════════════════════╦══════════╦══════════╣${RESET}"
    echo -e "${CYAN}║${RESET}  #  ${CYAN}║${RESET} 标签           ${CYAN}║${RESET} 类型          ${CYAN}║${RESET} 服务器                    ${CYAN}║${RESET} 端口     ${CYAN}║${RESET} 状态     ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═════╬════════════════╬═══════════════╬═══════════════════════════╬══════════╬══════════╣${RESET}"
    
    local outbounds_count=$(jq '.outbounds | length' "$OUTBOUNDS_FILE" 2>/dev/null || echo 0)
    local idx=1
    
    for ((i=0; i<outbounds_count; i++)); do
        local tag=$(jq -r ".outbounds[$i].tag" "$OUTBOUNDS_FILE")
        local type=$(jq -r ".outbounds[$i].type" "$OUTBOUNDS_FILE")
        
        # 跳过内置出口
        [[ "$type" == "direct" || "$type" == "block" ]] && continue
        
        local server=$(jq -r ".outbounds[$i].server // \"-\"" "$OUTBOUNDS_FILE")
        local port=$(jq -r ".outbounds[$i].server_port // \"-\"" "$OUTBOUNDS_FILE")
        local enabled=$(jq -r ".outbounds[$i].enabled // true" "$OUTBOUNDS_FILE")
        
        # 类型图标
        local type_icon=""
        case $type in
            shadowsocks) type_icon="🔷 SS" ;;
            hysteria2) type_icon="🚀 Hy2" ;;
            vless) type_icon="⚡ VLESS" ;;
            *) type_icon="📍 $type" ;;
        esac
        
        # 状态
        local status_str=""
        if [ "$enabled" = "true" ]; then
            status_str="${GREEN}● 启用${RESET}"
        else
            status_str="${YELLOW}○ 禁用${RESET}"
        fi
        
        # 截断长服务器名
        local server_display="$server"
        [ ${#server} -gt 25 ] && server_display="${server:0:22}..."
        
        printf "${CYAN}║${RESET} %-3s ${CYAN}║${RESET} %-14s ${CYAN}║${RESET} %-13s ${CYAN}║${RESET} %-25s ${CYAN}║${RESET} %-8s ${CYAN}║${RESET} %-8s ${CYAN}║${RESET}\n" \
            "$idx" "$tag" "$type_icon" "$server_display" "$port" "$status_str"
        
        ((idx++))
    done
    
    if [ $idx -eq 1 ]; then
        echo -e "${CYAN}║${RESET}                           ${YELLOW}暂无落地代理配置${RESET}                                        ${CYAN}║${RESET}"
    fi
    
    echo -e "${CYAN}╚═════╩════════════════╩═══════════════╩═══════════════════════════╩══════════╩══════════╝${RESET}"
    
    # 显示自动选择组
    local auto_select_outbounds=$(jq -r '.auto_select.outbounds | join(", ")' "$OUTBOUNDS_FILE" 2>/dev/null)
    if [ -n "$auto_select_outbounds" ] && [ "$auto_select_outbounds" != "" ]; then
        echo ""
        echo -e "${CYAN}自动选择组:${RESET} $auto_select_outbounds"
    fi
    echo ""
}

# =========================================
# 添加 Shadowsocks 代理
# =========================================
add_shadowsocks() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   添加 Shadowsocks 落地代理${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    # 标签
    read -p "代理标签 (如 proxy-us): " tag
    [ -z "$tag" ] && { echo -e "${RED}标签不能为空${RESET}"; return 1; }
    
    # 检查标签是否已存在
    local exists=$(jq --arg t "$tag" '.outbounds | map(select(.tag == $t)) | length' "$OUTBOUNDS_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "${RED}标签已存在: $tag${RESET}"
        return 1
    fi
    
    # 服务器地址
    read -p "服务器地址: " server
    [ -z "$server" ] && { echo -e "${RED}服务器地址不能为空${RESET}"; return 1; }
    
    # 端口
    read -p "端口 (默认: 8388): " port
    port=${port:-8388}
    
    # 加密方式
    echo ""
    echo -e "${YELLOW}选择加密方式:${RESET}"
    echo -e "  1. 2022-blake3-aes-128-gcm ${GREEN}(推荐)${RESET}"
    echo -e "  2. 2022-blake3-aes-256-gcm"
    echo -e "  3. 2022-blake3-chacha20-poly1305"
    echo -e "  4. aes-128-gcm"
    echo -e "  5. aes-256-gcm"
    echo -e "  6. chacha20-ietf-poly1305"
    echo ""
    read -p "请选择 [1-6] (默认: 1): " method_choice
    
    local method=""
    case ${method_choice:-1} in
        1) method="2022-blake3-aes-128-gcm" ;;
        2) method="2022-blake3-aes-256-gcm" ;;
        3) method="2022-blake3-chacha20-poly1305" ;;
        4) method="aes-128-gcm" ;;
        5) method="aes-256-gcm" ;;
        6) method="chacha20-ietf-poly1305" ;;
        *) method="2022-blake3-aes-128-gcm" ;;
    esac
    
    # 密码
    read -p "密码: " password
    [ -z "$password" ] && { echo -e "${RED}密码不能为空${RESET}"; return 1; }
    
    # 构建配置
    local new_outbound=$(jq -n \
        --arg tag "$tag" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg method "$method" \
        --arg password "$password" \
        '{
            "tag": $tag,
            "type": "shadowsocks",
            "server": $server,
            "server_port": $port,
            "method": $method,
            "password": $password,
            "enabled": true
        }')
    
    # 添加到配置
    local temp_file=$(mktemp)
    jq --argjson new "$new_outbound" '.outbounds += [$new]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
    chmod 600 "$OUTBOUNDS_FILE"
    
    # 询问是否添加到自动选择组
    read -p "是否添加到自动选择组? (y/n): " add_to_auto
    if [[ "$add_to_auto" =~ ^[Yy]$ ]]; then
        temp_file=$(mktemp)
        jq --arg tag "$tag" '.auto_select.outbounds += [$tag]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
        chmod 600 "$OUTBOUNDS_FILE"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Shadowsocks 代理添加成功${RESET}"
    echo -e "  标签: ${CYAN}$tag${RESET}"
    echo -e "  服务器: ${CYAN}$server:$port${RESET}"
    echo -e "  加密: ${CYAN}$method${RESET}"
    echo ""
}

# =========================================
# 添加 Hysteria2 代理
# =========================================
add_hysteria2() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   添加 Hysteria2 落地代理${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    # 标签
    read -p "代理标签 (如 proxy-sg): " tag
    [ -z "$tag" ] && { echo -e "${RED}标签不能为空${RESET}"; return 1; }
    
    # 检查标签是否已存在
    local exists=$(jq --arg t "$tag" '.outbounds | map(select(.tag == $t)) | length' "$OUTBOUNDS_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "${RED}标签已存在: $tag${RESET}"
        return 1
    fi
    
    # 服务器地址
    read -p "服务器地址: " server
    [ -z "$server" ] && { echo -e "${RED}服务器地址不能为空${RESET}"; return 1; }
    
    # 端口
    read -p "端口 (默认: 443): " port
    port=${port:-443}
    
    # 密码
    read -p "认证密码: " password
    [ -z "$password" ] && { echo -e "${RED}密码不能为空${RESET}"; return 1; }
    
    # TLS SNI
    read -p "TLS SNI (留空使用服务器地址): " sni
    sni=${sni:-$server}
    
    # 是否跳过证书验证
    read -p "跳过证书验证? (y/n, 默认: n): " insecure
    local insecure_bool=false
    [[ "$insecure" =~ ^[Yy]$ ]] && insecure_bool=true
    
    # 构建配置
    local new_outbound=$(jq -n \
        --arg tag "$tag" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg password "$password" \
        --arg sni "$sni" \
        --argjson insecure "$insecure_bool" \
        '{
            "tag": $tag,
            "type": "hysteria2",
            "server": $server,
            "server_port": $port,
            "password": $password,
            "tls": {
                "enabled": true,
                "server_name": $sni,
                "insecure": $insecure
            },
            "enabled": true
        }')
    
    # 添加到配置
    local temp_file=$(mktemp)
    jq --argjson new "$new_outbound" '.outbounds += [$new]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
    chmod 600 "$OUTBOUNDS_FILE"
    
    # 询问是否添加到自动选择组
    read -p "是否添加到自动选择组? (y/n): " add_to_auto
    if [[ "$add_to_auto" =~ ^[Yy]$ ]]; then
        temp_file=$(mktemp)
        jq --arg tag "$tag" '.auto_select.outbounds += [$tag]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
        chmod 600 "$OUTBOUNDS_FILE"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Hysteria2 代理添加成功${RESET}"
    echo -e "  标签: ${CYAN}$tag${RESET}"
    echo -e "  服务器: ${CYAN}$server:$port${RESET}"
    echo -e "  SNI: ${CYAN}$sni${RESET}"
    echo ""
}

# =========================================
# 添加 VLESS 代理
# =========================================
add_vless() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   添加 VLESS 落地代理${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    # 标签
    read -p "代理标签 (如 proxy-jp): " tag
    [ -z "$tag" ] && { echo -e "${RED}标签不能为空${RESET}"; return 1; }
    
    # 检查标签是否已存在
    local exists=$(jq --arg t "$tag" '.outbounds | map(select(.tag == $t)) | length' "$OUTBOUNDS_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "${RED}标签已存在: $tag${RESET}"
        return 1
    fi
    
    # 服务器地址
    read -p "服务器地址: " server
    [ -z "$server" ] && { echo -e "${RED}服务器地址不能为空${RESET}"; return 1; }
    
    # 端口
    read -p "端口 (默认: 443): " port
    port=${port:-443}
    
    # UUID
    read -p "UUID: " uuid
    [ -z "$uuid" ] && { echo -e "${RED}UUID不能为空${RESET}"; return 1; }
    
    # 是否使用 Reality
    echo ""
    echo -e "${YELLOW}选择 TLS 类型:${RESET}"
    echo -e "  1. VLESS + Reality ${GREEN}(推荐)${RESET}"
    echo -e "  2. VLESS + TLS"
    echo ""
    read -p "请选择 [1-2] (默认: 1): " tls_choice
    
    local new_outbound=""
    
    if [ "${tls_choice:-1}" = "1" ]; then
        # Reality 模式
        read -p "Reality Public Key: " public_key
        [ -z "$public_key" ] && { echo -e "${RED}Public Key不能为空${RESET}"; return 1; }
        
        read -p "Short ID (可留空): " short_id
        
        # 伪装域名
        select_tls_domain "选择 Reality 伪装域名"
        local server_name="$TLS_DOMAIN"
        
        # Flow
        echo ""
        echo -e "${YELLOW}选择 Flow:${RESET}"
        echo -e "  1. xtls-rprx-vision ${GREEN}(推荐)${RESET}"
        echo -e "  2. 无"
        echo ""
        read -p "请选择 [1-2] (默认: 1): " flow_choice
        
        local flow=""
        [ "${flow_choice:-1}" = "1" ] && flow="xtls-rprx-vision"
        
        new_outbound=$(jq -n \
            --arg tag "$tag" \
            --arg server "$server" \
            --argjson port "$port" \
            --arg uuid "$uuid" \
            --arg flow "$flow" \
            --arg server_name "$server_name" \
            --arg public_key "$public_key" \
            --arg short_id "$short_id" \
            '{
                "tag": $tag,
                "type": "vless",
                "server": $server,
                "server_port": $port,
                "uuid": $uuid,
                "flow": $flow,
                "tls": {
                    "enabled": true,
                    "server_name": $server_name,
                    "utls": {
                        "enabled": true,
                        "fingerprint": "chrome"
                    },
                    "reality": {
                        "enabled": true,
                        "public_key": $public_key,
                        "short_id": $short_id
                    }
                },
                "enabled": true
            }')
    else
        # 普通 TLS 模式
        read -p "TLS SNI: " server_name
        [ -z "$server_name" ] && server_name="$server"
        
        new_outbound=$(jq -n \
            --arg tag "$tag" \
            --arg server "$server" \
            --argjson port "$port" \
            --arg uuid "$uuid" \
            --arg server_name "$server_name" \
            '{
                "tag": $tag,
                "type": "vless",
                "server": $server,
                "server_port": $port,
                "uuid": $uuid,
                "tls": {
                    "enabled": true,
                    "server_name": $server_name
                },
                "enabled": true
            }')
    fi
    
    # 添加到配置
    local temp_file=$(mktemp)
    jq --argjson new "$new_outbound" '.outbounds += [$new]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
    chmod 600 "$OUTBOUNDS_FILE"
    
    # 询问是否添加到自动选择组
    read -p "是否添加到自动选择组? (y/n): " add_to_auto
    if [[ "$add_to_auto" =~ ^[Yy]$ ]]; then
        temp_file=$(mktemp)
        jq --arg tag "$tag" '.auto_select.outbounds += [$tag]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
        chmod 600 "$OUTBOUNDS_FILE"
    fi
    
    echo ""
    echo -e "${GREEN}✓ VLESS 代理添加成功${RESET}"
    echo -e "  标签: ${CYAN}$tag${RESET}"
    echo -e "  服务器: ${CYAN}$server:$port${RESET}"
    echo ""
}

# =========================================
# 删除落地代理
# =========================================
remove_outbound() {
    init_outbounds_file
    list_outbounds
    
    echo ""
    read -p "请输入要删除的代理标签: " tag
    [ -z "$tag" ] && return 0
    
    # 检查是否为内置出口
    if [[ "$tag" == "direct" || "$tag" == "block" ]]; then
        echo -e "${RED}不能删除内置出口: $tag${RESET}"
        return 1
    fi
    
    # 检查标签是否存在
    local exists=$(jq --arg t "$tag" '.outbounds | map(select(.tag == $t)) | length' "$OUTBOUNDS_FILE")
    if [ "$exists" -eq 0 ]; then
        echo -e "${RED}代理不存在: $tag${RESET}"
        return 1
    fi
    
    read -p "确认删除代理 [$tag]? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return 0
    
    # 删除代理
    local temp_file=$(mktemp)
    jq --arg t "$tag" '
        .outbounds = [.outbounds[] | select(.tag != $t)] |
        .auto_select.outbounds = [.auto_select.outbounds[] | select(. != $t)]
    ' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
    
    chmod 600 "$OUTBOUNDS_FILE"
    
    echo -e "${GREEN}✓ 代理已删除: $tag${RESET}"
}

# =========================================
# 切换代理启用状态
# =========================================
toggle_outbound() {
    init_outbounds_file
    list_outbounds
    
    echo ""
    read -p "请输入要切换状态的代理标签: " tag
    [ -z "$tag" ] && return 0
    
    # 检查标签是否存在
    local exists=$(jq --arg t "$tag" '.outbounds | map(select(.tag == $t and .type != "direct" and .type != "block")) | length' "$OUTBOUNDS_FILE")
    if [ "$exists" -eq 0 ]; then
        echo -e "${RED}代理不存在或为内置出口: $tag${RESET}"
        return 1
    fi
    
    # 切换状态
    local temp_file=$(mktemp)
    jq --arg t "$tag" '
        .outbounds = [.outbounds[] | if .tag == $t then .enabled = (.enabled | not) else . end]
    ' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
    
    chmod 600 "$OUTBOUNDS_FILE"
    
    local new_state=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .enabled' "$OUTBOUNDS_FILE")
    if [ "$new_state" = "true" ]; then
        echo -e "${GREEN}✓ 代理已启用: $tag${RESET}"
    else
        echo -e "${YELLOW}✓ 代理已禁用: $tag${RESET}"
    fi
}

# =========================================
# 测试落地代理连接
# =========================================
test_outbound() {
    init_outbounds_file
    list_outbounds
    
    echo ""
    read -p "请输入要测试的代理标签 (或 'all' 测试所有): " tag
    [ -z "$tag" ] && return 0
    
    echo ""
    echo -e "${CYAN}正在测试代理连接...${RESET}"
    echo ""
    
    if [ "$tag" = "all" ]; then
        # 测试所有代理
        local outbounds_count=$(jq '.outbounds | length' "$OUTBOUNDS_FILE")
        
        for ((i=0; i<outbounds_count; i++)); do
            local t=$(jq -r ".outbounds[$i].tag" "$OUTBOUNDS_FILE")
            local type=$(jq -r ".outbounds[$i].type" "$OUTBOUNDS_FILE")
            
            # 跳过内置出口
            [[ "$type" == "direct" || "$type" == "block" ]] && continue
            
            local server=$(jq -r ".outbounds[$i].server" "$OUTBOUNDS_FILE")
            local port=$(jq -r ".outbounds[$i].server_port" "$OUTBOUNDS_FILE")
            
            echo -n "  测试 $t ($server:$port)... "
            
            # 简单的 TCP 连接测试
            if timeout 5 bash -c "echo >/dev/tcp/$server/$port" 2>/dev/null; then
                echo -e "${GREEN}✓ 连接成功${RESET}"
            else
                echo -e "${RED}✗ 连接失败${RESET}"
            fi
        done
    else
        # 测试单个代理
        local server=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .server' "$OUTBOUNDS_FILE")
        local port=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .server_port' "$OUTBOUNDS_FILE")
        
        if [ -z "$server" ] || [ "$server" = "null" ]; then
            echo -e "${RED}代理不存在: $tag${RESET}"
            return 1
        fi
        
        echo -n "  测试 $tag ($server:$port)... "
        
        if timeout 5 bash -c "echo >/dev/tcp/$server/$port" 2>/dev/null; then
            echo -e "${GREEN}✓ 连接成功${RESET}"
            
            # 延迟测试
            echo -n "  测量延迟... "
            local start_time=$(date +%s%N)
            timeout 5 bash -c "echo >/dev/tcp/$server/$port" 2>/dev/null
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            echo -e "${CYAN}${latency}ms${RESET}"
        else
            echo -e "${RED}✗ 连接失败${RESET}"
        fi
    fi
    
    echo ""
}

# =========================================
# 管理自动选择组
# =========================================
manage_auto_select() {
    init_outbounds_file
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   自动选择组管理${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    local current=$(jq -r '.auto_select.outbounds | join(", ")' "$OUTBOUNDS_FILE")
    echo -e "当前成员: ${YELLOW}${current:-无}${RESET}"
    echo ""
    
    echo -e "${YELLOW}1.${RESET} 添加代理到组"
    echo -e "${YELLOW}2.${RESET} 从组中移除代理"
    echo -e "${YELLOW}3.${RESET} 设置测速 URL"
    echo -e "${YELLOW}4.${RESET} 设置测速间隔"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1)
            list_outbounds
            read -p "输入要添加的代理标签: " tag
            [ -z "$tag" ] && return 0
            
            local temp_file=$(mktemp)
            jq --arg t "$tag" '.auto_select.outbounds += [$t] | .auto_select.outbounds |= unique' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
            chmod 600 "$OUTBOUNDS_FILE"
            echo -e "${GREEN}✓ 已添加: $tag${RESET}"
            ;;
        2)
            read -p "输入要移除的代理标签: " tag
            [ -z "$tag" ] && return 0
            
            local temp_file=$(mktemp)
            jq --arg t "$tag" '.auto_select.outbounds = [.auto_select.outbounds[] | select(. != $t)]' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
            chmod 600 "$OUTBOUNDS_FILE"
            echo -e "${GREEN}✓ 已移除: $tag${RESET}"
            ;;
        3)
            local current_url=$(jq -r '.auto_select.url' "$OUTBOUNDS_FILE")
            echo -e "当前 URL: ${YELLOW}$current_url${RESET}"
            read -p "输入新的测速 URL: " new_url
            [ -z "$new_url" ] && return 0
            
            local temp_file=$(mktemp)
            jq --arg u "$new_url" '.auto_select.url = $u' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
            chmod 600 "$OUTBOUNDS_FILE"
            echo -e "${GREEN}✓ 已更新${RESET}"
            ;;
        4)
            local current_interval=$(jq -r '.auto_select.interval' "$OUTBOUNDS_FILE")
            echo -e "当前间隔: ${YELLOW}$current_interval${RESET}"
            read -p "输入新的间隔 (如 3m, 5m, 1h): " new_interval
            [ -z "$new_interval" ] && return 0
            
            local temp_file=$(mktemp)
            jq --arg i "$new_interval" '.auto_select.interval = $i' "$OUTBOUNDS_FILE" > "$temp_file" && mv "$temp_file" "$OUTBOUNDS_FILE"
            chmod 600 "$OUTBOUNDS_FILE"
            echo -e "${GREEN}✓ 已更新${RESET}"
            ;;
        0) return 0 ;;
    esac
}

# =========================================
# 生成 Sing-box outbounds 配置
# =========================================
generate_outbounds_config() {
    init_outbounds_file
    
    local outbounds="[]"
    local outbounds_count=$(jq '.outbounds | length' "$OUTBOUNDS_FILE")
    
    for ((i=0; i<outbounds_count; i++)); do
        local enabled=$(jq -r ".outbounds[$i].enabled // true" "$OUTBOUNDS_FILE")
        local type=$(jq -r ".outbounds[$i].type" "$OUTBOUNDS_FILE")
        
        # 内置出口始终包含
        if [[ "$type" == "direct" || "$type" == "block" ]]; then
            local outbound=$(jq ".outbounds[$i]" "$OUTBOUNDS_FILE")
            outbounds=$(echo "$outbounds" | jq --argjson o "$outbound" '. += [$o]')
            continue
        fi
        
        # 跳过禁用的代理
        [ "$enabled" != "true" ] && continue
        
        # 移除 enabled 字段并添加到输出
        local outbound=$(jq ".outbounds[$i] | del(.enabled)" "$OUTBOUNDS_FILE")
        outbounds=$(echo "$outbounds" | jq --argjson o "$outbound" '. += [$o]')
    done
    
    # 生成自动选择组
    local auto_select_outbounds=$(jq -r '.auto_select.outbounds | length' "$OUTBOUNDS_FILE")
    if [ "$auto_select_outbounds" -gt 0 ]; then
        local auto_select=$(jq '.auto_select' "$OUTBOUNDS_FILE")
        outbounds=$(echo "$outbounds" | jq --argjson a "$auto_select" '. += [$a]')
    fi
    
    echo "$outbounds"
}

# =========================================
# 落地代理管理菜单
# =========================================
outbound_menu() {
    while true; do
        init_outbounds_file
        
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                         📡 落地代理管理                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}1.${RESET} 查看代理列表                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}2.${RESET} 添加 Shadowsocks 代理                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}3.${RESET} 添加 Hysteria2 代理                                                ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}4.${RESET} 添加 VLESS 代理                                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}5.${RESET} 删除代理                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}6.${RESET} 启用/禁用代理                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}7.${RESET} 测试代理连接                                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}8.${RESET} 管理自动选择组                                                     ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}0.${RESET} 返回上级菜单                                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        
        read -p "请选择 [0-8]: " choice
        
        case $choice in
            1) list_outbounds ;;
            2) add_shadowsocks ;;
            3) add_hysteria2 ;;
            4) add_vless ;;
            5) remove_outbound ;;
            6) toggle_outbound ;;
            7) test_outbound ;;
            8) manage_auto_select ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}
