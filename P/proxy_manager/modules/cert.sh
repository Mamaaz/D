#!/bin/bash
# =========================================
# Proxy Manager - Certificate Module
# Let's Encrypt 证书管理
# =========================================

[[ -n "${_CERT_LOADED:-}" ]] && return 0
_CERT_LOADED=1

# =========================================
# 安装 acme.sh
# =========================================
install_acme() {
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        echo -e "${CYAN}配置 Let's Encrypt 账户${RESET}"
        echo -e "${YELLOW}请输入您的邮箱地址:${RESET}"
        
        while true; do
            read -p "邮箱: " ACME_EMAIL
            [ -z "$ACME_EMAIL" ] && { echo -e "${RED}邮箱不能为空${RESET}"; continue; }
            validate_email "$ACME_EMAIL" && break
        done
        
        echo -e "${CYAN}正在安装 acme.sh...${RESET}"
        
        if ! curl https://get.acme.sh | sh -s email="$ACME_EMAIL" 2>"${LOG_DIR}/acme-install.log"; then
            echo -e "${RED}acme.sh 安装失败${RESET}"
            return 1
        fi
        
        sleep 2
        
        if [ ! -f ~/.acme.sh/acme.sh ]; then
            echo -e "${RED}acme.sh 安装失败：文件不存在${RESET}"
            return 1
        fi
        
        source ~/.acme.sh/acme.sh.env 2>/dev/null || true
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        
        echo -e "${GREEN}✓ acme.sh 安装成功${RESET}"
    fi
}

# =========================================
# 申请证书
# =========================================
issue_letsencrypt_cert() {
    local domain=$1
    local stopped_services=()
    
    echo -e "${CYAN}正在为 ${YELLOW}${domain}${CYAN} 申请证书...${RESET}"
    
    # 检查 80 端口
    if check_port 80; then
        echo -e "${YELLOW}80 端口被占用，尝试停止服务...${RESET}"
        
        for service in nginx apache2 httpd caddy hysteria2; do
            if systemctl is-active --quiet $service 2>/dev/null; then
                systemctl stop $service 2>/dev/null
                stopped_services+=("$service")
            fi
        done
        
        sleep 2
        
        if check_port 80; then
            echo -e "${RED}80 端口仍被占用${RESET}"
            for service in "${stopped_services[@]}"; do
                systemctl start "$service" 2>/dev/null
            done
            return 1
        fi
    fi
    
    if ! ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --keylength ec-256 --force 2>"${LOG_DIR}/acme-issue-${domain}.log"; then
        echo -e "${RED}证书申请失败${RESET}"
        echo -e "${YELLOW}请确保域名 ${domain} 已解析到此服务器${RESET}"
        
        for service in "${stopped_services[@]}"; do
            systemctl start "$service" 2>/dev/null
        done
        return 1
    fi
    
    for service in "${stopped_services[@]}"; do
        systemctl start "$service" 2>/dev/null
    done
    
    echo -e "${GREEN}✓ 证书申请成功${RESET}"
}

# =========================================
# 安装证书到 Hysteria2
# =========================================
install_cert_to_hysteria2() {
    local domain=$1
    
    mkdir -p /etc/hysteria2
    
    id -u hysteria2 &>/dev/null || useradd -r -s /usr/sbin/nologin hysteria2
    
    local default_group=$(get_default_group)
    
    if ! ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
        --key-file /etc/hysteria2/server.key \
        --fullchain-file /etc/hysteria2/server.crt \
        --reloadcmd "chown hysteria2:${default_group} /etc/hysteria2/server.key /etc/hysteria2/server.crt && chmod 600 /etc/hysteria2/server.key && systemctl restart hysteria2 2>/dev/null || true" \
        2>"${LOG_DIR}/acme-install-cert.log"; then
        echo -e "${RED}证书安装失败${RESET}"
        return 1
    fi
    
    chown hysteria2:${default_group} /etc/hysteria2/server.key /etc/hysteria2/server.crt 2>/dev/null
    chmod 600 /etc/hysteria2/server.key
    chmod 644 /etc/hysteria2/server.crt
    
    echo -e "${GREEN}✓ 证书安装成功${RESET}"
}

# =========================================
# 续签证书
# =========================================
renew_hysteria2_cert() {
    local domain=$(get_config "hysteria2" "HYSTERIA2_DOMAIN")
    
    [ -z "$domain" ] && { echo -e "${RED}未找到域名配置${RESET}"; return 1; }
    
    echo -e "${CYAN}正在续签证书: ${domain}${RESET}"
    
    systemctl stop hysteria2 2>/dev/null
    
    if ~/.acme.sh/acme.sh --renew -d "$domain" --ecc --force 2>"${LOG_DIR}/acme-renew.log"; then
        install_cert_to_hysteria2 "$domain"
        systemctl start hysteria2
        echo -e "${GREEN}✓ 证书续签成功${RESET}"
    else
        systemctl start hysteria2
        echo -e "${RED}证书续签失败${RESET}"
        return 1
    fi
}

# =========================================
# 查看证书状态
# =========================================
view_cert_status() {
    local domain=$(get_config "hysteria2" "HYSTERIA2_DOMAIN")
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Hysteria2 证书状态${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    
    if [ -f /etc/hysteria2/server.crt ]; then
        echo -e "${CYAN}域名: ${YELLOW}${domain}${RESET}"
        openssl x509 -in /etc/hysteria2/server.crt -noout -dates -subject
        
        local expiry=$(openssl x509 -in /etc/hysteria2/server.crt -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
        local current_epoch=$(date +%s)
        local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [ $days_left -gt 30 ]; then
            echo -e "${GREEN}剩余: ${days_left} 天${RESET}"
        elif [ $days_left -gt 7 ]; then
            echo -e "${YELLOW}剩余: ${days_left} 天 (建议续签)${RESET}"
        else
            echo -e "${RED}剩余: ${days_left} 天 (请立即续签)${RESET}"
        fi
    else
        echo -e "${RED}证书文件不存在${RESET}"
    fi
    echo ""
}
