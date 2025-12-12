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
    local enable_fallback=$5
    local fallback_port=${6:-8080}
    
    # 默认填充方案
    local padding_scheme='["stop=8", "0=30-30", "1=100-400", "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000", "3=9-9,500-1000", "4=500-1000", "5=500-1000", "6=500-1000", "7=500-1000"]'
    
    local config
    if [ "$enable_fallback" = "true" ]; then
        config=$(jq -n \
            --arg port "$port" \
            --arg password "$password" \
            --arg domain "$domain" \
            --arg fallback_port "$fallback_port" \
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
                    },
                    "fallback": {
                        "server": "127.0.0.1",
                        "server_port": ($fallback_port | tonumber)
                    }
                }],
                "outbounds": [{"type": "direct", "tag": "direct"}]
            }')
    else
        config=$(jq -n \
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
    fi
    
    echo "$config" > "$config_file"
    
    /usr/local/bin/sing-box check -c "$config_file" 2>&1 || return 1
}

# =========================================
# 创建 Fallback 伪装页面
# =========================================
create_fallback_page() {
    mkdir -p /var/www/anytls-fallback
    
    cat > /var/www/anytls-fallback/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
               display: flex; justify-content: center; align-items: center; 
               height: 100vh; margin: 0; background: #f5f5f5; }
        .container { text-align: center; padding: 40px; }
        h1 { color: #333; font-weight: 300; }
        p { color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to our server</h1>
        <p>This page is under construction.</p>
    </div>
</body>
</html>
EOF
}

# =========================================
# 启动简易 HTTP 服务 (用于 Fallback)
# =========================================
setup_fallback_service() {
    local port=$1
    
    # 创建伪装页面
    create_fallback_page
    
    # 使用 Python 的简易 HTTP 服务器
    local default_group=$(get_default_group)
    
    cat > /lib/systemd/system/anytls-fallback.service << EOF
[Unit]
Description=AnyTLS Fallback HTTP Server
After=network-online.target

[Service]
Type=simple
User=nobody
Group=${default_group}
WorkingDirectory=/var/www/anytls-fallback
ExecStart=/usr/bin/python3 -m http.server ${port} --bind 127.0.0.1
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable anytls-fallback
    systemctl start anytls-fallback
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
    
    local singbox_version=$(/usr/local/bin/sing-box version 2>/dev/null | grep -oP 'version \K[0-9.]+' | head -1)
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
        read -p "请输入 AnyTLS 端口 (默认: 8443): " ANYTLS_PORT
        ANYTLS_PORT=${ANYTLS_PORT:-8443}
        validate_port "$ANYTLS_PORT" && break
    done
    
    # Fallback 配置 (默认启用)
    echo ""
    echo -e "${CYAN}Fallback 功能说明:${RESET}"
    echo -e "${YELLOW}启用后，非代理请求会返回伪装网页，提高抗检测能力${RESET}"
    read -p "启用 Fallback？(Y/n，默认: Y): " enable_fallback
    enable_fallback=${enable_fallback:-Y}
    
    if [ "$enable_fallback" == "n" ] || [ "$enable_fallback" == "N" ]; then
        ENABLE_FALLBACK=false
        FALLBACK_PORT=""
    else
        ENABLE_FALLBACK=true
        FALLBACK_PORT=8080
        
        # 检查 Python3 是否可用
        if ! command -v python3 &>/dev/null; then
            echo -e "${YELLOW}未检测到 Python3，正在安装...${RESET}"
            apt-get update && apt-get install -y python3 || yum install -y python3 || {
                echo -e "${RED}Python3 安装失败，禁用 Fallback${RESET}"
                ENABLE_FALLBACK=false
            }
        fi
    fi
    
    # 域名配置
    echo ""
    echo -e "${YELLOW}请输入域名 (必须已解析到此服务器):${RESET}"
    while true; do
        read -p "域名: " ANYTLS_DOMAIN
        [ -z "$ANYTLS_DOMAIN" ] && { echo -e "${RED}域名不能为空${RESET}"; continue; }
        validate_domain "$ANYTLS_DOMAIN" && break
    done
    
    echo -e "${CYAN}域名: ${YELLOW}${ANYTLS_DOMAIN}${RESET}"
    read -p "确认继续？(y/n): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return
    
    # 安装证书
    install_acme || return 1
    issue_letsencrypt_cert "$ANYTLS_DOMAIN" || return 1
    install_cert_to_anytls "$ANYTLS_DOMAIN" || return 1
    
    # 启动 Fallback 服务
    if [ "$ENABLE_FALLBACK" = true ]; then
        setup_fallback_service "$FALLBACK_PORT"
    fi
    
    mkdir -p /etc/anytls
    
    if ! create_anytls_config "/etc/anytls/config.json" "$ANYTLS_PORT" "$ANYTLS_PASSWORD" "$ANYTLS_DOMAIN" "$ENABLE_FALLBACK" "$FALLBACK_PORT"; then
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
ENABLE_FALLBACK=$ENABLE_FALLBACK
FALLBACK_PORT=$FALLBACK_PORT
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
    [ "$ENABLE_FALLBACK" = true ] && echo -e "${CYAN}Fallback: ${GREEN}已启用${RESET}"
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
    systemctl stop anytls-fallback 2>/dev/null
    systemctl disable anytls-fallback 2>/dev/null
    
    # 删除服务文件
    rm -f /lib/systemd/system/anytls.service
    rm -f /lib/systemd/system/anytls-fallback.service
    
    # 删除配置和证书
    rm -rf /etc/anytls
    rm -f /etc/anytls-proxy-config.txt
    rm -rf /var/www/anytls-fallback
    
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
    local fallback_status=""
    
    if [ "$ENABLE_FALLBACK" = "true" ]; then
        fallback_status=$(systemctl is-active anytls-fallback 2>/dev/null || echo "未运行")
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   AnyTLS 配置${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}域名: ${YELLOW}${ANYTLS_DOMAIN}${RESET}"
    echo -e "${CYAN}状态: ${YELLOW}${status}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${ANYTLS_PORT}${RESET}"
    [ "$ENABLE_FALLBACK" = "true" ] && echo -e "${CYAN}Fallback: ${GREEN}已启用${RESET} (状态: ${fallback_status})"
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
