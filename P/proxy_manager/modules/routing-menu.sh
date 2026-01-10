#!/bin/bash
# =========================================
# Proxy Manager - Routing Menu Module
# 分流管理统一菜单入口
# =========================================

# 防止重复加载
[[ -n "${_ROUTING_MENU_LOADED:-}" ]] && return 0
_ROUTING_MENU_LOADED=1

# =========================================
# 加载依赖模块
# =========================================
# 注意: 这些模块应该在主脚本中已经加载
# 这里的 source 语句是为了独立测试时使用
if [ -z "${_COMMON_LOADED:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
fi

# =========================================
# 显示分流管理状态概览
# =========================================
show_routing_status() {
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET}  ${YELLOW}分流状态概览${RESET}                                                            ${CYAN}│${RESET}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
    
    # 落地代理数量
    local outbounds_count=0
    if [ -f "$UNIFIED_CONFIG_DIR/outbounds.json" ]; then
        outbounds_count=$(jq '[.outbounds[] | select(.type != "direct" and .type != "block")] | length' "$UNIFIED_CONFIG_DIR/outbounds.json" 2>/dev/null || echo 0)
    fi
    
    # 规则数量
    local rules_count=0
    if [ -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
        rules_count=$(jq '.rules | length' "$UNIFIED_CONFIG_DIR/rules.json" 2>/dev/null || echo 0)
    fi
    
    # 订阅数量
    local subs_count=0
    if [ -f "$UNIFIED_CONFIG_DIR/subscriptions.json" ]; then
        subs_count=$(jq '.subscriptions | length' "$UNIFIED_CONFIG_DIR/subscriptions.json" 2>/dev/null || echo 0)
    fi
    
    # GeoIP/GeoSite 状态
    local geoip_status="${RED}未安装${RESET}"
    local geosite_status="${RED}未安装${RESET}"
    [ -f "$UNIFIED_CONFIG_DIR/geoip.db" ] && geoip_status="${GREEN}已安装${RESET}"
    [ -f "$UNIFIED_CONFIG_DIR/geosite.db" ] && geosite_status="${GREEN}已安装${RESET}"
    
    printf "${CYAN}│${RESET}  落地代理: ${YELLOW}%-5d${RESET}  分流规则: ${YELLOW}%-5d${RESET}  订阅规则集: ${YELLOW}%-5d${RESET}             ${CYAN}│${RESET}\n" \
        "$outbounds_count" "$rules_count" "$subs_count"
    echo -e "${CYAN}│${RESET}  GeoIP: $geoip_status    GeoSite: $geosite_status                                     ${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
}

# =========================================
# 应用配置 - 生成完整 sing-box 配置
# =========================================
apply_routing_config() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   应用分流配置${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    # 检查是否有配置
    if [ ! -f "$UNIFIED_CONFIG_DIR/outbounds.json" ] && [ ! -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
        echo -e "${YELLOW}未找到分流配置，请先配置落地代理和规则${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}正在生成配置...${RESET}"
    
    # 生成 outbounds
    local outbounds="[]"
    if [ -f "$UNIFIED_CONFIG_DIR/outbounds.json" ]; then
        outbounds=$(generate_outbounds_config 2>/dev/null || echo "[]")
    fi
    
    # 生成 rule_set (先从订阅获取)
    local rule_sets="[]"
    if [ -f "$UNIFIED_CONFIG_DIR/subscriptions.json" ]; then
        rule_sets=$(generate_ruleset_config 2>/dev/null || echo "[]")
    fi
    
    # 自动为 geosite/geoip 规则添加 rule_set 定义
    if [ -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
        local rules_count=$(jq '.rules | length' "$UNIFIED_CONFIG_DIR/rules.json" 2>/dev/null || echo 0)
        
        for ((i=0; i<rules_count; i++)); do
            local type=$(jq -r ".rules[$i].type" "$UNIFIED_CONFIG_DIR/rules.json")
            local value=$(jq -r ".rules[$i].value" "$UNIFIED_CONFIG_DIR/rules.json")
            local enabled=$(jq -r ".rules[$i].enabled" "$UNIFIED_CONFIG_DIR/rules.json")
            
            [ "$enabled" != "true" ] && continue
            
            if [ "$type" = "geosite" ]; then
                local tag="geosite-$value"
                local exists=$(echo "$rule_sets" | jq --arg t "$tag" '[.[] | select(.tag == $t)] | length')
                if [ "$exists" = "0" ]; then
                    local rs=$(jq -n \
                        --arg tag "$tag" \
                        --arg url "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-$value.srs" \
                        '{
                            "tag": $tag,
                            "type": "remote",
                            "format": "binary",
                            "url": $url,
                            "download_detour": "direct"
                        }')
                    rule_sets=$(echo "$rule_sets" | jq --argjson rs "$rs" '. += [$rs]')
                fi
            elif [ "$type" = "geoip" ]; then
                local tag="geoip-$value"
                local exists=$(echo "$rule_sets" | jq --arg t "$tag" '[.[] | select(.tag == $t)] | length')
                if [ "$exists" = "0" ]; then
                    local rs=$(jq -n \
                        --arg tag "$tag" \
                        --arg url "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-$value.srs" \
                        '{
                            "tag": $tag,
                            "type": "remote",
                            "format": "binary",
                            "url": $url,
                            "download_detour": "direct"
                        }')
                    rule_sets=$(echo "$rule_sets" | jq --argjson rs "$rs" '. += [$rs]')
                fi
            fi
        done
    fi
    
    # 生成路由规则
    local route_rules="[]"
    
    # 添加基于订阅的规则
    if [ -f "$UNIFIED_CONFIG_DIR/subscriptions.json" ]; then
        local sub_rules=$(generate_subscription_rules 2>/dev/null || echo "[]")
        route_rules=$(echo "$route_rules" | jq --argjson r "$sub_rules" '. + $r')
    fi
    
    # 添加手动配置的规则
    if [ -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
        local manual_rules=$(generate_route_config 2>/dev/null | jq '.route.rules // []')
        route_rules=$(echo "$route_rules" | jq --argjson r "$manual_rules" '. + $r')
    fi
    
    # 获取 final 出口
    local final="direct"
    if [ -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
        final=$(jq -r '.final // "direct"' "$UNIFIED_CONFIG_DIR/rules.json" 2>/dev/null)
    fi
    
    # 生成完整配置 (sing-box 1.12+ 兼容格式)
    local full_config=$(jq -n \
        --argjson outbounds "$outbounds" \
        --argjson rule_sets "$rule_sets" \
        --argjson rules "$route_rules" \
        --arg final "$final" \
        '{
            "log": {
                "level": "info",
                "timestamp": true
            },
            "dns": {
                "servers": [
                    {
                        "tag": "local",
                        "address": "223.5.5.5",
                        "detour": "direct"
                    },
                    {
                        "tag": "google",
                        "address": "https://8.8.8.8/dns-query",
                        "address_resolver": "local",
                        "strategy": "prefer_ipv4"
                    }
                ],
                "rules": [
                    {
                        "domain_suffix": [".cn"],
                        "server": "local"
                    },
                    {
                        "domain_keyword": ["baidu", "taobao", "aliyun", "tencent", "qq"],
                        "server": "local"
                    }
                ],
                "final": "google"
            },
            "route": {
                "rule_set": $rule_sets,
                "rules": $rules,
                "final": $final,
                "auto_detect_interface": true
            },
            "outbounds": $outbounds
        }')
    
    # 保存配置
    local config_file="$UNIFIED_CONFIG_DIR/config.json"
    echo "$full_config" | jq '.' > "$config_file"
    chmod 600 "$config_file"
    
    echo -e "${GREEN}✓ 配置已生成: $config_file${RESET}"
    
    # 验证配置
    if command -v sing-box &>/dev/null; then
        echo ""
        echo -e "${CYAN}正在验证配置...${RESET}"
        if sing-box check -c "$config_file" 2>/dev/null; then
            echo -e "${GREEN}✓ 配置验证通过${RESET}"
        else
            echo -e "${RED}✗ 配置验证失败${RESET}"
            echo -e "${YELLOW}请检查配置文件: $config_file${RESET}"
            return 1
        fi
    fi
    
    # 询问是否重载服务
    echo ""
    read -p "是否重载 sing-box 服务? (y/n): " reload
    if [[ "$reload" =~ ^[Yy]$ ]]; then
        reload_singbox_services
    fi
    
    echo ""
}

# =========================================
# 查看当前配置
# =========================================
view_current_config() {
    local config_file="$UNIFIED_CONFIG_DIR/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}配置文件不存在，请先应用配置${RESET}"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   当前分流配置${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    # 显示配置文件信息
    local size=$(ls -lh "$config_file" 2>/dev/null | awk '{print $5}')
    local modified=$(stat -c %y "$config_file" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$config_file" 2>/dev/null || echo "-")
    
    echo -e "配置文件: ${CYAN}$config_file${RESET}"
    echo -e "文件大小: ${YELLOW}$size${RESET}"
    echo -e "修改时间: ${YELLOW}$modified${RESET}"
    echo ""
    
    # 询问是否查看详细内容
    read -p "是否查看详细配置内容? (y/n): " view_detail
    if [[ "$view_detail" =~ ^[Yy]$ ]]; then
        echo ""
        jq '.' "$config_file" | head -100
        
        local total_lines=$(jq '.' "$config_file" | wc -l)
        if [ "$total_lines" -gt 100 ]; then
            echo ""
            echo -e "${YELLOW}... (共 $total_lines 行，只显示前 100 行)${RESET}"
        fi
    fi
}

# =========================================
# 增强的规则测试功能
# =========================================
enhanced_rule_test() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   规则匹配测试${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    echo -e "${YELLOW}输入要测试的域名或 IP (输入 'q' 退出):${RESET}"
    echo ""
    
    while true; do
        read -p "测试 > " test_input
        
        [ -z "$test_input" ] && continue
        [ "$test_input" = "q" ] || [ "$test_input" = "quit" ] || [ "$test_input" = "exit" ] && break
        
        echo ""
        echo -e "测试: ${CYAN}$test_input${RESET}"
        echo -e "${CYAN}────────────────────────────────────────${RESET}"
        
        local matched=false
        
        # 1. 检查订阅规则集
        if [ -f "$UNIFIED_CONFIG_DIR/subscriptions.json" ]; then
            local subs_count=$(jq '.subscriptions | length' "$UNIFIED_CONFIG_DIR/subscriptions.json" 2>/dev/null || echo 0)
            
            for ((i=0; i<subs_count; i++)); do
                local name=$(jq -r ".subscriptions[$i].name" "$UNIFIED_CONFIG_DIR/subscriptions.json")
                local enabled=$(jq -r ".subscriptions[$i].enabled // true" "$SUBSCRIPTIONS_FILE")
                local outbound=$(jq -r ".subscriptions[$i].outbound" "$UNIFIED_CONFIG_DIR/subscriptions.json")
                
                [ "$enabled" != "true" ] && continue
                
                # 基于名称的启发式匹配
                local hint_match=false
                case $name in
                    reject)
                        [[ "$test_input" == *"ad"* || "$test_input" == *"track"* || "$test_input" == *"analytics"* ]] && hint_match=true
                        ;;
                    proxy|gfw)
                        [[ "$test_input" == *"google"* || "$test_input" == *"facebook"* || "$test_input" == *"twitter"* || "$test_input" == *"youtube"* ]] && hint_match=true
                        ;;
                    direct|cncidr)
                        [[ "$test_input" == *".cn" || "$test_input" == *"baidu"* || "$test_input" == *"taobao"* || "$test_input" == *"aliyun"* ]] && hint_match=true
                        ;;
                    telegram*)
                        [[ "$test_input" == *"telegram"* || "$test_input" == *"t.me"* ]] && hint_match=true
                        ;;
                esac
                
                if [ "$hint_match" = true ]; then
                    echo -e "${GREEN}✓ 可能匹配订阅规则集: $name${RESET}"
                    echo -e "  出口: ${CYAN}$outbound${RESET}"
                    matched=true
                    break
                fi
            done
        fi
        
        # 2. 检查手动配置的规则
        if [ "$matched" = false ] && [ -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
            local rules_count=$(jq '.rules | length' "$UNIFIED_CONFIG_DIR/rules.json" 2>/dev/null || echo 0)
            
            for ((i=0; i<rules_count; i++)); do
                local enabled=$(jq -r ".rules[$i].enabled" "$UNIFIED_CONFIG_DIR/rules.json")
                [ "$enabled" != "true" ] && continue
                
                local type=$(jq -r ".rules[$i].type" "$UNIFIED_CONFIG_DIR/rules.json")
                local value=$(jq -r ".rules[$i].value" "$UNIFIED_CONFIG_DIR/rules.json")
                local outbound=$(jq -r ".rules[$i].outbound" "$UNIFIED_CONFIG_DIR/rules.json")
                local priority=$(jq -r ".rules[$i].priority" "$UNIFIED_CONFIG_DIR/rules.json")
                
                local match=false
                case $type in
                    domain)
                        [ "$test_input" = "$value" ] && match=true
                        ;;
                    domain_suffix)
                        [[ "$test_input" == *"$value" ]] && match=true
                        ;;
                    geosite)
                        case $value in
                            cn)
                                [[ "$test_input" == *".cn" || "$test_input" == *"baidu"* || "$test_input" == *"taobao"* ]] && match=true
                                ;;
                            netflix)
                                [[ "$test_input" == *"netflix"* ]] && match=true
                                ;;
                            openai)
                                [[ "$test_input" == *"openai"* || "$test_input" == *"chatgpt"* ]] && match=true
                                ;;
                            google)
                                [[ "$test_input" == *"google"* || "$test_input" == *"gstatic"* ]] && match=true
                                ;;
                            category-ads-all)
                                [[ "$test_input" == *"ad"* || "$test_input" == *"track"* ]] && match=true
                                ;;
                        esac
                        ;;
                    geoip)
                        # IP 匹配需要实际查询
                        echo -e "${YELLOW}  (GeoIP 匹配需要运行时检查: $value)${RESET}"
                        ;;
                    ip_cidr)
                        # CIDR 匹配需要计算
                        echo -e "${YELLOW}  (IP CIDR 匹配需要运行时检查: $value)${RESET}"
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
        fi
        
        # 3. 如果没有匹配，显示默认出口
        if [ "$matched" = false ]; then
            local final="direct"
            if [ -f "$UNIFIED_CONFIG_DIR/rules.json" ]; then
                final=$(jq -r '.final // "direct"' "$UNIFIED_CONFIG_DIR/rules.json" 2>/dev/null)
            fi
            echo -e "${YELLOW}未匹配任何规则${RESET}"
            echo -e "  默认出口: ${CYAN}$final${RESET}"
        fi
        
        echo ""
    done
}

# =========================================
# 分流管理主菜单
# =========================================
routing_main_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}              ${GREEN}🌐 Sing-box 高级分流管理${RESET}                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
        
        show_routing_status
        
        echo ""
        echo -e "${GREEN}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${GREEN}│${RESET}  ${YELLOW}落地代理${RESET}                                                                ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}1.${RESET} 落地代理管理 (SS/Hysteria2/VLESS)                                   ${GREEN}│${RESET}"
        echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
        echo -e "${GREEN}│${RESET}  ${YELLOW}分流规则${RESET}                                                                ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}2.${RESET} 分流规则管理                                                        ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}3.${RESET} 远程订阅规则集                                                      ${GREEN}│${RESET}"
        echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
        echo -e "${GREEN}│${RESET}  ${YELLOW}数据库${RESET}                                                                  ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}4.${RESET} GeoIP/GeoSite 管理                                                  ${GREEN}│${RESET}"
        echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
        echo -e "${GREEN}│${RESET}  ${YELLOW}工具${RESET}                                                                    ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}5.${RESET} 规则测试                                                            ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}6.${RESET} 应用配置                                                            ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}7.${RESET} 查看当前配置                                                        ${GREEN}│${RESET}"
        echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
        echo -e "${GREEN}│${RESET}    ${CYAN}0.${RESET} 返回主菜单                                                          ${GREEN}│${RESET}"
        echo -e "${GREEN}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
        echo ""
        
        read -p "请选择 [0-7]: " choice
        
        case $choice in
            1) outbound_menu ;;
            2) routing_menu ;;
            3) subscription_menu ;;
            4) geo_update_menu ;;
            5) enhanced_rule_test ;;
            6) apply_routing_config ;;
            7) view_current_config ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${RESET}"; sleep 1 ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}
