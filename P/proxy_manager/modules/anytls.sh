#!/bin/bash
# =========================================
# Proxy Manager - AnyTLS Module
# AnyTLS + Let's Encrypt 安装/卸载/更新/查看
# 使用 sing-box 核心 (v1.12.0+)
# =========================================

[[ -n "${_ANYTLS_LOADED:-}" ]] && return 0
_ANYTLS_LOADED=1

# =========================================
# 检测函数
# =========================================
check_anytls_installed() {
    [ -f "/etc/anytls-proxy-config.txt" ] && return 0
    [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null && jq -e ".anytls" "$CONFIG_FILE" &>/dev/null && return 0
    return 1
}

# =========================================
# 创建 AnyTLS 配置文件
# =========================================
create_anytls_config() {
    local config_file=$1
    local port=$2
    local password=$3
    local domain=$4
    local padding_scheme=$5
    
    local config=$(jq -n \
        --arg port "$port" \
        --arg password "$password" \
        --arg domain "$domain" \
        --argjson padding "$padding_scheme" \
        '{
            "log": {"level": "info", "timestamp": true},
            "inbounds": [{
                "type": "anytls",
                "tag": "anytls-in",
                "listen": "::",
                "listen_port": ($port | tonumber),
                "users": [{"password": $password}],
                "padding_scheme": $padding,
                "tls": {
                    "enabled": true,
                    "server_name": $domain,
                    "key_path": "/etc/anytls/server.key",
                    "certificate_path": "/etc/anytls/server.crt"
                }
            }],
            "outbounds": [{"type": "direct", "tag": "direct"}]
        }')
    
    echo "$config" > "$config_file"
    
    /usr/local/bin/sing-box check -c "$config_file" 2>&1 || return 1
}

# =========================================
# 填充方案选择
# =========================================
select_padding_scheme() {
    echo ""
    echo -e "${CYAN}选择填充方案:${RESET}"
    echo -e "${YELLOW}1.${RESET} 默认方案 ${GREEN}(推荐)${RESET}"
    echo -e "   适合大多数场景，平衡性能和隐蔽性"
    echo -e "${YELLOW}2.${RESET} 激进方案"
    echo -e "   更多填充，更强隐蔽性，略影响性能"
    echo -e "${YELLOW}3.${RESET} 最小方案"
    echo -e "   最少填充，性能最优，隐蔽性较低"
    echo ""
    
    read -p "请选择 [1-3] (默认: 1): " padding_choice
    padding_choice=${padding_choice:-1}
    
    case $padding_choice in
        1)
            # 默认方案 - 官方推荐
            PADDING_SCHEME='["stop=8", "0=30-30", "1=100-400", "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000", "3=9-9,500-1000", "4=500-1000", "5=500-1000", "6=500-1000", "7=500-1000"]'
            PADDING_NAME="默认"
            ;;
        2)
            # 激进方案 - 更多填充
            PADDING_SCHEME='["stop=12", "0=50-100", "1=200-600", "2=500-800,c,800-1200,c,800-1200,c,800-1200,c,800-1200,c,800-1200", "3=15-15,600-1200", "4=600-1200", "5=600-1200", "6=600-1200", "7=600-1200", "8=600-1200", "9=600-1200", "10=600-1200", "11=600-1200"]'
            PADDING_NAME="激进"
            ;;
        3)
            # 最小方案 - 性能优先
            PADDING_SCHEME='["stop=4", "0=10-20", "1=50-150", "2=100-300", "3=5-5,200-400"]'
            PADDING_NAME="最小"
            ;;
        *)
            PADDING_SCHEME='["stop=8", "0=30-30", "1=100-400", "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000", "3=9-9,500-1000", "4=500-1000", "5=500-1000", "6=500-1000", "7=500-1000"]'
            PADDING_NAME="默认"
            ;;
    esac
    
    echo -e "${GREEN}已选择: ${PADDING_NAME}方案${RESET}"
}

# =========================================
# 安装证书到 AnyTLS
# =========================================
install_cert_to_anytls() {
    local domain=$1
    
    mkdir -p /etc/anytls
    
    id -u anytls &>/dev/null || useradd -r -s /usr/sbin/nologin anytls
    
    local default_group=$(get_default_group)
    
    if ! ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
        --key-file /etc/anytls/server.key \
        --fullchain-file /etc/anytls/server.crt \
        --reloadcmd "chown anytls:${default_group} /etc/anytls/server.key /etc/anytls/server.crt && chmod 600 /etc/anytls/server.key && systemctl restart anytls 2>/dev/null || true" \
        2>"${LOG_DIR}/acme-install-cert-anytls.log"; then
        echo -e "${RED}证书安装失败${RESET}"
        return 1
    fi
    
    chown anytls:${default_group} /etc/anytls/server.key /etc/anytls/server.crt 2>/dev/null
    chmod 600 /etc/anytls/server.key
    chmod 644 /etc/anytls/server.crt
    
    echo -e "${GREEN}✓ 证书安装成功${RESET}"
}

# =========================================
# 安装 AnyTLS
# =========================================
install_anytls() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装 AnyTLS (Let's Encrypt)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if check_anytls_installed; then
        read -p "AnyTLS 已安装，重新安装？(y/n): " reinstall
        [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ] && return
        uninstall_anytls
    fi
    
    install_dependencies
    detect_architecture
    get_server_ip
    
    # 检查 sing-box 版本 (需要 v1.12.0+)
    download_singbox
    
    local singbox_version=$(/usr/local/bin/sing-box version 2>/dev/null | awk '/version/ {print $3}' | head -1)
    if [ -n "$singbox_version" ]; then
        # 简单版本比较 (主版本号.次版本号)
        local major=$(echo "$singbox_version" | cut -d. -f1)
        local minor=$(echo "$singbox_version" | cut -d. -f2)
        if [ "$major" -lt 1 ] || ([ "$major" -eq 1 ] && [ "$minor" -lt 12 ]); then
            echo -e "${RED}sing-box 版本过低，AnyTLS 需要 v1.12.0+${RESET}"
            echo -e "${YELLOW}当前版本: ${singbox_version}${RESET}"
            return 1
        fi
    fi
    
    # 生成密码
    ANYTLS_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    
    # 端口配置
    while true; do
        read -p "请输入 AnyTLS 端口 (默认: 443): " ANYTLS_PORT
        ANYTLS_PORT=${ANYTLS_PORT:-443}
        validate_port "$ANYTLS_PORT" && break
    done
    
    # 填充方案选择
    select_padding_scheme
    
    # 域名配置
    echo ""
    echo -e "${YELLOW}请输入域名 (必须已解析到此服务器):${RESET}"
    while true; do
        read -p "域名: " ANYTLS_DOMAIN
        [ -z "$ANYTLS_DOMAIN" ] && { echo -e "${RED}域名不能为空${RESET}"; continue; }
        validate_domain "$ANYTLS_DOMAIN" && break
    done
    
    echo -e "${CYAN}域名: ${YELLOW}${ANYTLS_DOMAIN}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${ANYTLS_PORT}${RESET}"
    read -p "确认继续？(y/n): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return
    
    # 安装证书
    install_acme || return 1
    issue_letsencrypt_cert "$ANYTLS_DOMAIN" || return 1
    install_cert_to_anytls "$ANYTLS_DOMAIN" || return 1
    
    mkdir -p /etc/anytls
    
    # 创建配置，使用选择的填充方案
    if ! create_anytls_config "/etc/anytls/config.json" "$ANYTLS_PORT" "$ANYTLS_PASSWORD" "$ANYTLS_DOMAIN" "$PADDING_SCHEME"; then
        echo -e "${RED}配置文件创建失败${RESET}"
        return 1
    fi
    
    id -u anytls &>/dev/null || useradd -r -s /usr/sbin/nologin anytls
    
    local default_group=$(get_default_group)
    
    cat <<EOF > /lib/systemd/system/anytls.service
[Unit]
Description=AnyTLS Service
After=network-online.target

[Service]
Type=simple
User=anytls
Group=${default_group}
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/anytls/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable anytls
    systemctl start anytls
    
    # 验证服务启动
    verify_service_started "anytls" || log_message "WARN" "AnyTLS 服务启动异常"
    
    # 保存配置
    cat <<EOF > /etc/anytls-proxy-config.txt
TYPE=anytls
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
ANYTLS_PORT=$ANYTLS_PORT
ANYTLS_PASSWORD=$ANYTLS_PASSWORD
ANYTLS_DOMAIN=$ANYTLS_DOMAIN
CERT_TYPE=letsencrypt
PADDING_NAME=$PADDING_NAME
EOF
    
    # 设置配置文件权限
    secure_config_file "/etc/anytls-proxy-config.txt"
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}域名: ${YELLOW}${ANYTLS_DOMAIN}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${ANYTLS_PORT}${RESET}"
    echo -e "${CYAN}密码: ${YELLOW}${ANYTLS_PASSWORD}${RESET}"
    echo -e "${CYAN}填充方案: ${YELLOW}${PADDING_NAME}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = anytls, ${ANYTLS_DOMAIN}, ${ANYTLS_PORT}, password=${ANYTLS_PASSWORD}, sni=${ANYTLS_DOMAIN}${RESET}"
    echo ""
}

# =========================================
# 卸载 AnyTLS
# =========================================
uninstall_anytls() {
    if [ -f /etc/anytls-proxy-config.txt ]; then
        safe_source_config /etc/anytls-proxy-config.txt
        
        if [ "$CERT_TYPE" == "letsencrypt" ] && [ -n "$ANYTLS_DOMAIN" ]; then
            read -p "删除证书？(y/n): " remove_cert
            [ "$remove_cert" == "y" ] && ~/.acme.sh/acme.sh --remove -d "$ANYTLS_DOMAIN" --ecc 2>/dev/null
        fi
    fi
    
    # 停止服务
    systemctl stop anytls 2>/dev/null
    systemctl disable anytls 2>/dev/null
    
    # 删除服务文件
    rm -f /lib/systemd/system/anytls.service
    
    # 删除配置和证书
    rm -rf /etc/anytls
    rm -f /etc/anytls-proxy-config.txt
    
    # 删除用户
    id -u anytls &>/dev/null && userdel anytls 2>/dev/null
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ AnyTLS 已卸载${RESET}"
}

# =========================================
# 查看 AnyTLS 配置
# =========================================
view_anytls_config() {
    [ ! -f /etc/anytls-proxy-config.txt ] && { echo -e "${RED}未找到配置${RESET}"; return; }
    
    safe_source_config /etc/anytls-proxy-config.txt
    local status=$(systemctl is-active anytls 2>/dev/null || echo "未运行")
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   AnyTLS 配置${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}域名: ${YELLOW}${ANYTLS_DOMAIN}${RESET}"
    echo -e "${CYAN}状态: ${YELLOW}${status}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${ANYTLS_PORT}${RESET}"
    [ -n "$PADDING_NAME" ] && echo -e "${CYAN}填充方案: ${YELLOW}${PADDING_NAME}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = anytls, ${ANYTLS_DOMAIN}, ${ANYTLS_PORT}, password=${ANYTLS_PASSWORD}, sni=${ANYTLS_DOMAIN}${RESET}"
    echo ""
}

# =========================================
# 更新 AnyTLS (sing-box 核心)
# =========================================
update_anytls() {
    if ! check_anytls_installed; then
        echo -e "${RED}AnyTLS 未安装${RESET}"
        return
    fi
    
    echo -e "${GREEN}正在检查 AnyTLS (sing-box) 更新...${RESET}"
    
    detect_architecture
    
    local current_version=""
    if [ -f /etc/anytls-proxy-config.txt ]; then
        current_version=$(grep "^SINGBOX_VERSION=" /etc/anytls-proxy-config.txt 2>/dev/null | cut -d'=' -f2)
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
    systemctl stop anytls 2>/dev/null
    
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
        sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$latest_version/" /etc/anytls-proxy-config.txt 2>/dev/null
        
        systemctl start anytls
        verify_service_started "anytls"
        
        echo -e "${GREEN}✓ 更新成功！${RESET}"
    else
        # 回滚
        mv /usr/local/bin/sing-box.bak /usr/local/bin/sing-box 2>/dev/null
        systemctl start anytls
        echo -e "${RED}更新失败，已回滚${RESET}"
    fi
    
    rm -f /usr/local/bin/sing-box.bak 2>/dev/null
}

# =========================================
# 续签 AnyTLS 证书
# =========================================
renew_anytls_cert() {
    local domain=$(grep "^ANYTLS_DOMAIN=" /etc/anytls-proxy-config.txt 2>/dev/null | cut -d'=' -f2)
    
    [ -z "$domain" ] && { echo -e "${RED}未找到域名配置${RESET}"; return 1; }
    
    echo -e "${CYAN}正在续签证书: ${domain}${RESET}"
    
    systemctl stop anytls 2>/dev/null
    
    if ~/.acme.sh/acme.sh --renew -d "$domain" --ecc --force 2>"${LOG_DIR}/acme-renew-anytls.log"; then
        install_cert_to_anytls "$domain"
        systemctl start anytls
        echo -e "${GREEN}✓ 证书续签成功${RESET}"
    else
        systemctl start anytls
        echo -e "${RED}证书续签失败${RESET}"
        return 1
    fi
}
