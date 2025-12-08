#!/bin/bash
# =========================================
# Proxy Manager - Reality Module
# VLESS Reality 安装/卸载/更新/查看
# =========================================

[[ -n "${_REALITY_LOADED:-}" ]] && return 0
_REALITY_LOADED=1

# =========================================
# 检测函数
# =========================================
check_reality_installed() {
    [ -f "/etc/reality-proxy-config.txt" ] && return 0
    [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null && jq -e ".reality" "$CONFIG_FILE" &>/dev/null && return 0
    return 1
}

# =========================================
# Reality 目标网站选择
# =========================================
select_reality_dest() {
    echo ""
    echo -e "${CYAN}选择 Reality 目标网站:${RESET}"
    echo -e "${YELLOW}1.${RESET} www.microsoft.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}2.${RESET} www.apple.com"
    echo -e "${YELLOW}3.${RESET} www.cloudflare.com"
    echo -e "${YELLOW}4.${RESET} www.amazon.com"
    echo -e "${YELLOW}5.${RESET} www.google.com"
    echo -e "${YELLOW}0.${RESET} 自定义"
    echo ""
    
    while true; do
        read -p "请选择 [0-5] (默认: 1): " choice
        choice=${choice:-1}
        
        case $choice in
            1) REALITY_DEST="www.microsoft.com"; break ;;
            2) REALITY_DEST="www.apple.com"; break ;;
            3) REALITY_DEST="www.cloudflare.com"; break ;;
            4) REALITY_DEST="www.amazon.com"; break ;;
            5) REALITY_DEST="www.google.com"; break ;;
            0)
                read -p "请输入域名: " REALITY_DEST
                [ -n "$REALITY_DEST" ] && break
                ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
    done
    
    echo -e "${GREEN}已选择: ${REALITY_DEST}${RESET}"
}

# =========================================
# 生成 Reality 密钥对
# =========================================
generate_reality_keypair() {
    log_message "INFO" "生成 Reality 密钥对..."
    
    if [ ! -f /usr/local/bin/sing-box ]; then
        download_singbox
    fi
    
    local output=$(/usr/local/bin/sing-box generate reality-keypair 2>/dev/null)
    
    REALITY_PRIVATE_KEY=$(echo "$output" | grep -i "PrivateKey" | sed -E 's/.*PrivateKey[: ]+([A-Za-z0-9_-]+).*/\1/' | tr -d '[:space:]')
    REALITY_PUBLIC_KEY=$(echo "$output" | grep -i "PublicKey" | sed -E 's/.*PublicKey[: ]+([A-Za-z0-9_-]+).*/\1/' | tr -d '[:space:]')
    
    if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
        echo -e "${RED}密钥对生成失败${RESET}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 密钥对生成成功${RESET}"
}

# =========================================
# 安装 Reality
# =========================================
install_reality() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装 VLESS Reality${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if check_reality_installed; then
        read -p "Reality 已安装，重新安装？(y/n): " reinstall
        [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ] && return
        uninstall_reality
    fi
    
    install_dependencies
    detect_architecture
    get_server_ip
    download_singbox
    
    generate_reality_keypair || return 1
    
    REALITY_UUID=$(cat /proc/sys/kernel/random/uuid)
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    
    select_reality_dest
    
    while true; do
        read -p "请输入 Reality 端口 (默认: 443): " REALITY_PORT
        REALITY_PORT=${REALITY_PORT:-443}
        validate_port "$REALITY_PORT" && break
    done
    
    mkdir -p /etc/sing-box-reality
    
    cat <<EOF > /etc/sing-box-reality/config.json
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "vless",
    "tag": "vless-in",
    "listen": "::",
    "listen_port": $REALITY_PORT,
    "users": [{"uuid": "$REALITY_UUID", "flow": "xtls-rprx-vision"}],
    "tls": {
      "enabled": true,
      "server_name": "$REALITY_DEST",
      "reality": {
        "enabled": true,
        "handshake": {"server": "$REALITY_DEST", "server_port": 443},
        "private_key": "$REALITY_PRIVATE_KEY",
        "short_id": ["$REALITY_SHORT_ID"]
      }
    }
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
    
    id -u sing-box-reality &>/dev/null || useradd -r -s /usr/sbin/nologin sing-box-reality
    
    local default_group=$(get_default_group)
    cat <<EOF > /lib/systemd/system/sing-box-reality.service
[Unit]
Description=Sing-box Reality Service
After=network-online.target

[Service]
Type=simple
User=sing-box-reality
Group=${default_group}
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box-reality/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sing-box-reality
    systemctl start sing-box-reality
    
    cat <<EOF > /etc/reality-proxy-config.txt
TYPE=reality
SERVER_IP=$SERVER_IP
IP_VERSION=$IP_VERSION
SINGBOX_VERSION=$SINGBOX_VERSION
REALITY_PORT=$REALITY_PORT
REALITY_UUID=$REALITY_UUID
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
REALITY_DEST=$REALITY_DEST
EOF
    
    local link="vless://${REALITY_UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#Reality-${SERVER_IP}"
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${REALITY_PORT}${RESET}"
    echo -e "${CYAN}UUID: ${YELLOW}${REALITY_UUID}${RESET}"
    echo -e "${CYAN}Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${RESET}"
    echo -e "${CYAN}Short ID: ${YELLOW}${REALITY_SHORT_ID}${RESET}"
    echo -e "${CYAN}目标网站: ${YELLOW}${REALITY_DEST}${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${link}${RESET}"
    echo ""
    
    command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "$link"
}

# =========================================
# 卸载
# =========================================
uninstall_reality() {
    systemctl stop sing-box-reality 2>/dev/null
    systemctl disable sing-box-reality 2>/dev/null
    rm -f /lib/systemd/system/sing-box-reality.service
    rm -rf /etc/sing-box-reality
    rm -f /etc/reality-proxy-config.txt
    id -u sing-box-reality &>/dev/null && userdel sing-box-reality 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}✓ Reality 已卸载${RESET}"
}

# =========================================
# 查看配置
# =========================================
view_reality_config() {
    [ ! -f /etc/reality-proxy-config.txt ] && { echo -e "${RED}未找到配置${RESET}"; return; }
    
    safe_source_config /etc/reality-proxy-config.txt
    local status=$(systemctl is-active sing-box-reality 2>/dev/null || echo "未运行")
    
    local link="vless://${REALITY_UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#Reality-${SERVER_IP}"
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   VLESS Reality 配置${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}状态: ${YELLOW}${status}${RESET}"
    echo -e "${CYAN}端口: ${YELLOW}${REALITY_PORT}${RESET}"
    echo -e "${CYAN}UUID: ${YELLOW}${REALITY_UUID}${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${link}${RESET}"
    echo ""
}
