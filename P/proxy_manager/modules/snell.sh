#!/bin/bash
# =========================================
# Proxy Manager - Snell Module
# Snell + Shadow-TLS 安装/卸载/更新/查看
# =========================================

# 防止重复加载
[[ -n "${_SNELL_LOADED:-}" ]] && return 0
_SNELL_LOADED=1

# =========================================
# 检测函数
# =========================================

check_snell_installed() {
    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        if jq -e ".snell" "$CONFIG_FILE" &> /dev/null; then
            return 0
        fi
    fi
    
    if [ -f "/etc/snell-proxy-config.txt" ]; then
        return 0
    fi
    
    return 1
}

# =========================================
# 注意: select_tls_domain 函数已移至 lib/common.sh
# =========================================

# =========================================
# 下载 Shadow-TLS
# =========================================
download_shadow_tls() {
    if [ ! -f /usr/local/bin/shadow-tls ]; then
        log_message "INFO" "开始下载 Shadow-TLS..."
        echo -e "${GREEN}正在下载 Shadow-TLS...${RESET}"
        
        # 使用正确的服务名获取版本
        SHADOW_TLS_VERSION=$(get_latest_version "" "shadow-tls" "$DEFAULT_SHADOW_TLS_VERSION")
        
        echo -e "${GREEN}Shadow-TLS 版本: ${SHADOW_TLS_VERSION}${RESET}"
        
        local url="https://github.com/ihciah/shadow-tls/releases/download/${SHADOW_TLS_VERSION}/shadow-tls-${SHADOW_TLS_ARCH}"
        local temp_file=$(create_temp_file)
        
        if ! download_file "$url" "$temp_file" 3 5; then
            rm -f "$temp_file" 2>/dev/null || true
            return 1
        fi
        
        mv "$temp_file" /usr/local/bin/shadow-tls
        chmod +x /usr/local/bin/shadow-tls
        
        echo -e "${GREEN}✓ Shadow-TLS 安装成功${RESET}"
    else
        echo -e "${GREEN}Shadow-TLS 已安装${RESET}"
    fi
}

# =========================================
# 安装 Snell
# =========================================
install_snell() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装 Snell + Shadow-TLS${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    log_message "INFO" "开始安装 Snell + Shadow-TLS"
    
    if check_snell_installed; then
        echo -e "${YELLOW}检测到 Snell 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            return
        fi
        uninstall_snell
    fi
    
    install_dependencies
    detect_architecture
    get_server_ip
    
    # 下载 Snell
    log_message "INFO" "开始安装 Snell Server..."
    SNELL_VERSION=$(get_latest_version "" "snell" "$DEFAULT_SNELL_VERSION")
    echo -e "${GREEN}Snell 版本: v${SNELL_VERSION}${RESET}"
    
    local url="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"
    local temp_file=$(create_temp_file ".zip")
    
    if ! download_file "$url" "$temp_file" 3 5; then
        return 1
    fi
    
    unzip -o "$temp_file" -d /usr/local/bin
    chmod +x /usr/local/bin/snell-server
    rm -f "$temp_file"
    
    # 生成配置
    mkdir -p /etc/snell
    echo "y" | /usr/local/bin/snell-server --wizard -c /etc/snell/snell-server.conf
    sed -i 's/listen = 0.0.0.0:/listen = 127.0.0.1:/' /etc/snell/snell-server.conf
    
    SNELL_PORT=$(grep "listen" /etc/snell/snell-server.conf | cut -d ':' -f 2 | tr -d ' ')
    SNELL_PSK=$(grep "psk" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')
    
    # 创建用户
    if ! id -u snell > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin snell
    fi
    
    # 创建 systemd 服务
    local default_group=$(get_default_group)
    cat <<EOF > /lib/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=snell
Group=${default_group}
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable snell
    
    # 安装 Shadow-TLS
    download_shadow_tls
    
    SNELL_SHADOW_TLS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    select_tls_domain
    SNELL_TLS_DOMAIN=$TLS_DOMAIN
    
    while true; do
        read -p "请输入 Shadow-TLS 监听端口 (默认: 8444): " SNELL_SHADOW_TLS_PORT
        SNELL_SHADOW_TLS_PORT=${SNELL_SHADOW_TLS_PORT:-8444}
        validate_port "$SNELL_SHADOW_TLS_PORT" && break
    done
    
    cat <<EOF > /etc/systemd/system/shadow-tls-snell.service
[Unit]
Description=Shadow-TLS for Snell
After=network-online.target snell.service
Requires=snell.service

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen ::0:$SNELL_SHADOW_TLS_PORT --server 127.0.0.1:$SNELL_PORT --tls $SNELL_TLS_DOMAIN --password $SNELL_SHADOW_TLS_PASSWORD
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable shadow-tls-snell
    systemctl start snell
    systemctl start shadow-tls-snell
    
    # 验证服务启动
    verify_service_started "snell" || log_message "WARN" "Snell 服务启动异常"
    verify_service_started "shadow-tls-snell" || log_message "WARN" "Shadow-TLS 服务启动异常"
    
    # 保存配置
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
    
    # 设置配置文件权限
    secure_config_file "/etc/snell-proxy-config.txt"
    
    log_message "SUCCESS" "Snell + Shadow-TLS 安装完成"
    
    # 显示配置
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}Snell 版本: ${YELLOW}v${SNELL_VERSION}${RESET}"
    echo -e "${CYAN}Snell PSK: ${YELLOW}${SNELL_PSK}${RESET}"
    echo -e "${CYAN}Shadow-TLS 端口: ${YELLOW}${SNELL_SHADOW_TLS_PORT}${RESET}"
    echo -e "${CYAN}Shadow-TLS 密码: ${YELLOW}${SNELL_SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "${CYAN}伪装域名: ${YELLOW}${SNELL_TLS_DOMAIN}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SNELL_SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SNELL_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SNELL_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
}

# =========================================
# 卸载 Snell
# =========================================
uninstall_snell() {
    echo -e "${YELLOW}正在卸载 Snell + Shadow-TLS...${RESET}"
    
    systemctl stop shadow-tls-snell 2>/dev/null
    systemctl stop snell 2>/dev/null
    systemctl disable shadow-tls-snell 2>/dev/null
    systemctl disable snell 2>/dev/null
    
    rm -f /lib/systemd/system/snell.service
    rm -f /etc/systemd/system/shadow-tls-snell.service
    rm -f /usr/local/bin/snell-server
    rm -rf /etc/snell
    rm -f /etc/snell-proxy-config.txt
    
    if id -u snell > /dev/null 2>&1; then
        userdel snell 2>/dev/null
    fi
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Snell + Shadow-TLS 已卸载${RESET}"
}

# =========================================
# 查看 Snell 配置
# =========================================
view_snell_config() {
    if [ ! -f /etc/snell-proxy-config.txt ]; then
        echo -e "${RED}未找到 Snell 配置${RESET}"
        return
    fi
    
    safe_source_config /etc/snell-proxy-config.txt
    
    local snell_status=$(systemctl is-active snell 2>/dev/null || echo "未运行")
    local shadow_status=$(systemctl is-active shadow-tls-snell 2>/dev/null || echo "未运行")
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Snell + Shadow-TLS 配置${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}Snell 版本: ${YELLOW}v${SNELL_VERSION}${RESET}"
    echo -e "${CYAN}Snell 状态: ${YELLOW}${snell_status}${RESET}"
    echo -e "${CYAN}Shadow-TLS 状态: ${YELLOW}${shadow_status}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
}

# =========================================
# 更新 Snell
# =========================================
update_snell() {
    if ! check_snell_installed; then
        echo -e "${RED}Snell 未安装${RESET}"
        return
    fi
    
    echo -e "${GREEN}正在更新 Snell...${RESET}"
    
    detect_architecture
    
    local current_version=$(get_config "snell" "SNELL_VERSION")
    local latest_version=$(get_latest_version "" "snell" "$DEFAULT_SNELL_VERSION")
    
    echo -e "${CYAN}当前版本: ${YELLOW}${current_version}${RESET}"
    echo -e "${CYAN}最新版本: ${YELLOW}${latest_version}${RESET}"
    
    if [ "$current_version" == "$latest_version" ]; then
        echo -e "${GREEN}已是最新版本${RESET}"
        return
    fi
    
    read -p "确认更新？(y/n): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return
    
    systemctl stop shadow-tls-snell
    systemctl stop snell
    
    cp /usr/local/bin/snell-server /usr/local/bin/snell-server.bak
    
    local url="https://dl.nssurge.com/snell/snell-server-v${latest_version}-linux-${SNELL_ARCH}.zip"
    local temp_file=$(create_temp_file ".zip")
    
    if download_file "$url" "$temp_file" 3 5; then
        unzip -o "$temp_file" -d /usr/local/bin
        chmod +x /usr/local/bin/snell-server
        rm -f "$temp_file"
        
        sed -i "s/SNELL_VERSION=.*/SNELL_VERSION=$latest_version/" /etc/snell-proxy-config.txt
        
        systemctl start snell
        systemctl start shadow-tls-snell
        
        echo -e "${GREEN}✓ 更新成功！${RESET}"
    else
        mv /usr/local/bin/snell-server.bak /usr/local/bin/snell-server
        systemctl start snell
        systemctl start shadow-tls-snell
        echo -e "${RED}更新失败，已回滚${RESET}"
    fi
}
