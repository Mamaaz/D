#!/bin/bash
# =========================================
# Proxy Manager - Multi-Server Module (API Mode)
# 多服务器集中管理模块 - Agent 探针模式
# =========================================

[[ -n "${_MULTI_SERVER_LOADED:-}" ]] && return 0
_MULTI_SERVER_LOADED=1

# =========================================
# 配置文件路径
# =========================================
SERVERS_FILE="${CONFIG_DIR}/servers.json"
AGENT_INSTALL_URL="https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/agent/install-agent.sh"

# =========================================
# 初始化
# =========================================
init_multi_server() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    if [ ! -f "$SERVERS_FILE" ]; then
        echo '{"servers":[]}' > "$SERVERS_FILE"
        chmod 600 "$SERVERS_FILE"
    fi
}

# =========================================
# API 调用函数
# =========================================

# 调用远程 Agent API
call_agent_api() {
    local server_id=$1
    local endpoint=$2
    local method=${3:-GET}
    local data=${4:-}
    
    local server_info=$(jq -r ".servers[] | select(.id == \"$server_id\")" "$SERVERS_FILE" 2>/dev/null)
    
    if [ -z "$server_info" ]; then
        echo '{"error": "server not found"}' 
        return 1
    fi
    
    local host=$(echo "$server_info" | jq -r '.host')
    local port=$(echo "$server_info" | jq -r '.port')
    local token=$(echo "$server_info" | jq -r '.token')
    
    local url="http://${host}:${port}${endpoint}"
    local auth_header="Authorization: Bearer ${token}"
    
    if [ "$method" == "GET" ]; then
        curl -s --connect-timeout 5 --max-time 10 \
             -H "$auth_header" \
             "$url" 2>/dev/null
    else
        curl -s --connect-timeout 5 --max-time 30 \
             -X "$method" \
             -H "$auth_header" \
             -H "Content-Type: application/json" \
             -d "$data" \
             "$url" 2>/dev/null
    fi
}

# 测试 Agent 连接
test_agent_connection() {
    local host=$1
    local port=$2
    local token=$3
    
    local result=$(curl -s --connect-timeout 5 --max-time 10 \
         -H "Authorization: Bearer ${token}" \
         "http://${host}:${port}/api/status" 2>/dev/null)
    
    if echo "$result" | jq -e '.ip' &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# =========================================
# 服务器管理函数
# =========================================

# 列出所有服务器
list_servers() {
    init_multi_server
    
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}需要安装 jq${RESET}"
        return 1
    fi
    
    local count=$(jq '.servers | length' "$SERVERS_FILE" 2>/dev/null)
    
    if [ "$count" == "0" ] || [ -z "$count" ]; then
        echo -e "${YELLOW}暂无已添加的服务器${RESET}"
        echo ""
        echo -e "${CYAN}添加服务器步骤:${RESET}"
        echo -e "  1. 在目标 VPS 上运行: ${GREEN}bash <(curl -sL $AGENT_INSTALL_URL)${RESET}"
        echo -e "  2. 记录显示的 Token"
        echo -e "  3. 在此选择选项 [1] 添加服务器"
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}                      ${YELLOW}已添加的服务器${RESET}                            ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${RESET}"
    printf "${CYAN}║${RESET}  %-6s │ %-12s │ %-20s │ %-6s ${CYAN}║${RESET}\n" "ID" "名称" "主机" "端口"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${RESET}"
    
    jq -r '.servers[] | "\(.id)|\(.name)|\(.host)|\(.port)"' "$SERVERS_FILE" 2>/dev/null | \
    while IFS='|' read -r id name host port; do
        printf "${CYAN}║${RESET}  %-6s │ %-12s │ %-20s │ %-6s ${CYAN}║${RESET}\n" "$id" "$name" "$host" "$port"
    done
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# 添加服务器
add_server() {
    init_multi_server
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   添加远程服务器 (Agent 模式)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${YELLOW}提示: 目标服务器需要先安装 Agent${RESET}"
    echo -e "${CYAN}安装命令: bash <(curl -sL $AGENT_INSTALL_URL)${RESET}"
    echo ""
    
    # 服务器 ID
    while true; do
        read -p "服务器 ID (如 us1, jp1): " server_id
        server_id=$(echo "$server_id" | tr -cd 'a-zA-Z0-9_-')
        [ -z "$server_id" ] && { echo -e "${RED}ID 不能为空${RESET}"; continue; }
        
        if jq -e ".servers[] | select(.id == \"$server_id\")" "$SERVERS_FILE" &>/dev/null; then
            echo -e "${RED}ID '$server_id' 已存在${RESET}"
            continue
        fi
        break
    done
    
    # 服务器名称
    read -p "服务器名称 (如 美国1): " server_name
    server_name=${server_name:-$server_id}
    
    # 主机地址
    while true; do
        read -p "Agent 地址 (IP): " server_host
        [ -z "$server_host" ] && { echo -e "${RED}地址不能为空${RESET}"; continue; }
        break
    done
    
    # Agent 端口
    read -p "Agent 端口 (默认: 9900): " server_port
    server_port=${server_port:-9900}
    
    # Token
    while true; do
        read -p "Agent Token: " server_token
        [ -z "$server_token" ] && { echo -e "${RED}Token 不能为空${RESET}"; continue; }
        break
    done
    
    echo ""
    echo -e "${CYAN}正在测试连接...${RESET}"
    
    if test_agent_connection "$server_host" "$server_port" "$server_token"; then
        echo -e "${GREEN}✓ Agent 连接成功${RESET}"
    else
        echo -e "${RED}✗ Agent 连接失败${RESET}"
        echo -e "${YELLOW}请检查:${RESET}"
        echo -e "  1. Agent 是否已安装并运行"
        echo -e "  2. 防火墙是否开放端口 $server_port"
        echo -e "  3. Token 是否正确"
        read -p "仍要添加？(y/n): " confirm
        [ "$confirm" != "y" ] && return 1
    fi
    
    # 保存服务器信息
    local temp_file=$(mktemp)
    jq --arg id "$server_id" \
       --arg name "$server_name" \
       --arg host "$server_host" \
       --arg port "$server_port" \
       --arg token "$server_token" \
       '.servers += [{"id": $id, "name": $name, "host": $host, "port": ($port|tonumber), "token": $token}]' \
       "$SERVERS_FILE" > "$temp_file"
    
    mv "$temp_file" "$SERVERS_FILE"
    chmod 600 "$SERVERS_FILE"
    
    echo ""
    echo -e "${GREEN}✓ 服务器添加成功！${RESET}"
}

# 删除服务器
remove_server() {
    init_multi_server
    
    list_servers
    
    local count=$(jq '.servers | length' "$SERVERS_FILE" 2>/dev/null)
    [ "$count" == "0" ] && return
    
    echo ""
    read -p "输入要删除的服务器 ID: " server_id
    
    if ! jq -e ".servers[] | select(.id == \"$server_id\")" "$SERVERS_FILE" &>/dev/null; then
        echo -e "${RED}服务器 ID 不存在${RESET}"
        return 1
    fi
    
    read -p "确认删除 '$server_id'? (y/n): " confirm
    [ "$confirm" != "y" ] && return
    
    local temp_file=$(mktemp)
    jq --arg id "$server_id" 'del(.servers[] | select(.id == $id))' "$SERVERS_FILE" > "$temp_file"
    mv "$temp_file" "$SERVERS_FILE"
    chmod 600 "$SERVERS_FILE"
    
    echo -e "${GREEN}✓ 已删除服务器 '$server_id'${RESET}"
}

# =========================================
# 状态监控函数
# =========================================

# 批量查看所有服务器状态
batch_status() {
    init_multi_server
    
    local count=$(jq '.servers | length' "$SERVERS_FILE" 2>/dev/null)
    
    if [ "$count" == "0" ] || [ -z "$count" ]; then
        echo -e "${YELLOW}暂无已添加的服务器${RESET}"
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}                           ${YELLOW}多服务器状态概览${RESET}                                 ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    printf "${CYAN}║${RESET}  %-10s │ %-18s │ %-8s │ %-30s ${CYAN}║${RESET}\n" "名称" "主机" "状态" "运行服务"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    jq -r '.servers[] | "\(.id)|\(.name)|\(.host)"' "$SERVERS_FILE" 2>/dev/null | \
    while IFS='|' read -r id name host; do
        echo -e "${CYAN}检查 ${name}...${RESET}" >&2
        
        local result=$(call_agent_api "$id" "/api/status")
        
        if echo "$result" | jq -e '.ip' &>/dev/null; then
            local services_str=""
            
            for svc in snell singbox reality hysteria2; do
                local status=$(echo "$result" | jq -r ".services.${svc}.status // \"none\"")
                local installed=$(echo "$result" | jq -r ".services.${svc}.installed // false")
                
                if [ "$installed" == "true" ]; then
                    if [ "$status" == "active" ]; then
                        services_str+="${svc}✓ "
                    else
                        services_str+="${svc}✗ "
                    fi
                fi
            done
            
            [ -z "$services_str" ] && services_str="无"
            
            printf "${CYAN}║${RESET}  %-10s │ %-18s │ ${GREEN}%-8s${RESET} │ %-30s ${CYAN}║${RESET}\n" "$name" "$host" "在线" "$services_str"
        else
            printf "${CYAN}║${RESET}  %-10s │ %-18s │ ${RED}%-8s${RESET} │ %-30s ${CYAN}║${RESET}\n" "$name" "$host" "离线" "--"
        fi
    done
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# =========================================
# 批量操作函数
# =========================================

# 批量重启服务
batch_restart() {
    echo -e "${CYAN}选择要重启的服务:${RESET}"
    echo -e "${YELLOW}1.${RESET} snell"
    echo -e "${YELLOW}2.${RESET} singbox"
    echo -e "${YELLOW}3.${RESET} reality"
    echo -e "${YELLOW}4.${RESET} hysteria2"
    echo -e "${YELLOW}5.${RESET} 全部服务"
    echo ""
    
    read -p "选择 [1-5]: " choice
    
    local service_type
    case $choice in
        1) service_type="snell" ;;
        2) service_type="singbox" ;;
        3) service_type="reality" ;;
        4) service_type="hysteria2" ;;
        5) service_type="all" ;;
        *) echo -e "${RED}无效选择${RESET}"; return ;;
    esac
    
    echo ""
    jq -r '.servers[] | "\(.id)|\(.name)"' "$SERVERS_FILE" 2>/dev/null | \
    while IFS='|' read -r id name; do
        echo -e "${CYAN}正在重启 ${name} 的 ${service_type}...${RESET}"
        
        local result=$(call_agent_api "$id" "/api/restart" "POST" "{\"type\": \"$service_type\"}")
        
        if echo "$result" | jq -e '.status == "ok"' &>/dev/null; then
            echo -e "${GREEN}✓ ${name} 重启成功${RESET}"
        else
            local error=$(echo "$result" | jq -r '.error // .message // "unknown error"')
            echo -e "${RED}✗ ${name} 重启失败: ${error}${RESET}"
        fi
    done
}

# 批量卸载服务
batch_uninstall() {
    echo -e "${CYAN}选择要卸载的服务:${RESET}"
    echo -e "${YELLOW}1.${RESET} snell"
    echo -e "${YELLOW}2.${RESET} singbox"
    echo -e "${YELLOW}3.${RESET} reality"
    echo -e "${YELLOW}4.${RESET} hysteria2"
    echo ""
    
    read -p "选择 [1-4]: " choice
    
    local service_type
    case $choice in
        1) service_type="snell" ;;
        2) service_type="singbox" ;;
        3) service_type="reality" ;;
        4) service_type="hysteria2" ;;
        *) echo -e "${RED}无效选择${RESET}"; return ;;
    esac
    
    echo ""
    read -p "确认要卸载所有服务器的 ${service_type}？(y/n): " confirm
    [ "$confirm" != "y" ] && return
    
    jq -r '.servers[] | "\(.id)|\(.name)"' "$SERVERS_FILE" 2>/dev/null | \
    while IFS='|' read -r id name; do
        echo -e "${CYAN}正在卸载 ${name} 的 ${service_type}...${RESET}"
        
        local result=$(call_agent_api "$id" "/api/uninstall" "POST" "{\"type\": \"$service_type\"}")
        
        if echo "$result" | jq -e '.status == "ok"' &>/dev/null; then
            echo -e "${GREEN}✓ ${name} 卸载成功${RESET}"
        else
            local error=$(echo "$result" | jq -r '.error // "unknown error"')
            echo -e "${RED}✗ ${name} 卸载失败: ${error}${RESET}"
        fi
    done
}

# 查看单个服务器详情
view_server_details() {
    list_servers
    
    local count=$(jq '.servers | length' "$SERVERS_FILE" 2>/dev/null)
    [ "$count" == "0" ] && return
    
    echo ""
    read -p "输入服务器 ID: " server_id
    
    if ! jq -e ".servers[] | select(.id == \"$server_id\")" "$SERVERS_FILE" &>/dev/null; then
        echo -e "${RED}服务器不存在${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}正在获取详情...${RESET}"
    
    local result=$(call_agent_api "$server_id" "/api/status")
    
    if ! echo "$result" | jq -e '.ip' &>/dev/null; then
        echo -e "${RED}无法连接到服务器${RESET}"
        return 1
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   服务器详情${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}IP: ${YELLOW}$(echo "$result" | jq -r '.ip')${RESET}"
    echo -e "${CYAN}主机名: ${YELLOW}$(echo "$result" | jq -r '.hostname')${RESET}"
    echo ""
    echo -e "${CYAN}服务状态:${RESET}"
    
    for svc in snell singbox reality hysteria2; do
        local status=$(echo "$result" | jq -r ".services.${svc}.status // \"none\"")
        local installed=$(echo "$result" | jq -r ".services.${svc}.installed // false")
        
        if [ "$installed" == "true" ]; then
            if [ "$status" == "active" ]; then
                echo -e "  ${svc}: ${GREEN}运行中${RESET}"
            else
                echo -e "  ${svc}: ${RED}已停止${RESET}"
            fi
        else
            echo -e "  ${svc}: ${YELLOW}未安装${RESET}"
        fi
    done
    echo ""
}

# =========================================
# Agent 安装函数
# =========================================

# 显示 Agent 安装命令
show_agent_install_command() {
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   在目标 VPS 安装 Agent${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}复制以下命令到目标 VPS 执行:${RESET}"
    echo ""
    echo -e "${YELLOW}bash <(curl -sL ${AGENT_INSTALL_URL})${RESET}"
    echo ""
    echo -e "${CYAN}安装完成后会显示:${RESET}"
    echo -e "  - 服务器 IP"
    echo -e "  - Agent 端口 (默认 9900)"
    echo -e "  - Token (添加服务器时需要)"
    echo ""
    echo -e "${GREEN}然后回到此菜单选择 [1] 添加服务器${RESET}"
    echo ""
}

# 在本机安装 Agent
install_agent_local() {
    echo ""
    echo -e "${CYAN}正在本机安装 Agent...${RESET}"
    echo ""
    
    # 下载并执行安装脚本
    if [ -f "${SCRIPT_DIR}/agent/install-agent.sh" ]; then
        bash "${SCRIPT_DIR}/agent/install-agent.sh"
    else
        bash <(curl -sL "${AGENT_INSTALL_URL}")
    fi
}
# 卸载本机 Agent
uninstall_agent_local() {
    echo ""
    read -p "确认卸载本机 Agent？(y/n): " confirm
    [ "$confirm" != "y" ] && return
    
    echo -e "${CYAN}正在卸载本机 Agent...${RESET}"
    
    if [ -f "${SCRIPT_DIR}/agent/install-agent.sh" ]; then
        bash "${SCRIPT_DIR}/agent/install-agent.sh" uninstall
    else
        bash <(curl -sL "${AGENT_INSTALL_URL}") uninstall
    fi
}

# =========================================
# 多服务器菜单
# =========================================
show_multi_server_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${GREEN}   多服务器管理 (Agent 模式)${RESET}"
        echo -e "${GREEN}=========================================${RESET}"
        echo ""
        echo -e "${YELLOW}Agent 管理${RESET}"
        echo -e "  ${CYAN}1.${RESET} 显示 Agent 安装命令"
        echo -e "  ${CYAN}2.${RESET} 在本机安装 Agent"
        echo -e "  ${CYAN}3.${RESET} 卸载本机 Agent"
        echo ""
        echo -e "${YELLOW}服务器管理${RESET}"
        echo -e "  ${CYAN}4.${RESET} 添加服务器"
        echo -e "  ${CYAN}5.${RESET} 删除服务器"
        echo -e "  ${CYAN}6.${RESET} 查看服务器列表"
        echo ""
        echo -e "${YELLOW}状态监控${RESET}"
        echo -e "  ${CYAN}7.${RESET} 批量查看状态"
        echo -e "  ${CYAN}8.${RESET} 查看单个服务器详情"
        echo ""
        echo -e "${YELLOW}批量操作${RESET}"
        echo -e "  ${CYAN}9.${RESET} 批量重启服务"
        echo -e "  ${CYAN}10.${RESET} 批量卸载服务"
        echo ""
        echo -e "  ${CYAN}0.${RESET} 返回上级菜单"
        echo ""
        
        read -p "请选择 [0-10]: " choice
        
        case $choice in
            1) show_agent_install_command ;;
            2) install_agent_local ;;
            3) uninstall_agent_local ;;
            4) add_server ;;
            5) remove_server ;;
            6) list_servers ;;
            7) batch_status ;;
            8) view_server_details ;;
            9) batch_restart ;;
            10) batch_uninstall ;;
            0) return ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
        
        read -p "按回车键继续..."
    done
}
