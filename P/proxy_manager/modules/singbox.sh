#!/bin/bash
# =========================================
# Proxy Manager - Sing-box Module
# SS-2022 + Shadow-TLS 安装/卸载/更新/查看
# =========================================

[[ -n "${_SINGBOX_LOADED:-}" ]] && return 0
_SINGBOX_LOADED=1

# =========================================
# 检测函数
# =========================================
check_singbox_installed() {
    [ -f "/etc/singbox-proxy-config.txt" ] && return 0
    [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null && jq -e ".singbox" "$CONFIG_FILE" &>/dev/null && return 0
    return 1
}

# =========================================
# 下载 Sing-box
# =========================================
download_singbox() {
    if [ ! -f /usr/local/bin/sing-box ]; then
        log_message "INFO" "开始下载 Sing-box..."
        
        detect_architecture
        
        # 使用统一的版本获取函数
        SINGBOX_VERSION=$(get_latest_version "" "sing-box" "$DEFAULT_SINGBOX_VERSION")
        
        echo -e "${GREEN}Sing-box 版本: ${SINGBOX_VERSION}${RESET}"
        
        local url="https://github.com/SagerNet/sing-box/releases/download/${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
        local temp_file=$(create_temp_file ".tar.gz")
        
        if ! download_file "$url" "$temp_file" 3 5; then
            rm -f "$temp_file" 2>/dev/null || true
            return 1
        fi
        
        # 解压并安装
        cd /tmp || return 1
        tar -xzf "$temp_file" || { rm -f "$temp_file"; return 1; }
        rm -f "$temp_file"
        
        local dir=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
        if [ -n "$dir" ]; then
            mv "$dir/sing-box" /usr/local/bin/
            chmod +x /usr/local/bin/sing-box
            rm -rf "$dir"
        else
            log_message "ERROR" "解压 Sing-box 失败"
            return 1
        fi
        
        # 清理临时文件
        rm -rf /tmp/sing-box* 2>/dev/null || true
        
        echo -e "${GREEN}✓ Sing-box 安装成功${RESET}"
    fi
}

# =========================================
# SS 加密方式选择
# =========================================
select_ss_method() {
    echo ""
    echo -e "${CYAN}选择 Shadowsocks 加密方式:${RESET}"
    echo -e "${YELLOW}1.${RESET} 2022-blake3-aes-256-gcm ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}2.${RESET} 2022-blake3-aes-128-gcm"
    echo -e "${YELLOW}3.${RESET} 2022-blake3-chacha20-poly1305"
    echo ""
    
    read -p "请选择 [1-3] (默认: 1): " choice
    choice=${choice:-1}
    
    case $choice in
        1) SS_METHOD="2022-blake3-aes-256-gcm"; SS_PASSWORD=$(openssl rand -base64 32) ;;
        2) SS_METHOD="2022-blake3-aes-128-gcm"; SS_PASSWORD=$(openssl rand -base64 16) ;;
        3) SS_METHOD="2022-blake3-chacha20-poly1305"; SS_PASSWORD=$(openssl rand -base64 32) ;;
        *) SS_METHOD="2022-blake3-aes-256-gcm"; SS_PASSWORD=$(openssl rand -base64 32) ;;
    esac
    
    echo -e "${GREEN}已选择: ${SS_METHOD}${RESET}"
}

# =========================================
# 创建配置文件
# =========================================
create_singbox_config() {
    local config_file=$1
    local ss_port=$2
    local ss_method=$3
    local ss_password=$4
    local stls_port=$5
    local stls_password=$6
    local tls_domain=$7
    
    jq -n \
        --arg ss_port "$ss_port" \
        --arg ss_method "$ss_method" \
        --arg ss_password "$ss_password" \
        --arg stls_port "$stls_port" \
        --arg stls_password "$stls_password" \
        --arg tls_domain "$tls_domain" \
        '{
            "log": {"level": "info", "timestamp": true},
            "inbounds": [
                {
                    "type": "shadowsocks",
                    "tag": "ss-in",
                    "listen": "127.0.0.1",
                    "listen_port": ($ss_port | tonumber),
                    "method": $ss_method,
                    "password": $ss_password,
                    "tcp_fast_open": true,
                    "udp_fragment": true
                },
                {
                    "type": "shadowtls",
                    "tag": "st-in",
                    "listen": "::",
                    "listen_port": ($stls_port | tonumber),
                    "version": 3,
                    "users": [{"name": "user1", "password": $stls_password}],
                    "handshake": {"server": $tls_domain, "server_port": 443},
                    "strict_mode": true,
                    "detour": "ss-in"
                }
            ],
            "outbounds": [{"type": "direct", "tag": "direct"}]
        }' > "$config_file"
    
    /usr/local/bin/sing-box check -c "$config_file" 2>&1 || return 1
}

# =========================================
# 安装 Sing-box
# =========================================
install_singbox() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装 Sing-box (SS-2022 + Shadow-TLS)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if check_singbox_installed; then
        read -p "Sing-box 已安装，重新安装？(y/n): " reinstall
        [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ] && return
        uninstall_singbox
    fi
    
    install_dependencies
    detect_architecture
    get_server_ip
    download_singbox
    
    select_ss_method
    
    while true; do
        read -p "请输入 SS 监听端口 (默认: 8388): " SS_PORT
        SS_PORT=${SS_PORT:-8388}
        validate_port "$SS_PORT" && break
    done
    
    select_tls_domain
    SINGBOX_TLS_DOMAIN=$TLS_DOMAIN
    
    while true; do
        read -p "请输入 Shadow-TLS 监听端口 (默认: 9443): " SINGBOX_SHADOW_TLS_PORT
        SINGBOX_SHADOW_TLS_PORT=${SINGBOX_SHADOW_TLS_PORT:-9443}
        validate_port "$SINGBOX_SHADOW_TLS_PORT" && break
    done
    
    SINGBOX_SHADOW_TLS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    mkdir -p /etc/sing-box
    
    if ! create_singbox_config "/etc/sing-box/config.json" "$SS_PORT" "$SS_METHOD" "$SS_PASSWORD" "$SINGBOX_SHADOW_TLS_PORT" "$SINGBOX_SHADOW_TLS_PASSWORD" "$SINGBOX_TLS_DOMAIN"; then
        echo -e "${RED}配置文件创建失败${RESET}"
        return 1
    fi
    
    # 创建用户和服务
    id -u sing-box &>/dev/null || useradd -r -s /usr/sbin/nologin sing-box
    
    local default_group=$(get_default_group)
    cat <<EOF > /lib/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network-online.target

[Service]
Type=simple
User=sing-box
Group=${default_group}
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    
    # 验证服务启动
    verify_service_started "sing-box" || log_message "WARN" "Sing-box 服务启动异常"
    
    # 保存配置
    cat <<EOF > /etc/singbox-proxy-config.txt
TYPE=singbox
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
SS_PORT=$SS_PORT
SS_PASSWORD=$SS_PASSWORD
SS_METHOD=$SS_METHOD
SHADOW_TLS_PORT=$SINGBOX_SHADOW_TLS_PORT
SHADOW_TLS_PASSWORD=$SINGBOX_SHADOW_TLS_PASSWORD
TLS_DOMAIN=$SINGBOX_TLS_DOMAIN
EOF
    
    # 设置配置文件权限
    secure_config_file "/etc/singbox-proxy-config.txt"
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}SS 加密方式: ${YELLOW}${SS_METHOD}${RESET}"
    echo -e "${CYAN}Shadow-TLS 端口: ${YELLOW}${SINGBOX_SHADOW_TLS_PORT}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = ss, ${SERVER_IP}, ${SINGBOX_SHADOW_TLS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${SINGBOX_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SINGBOX_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
}

# =========================================
# 卸载
# =========================================
uninstall_singbox() {
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    rm -f /lib/systemd/system/sing-box.service
    rm -rf /etc/sing-box
    rm -f /etc/singbox-proxy-config.txt
    id -u sing-box &>/dev/null && userdel sing-box 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}✓ Sing-box 已卸载${RESET}"
}

# =========================================
# 查看配置
# =========================================
view_singbox_config() {
    [ ! -f /etc/singbox-proxy-config.txt ] && { echo -e "${RED}未找到配置${RESET}"; return; }
    
    safe_source_config /etc/singbox-proxy-config.txt
    local status=$(systemctl is-active sing-box 2>/dev/null || echo "未运行")
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Sing-box 配置${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}状态: ${YELLOW}${status}${RESET}"
    echo -e "${CYAN}加密方式: ${YELLOW}${SS_METHOD}${RESET}"
    echo ""
    echo -e "${CYAN}Surge:${RESET}"
    echo -e "${GREEN}Proxy = ss, ${SERVER_IP}, ${SHADOW_TLS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
}

# =========================================
# 更新 Sing-box
# =========================================
update_singbox() {
    if ! check_singbox_installed; then
        echo -e "${RED}Sing-box 未安装${RESET}"
        return
    fi
    
    echo -e "${GREEN}正在检查 Sing-box 更新...${RESET}"
    
    detect_architecture
    
    local current_version=""
    if [ -f /etc/singbox-proxy-config.txt ]; then
        current_version=$(grep "^SINGBOX_VERSION=" /etc/singbox-proxy-config.txt 2>/dev/null | cut -d'=' -f2)
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
    systemctl stop sing-box 2>/dev/null
    
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
        sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$latest_version/" /etc/singbox-proxy-config.txt 2>/dev/null
        
        systemctl start sing-box
        verify_service_started "sing-box"
        
        echo -e "${GREEN}✓ 更新成功！${RESET}"
    else
        # 回滚
        mv /usr/local/bin/sing-box.bak /usr/local/bin/sing-box 2>/dev/null
        systemctl start sing-box
        echo -e "${RED}更新失败，已回滚${RESET}"
    fi
    
    rm -f /usr/local/bin/sing-box.bak 2>/dev/null
}
