#!/bin/bash
# =========================================
# Proxy Manager - Subscriptions Library
# 远程订阅规则集管理
# =========================================

# 防止重复加载
[[ -n "${_SUBSCRIPTIONS_LOADED:-}" ]] && return 0
_SUBSCRIPTIONS_LOADED=1

# =========================================
# 配置路径
# =========================================
UNIFIED_CONFIG_DIR="${UNIFIED_CONFIG_DIR:-/etc/unified-singbox}"
SUBSCRIPTIONS_FILE="$UNIFIED_CONFIG_DIR/subscriptions.json"
RULESETS_DIR="$UNIFIED_CONFIG_DIR/rulesets"

# =========================================
# 预设订阅源 (Loyalsoldier sing-box-rules)
# =========================================
declare -A PRESET_SUBSCRIPTIONS=(
    ["reject"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/reject.srs|domain|广告拦截"
    ["proxy"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/proxy.srs|domain|代理域名"
    ["direct"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/direct.srs|domain|直连域名"
    ["gfw"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/gfw.srs|domain|GFW列表"
    ["private"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/private.srs|domain|私有网络"
    ["apple-cn"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/apple-cn.srs|domain|Apple中国"
    ["google-cn"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/google-cn.srs|domain|Google中国"
    ["telegram"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/telegram.srs|ipcidr|Telegram"
    ["telegramcidr"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/telegramcidr.srs|ipcidr|TelegramIP段"
    ["cncidr"]="https://raw.githubusercontent.com/Loyalsoldier/sing-box-rules/release/cncidr.srs|ipcidr|中国IP段"
)

# =========================================
# 初始化订阅配置文件
# =========================================
init_subscriptions_file() {
    if [ ! -f "$SUBSCRIPTIONS_FILE" ]; then
        mkdir -p "$UNIFIED_CONFIG_DIR"
        mkdir -p "$RULESETS_DIR"
        cat > "$SUBSCRIPTIONS_FILE" <<'EOF'
{
  "subscriptions": [],
  "auto_update": {
    "enabled": false,
    "interval": "1d"
  }
}
EOF
        chmod 600 "$SUBSCRIPTIONS_FILE"
        log_message "INFO" "初始化订阅配置文件: $SUBSCRIPTIONS_FILE"
    fi
    
    # 确保规则集目录存在
    mkdir -p "$RULESETS_DIR"
}

# =========================================
# 列出所有订阅
# =========================================
list_subscriptions() {
    init_subscriptions_file
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}                                    📋 远程订阅规则集                                            ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═════╦════════════════╦══════════╦═══════════════════════════════════════════════════╦══════════╣${RESET}"
    echo -e "${CYAN}║${RESET}  #  ${CYAN}║${RESET} 名称           ${CYAN}║${RESET} 类型     ${CYAN}║${RESET} URL                                               ${CYAN}║${RESET} 状态     ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═════╬════════════════╬══════════╬═══════════════════════════════════════════════════╬══════════╣${RESET}"
    
    local subs_count=$(jq '.subscriptions | length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    if [ "$subs_count" -eq 0 ]; then
        echo -e "${CYAN}║${RESET}                              ${YELLOW}暂无订阅规则集${RESET}                                                  ${CYAN}║${RESET}"
    else
        for ((i=0; i<subs_count; i++)); do
            local name=$(jq -r ".subscriptions[$i].name" "$SUBSCRIPTIONS_FILE")
            local type=$(jq -r ".subscriptions[$i].type" "$SUBSCRIPTIONS_FILE")
            local url=$(jq -r ".subscriptions[$i].url" "$SUBSCRIPTIONS_FILE")
            local enabled=$(jq -r ".subscriptions[$i].enabled // true" "$SUBSCRIPTIONS_FILE")
            local last_updated=$(jq -r ".subscriptions[$i].last_updated // \"-\"" "$SUBSCRIPTIONS_FILE")
            
            # 截断长 URL
            local url_display="$url"
            [ ${#url} -gt 49 ] && url_display="${url:0:46}..."
            
            # 状态
            local status_str=""
            if [ "$enabled" = "true" ]; then
                status_str="${GREEN}● 启用${RESET}"
            else
                status_str="${YELLOW}○ 禁用${RESET}"
            fi
            
            printf "${CYAN}║${RESET} %-3s ${CYAN}║${RESET} %-14s ${CYAN}║${RESET} %-8s ${CYAN}║${RESET} %-49s ${CYAN}║${RESET} %-8s ${CYAN}║${RESET}\n" \
                "$((i+1))" "$name" "$type" "$url_display" "$status_str"
        done
    fi
    
    echo -e "${CYAN}╚═════╩════════════════╩══════════╩═══════════════════════════════════════════════════╩══════════╝${RESET}"
    
    # 显示自动更新状态
    local auto_enabled=$(jq -r '.auto_update.enabled // false' "$SUBSCRIPTIONS_FILE" 2>/dev/null)
    local auto_interval=$(jq -r '.auto_update.interval // "1d"' "$SUBSCRIPTIONS_FILE" 2>/dev/null)
    echo ""
    echo -e "自动更新: $([ "$auto_enabled" = "true" ] && echo "${GREEN}已启用 (每 $auto_interval)${RESET}" || echo "${YELLOW}未启用${RESET}")"
    echo ""
}

# =========================================
# 添加订阅
# =========================================
add_subscription() {
    init_subscriptions_file
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   添加远程订阅规则集${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    # 订阅名称
    read -p "订阅名称 (如 my-reject): " name
    [ -z "$name" ] && { echo -e "${RED}名称不能为空${RESET}"; return 1; }
    
    # 检查名称是否已存在
    local exists=$(jq --arg n "$name" '.subscriptions | map(select(.name == $n)) | length' "$SUBSCRIPTIONS_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "${RED}订阅已存在: $name${RESET}"
        return 1
    fi
    
    # 订阅 URL
    read -p "订阅 URL: " url
    [ -z "$url" ] && { echo -e "${RED}URL不能为空${RESET}"; return 1; }
    
    # 规则类型
    echo ""
    echo -e "${YELLOW}选择规则类型:${RESET}"
    echo -e "  1. domain (域名规则)"
    echo -e "  2. ipcidr (IP 段规则)"
    echo ""
    read -p "请选择 [1-2] (默认: 1): " type_choice
    
    local rule_type=""
    case ${type_choice:-1} in
        1) rule_type="domain" ;;
        2) rule_type="ipcidr" ;;
        *) rule_type="domain" ;;
    esac
    
    # 规则格式
    echo ""
    echo -e "${YELLOW}选择规则格式:${RESET}"
    echo -e "  1. binary (.srs 格式) ${GREEN}(推荐)${RESET}"
    echo -e "  2. source (JSON 格式)"
    echo ""
    read -p "请选择 [1-2] (默认: 1): " format_choice
    
    local format=""
    case ${format_choice:-1} in
        1) format="binary" ;;
        2) format="source" ;;
        *) format="binary" ;;
    esac
    
    # 关联出口
    echo ""
    read -p "关联出口 (如 proxy, direct, block): " outbound
    outbound=${outbound:-proxy}
    
    # 描述
    read -p "描述 (可选): " description
    
    # 构建订阅配置
    local new_sub=$(jq -n \
        --arg name "$name" \
        --arg type "$rule_type" \
        --arg format "$format" \
        --arg url "$url" \
        --arg outbound "$outbound" \
        --arg desc "$description" \
        '{
            "name": $name,
            "type": $type,
            "format": $format,
            "url": $url,
            "outbound": $outbound,
            "description": $desc,
            "download_detour": "direct",
            "update_interval": "1d",
            "enabled": true
        }')
    
    # 添加到配置
    local temp_file=$(mktemp)
    jq --argjson new "$new_sub" '.subscriptions += [$new]' "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
    chmod 600 "$SUBSCRIPTIONS_FILE"
    
    echo ""
    echo -e "${GREEN}✓ 订阅添加成功${RESET}"
    echo -e "  名称: ${CYAN}$name${RESET}"
    echo -e "  类型: ${CYAN}$rule_type${RESET}"
    echo -e "  出口: ${CYAN}$outbound${RESET}"
    echo ""
    
    # 询问是否立即下载
    read -p "是否立即下载规则集? (y/n): " download_now
    if [[ "$download_now" =~ ^[Yy]$ ]]; then
        download_subscription "$name"
    fi
}

# =========================================
# 导入预设订阅
# =========================================
import_preset_subscriptions() {
    init_subscriptions_file
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   导入预设订阅规则集${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    echo -e "${YELLOW}可用的预设订阅 (Loyalsoldier sing-box-rules):${RESET}"
    echo ""
    
    local idx=1
    local preset_names=()
    for name in "${!PRESET_SUBSCRIPTIONS[@]}"; do
        local info="${PRESET_SUBSCRIPTIONS[$name]}"
        local desc=$(echo "$info" | cut -d'|' -f3)
        printf "  ${CYAN}%2d.${RESET} %-15s - %s\n" "$idx" "$name" "$desc"
        preset_names+=("$name")
        ((idx++))
    done
    
    echo ""
    echo -e "  ${CYAN}99.${RESET} 导入全部"
    echo -e "  ${CYAN} 0.${RESET} 返回"
    echo ""
    
    read -p "请选择要导入的订阅 (多个用空格分隔): " -a selections
    
    [ ${#selections[@]} -eq 0 ] && return 0
    
    for sel in "${selections[@]}"; do
        [ "$sel" = "0" ] && return 0
        
        if [ "$sel" = "99" ]; then
            # 导入全部
            for name in "${!PRESET_SUBSCRIPTIONS[@]}"; do
                import_single_preset "$name"
            done
            break
        fi
        
        # 单个导入
        local idx=$((sel - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#preset_names[@]} ]; then
            import_single_preset "${preset_names[$idx]}"
        else
            echo -e "${RED}无效选择: $sel${RESET}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓ 预设订阅导入完成${RESET}"
    echo ""
    
    # 询问是否立即下载
    read -p "是否立即下载所有规则集? (y/n): " download_now
    if [[ "$download_now" =~ ^[Yy]$ ]]; then
        update_all_subscriptions
    fi
}

# =========================================
# 导入单个预设订阅
# =========================================
import_single_preset() {
    local name=$1
    local info="${PRESET_SUBSCRIPTIONS[$name]}"
    
    [ -z "$info" ] && return 1
    
    local url=$(echo "$info" | cut -d'|' -f1)
    local type=$(echo "$info" | cut -d'|' -f2)
    local desc=$(echo "$info" | cut -d'|' -f3)
    
    # 检查是否已存在
    local exists=$(jq --arg n "$name" '.subscriptions | map(select(.name == $n)) | length' "$SUBSCRIPTIONS_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "${YELLOW}订阅已存在，跳过: $name${RESET}"
        return 0
    fi
    
    # 确定默认出口
    local outbound="proxy"
    case $name in
        reject) outbound="block" ;;
        direct|private|apple-cn|google-cn|cncidr) outbound="direct" ;;
        *) outbound="proxy" ;;
    esac
    
    # 构建订阅配置
    local new_sub=$(jq -n \
        --arg name "$name" \
        --arg type "$type" \
        --arg url "$url" \
        --arg outbound "$outbound" \
        --arg desc "$desc" \
        '{
            "name": $name,
            "type": $type,
            "format": "binary",
            "url": $url,
            "outbound": $outbound,
            "description": $desc,
            "download_detour": "direct",
            "update_interval": "1d",
            "enabled": true
        }')
    
    # 添加到配置
    local temp_file=$(mktemp)
    jq --argjson new "$new_sub" '.subscriptions += [$new]' "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
    chmod 600 "$SUBSCRIPTIONS_FILE"
    
    echo -e "${GREEN}✓ 已导入: $name${RESET}"
}

# =========================================
# 下载单个订阅规则集
# =========================================
download_subscription() {
    local name=$1
    
    local sub=$(jq --arg n "$name" '.subscriptions[] | select(.name == $n)' "$SUBSCRIPTIONS_FILE")
    
    if [ -z "$sub" ] || [ "$sub" = "null" ]; then
        echo -e "${RED}订阅不存在: $name${RESET}"
        return 1
    fi
    
    local url=$(echo "$sub" | jq -r '.url')
    local format=$(echo "$sub" | jq -r '.format // "binary"')
    
    # 确定文件扩展名
    local ext=".srs"
    [ "$format" = "source" ] && ext=".json"
    
    local output_file="$RULESETS_DIR/${name}${ext}"
    
    echo -n "  下载 $name... "
    
    if wget -q --timeout=30 --tries=3 "$url" -O "$output_file" 2>/dev/null; then
        if [ -s "$output_file" ]; then
            chmod 644 "$output_file"
            
            # 更新 last_updated
            local temp_file=$(mktemp)
            jq --arg n "$name" --arg t "$(date -Iseconds)" \
               '(.subscriptions[] | select(.name == $n)).last_updated = $t' \
               "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
            chmod 600 "$SUBSCRIPTIONS_FILE"
            
            echo -e "${GREEN}成功${RESET}"
            return 0
        else
            rm -f "$output_file"
            echo -e "${RED}失败 (文件为空)${RESET}"
            return 1
        fi
    else
        rm -f "$output_file"
        echo -e "${RED}失败${RESET}"
        return 1
    fi
}

# =========================================
# 更新所有订阅
# =========================================
update_all_subscriptions() {
    init_subscriptions_file
    
    echo ""
    echo -e "${CYAN}正在更新所有订阅规则集...${RESET}"
    echo ""
    
    local subs_count=$(jq '.subscriptions | length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    if [ "$subs_count" -eq 0 ]; then
        echo -e "${YELLOW}暂无订阅${RESET}"
        return 0
    fi
    
    local success=0
    local failed=0
    
    for ((i=0; i<subs_count; i++)); do
        local name=$(jq -r ".subscriptions[$i].name" "$SUBSCRIPTIONS_FILE")
        local enabled=$(jq -r ".subscriptions[$i].enabled // true" "$SUBSCRIPTIONS_FILE")
        
        [ "$enabled" != "true" ] && continue
        
        if download_subscription "$name"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓ 更新完成${RESET}: 成功 $success, 失败 $failed"
    echo ""
}

# =========================================
# 删除订阅
# =========================================
remove_subscription() {
    init_subscriptions_file
    list_subscriptions
    
    echo ""
    read -p "请输入要删除的订阅名称: " name
    [ -z "$name" ] && return 0
    
    # 检查是否存在
    local exists=$(jq --arg n "$name" '.subscriptions | map(select(.name == $n)) | length' "$SUBSCRIPTIONS_FILE")
    if [ "$exists" -eq 0 ]; then
        echo -e "${RED}订阅不存在: $name${RESET}"
        return 1
    fi
    
    read -p "确认删除订阅 [$name]? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return 0
    
    # 删除配置
    local temp_file=$(mktemp)
    jq --arg n "$name" '.subscriptions = [.subscriptions[] | select(.name != $n)]' "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
    chmod 600 "$SUBSCRIPTIONS_FILE"
    
    # 删除规则集文件
    rm -f "$RULESETS_DIR/${name}.srs" "$RULESETS_DIR/${name}.json" 2>/dev/null
    
    echo -e "${GREEN}✓ 订阅已删除: $name${RESET}"
}

# =========================================
# 切换订阅启用状态
# =========================================
toggle_subscription() {
    init_subscriptions_file
    list_subscriptions
    
    echo ""
    read -p "请输入要切换状态的订阅名称: " name
    [ -z "$name" ] && return 0
    
    # 检查是否存在
    local exists=$(jq --arg n "$name" '.subscriptions | map(select(.name == $n)) | length' "$SUBSCRIPTIONS_FILE")
    if [ "$exists" -eq 0 ]; then
        echo -e "${RED}订阅不存在: $name${RESET}"
        return 1
    fi
    
    # 切换状态
    local temp_file=$(mktemp)
    jq --arg n "$name" \
       '(.subscriptions[] | select(.name == $n)).enabled |= not' \
       "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
    chmod 600 "$SUBSCRIPTIONS_FILE"
    
    local new_state=$(jq -r --arg n "$name" '.subscriptions[] | select(.name == $n) | .enabled' "$SUBSCRIPTIONS_FILE")
    if [ "$new_state" = "true" ]; then
        echo -e "${GREEN}✓ 订阅已启用: $name${RESET}"
    else
        echo -e "${YELLOW}✓ 订阅已禁用: $name${RESET}"
    fi
}

# =========================================
# 编辑订阅出口
# =========================================
edit_subscription_outbound() {
    init_subscriptions_file
    list_subscriptions
    
    echo ""
    read -p "请输入要编辑的订阅名称: " name
    [ -z "$name" ] && return 0
    
    # 检查是否存在
    local current_outbound=$(jq -r --arg n "$name" '.subscriptions[] | select(.name == $n) | .outbound' "$SUBSCRIPTIONS_FILE")
    if [ -z "$current_outbound" ] || [ "$current_outbound" = "null" ]; then
        echo -e "${RED}订阅不存在: $name${RESET}"
        return 1
    fi
    
    echo -e "当前出口: ${YELLOW}$current_outbound${RESET}"
    read -p "新的出口 (direct/proxy/block/auto-select): " new_outbound
    [ -z "$new_outbound" ] && return 0
    
    # 更新出口
    local temp_file=$(mktemp)
    jq --arg n "$name" --arg o "$new_outbound" \
       '(.subscriptions[] | select(.name == $n)).outbound = $o' \
       "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
    chmod 600 "$SUBSCRIPTIONS_FILE"
    
    echo -e "${GREEN}✓ 出口已更新: $name -> $new_outbound${RESET}"
}

# =========================================
# 生成 Sing-box rule_set 配置
# =========================================
generate_ruleset_config() {
    init_subscriptions_file
    
    local rule_sets="[]"
    local subs_count=$(jq '.subscriptions | length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    for ((i=0; i<subs_count; i++)); do
        local enabled=$(jq -r ".subscriptions[$i].enabled // true" "$SUBSCRIPTIONS_FILE")
        [ "$enabled" != "true" ] && continue
        
        local name=$(jq -r ".subscriptions[$i].name" "$SUBSCRIPTIONS_FILE")
        local type=$(jq -r ".subscriptions[$i].type" "$SUBSCRIPTIONS_FILE")
        local format=$(jq -r ".subscriptions[$i].format // \"binary\"" "$SUBSCRIPTIONS_FILE")
        local url=$(jq -r ".subscriptions[$i].url" "$SUBSCRIPTIONS_FILE")
        
        # 检查本地文件是否存在
        local ext=".srs"
        [ "$format" = "source" ] && ext=".json"
        local local_file="$RULESETS_DIR/${name}${ext}"
        
        local rule_set=""
        if [ -f "$local_file" ]; then
            # 使用本地文件
            rule_set=$(jq -n \
                --arg tag "$name" \
                --arg type "$type" \
                --arg format "$format" \
                --arg path "$local_file" \
                '{
                    "tag": $tag,
                    "type": "local",
                    "format": $format,
                    "path": $path
                }')
        else
            # 使用远程 URL
            rule_set=$(jq -n \
                --arg tag "$name" \
                --arg type "$type" \
                --arg format "$format" \
                --arg url "$url" \
                '{
                    "tag": $tag,
                    "type": "remote",
                    "format": $format,
                    "url": $url,
                    "download_detour": "direct"
                }')
        fi
        
        rule_sets=$(echo "$rule_sets" | jq --argjson rs "$rule_set" '. += [$rs]')
    done
    
    echo "$rule_sets"
}

# =========================================
# 生成基于订阅的路由规则
# =========================================
generate_subscription_rules() {
    init_subscriptions_file
    
    local rules="[]"
    local subs_count=$(jq '.subscriptions | length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    for ((i=0; i<subs_count; i++)); do
        local enabled=$(jq -r ".subscriptions[$i].enabled // true" "$SUBSCRIPTIONS_FILE")
        [ "$enabled" != "true" ] && continue
        
        local name=$(jq -r ".subscriptions[$i].name" "$SUBSCRIPTIONS_FILE")
        local outbound=$(jq -r ".subscriptions[$i].outbound // \"proxy\"" "$SUBSCRIPTIONS_FILE")
        
        local rule=$(jq -n \
            --arg tag "$name" \
            --arg outbound "$outbound" \
            '{
                "rule_set": [$tag],
                "outbound": $outbound
            }')
        
        rules=$(echo "$rules" | jq --argjson r "$rule" '. += [$r]')
    done
    
    echo "$rules"
}

# =========================================
# 配置订阅自动更新
# =========================================
setup_subscription_auto_update() {
    init_subscriptions_file
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   配置订阅自动更新${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    local current_enabled=$(jq -r '.auto_update.enabled // false' "$SUBSCRIPTIONS_FILE" 2>/dev/null)
    local current_interval=$(jq -r '.auto_update.interval // "1d"' "$SUBSCRIPTIONS_FILE" 2>/dev/null)
    
    echo -e "当前状态: $([ "$current_enabled" = "true" ] && echo "${GREEN}已启用${RESET}" || echo "${RED}未启用${RESET}")"
    echo -e "更新间隔: ${YELLOW}$current_interval${RESET}"
    echo ""
    
    echo -e "${YELLOW}1.${RESET} 启用自动更新"
    echo -e "${YELLOW}2.${RESET} 禁用自动更新"
    echo -e "${YELLOW}3.${RESET} 修改更新间隔"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-3]: " choice
    
    case $choice in
        1)
            create_subscription_update_timer
            
            local temp_file=$(mktemp)
            jq '.auto_update.enabled = true' "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
            chmod 600 "$SUBSCRIPTIONS_FILE"
            
            echo -e "${GREEN}✓ 订阅自动更新已启用${RESET}"
            ;;
        2)
            systemctl stop subscription-update.timer 2>/dev/null || true
            systemctl disable subscription-update.timer 2>/dev/null || true
            
            local temp_file=$(mktemp)
            jq '.auto_update.enabled = false' "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
            chmod 600 "$SUBSCRIPTIONS_FILE"
            
            echo -e "${YELLOW}✓ 订阅自动更新已禁用${RESET}"
            ;;
        3)
            echo ""
            echo -e "${YELLOW}选择更新间隔:${RESET}"
            echo -e "  1. 每天 (1d)"
            echo -e "  2. 每12小时 (12h)"
            echo -e "  3. 每周 (7d)"
            echo ""
            read -p "请选择 [1-3]: " interval_choice
            
            local new_interval=""
            local timer_calendar=""
            case $interval_choice in
                1) new_interval="1d"; timer_calendar="daily" ;;
                2) new_interval="12h"; timer_calendar="*-*-* 00,12:00:00" ;;
                3) new_interval="7d"; timer_calendar="weekly" ;;
                *) new_interval="1d"; timer_calendar="daily" ;;
            esac
            
            local temp_file=$(mktemp)
            jq --arg i "$new_interval" '.auto_update.interval = $i' "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
            chmod 600 "$SUBSCRIPTIONS_FILE"
            
            if [ "$current_enabled" = "true" ]; then
                create_subscription_update_timer "$timer_calendar"
            fi
            
            echo -e "${GREEN}✓ 更新间隔已设置为: $new_interval${RESET}"
            ;;
        0) return 0 ;;
    esac
}

# =========================================
# 创建订阅更新定时器
# =========================================
create_subscription_update_timer() {
    local calendar=${1:-"daily"}
    
    cat > /etc/systemd/system/subscription-update.service <<EOF
[Unit]
Description=Update subscription rule sets
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'source /opt/proxy-manager/lib/common.sh && source /opt/proxy-manager/lib/subscriptions.sh && update_all_subscriptions_silent'
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/subscription-update.timer <<EOF
[Unit]
Description=Subscription Rule Sets Auto Update Timer

[Timer]
OnCalendar=$calendar
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF

    chmod 644 /etc/systemd/system/subscription-update.service
    chmod 644 /etc/systemd/system/subscription-update.timer
    
    systemctl daemon-reload
    systemctl enable subscription-update.timer
    systemctl start subscription-update.timer
    
    log_message "INFO" "已创建订阅自动更新定时器: $calendar"
}

# =========================================
# 静默更新所有订阅 (用于定时任务)
# =========================================
update_all_subscriptions_silent() {
    init_subscriptions_file
    
    local subs_count=$(jq '.subscriptions | length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    for ((i=0; i<subs_count; i++)); do
        local name=$(jq -r ".subscriptions[$i].name" "$SUBSCRIPTIONS_FILE")
        local enabled=$(jq -r ".subscriptions[$i].enabled // true" "$SUBSCRIPTIONS_FILE")
        local url=$(jq -r ".subscriptions[$i].url" "$SUBSCRIPTIONS_FILE")
        local format=$(jq -r ".subscriptions[$i].format // \"binary\"" "$SUBSCRIPTIONS_FILE")
        
        [ "$enabled" != "true" ] && continue
        
        local ext=".srs"
        [ "$format" = "source" ] && ext=".json"
        local output_file="$RULESETS_DIR/${name}${ext}"
        
        if wget -q --timeout=30 --tries=3 "$url" -O "$output_file" 2>/dev/null; then
            if [ -s "$output_file" ]; then
                chmod 644 "$output_file"
                
                local temp_file=$(mktemp)
                jq --arg n "$name" --arg t "$(date -Iseconds)" \
                   '(.subscriptions[] | select(.name == $n)).last_updated = $t' \
                   "$SUBSCRIPTIONS_FILE" > "$temp_file" && mv "$temp_file" "$SUBSCRIPTIONS_FILE"
                chmod 600 "$SUBSCRIPTIONS_FILE"
                
                log_message "INFO" "订阅更新成功: $name"
            fi
        else
            rm -f "$output_file"
            log_message "WARN" "订阅更新失败: $name"
        fi
    done
    
    # 重载服务
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl reload sing-box 2>/dev/null || true
    fi
}

# =========================================
# 订阅管理菜单
# =========================================
subscription_menu() {
    while true; do
        init_subscriptions_file
        
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                       📋 远程订阅规则集管理                                 ${CYAN}║${RESET}"
        echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}1.${RESET} 查看订阅列表                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}2.${RESET} 添加订阅                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}3.${RESET} 导入预设订阅 (Loyalsoldier)                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}4.${RESET} 更新所有订阅                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}5.${RESET} 删除订阅                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}6.${RESET} 启用/禁用订阅                                                     ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}7.${RESET} 编辑订阅出口                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}8.${RESET} 配置自动更新                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}0.${RESET} 返回上级菜单                                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        
        read -p "请选择 [0-8]: " choice
        
        case $choice in
            1) list_subscriptions ;;
            2) add_subscription ;;
            3) import_preset_subscriptions ;;
            4) update_all_subscriptions ;;
            5) remove_subscription ;;
            6) toggle_subscription ;;
            7) edit_subscription_outbound ;;
            8) setup_subscription_auto_update ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}
