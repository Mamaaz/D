#!/bin/bash
# =========================================
# Proxy Manager - Hysteria2 Module
# Hysteria2 + Let's Encrypt 安装/卸载/更新/查看
# =========================================

[[ -n "${_HYSTERIA2_LOADED:-}" ]] && return 0
_HYSTERIA2_LOADED=1

# =========================================
# 检测函数
# =========================================
check_hysteria2_installed() {
    [ -f "/etc/hysteria2-proxy-config.txt" ] && return 0
    [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null && jq -e ".hysteria2" "$CONFIG_FILE" &>/dev/null && return 0
    return 1
}

# =========================================
# 创建配置文件
# =========================================
create_hysteria2_config() {
    local config_file=$1
    local port=$2
    local password=$3
    local domain=$4
    local enable_obfs=$5
    local obfs_password=$6
    
    local config=$(jq -n \
        --arg port "$port" \
        --arg password "$password" \
        --arg domain "$domain" \
        '{
            "log": {"level": "info", "timestamp": true},
            "inbounds": [{
                "type": "hysteria2",
                "tag": "hy2-in",
                "listen": "::",
                "listen_port": ($port | tonumber),
                "users": [{"name": "user1", "password": $password}],
                "tls": {
                    "enabled": true,
                    "server_name": $domain,
                    "key_path": "/etc/hysteria2/server.key",
                    "certificate_path": "/etc/hysteria2/server.crt"
                }
            }],
            "outbounds": [{"type": "direct", "tag": "direct"}]
        }')
    
    if [ "$enable_obfs" = "true" ]; then
        config=$(echo "$config" | jq --arg obfs "$obfs_password" '.inbounds[0].obfs = {"type": "salamander", "password": $obfs}')
    fi
    
    echo "$config" > "$config_file"
    
    /usr/local/bin/sing-box check -c "$config_file" 2>&1 || return 1
}

# =========================================
# 安装 Hysteria2
# =========================================
install_hysteria2() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装 Hysteria2 (Let's Encrypt)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if check_hysteria2_installed; then
        read -p "Hysteria2 已安装，重新安装？(y/n): " reinstall
        [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ] && return
        uninstall_hysteria2
    fi
    
    install_dependencies
    detect_architecture
    get_server_ip
    download_singbox
    
    HYSTERIA2_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    while true; do
        read -p "请输入 Hysteria2 端口 (默认: 443): " HYSTERIA2_PORT
        HYSTERIA2_PORT=${HYSTERIA2_PORT:-443}
        validate_port "$HYSTERIA2_PORT" && break
    done
    
    # 混淆配置
    read -p "启用混淆？(y/n，默认: n): " enable_obfs
    enable_obfs=${enable_obfs:-n}
    
    if [ "$enable_obfs" == "y" ] || [ "$enable_obfs" == "Y" ]; then
        ENABLE_OBFS=true
        OBFS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
        echo -e "${GREEN}混淆密码: ${OBFS_PASSWORD}${RESET}"
    else
        ENABLE_OBFS=false
        OBFS_PASSWORD=""
    fi
    
    # 域名配置
    echo -e "${YELLOW}请输入域名 (必须已解析到此服务器):${RESET}"
    while true; do
        read -p "域名: " HYSTERIA2_DOMAIN
        [ -z "$HYSTERIA2_DOMAIN" ] && { echo -e "${RED}域名不能为空${RESET}"; continue; }
        validate_domain "$HYSTERIA2_DOMAIN" && break
    done
    
    echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    read -p "确认继续？(y/n): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return
    
    # 安装证书
    install_acme || return 1
    issue_letsencrypt_cert "$HYSTERIA2_DOMAIN" || return 1
    install_cert_to_hysteria2 "$HYSTERIA2_DOMAIN" || return 1
    
    mkdir -p /etc/hysteria2
    
    if ! create_hysteria2_config "/etc/hysteria2/config.json" "$HYSTERIA2_PORT" "$HYSTERIA2_PASSWORD" "$HYSTERIA2_DOMAIN" "$ENABLE_OBFS" "$OBFS_PASSWORD"; then
        echo -e "${RED}配置文件创建失败${RESET}"
        return 1
    fi
    
    id -u hysteria2 &>/dev/null || useradd -r -s /usr/sbin/nologin hysteria2
    
    local default_group=$(get_default_group)
    cat <<EOF > /lib/systemd/system/hysteria2.service
[Unit]
Description=Hysteria2 Service
After=network-online.target

[Service]
Type=simple
User=hysteria2
Group=${default_group}
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/hysteria2/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable hysteria2
    systemctl start hysteria2
    
    # 验证服务启动
    verify_service_started "hysteria2" || log_message "WARN" "Hysteria2 服务启动异常"
    
    # 保存配置
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
    
    # 设置配置文件权限
    secure_config_file "/etc/hysteria2-proxy-config.txt"
    
    # 生成分享链接
    if [ "$ENABLE_OBFS" = true ]; then
        local link="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
    else
        local link="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${HYSTERIA2_PORT}${RESET}"
    echo -e "${CYAN}密码: ${YELLOW}${HYSTERIA2_PASSWORD}${RESET}"
    [ "$ENABLE_OBFS" = true ] && echo -e "${CYAN}混淆密码: ${YELLOW}${OBFS_PASSWORD}${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${link}${RESET}"
    echo ""
    
    command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "$link"
    
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
    else
        echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}${RESET}"
    fi
    echo ""
}

# =========================================
# 卸载
# =========================================
uninstall_hysteria2() {
    if [ -f /etc/hysteria2-proxy-config.txt ]; then
        safe_source_config /etc/hysteria2-proxy-config.txt
        
        if [ "$CERT_TYPE" == "letsencrypt" ] && [ -n "$HYSTERIA2_DOMAIN" ]; then
            read -p "删除证书？(y/n): " remove_cert
            [ "$remove_cert" == "y" ] && ~/.acme.sh/acme.sh --remove -d "$HYSTERIA2_DOMAIN" --ecc 2>/dev/null
        fi
    fi
    
    systemctl stop hysteria2 2>/dev/null
    systemctl disable hysteria2 2>/dev/null
    rm -f /lib/systemd/system/hysteria2.service
    rm -rf /etc/hysteria2
    rm -f /etc/hysteria2-proxy-config.txt
    id -u hysteria2 &>/dev/null && userdel hysteria2 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}✓ Hysteria2 已卸载${RESET}"
}

# =========================================
# 查看配置
# =========================================
view_hysteria2_config() {
    [ ! -f /etc/hysteria2-proxy-config.txt ] && { echo -e "${RED}未找到配置${RESET}"; return; }
    
    safe_source_config /etc/hysteria2-proxy-config.txt
    local status=$(systemctl is-active hysteria2 2>/dev/null || echo "未运行")
    
    if [ "$ENABLE_OBFS" = "true" ]; then
        local link="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=${HYSTERIA2_DOMAIN}#Hysteria2"
    else
        local link="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_DOMAIN}#Hysteria2"
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Hysteria2 配置${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo -e "${CYAN}状态: ${YELLOW}${status}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${HYSTERIA2_PORT}${RESET}"
    [ "$ENABLE_OBFS" = "true" ] && echo -e "${CYAN}混淆: ${GREEN}已启用${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${link}${RESET}"
    echo ""
}

# =========================================
# 更新 Hysteria2 (sing-box 核心)
# =========================================
update_hysteria2() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装${RESET}"
        return
    fi
    
    echo -e "${GREEN}正在检查 Hysteria2 (sing-box) 更新...${RESET}"
    
    detect_architecture
    
    local current_version=""
    if [ -f /etc/hysteria2-proxy-config.txt ]; then
        current_version=$(grep "^SINGBOX_VERSION=" /etc/hysteria2-proxy-config.txt 2>/dev/null | cut -d'=' -f2)
    fi
    local latest_version=$(get_latest_version "" "sing-box" "$DEFAULT_SINGBOX_VERSION")
    
    echo -e "${CYAN}当前版本: ${YELLOW}${current_version:-未知}${RESET}"
    echo -e "${CYAN}最新版本: ${YELLOW}${latest_version}${RESET}"
    
    if [ "$current_version" == "$latest_version" ]; then
        echo -e "${GREEN}已是最新版本${RESET}"
        return
    fi
    
    read -p "确认更新？(y/n): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return
    
    # 停止服务
    systemctl stop hysteria2 2>/dev/null
    
    # 备份旧版本
    cp /usr/local/bin/sing-box /usr/local/bin/sing-box.bak 2>/dev/null
    
    # 下载新版本
    local url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/sing-box-${latest_version#v}-linux-${SINGBOX_ARCH}.tar.gz"
    local temp_file=$(create_temp_file ".tar.gz")
    
    if download_file "$url" "$temp_file" 3 5; then
        cd /tmp || { rm -f "$temp_file"; return 1; }
        tar -xzf "$temp_file" || { rm -f "$temp_file"; return 1; }
        rm -f "$temp_file"
        
        local dir=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
        if [ -n "$dir" ]; then
            mv "$dir/sing-box" /usr/local/bin/
            chmod +x /usr/local/bin/sing-box
            rm -rf "$dir"
        fi
        
        rm -rf /tmp/sing-box* 2>/dev/null || true
        
        # 更新配置文件中的版本
        sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$latest_version/" /etc/hysteria2-proxy-config.txt 2>/dev/null
        
        systemctl start hysteria2
        verify_service_started "hysteria2"
        
        echo -e "${GREEN}✓ 更新成功！${RESET}"
    else
        # 回滚
        mv /usr/local/bin/sing-box.bak /usr/local/bin/sing-box 2>/dev/null
        systemctl start hysteria2
        echo -e "${RED}更新失败，已回滚${RESET}"
    fi
    
    rm -f /usr/local/bin/sing-box.bak 2>/dev/null
}
