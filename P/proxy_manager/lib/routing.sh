#!/bin/bash
# =========================================
# Proxy Manager - Routing Library
# 分流规则管理：增删改查、配置生成
# =========================================

# 防止重复加载
[[ -n "${_ROUTING_LOADED:-}" ]] && return 0
_ROUTING_LOADED=1

# =========================================
# 配置路径
# =========================================
UNIFIED_CONFIG_DIR="/etc/unified-singbox"
RULES_FILE="$UNIFIED_CONFIG_DIR/rules.json"
GEOIP_FILE="$UNIFIED_CONFIG_DIR/geoip.db"
GEOSITE_FILE="$UNIFIED_CONFIG_DIR/geosite.db"

# =========================================
# 初始化规则文件
# =========================================
init_rules_file() {
    if [ ! -f "$RULES_FILE" ]; then
        mkdir -p "$UNIFIED_CONFIG_DIR"
        cat > "$RULES_FILE" <<'EOF'
{
  "rules": [
    {"priority": 1, "type": "geosite", "value": "category-ads-all", "outbound": "block", "enabled": true},
    {"priority": 2, "type": "geosite", "value": "cn", "outbound": "direct", "enabled": true},
    {"priority": 3, "type": "geoip", "value": "cn", "outbound": "direct", "enabled": true}
  ],
  "final": "auto-select"
}
EOF
        chmod 600 "$RULES_FILE"
        log_message "INFO" "初始化规则文件: $RULES_FILE"
    fi
}

# =========================================
# 列出所有规则
# =========================================
list_rules() {
    init_rules_file
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}                         📋 分流规则列表                                    ${CYAN}║${RESET}"
    echo -e "${CYAN}╠════╦═══════════╦════════════════════════════╦═══════════════╦═══════════╣${RESET}"
    echo -e "${CYAN}║${RESET} #  ${CYAN}║${RESET} 类型      ${CYAN}║${RESET} 匹配条件                   ${CYAN}║${RESET} 出口          ${CYAN}║${RESET} 状态      ${CYAN}║${RESET}"
    echo -e "${CYAN}╠════╬═══════════╬════════════════════════════╬═══════════════╬═══════════╣${RESET}"
    
    local rules_count=$(jq '.rules | length' "$RULES_FILE" 2>/dev/null || echo 0)
    
    for ((i=0; i<rules_count; i++)); do
        local priority=$(jq -r ".rules[$i].priority" "$RULES_FILE")
        local type=$(jq -r ".rules[$i].type" "$RULES_FILE")
        local value=$(jq -r ".rules[$i].value" "$RULES_FILE")
        local outbound=$(jq -r ".rules[$i].outbound" "$RULES_FILE")
        local enabled=$(jq -r ".rules[$i].enabled" "$RULES_FILE")
        
        # 出口图标
        local outbound_icon=""
        case $outbound in
            block) outbound_icon="🚫" ;;
            direct) outbound_icon="🔵" ;;
            proxy-us) outbound_icon="🇺🇸" ;;
            proxy-sg) outbound_icon="🇸🇬" ;;
            proxy-jp) outbound_icon="🇯🇵" ;;
            proxy-hk) outbound_icon="🇭🇰" ;;
            auto-select) outbound_icon="🌐" ;;
            *) outbound_icon="📍" ;;
        esac
        
        # 状态
        local status_str=""
        if [ "$enabled" = "true" ]; then
            status_str="${GREEN}● 启用${RESET}"
        else
            status_str="${YELLOW}○ 禁用${RESET}"
        fi
        
        printf "${CYAN}║${RESET} %-2s ${CYAN}║${RESET} %-9s ${CYAN}║${RESET} %-26s ${CYAN}║${RESET} %s %-10s ${CYAN}║${RESET} %-9s ${CYAN}║${RESET}\n" \
            "$priority" "$type" "$value" "$outbound_icon" "$outbound" "$status_str"
    done
    
    # Final 规则
    local final=$(jq -r '.final' "$RULES_FILE" 2>/dev/null || echo "direct")
    echo -e "${CYAN}╠════╬═══════════╬════════════════════════════╬═══════════════╬═══════════╣${RESET}"
    printf "${CYAN}║${RESET} ∞  ${CYAN}║${RESET} final     ${CYAN}║${RESET} *                          ${CYAN}║${RESET} 🌐 %-10s ${CYAN}║${RESET} ${GREEN}● 启用${RESET}    ${CYAN}║${RESET}\n" "$final"
    echo -e "${CYAN}╚════╩═══════════╩════════════════════════════╩═══════════════╩═══════════╝${RESET}"
    echo ""
}

# =========================================
# 添加规则
# =========================================
add_rule() {
    init_rules_file
    
    echo ""
    echo -e "${CYAN}添加分流规则${RESET}"
    echo ""
    
    # 选择规则类型
    echo -e "${YELLOW}选择规则类型:${RESET}"
    echo -e "  1. geosite  (域名规则库)"
    echo -e "  2. geoip    (IP 规则库)"
    echo -e "  3. domain   (精确域名)"
    echo -e "  4. domain_suffix (域名后缀)"
    echo -e "  5. ip_cidr  (IP 段)"
    echo ""
    
    read -p "请选择 [1-5]: " type_choice
    
    local rule_type=""
    case $type_choice in
        1) rule_type="geosite" ;;
        2) rule_type="geoip" ;;
        3) rule_type="domain" ;;
        4) rule_type="domain_suffix" ;;
        5) rule_type="ip_cidr" ;;
        *) echo -e "${RED}无效选择${RESET}"; return 1 ;;
    esac
    
    # 输入匹配值
    local hint=""
    case $rule_type in
        geosite) hint="输入 geosite 规则名 (如: netflix, openai, cn, category-ads):" ;;
        geoip) hint="输入 geoip 规则名 (如: cn, us, jp, hk, sg, tw):" ;;
        domain) hint="输入精确域名 (如: example.com):" ;;
        domain_suffix) hint="输入域名后缀 (如: .netflix.com):" ;;
        ip_cidr) hint="输入 IP 段 (如: 10.0.0.0/8):" ;;
    esac
    
    echo ""
    read -p "$hint " rule_value
    [ -z "$rule_value" ] && { echo -e "${RED}值不能为空${RESET}"; return 1; }
    
    # 选择出口
    echo ""
    echo -e "${YELLOW}选择出口:${RESET}"
    
    # 读取可用的出口
    local outbounds_file="$UNIFIED_CONFIG_DIR/outbounds.json"
    if [ -f "$outbounds_file" ]; then
        local outbound_tags=$(jq -r '.outbounds[].tag' "$outbounds_file" 2>/dev/null | grep -v '^$')
        local i=1
        while IFS= read -r tag; do
            echo -e "  $i. $tag"
            ((i++))
        done <<< "$outbound_tags"
    else
        echo -e "  1. direct"
        echo -e "  2. block"
        echo -e "  3. auto-select"
    fi
    
    echo ""
    read -p "请输入出口名称: " rule_outbound
    [ -z "$rule_outbound" ] && rule_outbound="direct"
    
    # 获取当前最大优先级
    local max_priority=$(jq '[.rules[].priority] | max // 0' "$RULES_FILE" 2>/dev/null || echo 0)
    local new_priority=$((max_priority + 1))
    
    # 添加规则
    local temp_file=$(mktemp)
    jq --arg type "$rule_type" \
       --arg value "$rule_value" \
       --arg outbound "$rule_outbound" \
       --argjson priority "$new_priority" \
       '.rules += [{"priority": $priority, "type": $type, "value": $value, "outbound": $outbound, "enabled": true}]' \
       "$RULES_FILE" > "$temp_file" && mv "$temp_file" "$RULES_FILE"
    
    chmod 600 "$RULES_FILE"
    
    echo ""
    echo -e "${GREEN}✓ 规则添加成功${RESET}"
    echo -e "  类型: ${CYAN}$rule_type${RESET}"
    echo -e "  匹配: ${CYAN}$rule_value${RESET}"
    echo -e "  出口: ${CYAN}$rule_outbound${RESET}"
    echo -e "  优先级: ${CYAN}$new_priority${RESET}"
    echo ""
}

# =========================================
# 删除规则
# =========================================
remove_rule() {
    init_rules_file
    list_rules
    
    echo ""
    read -p "请输入要删除的规则优先级编号: " priority
    
    if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}无效的优先级编号${RESET}"
        return 1
    fi
    
    # 检查规则是否存在
    local exists=$(jq --argjson p "$priority" '.rules | map(select(.priority == $p)) | length' "$RULES_FILE")
    if [ "$exists" -eq 0 ]; then
        echo -e "${RED}规则不存在${RESET}"
        return 1
    fi
    
    # 获取规则信息
    local rule_info=$(jq -r --argjson p "$priority" '.rules[] | select(.priority == $p) | "\(.type):\(.value) -> \(.outbound)"' "$RULES_FILE")
    
    read -p "确认删除规则 [$rule_info]? (y/n): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    
    # 删除规则
    local temp_file=$(mktemp)
    jq --argjson p "$priority" '.rules = [.rules[] | select(.priority != $p)]' "$RULES_FILE" > "$temp_file" && mv "$temp_file" "$RULES_FILE"
    
    chmod 600 "$RULES_FILE"
    
    echo -e "${GREEN}✓ 规则已删除${RESET}"
}

# =========================================
# 调整规则优先级
# =========================================
move_rule() {
    init_rules_file
    list_rules
    
    echo ""
    read -p "请输入要移动的规则优先级编号: " src_priority
    read -p "请输入目标位置优先级编号: " dst_priority
    
    if ! [[ "$src_priority" =~ ^[0-9]+$ ]] || ! [[ "$dst_priority" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}无效的优先级编号${RESET}"
        return 1
    fi
    
    # 重新排序规则
    local temp_file=$(mktemp)
    jq --argjson src "$src_priority" --argjson dst "$dst_priority" '
        .rules |= (
            map(
                if .priority == $src then .priority = $dst
                elif .priority >= $dst and .priority < $src then .priority = .priority + 1
                elif .priority <= $dst and .priority > $src then .priority = .priority - 1
                else .
                end
            ) | sort_by(.priority)
        )
    ' "$RULES_FILE" > "$temp_file" && mv "$temp_file" "$RULES_FILE"
    
    chmod 600 "$RULES_FILE"
    
    echo -e "${GREEN}✓ 规则优先级已调整${RESET}"
    list_rules
}

# =========================================
# 切换规则启用/禁用状态
# =========================================
toggle_rule() {
    init_rules_file
    list_rules
    
    echo ""
    read -p "请输入要切换状态的规则优先级编号: " priority
    
    if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}无效的优先级编号${RESET}"
        return 1
    fi
    
    # 切换状态
    local temp_file=$(mktemp)
    jq --argjson p "$priority" '
        .rules = [.rules[] | if .priority == $p then .enabled = (.enabled | not) else . end]
    ' "$RULES_FILE" > "$temp_file" && mv "$temp_file" "$RULES_FILE"
    
    chmod 600 "$RULES_FILE"
    
    local new_state=$(jq -r --argjson p "$priority" '.rules[] | select(.priority == $p) | .enabled' "$RULES_FILE")
    if [ "$new_state" = "true" ]; then
        echo -e "${GREEN}✓ 规则已启用${RESET}"
    else
        echo -e "${YELLOW}✓ 规则已禁用${RESET}"
    fi
}

# =========================================
# 设置 final 出口
# =========================================
set_final_outbound() {
    init_rules_file
    
    echo ""
    echo -e "${CYAN}设置默认出口 (final)${RESET}"
    echo ""
    
    local current_final=$(jq -r '.final' "$RULES_FILE" 2>/dev/null || echo "direct")
    echo -e "当前默认出口: ${YELLOW}$current_final${RESET}"
    echo ""
    
    read -p "请输入新的默认出口: " new_final
    [ -z "$new_final" ] && return 0
    
    local temp_file=$(mktemp)
    jq --arg f "$new_final" '.final = $f' "$RULES_FILE" > "$temp_file" && mv "$temp_file" "$RULES_FILE"
    
    chmod 600 "$RULES_FILE"
    
    echo -e "${GREEN}✓ 默认出口已设置为: $new_final${RESET}"
}

# =========================================
# 导入预设规则集
# =========================================
import_preset_rules() {
    echo ""
    echo -e "${CYAN}导入预设规则集${RESET}"
    echo ""
    echo -e "  1. 基础规则 (广告拦截 + 中国直连)"
    echo -e "  2. 流媒体规则 (Netflix/Disney+ 等)"
    echo -e "  3. AI 服务规则 (OpenAI/Claude/Gemini)"
    echo -e "  4. 开发者规则 (GitHub/Docker/npm)"
    echo -e "  5. 游戏规则 (Steam/Epic/PSN)"
    echo ""
    
    read -p "请选择 [1-5]: " preset_choice
    
    local rules_to_add=""
    case $preset_choice in
        1)
            rules_to_add='[
                {"type": "geosite", "value": "category-ads-all", "outbound": "block"},
                {"type": "geosite", "value": "cn", "outbound": "direct"},
                {"type": "geoip", "value": "cn", "outbound": "direct"}
            ]'
            ;;
        2)
            rules_to_add='[
                {"type": "geosite", "value": "netflix", "outbound": "proxy-sg"},
                {"type": "geosite", "value": "disney", "outbound": "proxy-sg"},
                {"type": "geosite", "value": "hbo", "outbound": "proxy-us"},
                {"type": "geosite", "value": "spotify", "outbound": "proxy-us"}
            ]'
            ;;
        3)
            rules_to_add='[
                {"type": "geosite", "value": "openai", "outbound": "proxy-us"},
                {"type": "geosite", "value": "anthropic", "outbound": "proxy-us"},
                {"type": "domain_suffix", "value": "claude.ai", "outbound": "proxy-us"},
                {"type": "domain_suffix", "value": "gemini.google.com", "outbound": "proxy-us"}
            ]'
            ;;
        4)
            rules_to_add='[
                {"type": "geosite", "value": "github", "outbound": "auto-select"},
                {"type": "geosite", "value": "docker", "outbound": "auto-select"},
                {"type": "domain_suffix", "value": "npmjs.org", "outbound": "auto-select"},
                {"type": "domain_suffix", "value": "pypi.org", "outbound": "auto-select"}
            ]'
            ;;
        5)
            rules_to_add='[
                {"type": "geosite", "value": "steam", "outbound": "auto-select"},
                {"type": "geosite", "value": "epicgames", "outbound": "proxy-us"},
                {"type": "domain_suffix", "value": "playstation.com", "outbound": "proxy-jp"}
            ]'
            ;;
        *)
            echo -e "${RED}无效选择${RESET}"
            return 1
            ;;
    esac
    
    # 获取当前最大优先级
    local max_priority=$(jq '[.rules[].priority] | max // 0' "$RULES_FILE" 2>/dev/null || echo 0)
    
    # 添加规则，自动分配优先级
    local temp_file=$(mktemp)
    jq --argjson new_rules "$rules_to_add" --argjson start_priority "$((max_priority + 1))" '
        .rules += [
            $new_rules | to_entries[] | 
            .value + {"priority": ($start_priority + .key), "enabled": true}
        ]
    ' "$RULES_FILE" > "$temp_file" && mv "$temp_file" "$RULES_FILE"
    
    chmod 600 "$RULES_FILE"
    
    echo -e "${GREEN}✓ 预设规则导入成功${RESET}"
    list_rules
}

# =========================================
# 生成 Sing-box route 配置
# =========================================
generate_route_config() {
    init_rules_file
    
    local rules_json="[]"
    local rules_count=$(jq '.rules | length' "$RULES_FILE" 2>/dev/null || echo 0)
    
    for ((i=0; i<rules_count; i++)); do
        local enabled=$(jq -r ".rules[$i].enabled" "$RULES_FILE")
        [ "$enabled" != "true" ] && continue
        
        local type=$(jq -r ".rules[$i].type" "$RULES_FILE")
        local value=$(jq -r ".rules[$i].value" "$RULES_FILE")
        local outbound=$(jq -r ".rules[$i].outbound" "$RULES_FILE")
        
        local rule_obj=""
        case $type in
            geosite)
                # sing-box 1.12+ 使用 rule_set 格式
                rule_obj="{\"rule_set\": \"geosite-$value\", \"outbound\": \"$outbound\"}"
                ;;
            geoip)
                # sing-box 1.12+ 使用 rule_set 格式
                rule_obj="{\"rule_set\": \"geoip-$value\", \"outbound\": \"$outbound\"}"
                ;;
            domain)
                rule_obj="{\"domain\": [\"$value\"], \"outbound\": \"$outbound\"}"
                ;;
            domain_suffix)
                rule_obj="{\"domain_suffix\": [\"$value\"], \"outbound\": \"$outbound\"}"
                ;;
            ip_cidr)
                rule_obj="{\"ip_cidr\": [\"$value\"], \"outbound\": \"$outbound\"}"
                ;;
        esac
        
        if [ -n "$rule_obj" ]; then
            rules_json=$(echo "$rules_json" | jq --argjson rule "$rule_obj" '. += [$rule]')
        fi
    done
    
    local final=$(jq -r '.final' "$RULES_FILE" 2>/dev/null || echo "direct")
    
    # 生成完整的 route 配置 (sing-box 1.12+ 兼容格式)
    jq -n \
        --argjson rules "$rules_json" \
        --arg final "$final" \
        '{
            "route": {
                "rules": $rules,
                "final": $final,
                "auto_detect_interface": true
            }
        }'
}

# =========================================
# 更新 GeoIP/GeoSite 数据库
# =========================================
update_geo_databases() {
    echo -e "${CYAN}更新 GeoIP/GeoSite 数据库...${RESET}"
    
    mkdir -p "$UNIFIED_CONFIG_DIR"
    
    # 下载 GeoIP
    echo -e "${YELLOW}下载 GeoIP 数据库...${RESET}"
    local geoip_url="https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db"
    if download_file "$geoip_url" "$GEOIP_FILE" 3 5; then
        echo -e "${GREEN}✓ GeoIP 更新成功${RESET}"
    else
        echo -e "${RED}✗ GeoIP 更新失败${RESET}"
    fi
    
    # 下载 GeoSite
    echo -e "${YELLOW}下载 GeoSite 数据库...${RESET}"
    local geosite_url="https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db"
    if download_file "$geosite_url" "$GEOSITE_FILE" 3 5; then
        echo -e "${GREEN}✓ GeoSite 更新成功${RESET}"
    else
        echo -e "${RED}✗ GeoSite 更新失败${RESET}"
    fi
    
    echo ""
    echo -e "${GREEN}数据库更新完成${RESET}"
}

# =========================================
# 规则测试功能
# =========================================
test_rule_match() {
    init_rules_file
    
    echo ""
    echo -e "${CYAN}规则匹配测试${RESET}"
    echo ""
    read -p "请输入要测试的域名或 IP: " test_input
    [ -z "$test_input" ] && return 0
    
    echo ""
    echo -e "测试: ${YELLOW}$test_input${RESET}"
    echo ""
    
    # 简单的规则匹配模拟
    local matched=false
    local rules_count=$(jq '.rules | length' "$RULES_FILE" 2>/dev/null || echo 0)
    
    for ((i=0; i<rules_count; i++)); do
        local enabled=$(jq -r ".rules[$i].enabled" "$RULES_FILE")
        [ "$enabled" != "true" ] && continue
        
        local type=$(jq -r ".rules[$i].type" "$RULES_FILE")
        local value=$(jq -r ".rules[$i].value" "$RULES_FILE")
        local outbound=$(jq -r ".rules[$i].outbound" "$RULES_FILE")
        local priority=$(jq -r ".rules[$i].priority" "$RULES_FILE")
        
        local match=false
        case $type in
            domain)
                [ "$test_input" = "$value" ] && match=true
                ;;
            domain_suffix)
                [[ "$test_input" == *"$value" ]] && match=true
                ;;
            geosite)
                # GeoSite 需要完整的数据库查询，这里只做提示
                if [[ "$value" == "cn" ]] && [[ "$test_input" == *".cn" || "$test_input" == *"baidu.com"* || "$test_input" == *"taobao.com"* ]]; then
                    match=true
                elif [[ "$value" == "netflix" ]] && [[ "$test_input" == *"netflix"* ]]; then
                    match=true
                elif [[ "$value" == "openai" ]] && [[ "$test_input" == *"openai"* || "$test_input" == *"chatgpt"* ]]; then
                    match=true
                fi
                ;;
            ip_cidr)
                # IP CIDR 匹配需要更复杂的逻辑
                echo -e "${YELLOW}  (IP CIDR 匹配需要运行时检查)${RESET}"
                ;;
        esac
        
        if [ "$match" = true ]; then
            echo -e "${GREEN}✓ 匹配规则 #$priority${RESET}"
            echo -e "  类型: $type"
            echo -e "  条件: $value"
            echo -e "  出口: ${CYAN}$outbound${RESET}"
            matched=true
            break
        fi
    done
    
    if [ "$matched" = false ]; then
        local final=$(jq -r '.final' "$RULES_FILE" 2>/dev/null || echo "direct")
        echo -e "${YELLOW}未匹配任何规则，使用默认出口: ${CYAN}$final${RESET}"
    fi
    echo ""
}

# =========================================
# 分流规则管理菜单
# =========================================
routing_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                         📋 分流规则管理                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}1.${RESET} 查看规则列表                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}2.${RESET} 添加规则                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}3.${RESET} 删除规则                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}4.${RESET} 调整优先级                                                        ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}5.${RESET} 启用/禁用规则                                                     ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}6.${RESET} 设置默认出口 (final)                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}7.${RESET} 导入预设规则集                                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}8.${RESET} 测试规则匹配                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}9.${RESET} 更新 GeoIP/GeoSite                                                ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}0.${RESET} 返回上级菜单                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        
        read -p "请选择 [0-9]: " choice
        
        case $choice in
            1) list_rules ;;
            2) add_rule ;;
            3) remove_rule ;;
            4) move_rule ;;
            5) toggle_rule ;;
            6) set_final_outbound ;;
            7) import_preset_rules ;;
            8) test_rule_match ;;
            9) update_geo_databases ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}
