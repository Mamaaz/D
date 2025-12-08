#!/bin/bash

# =========================================
# Snell/Sing-box + Shadow-TLS 一键安装脚本
# 支持同时安装多个代理服务和自动更新
# 已集成安全配置和自动断联修复
# 新增 VLESS Reality 支持
# 新增 Hysteria2 支持（Let's Encrypt 证书 + 自动续签）
# 支持 IPv4/IPv6 选择
# 版本: 2.0 (完整修复版)
# =========================================

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 用户运行此脚本或使用 sudo${RESET}"
        exit 1
    fi
}

# 检查服务是否已安装
check_snell_installed() {
    if [ -f /etc/snell-proxy-config.txt ]; then
        return 0
    else
        return 1
    fi
}

check_singbox_installed() {
    if [ -f /etc/singbox-proxy-config.txt ]; then
        return 0
    else
        return 1
    fi
}

check_reality_installed() {
    if [ -f /etc/reality-proxy-config.txt ]; then
        return 0
    else
        return 1
    fi
}

check_hysteria2_installed() {
    if [ -f /etc/hysteria2-proxy-config.txt ]; then
        return 0
    else
        return 1
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${GREEN}   代理 + Shadow-TLS 一键安装脚本${RESET}"
    echo -e "${GREEN}   已集成安全配置和断联修复${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    # 显示已安装的服务
    if check_snell_installed; then
        SNELL_STATUS=$(systemctl is-active snell 2>/dev/null || echo "已停止")
        SNELL_SHADOW_STATUS=$(systemctl is-active shadow-tls-snell 2>/dev/null || echo "已停止")
        
        # 检查 Snell 是否安全配置
        if [ -f /etc/snell/snell-server.conf ]; then
            SNELL_LISTEN=$(grep "listen" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')
            if [[ $SNELL_LISTEN == 127.0.0.1:* ]]; then
                SECURITY_STATUS="${GREEN}[安全]${RESET}"
            else
                SECURITY_STATUS="${RED}[不安全]${RESET}"
            fi
        else
            SECURITY_STATUS=""
        fi
        
        echo -e "${GREEN}✓${RESET} Snell: ${YELLOW}${SNELL_STATUS}${RESET} | Shadow-TLS: ${YELLOW}${SNELL_SHADOW_STATUS}${RESET} ${SECURITY_STATUS}"
    else
        echo -e "${RED}✗${RESET} Snell + Shadow-TLS: 未安装"
    fi
    
    if check_singbox_installed; then
        SINGBOX_STATUS=$(systemctl is-active sing-box 2>/dev/null || echo "已停止")
        echo -e "${GREEN}✓${RESET} Sing-box (SS-2022 + Shadow-TLS): ${YELLOW}${SINGBOX_STATUS}${RESET}"
    else
        echo -e "${RED}✗${RESET} Sing-box (SS-2022 + Shadow-TLS): 未安装"
    fi
    
    if check_reality_installed; then
        REALITY_STATUS=$(systemctl is-active sing-box-reality 2>/dev/null || echo "已停止")
        echo -e "${GREEN}✓${RESET} VLESS Reality: ${YELLOW}${REALITY_STATUS}${RESET}"
    else
        echo -e "${RED}✗${RESET} VLESS Reality: 未安装"
    fi
    
    if check_hysteria2_installed; then
        HYSTERIA2_STATUS=$(systemctl is-active hysteria2 2>/dev/null || echo "已停止")
        # 检查证书类型
        if [ -f /etc/hysteria2-proxy-config.txt ]; then
            source /etc/hysteria2-proxy-config.txt
            if [ "$CERT_TYPE" == "letsencrypt" ]; then
                CERT_INFO="${GREEN}[Let's Encrypt]${RESET}"
            else
                CERT_INFO="${YELLOW}[自签名]${RESET}"
            fi
        else
            CERT_INFO=""
        fi
        echo -e "${GREEN}✓${RESET} Hysteria2: ${YELLOW}${HYSTERIA2_STATUS}${RESET} ${CERT_INFO}"
    else
        echo -e "${RED}✗${RESET} Hysteria2: 未安装"
    fi
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${YELLOW}安装选项:${RESET}"
    echo -e "${YELLOW}1.${RESET}  安装 Snell + Shadow-TLS"
    echo -e "${YELLOW}2.${RESET}  安装 Sing-box (SS-2022 + Shadow-TLS)"
    echo -e "${YELLOW}3.${RESET}  安装 VLESS Reality"
    echo -e "${YELLOW}4.${RESET}  安装 Hysteria2 ${GREEN}(Let's Encrypt 证书)${RESET}"
    echo ""
    echo -e "${YELLOW}更新选项:${RESET}"
    echo -e "${YELLOW}5.${RESET}  更新 Snell 到最新版本"
    echo -e "${YELLOW}6.${RESET}  更新 Sing-box 到最新版本"
    echo -e "${YELLOW}7.${RESET}  更新 Reality 到最新版本"
    echo -e "${YELLOW}8.${RESET}  更新 Hysteria2 到最新版本"
    echo -e "${YELLOW}9.${RESET}  更新所有服务"
    echo ""
    echo -e "${YELLOW}卸载选项:${RESET}"
    echo -e "${YELLOW}10.${RESET} 卸载 Snell + Shadow-TLS"
    echo -e "${YELLOW}11.${RESET} 卸载 Sing-box"
    echo -e "${YELLOW}12.${RESET} 卸载 VLESS Reality"
    echo -e "${YELLOW}13.${RESET} 卸载 Hysteria2"
    echo -e "${YELLOW}14.${RESET} 卸载所有服务"
    echo ""
    echo -e "${YELLOW}查看选项:${RESET}"
    echo -e "${YELLOW}15.${RESET} 查看 Snell 配置"
    echo -e "${YELLOW}16.${RESET} 查看 Sing-box 配置"
    echo -e "${YELLOW}17.${RESET} 查看 VLESS Reality 配置"
    echo -e "${YELLOW}18.${RESET} 查看 Hysteria2 配置"
    echo -e "${YELLOW}19.${RESET} 查看所有配置"
    echo -e "${YELLOW}20.${RESET} 查看服务日志"
    echo ""
    echo -e "${YELLOW}证书管理:${RESET}"
    echo -e "${YELLOW}21.${RESET} 手动续签 Hysteria2 证书"
    echo -e "${YELLOW}22.${RESET} 查看 Hysteria2 证书状态"
    echo ""
    echo -e "${YELLOW}0.${RESET}  退出脚本"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
}

# 安装必要工具
install_dependencies() {
    echo -e "${CYAN}正在更新软件包列表并安装必要工具...${RESET}"
    apt-get update -y && apt-get install -y vim curl wget unzip jq net-tools qrencode iproute2 openssl socat cron
}

# 检测体系结构
detect_architecture() {
    ARCH="$(uname -m)"
    echo -e "${CYAN}检测到系统架构: ${ARCH}${RESET}"

    case "$ARCH" in
        x86_64)
            SNELL_ARCH="amd64"
            SINGBOX_ARCH="amd64"
            SHADOW_TLS_ARCH="x86_64-unknown-linux-musl"
            HYSTERIA2_ARCH="amd64"
            ;;
        aarch64)
            SNELL_ARCH="aarch64"
            SINGBOX_ARCH="arm64"
            SHADOW_TLS_ARCH="aarch64-unknown-linux-musl"
            HYSTERIA2_ARCH="arm64"
            ;;
        armv7l)
            SNELL_ARCH="armv7l"
            SINGBOX_ARCH="armv7"
            SHADOW_TLS_ARCH="armv7-unknown-linux-musleabihf"
            HYSTERIA2_ARCH="armv7"
            ;;
        *)
            echo -e "${RED}不支持的系统架构: $ARCH${RESET}"
            exit 1
            ;;
    esac
}

# 安装 acme.sh（修复版 - 要求输入真实邮箱）
install_acme() {
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        echo -e "${CYAN}正在安装 acme.sh...${RESET}"
        echo ""
        echo -e "${YELLOW}=========================================${RESET}"
        echo -e "${YELLOW}   配置 Let's Encrypt 账户${RESET}"
        echo -e "${YELLOW}=========================================${RESET}"
        echo ""
        echo -e "${CYAN}Let's Encrypt 需要一个有效的邮箱地址用于：${RESET}"
        echo -e "  - 证书到期提醒"
        echo -e "  - 重要的账户通知"
        echo -e "  - 紧急安全公告"
        echo ""
        echo -e "${YELLOW}请输入您的邮箱地址:${RESET}"
        
        while true; do
            read -p "邮箱: " ACME_EMAIL
            
            # 验证邮箱不为空
            if [ -z "$ACME_EMAIL" ]; then
                echo -e "${RED}邮箱不能为空，请重新输入${RESET}"
                continue
            fi
            
            # 验证邮箱格式
            if [[ ! "$ACME_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                echo -e "${RED}邮箱格式不正确，请重新输入${RESET}"
                continue
            fi
            
            # 验证不是 example.com 域名
            if [[ "$ACME_EMAIL" =~ @example\. ]]; then
                echo -e "${RED}不能使用 example.com 域名的邮箱，请输入真实邮箱${RESET}"
                continue
            fi
            
            # 确认邮箱
            echo ""
            echo -e "${CYAN}您输入的邮箱是: ${YELLOW}${ACME_EMAIL}${RESET}"
            read -p "确认无误？(y/n): " confirm
            if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                break
            fi
            echo ""
        done
        
        echo ""
        echo -e "${CYAN}正在安装 acme.sh...${RESET}"
        curl https://get.acme.sh | sh -s email=$ACME_EMAIL
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}acme.sh 安装失败${RESET}"
            return 1
        fi
        
        # 设置默认 CA 为 Let's Encrypt
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        
        echo -e "${GREEN}✓ acme.sh 安装成功${RESET}"
        echo -e "${GREEN}✓ 邮箱: ${ACME_EMAIL}${RESET}"
        echo ""
    else
        echo -e "${GREEN}acme.sh 已安装${RESET}"
        
        # 检查是否已注册账户
        if [ -f ~/.acme.sh/ca/acme-v02.api.letsencrypt.org/directory/account.json ]; then
            REGISTERED_EMAIL=$(grep -oP '"contact":\["mailto:\K[^"]+' ~/.acme.sh/ca/acme-v02.api.letsencrypt.org/directory/account.json 2>/dev/null || echo "未知")
            echo -e "${GREEN}已注册邮箱: ${YELLOW}${REGISTERED_EMAIL}${RESET}"
        fi
    fi
}
# 获取服务器 IP（支持 IPv4/IPv6 选择）
get_server_ip() {
    echo -e "${CYAN}正在检测服务器 IP 地址...${RESET}"
    
    # 获取 IPv4
    echo -e "${CYAN}正在检测 IPv4...${RESET}"
    IPV4=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    if [ -z "$IPV4" ]; then
        IPV4=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null)
    fi
    if [ -z "$IPV4" ]; then
        IPV4=$(curl -4 -s --connect-timeout 5 api.ipify.org 2>/dev/null)
    fi
    if [ -z "$IPV4" ]; then
        IPV4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    fi
    
    # 获取 IPv6
    echo -e "${CYAN}正在检测 IPv6...${RESET}"
    IPV6=$(curl -6 -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    if [ -z "$IPV6" ]; then
        IPV6=$(curl -6 -s --connect-timeout 5 ip.sb 2>/dev/null)
    fi
    if [ -z "$IPV6" ]; then
        IPV6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
    fi
    
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   检测到的 IP 地址${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    
    local has_ipv4=false
    local has_ipv6=false
    
    if [ -n "$IPV4" ]; then
        echo -e "${GREEN}IPv4: ${YELLOW}${IPV4}${RESET}"
        has_ipv4=true
    else
        echo -e "${RED}IPv4: 未检测到${RESET}"
    fi
    
    if [ -n "$IPV6" ]; then
        echo -e "${GREEN}IPv6: ${YELLOW}${IPV6}${RESET}"
        has_ipv6=true
    else
        echo -e "${RED}IPv6: 未检测到${RESET}"
    fi
    
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    # 如果两者都存在，让用户选择
    if [ "$has_ipv4" = true ] && [ "$has_ipv6" = true ]; then
        echo -e "${YELLOW}检测到 IPv4 和 IPv6，请选择使用哪个:${RESET}"
        echo -e "${YELLOW}1.${RESET} 使用 IPv4 ${GREEN}(推荐)${RESET} - ${YELLOW}${IPV4}${RESET}"
        echo -e "${YELLOW}2.${RESET} 使用 IPv6 - ${YELLOW}${IPV6}${RESET}"
        echo -e "${YELLOW}3.${RESET} 手动输入"
        echo ""
        
        while true; do
            read -p "请选择 [1-3] (默认: 1): " ip_choice
            ip_choice=${ip_choice:-1}
            
            case $ip_choice in
                1)
                    SERVER_IP=$IPV4
                    IP_VERSION="IPv4"
                    break
                    ;;
                2)
                    SERVER_IP=$IPV6
                    IP_VERSION="IPv6"
                    break
                    ;;
                3)
                    read -p "请输入服务器 IP 地址: " SERVER_IP
                    if [ -n "$SERVER_IP" ]; then
                        # 判断输入的是 IPv4 还是 IPv6
                        if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            IP_VERSION="IPv4"
                        elif [[ $SERVER_IP =~ ^[0-9a-fA-F:]+$ ]]; then
                            IP_VERSION="IPv6"
                        else
                            IP_VERSION="Unknown"
                        fi
                        break
                    else
                        echo -e "${RED}IP 地址不能为空${RESET}"
                    fi
                    ;;
                *)
                    echo -e "${RED}无效的选择，请重新输入${RESET}"
                    ;;
            esac
        done
    elif [ "$has_ipv4" = true ]; then
        SERVER_IP=$IPV4
        IP_VERSION="IPv4"
        echo -e "${GREEN}自动使用 IPv4: ${YELLOW}${SERVER_IP}${RESET}"
    elif [ "$has_ipv6" = true ]; then
        SERVER_IP=$IPV6
        IP_VERSION="IPv6"
        echo -e "${YELLOW}仅检测到 IPv6: ${SERVER_IP}${RESET}"
        echo ""
        read -p "是否使用此 IPv6 地址？(y/n，默认: y): " use_ipv6
        use_ipv6=${use_ipv6:-y}
        if [ "$use_ipv6" != "y" ] && [ "$use_ipv6" != "Y" ]; then
            read -p "请手动输入服务器 IP 地址: " SERVER_IP
            if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                IP_VERSION="IPv4"
            elif [[ $SERVER_IP =~ ^[0-9a-fA-F:]+$ ]]; then
                IP_VERSION="IPv6"
            else
                IP_VERSION="Unknown"
            fi
        fi
    else
        echo -e "${RED}无法自动检测 IP 地址${RESET}"
        read -p "请手动输入服务器 IP 地址: " SERVER_IP
        if [ -z "$SERVER_IP" ]; then
            echo -e "${RED}IP 地址不能为空，退出安装${RESET}"
            exit 1
        fi
        if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IP_VERSION="IPv4"
        elif [[ $SERVER_IP =~ ^[0-9a-fA-F:]+$ ]]; then
            IP_VERSION="IPv6"
        else
            IP_VERSION="Unknown"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}已选择 IP 地址: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    sleep 1
}

# 选择 TLS 域名
select_tls_domain() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择 Shadow-TLS SNI 伪装域名${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${GREEN}国际知名域名:${RESET}"
    echo -e "${YELLOW}1.${RESET}  gateway.icloud.com ${GREEN}(推荐 - Apple iCloud)${RESET}"
    echo -e "${YELLOW}2.${RESET}  www.microsoft.com ${GREEN}(推荐 - 微软)${RESET}"
    echo -e "${YELLOW}3.${RESET}  www.apple.com ${GREEN}(推荐 - 苹果官网)${RESET}"
    echo -e "${YELLOW}4.${RESET}  itunes.apple.com ${GREEN}(推荐 - Apple iTunes)${RESET}"
    echo ""
    echo -e "${GREEN}国内常用域名:${RESET}"
    echo -e "${YELLOW}5.${RESET}  mp.weixin.qq.com (微信公众号)"
    echo -e "${YELLOW}6.${RESET}  www.qq.com (腾讯)"
    echo -e "${YELLOW}7.${RESET}  www.taobao.com (淘宝)"
    echo -e "${YELLOW}8.${RESET}  www.jd.com (京东)"
    echo -e "${YELLOW}9.${RESET}  www.baidu.com (百度)"
    echo -e "${YELLOW}10.${RESET} www.163.com (网易)"
    echo ""
    echo -e "${GREEN}CDN 与云服务:${RESET}"
    echo -e "${YELLOW}11.${RESET} cloudflare.com ${GREEN}(推荐 - Cloudflare)${RESET}"
    echo -e "${YELLOW}12.${RESET} www.cloudflare.com ${GREEN}(推荐 - Cloudflare)${RESET}"
    echo -e "${YELLOW}13.${RESET} aws.amazon.com ${GREEN}(推荐 - AWS)${RESET}"
    echo -e "${YELLOW}14.${RESET} azure.microsoft.com ${GREEN}(推荐 - Azure)${RESET}"
    echo -e "${YELLOW}15.${RESET} cloud.google.com ${GREEN}(推荐 - Google Cloud)${RESET}"
    echo ""
    echo -e "${YELLOW}0.${RESET}  自定义域名 (手动输入)"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    
    while true; do
        read -p "请选择域名 [0-15]: " domain_choice
        
        case $domain_choice in
            1) TLS_DOMAIN="gateway.icloud.com"; break;;
            2) TLS_DOMAIN="www.microsoft.com"; break;;
            3) TLS_DOMAIN="www.apple.com"; break;;
            4) TLS_DOMAIN="itunes.apple.com"; break;;
            5) TLS_DOMAIN="mp.weixin.qq.com"; break;;
            6) TLS_DOMAIN="www.qq.com"; break;;
            7) TLS_DOMAIN="www.taobao.com"; break;;
            8) TLS_DOMAIN="www.jd.com"; break;;
            9) TLS_DOMAIN="www.baidu.com"; break;;
            10) TLS_DOMAIN="www.163.com"; break;;
            11) TLS_DOMAIN="cloudflare.com"; break;;
            12) TLS_DOMAIN="www.cloudflare.com"; break;;
            13) TLS_DOMAIN="aws.amazon.com"; break;;
            14) TLS_DOMAIN="azure.microsoft.com"; break;;
            15) TLS_DOMAIN="cloud.google.com"; break;;
            0)
                read -p "请输入自定义域名 (例如: www.example.com): " TLS_DOMAIN
                if [ -n "$TLS_DOMAIN" ]; then
                    break
                else
                    echo -e "${RED}域名不能为空${RESET}"
                fi
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done
    
    echo -e "${GREEN}已选择域名: ${TLS_DOMAIN}${RESET}"
}

# 选择 Reality 目标网站
select_reality_dest() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择 Reality 目标网站${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${BLUE}提示: Reality 会伪装成访问这些网站${RESET}"
    echo ""
    echo -e "${GREEN}推荐网站 (支持 TLS 1.3 和 HTTP/2):${RESET}"
    echo -e "${YELLOW}1.${RESET}  www.microsoft.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}2.${RESET}  www.apple.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}3.${RESET}  www.cloudflare.com ${GREEN}(推荐)${RESET}"
    echo -e "${YELLOW}4.${RESET}  www.amazon.com"
    echo -e "${YELLOW}5.${RESET}  www.google.com"
    echo -e "${YELLOW}6.${RESET}  www.github.com"
    echo -e "${YELLOW}7.${RESET}  www.yahoo.com"
    echo -e "${YELLOW}8.${RESET}  www.nginx.com"
    echo ""
    echo -e "${YELLOW}0.${RESET}  自定义域名 (手动输入)"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    
    while true; do
        read -p "请选择目标网站 [0-8]: " dest_choice
        
        case $dest_choice in
            1) REALITY_DEST="www.microsoft.com"; break;;
            2) REALITY_DEST="www.apple.com"; break;;
            3) REALITY_DEST="www.cloudflare.com"; break;;
            4) REALITY_DEST="www.amazon.com"; break;;
            5) REALITY_DEST="www.google.com"; break;;
            6) REALITY_DEST="www.github.com"; break;;
            7) REALITY_DEST="www.yahoo.com"; break;;
            8) REALITY_DEST="www.nginx.com"; break;;
            0)
                read -p "请输入自定义域名 (例如: www.example.com): " REALITY_DEST
                if [ -n "$REALITY_DEST" ]; then
                    break
                else
                    echo -e "${RED}域名不能为空${RESET}"
                fi
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done
    
    echo -e "${GREEN}已选择目标网站: ${REALITY_DEST}${RESET}"
}

# 选择 Shadowsocks 加密方法
select_ss_method() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择 Shadowsocks 加密方式${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${GREEN}SS-2022 加密方式 (推荐):${RESET}"
    echo -e "${YELLOW}1.${RESET} 2022-blake3-aes-256-gcm ${GREEN}(推荐 - 最强安全性)${RESET}"
    echo -e "${YELLOW}2.${RESET} 2022-blake3-aes-128-gcm ${GREEN}(推荐 - 平衡性能)${RESET}"
    echo -e "${YELLOW}3.${RESET} 2022-blake3-chacha20-poly1305 (ChaCha20)"
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${BLUE}提示: SS-2022 加密方式提供更好的安全性和性能${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    while true; do
        read -p "请选择加密方式 [1-3] (默认: 1): " method_choice
        method_choice=${method_choice:-1}
        
        case $method_choice in
            1)
                SS_METHOD="2022-blake3-aes-256-gcm"
                SS_PASSWORD=$(openssl rand -base64 32)
                break
                ;;
            2)
                SS_METHOD="2022-blake3-aes-128-gcm"
                SS_PASSWORD=$(openssl rand -base64 16)
                break
                ;;
            3)
                SS_METHOD="2022-blake3-chacha20-poly1305"
                SS_PASSWORD=$(openssl rand -base64 32)
                break
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done
    
    echo -e "${GREEN}已选择加密方式: ${SS_METHOD}${RESET}"
}
# 下载 Shadow-TLS (如果未安装)
download_shadow_tls() {
    if [ ! -f /usr/local/bin/shadow-tls ]; then
        echo -e "${GREEN}正在下载 Shadow-TLS...${RESET}"

        # 获取最新的 Shadow-TLS 版本
        echo -e "${CYAN}正在获取最新的 Shadow-TLS 版本...${RESET}"
        SHADOW_TLS_VERSION=$(curl -s https://api.github.com/repos/ihciah/shadow-tls/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

        if [ -z "$SHADOW_TLS_VERSION" ]; then
            echo -e "${YELLOW}无法获取最新版本，使用默认版本 v0.2.25${RESET}"
            SHADOW_TLS_VERSION="v0.2.25"
        fi

        echo -e "${GREEN}最新 Shadow-TLS 版本: ${SHADOW_TLS_VERSION}${RESET}"

        # 构建下载链接
        SHADOW_TLS_DOWNLOAD_URL="https://github.com/ihciah/shadow-tls/releases/download/${SHADOW_TLS_VERSION}/shadow-tls-${SHADOW_TLS_ARCH}"

        # 下载 Shadow-TLS
        echo -e "${CYAN}正在从以下地址下载 Shadow-TLS: ${SHADOW_TLS_DOWNLOAD_URL}${RESET}"
        wget "$SHADOW_TLS_DOWNLOAD_URL" -O /tmp/shadow-tls

        if [ $? -ne 0 ]; then
            echo -e "${RED}下载 Shadow-TLS 失败${RESET}"
            exit 1
        fi

        # 移动到系统目录并赋予执行权限
        mv /tmp/shadow-tls /usr/local/bin/shadow-tls
        chmod +x /usr/local/bin/shadow-tls
    else
        echo -e "${GREEN}Shadow-TLS 已安装，跳过下载${RESET}"
        SHADOW_TLS_VERSION=$(shadow-tls --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' || echo "已安装")
    fi
}

# 下载 Sing-box (如果未安装)
download_singbox() {
    if [ ! -f /usr/local/bin/sing-box ]; then
        echo -e "${GREEN}正在下载 Sing-box...${RESET}"
        
        detect_architecture
        
        # 获取最新的 sing-box 版本
        echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
        SINGBOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

        if [ -z "$SINGBOX_VERSION" ]; then
            echo -e "${YELLOW}无法获取最新版本，使用默认版本 v1.10.0${RESET}"
            SINGBOX_VERSION="v1.10.0"
        fi

        echo -e "${GREEN}最新 Sing-box 版本: ${SINGBOX_VERSION}${RESET}"

        # 构建下载链接
        SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"

        # 下载 Sing-box
        echo -e "${CYAN}正在从以下地址下载 Sing-box: ${SINGBOX_DOWNLOAD_URL}${RESET}"
        
        cd /tmp
        wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz

        if [ $? -ne 0 ]; then
            echo -e "${RED}下载 Sing-box 失败${RESET}"
            exit 1
        fi

        # 解压
        tar -xzf sing-box.tar.gz
        
        # 查找并移动二进制文件
        SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
        if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
            mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
            chmod +x /usr/local/bin/sing-box
        else
            echo -e "${RED}未找到 sing-box 二进制文件${RESET}"
            exit 1
        fi
        
        # 清理临时文件
        rm -rf /tmp/sing-box*
        
        echo -e "${GREEN}Sing-box 安装成功${RESET}"
    else
        echo -e "${GREEN}Sing-box 已安装，跳过下载${RESET}"
        SINGBOX_VERSION=$(/usr/local/bin/sing-box version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "已安装")
    fi
}

# 创建健康检查脚本（修复版 - 兼容性改进）
create_healthcheck_script() {
    echo -e "${CYAN}正在创建健康检查脚本...${RESET}"
    
    cat <<'EOF' > /usr/local/bin/snell-healthcheck.sh
#!/bin/bash

LOG_FILE="/var/log/snell-healthcheck.log"
MAX_LOG_SIZE=10485760  # 10MB

# 日志轮转（兼容 Linux 和 macOS）
if [ -f "$LOG_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
    fi
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查 Snell 服务
if systemctl list-unit-files | grep -q "snell.service"; then
    if ! systemctl is-active --quiet snell; then
        log "Snell 服务已停止，正在重启..."
        systemctl restart snell
        sleep 3
        if systemctl is-active --quiet snell; then
            log "Snell 服务重启成功"
        else
            log "Snell 服务重启失败"
        fi
    fi
    
    # 检查 Snell 端口监听
    if ! ss -tulpn 2>/dev/null | grep -q "127.0.0.1:30622" && ! netstat -tulpn 2>/dev/null | grep -q "127.0.0.1:30622"; then
        log "Snell 端口未监听，重启服务..."
        systemctl restart snell
    fi
fi

# 检查 Shadow-TLS 服务 (Snell)
if systemctl list-unit-files | grep -q "shadow-tls-snell.service"; then
    if ! systemctl is-active --quiet shadow-tls-snell; then
        log "Shadow-TLS (Snell) 服务已停止，正在重启..."
        systemctl restart shadow-tls-snell
        sleep 3
        if systemctl is-active --quiet shadow-tls-snell; then
            log "Shadow-TLS (Snell) 服务重启成功"
        else
            log "Shadow-TLS (Snell) 服务重启失败"
        fi
    fi
    
    # 检查 Shadow-TLS 端口监听
    SHADOW_PORT=$(grep "ExecStart" /etc/systemd/system/shadow-tls-snell.service 2>/dev/null | grep -oP '::0:\K\d+' | head -1)
    if [ -n "$SHADOW_PORT" ]; then
        if ! ss -tulpn 2>/dev/null | grep -q ":$SHADOW_PORT" && ! netstat -tulpn 2>/dev/null | grep -q ":$SHADOW_PORT"; then
            log "Shadow-TLS 端口 $SHADOW_PORT 未监听，重启服务..."
            systemctl restart shadow-tls-snell
        fi
    fi
fi

# 检查 Sing-box 服务
if systemctl list-unit-files | grep -q "sing-box.service"; then
    if ! systemctl is-active --quiet sing-box; then
        log "Sing-box 服务已停止，正在重启..."
        systemctl restart sing-box
        sleep 3
        if systemctl is-active --quiet sing-box; then
            log "Sing-box 服务重启成功"
        else
            log "Sing-box 服务重启失败"
        fi
    fi
fi

# 检查 Reality 服务
if systemctl list-unit-files | grep -q "sing-box-reality.service"; then
    if ! systemctl is-active --quiet sing-box-reality; then
        log "Reality 服务已停止，正在重启..."
        systemctl restart sing-box-reality
        sleep 3
        if systemctl is-active --quiet sing-box-reality; then
            log "Reality 服务重启成功"
        else
            log "Reality 服务重启失败"
        fi
    fi
fi

# 检查 Hysteria2 服务
if systemctl list-unit-files | grep -q "hysteria2.service"; then
    if ! systemctl is-active --quiet hysteria2; then
        log "Hysteria2 服务已停止，正在重启..."
        systemctl restart hysteria2
        sleep 3
        if systemctl is-active --quiet hysteria2; then
            log "Hysteria2 服务重启成功"
        else
            log "Hysteria2 服务重启失败"
        fi
    fi
fi
EOF

    chmod +x /usr/local/bin/snell-healthcheck.sh
    
    # 添加 cron 任务
    if ! crontab -l 2>/dev/null | grep -q "snell-healthcheck.sh"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/snell-healthcheck.sh") | crontab -
        echo -e "${GREEN}✓ 已添加健康检查 cron 任务 (每5分钟执行一次)${RESET}"
    else
        echo -e "${YELLOW}健康检查 cron 任务已存在${RESET}"
    fi
}

# 生成 Reality 密钥对
generate_reality_keypair() {
    echo -e "${CYAN}正在生成 Reality 密钥对...${RESET}"
    
    # 确保 sing-box 已安装
    download_singbox
    
    # 生成密钥对
    KEYPAIR_OUTPUT=$(/usr/local/bin/sing-box generate reality-keypair)
    
    REALITY_PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | grep "PrivateKey:" | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT" | grep "PublicKey:" | awk '{print $2}')
    
    if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
        echo -e "${RED}生成密钥对失败${RESET}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 密钥对生成成功${RESET}"
}

# 生成短 ID
generate_short_id() {
    openssl rand -hex 8
}

# 检查端口占用
check_port() {
    local port=$1
    if ss -tulpn 2>/dev/null | grep -q ":$port " || netstat -tulpn 2>/dev/null | grep -q ":$port "; then
        return 0  # 端口被占用
    else
        return 1  # 端口空闲
    fi
}

# 申请 Let's Encrypt 证书（改进版 - 增加端口检查）
issue_letsencrypt_cert() {
    local domain=$1
    
    echo -e "${CYAN}正在为域名 ${YELLOW}${domain}${CYAN} 申请 Let's Encrypt 证书...${RESET}"
    
    # 检查 80 端口是否被占用
    if check_port 80; then
        echo -e "${YELLOW}警告: 80 端口已被占用${RESET}"
        echo -e "${CYAN}正在尝试停止可能占用 80 端口的服务...${RESET}"
        
        # 尝试停止常见的 Web 服务
        systemctl stop nginx 2>/dev/null
        systemctl stop apache2 2>/dev/null
        systemctl stop httpd 2>/dev/null
        systemctl stop hysteria2 2>/dev/null
        
        sleep 2
        
        # 再次检查
        if check_port 80; then
            echo -e "${RED}80 端口仍被占用，无法申请证书${RESET}"
            echo -e "${YELLOW}请手动停止占用 80 端口的服务：${RESET}"
            ss -tulpn 2>/dev/null | grep ":80 " || netstat -tulpn 2>/dev/null | grep ":80 "
            return 1
        fi
    fi
    
    # 使用 standalone 模式申请证书
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --keylength ec-256 --force
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}证书申请失败${RESET}"
        echo -e "${YELLOW}请确保:${RESET}"
        echo -e "  1. 域名 ${domain} 已正确解析到此服务器 (${SERVER_IP})"
        echo -e "  2. 防火墙已开放 80 端口"
        echo -e "  3. 没有其他服务占用 80 端口"
        echo ""
        echo -e "${CYAN}调试命令:${RESET}"
        echo -e "  检查域名解析: ${YELLOW}nslookup ${domain}${RESET}"
        echo -e "  检查端口占用: ${YELLOW}netstat -tulpn | grep :80${RESET}"
        echo -e "  查看详细日志: ${YELLOW}~/.acme.sh/acme.sh --issue -d ${domain} --standalone --debug${RESET}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 证书申请成功${RESET}"
    return 0
}

# 安装证书到 Hysteria2（改进版 - 增加错误处理）
install_cert_to_hysteria2() {
    local domain=$1
    
    echo -e "${CYAN}正在安装证书到 Hysteria2...${RESET}"
    
    # 确保目录存在
    mkdir -p /etc/hysteria2
    
    # 确保用户存在
    if ! id -u hysteria2 > /dev/null 2>&1; then
        echo -e "${YELLOW}hysteria2 用户不存在，正在创建...${RESET}"
        useradd -r -s /usr/sbin/nologin hysteria2
    fi
    
    # 安装证书
    ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
        --key-file /etc/hysteria2/server.key \
        --fullchain-file /etc/hysteria2/server.crt \
        --reloadcmd "chown hysteria2:nogroup /etc/hysteria2/server.key /etc/hysteria2/server.crt && chmod 600 /etc/hysteria2/server.key && chmod 644 /etc/hysteria2/server.crt && systemctl restart hysteria2 2>/dev/null || true"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}证书安装失败${RESET}"
        return 1
    fi
    
    # 手动设置权限（确保成功）
    chown hysteria2:nogroup /etc/hysteria2/server.key /etc/hysteria2/server.crt 2>/dev/null
    chmod 600 /etc/hysteria2/server.key
    chmod 644 /etc/hysteria2/server.crt
    
    # 验证证书文件
    if [ ! -f /etc/hysteria2/server.key ] || [ ! -f /etc/hysteria2/server.crt ]; then
        echo -e "${RED}证书文件不存在${RESET}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 证书安装成功${RESET}"
    return 0
}

# 手动续签证书
renew_hysteria2_cert() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装${RESET}"
        return
    fi
    
    source /etc/hysteria2-proxy-config.txt
    
    if [ "$CERT_TYPE" != "letsencrypt" ]; then
        echo -e "${RED}当前使用的不是 Let's Encrypt 证书，无需续签${RESET}"
        return
    fi
    
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在续签 Hysteria2 证书${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo ""
    
    # 停止服务以释放端口
    echo -e "${CYAN}正在停止 Hysteria2 服务...${RESET}"
    systemctl stop hysteria2
    
    # 强制续签
    ~/.acme.sh/acme.sh --renew -d "$HYSTERIA2_DOMAIN" --ecc --force
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 证书续签成功${RESET}"
        
        # 重新安装证书
        install_cert_to_hysteria2 "$HYSTERIA2_DOMAIN"
        
        # 启动服务
        systemctl start hysteria2
        
        sleep 2
        if systemctl is-active --quiet hysteria2; then
            echo -e "${GREEN}✓ Hysteria2 服务已重启${RESET}"
        else
            echo -e "${RED}Hysteria2 服务启动失败${RESET}"
            journalctl -u hysteria2 -n 20 --no-pager
        fi
    else
        echo -e "${RED}证书续签失败${RESET}"
        systemctl start hysteria2
    fi
}

# 查看证书状态
view_cert_status() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装${RESET}"
        return
    fi
    
    source /etc/hysteria2-proxy-config.txt
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Hysteria2 证书状态${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo -e "${CYAN}证书类型: ${GREEN}Let's Encrypt${RESET}"
        echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
        echo ""
        
        if [ -f /etc/hysteria2/server.crt ]; then
            echo -e "${CYAN}证书信息:${RESET}"
            openssl x509 -in /etc/hysteria2/server.crt -noout -dates -subject
            echo ""
            
            # 计算剩余天数
            EXPIRY_DATE=$(openssl x509 -in /etc/hysteria2/server.crt -noout -enddate | cut -d= -f2)
            EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null)
            CURRENT_EPOCH=$(date +%s)
            DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
            
            if [ $DAYS_LEFT -gt 30 ]; then
                echo -e "${GREEN}剩余有效期: ${DAYS_LEFT} 天${RESET}"
            elif [ $DAYS_LEFT -gt 7 ]; then
                echo -e "${YELLOW}剩余有效期: ${DAYS_LEFT} 天 (建议续签)${RESET}"
            else
                echo -e "${RED}剩余有效期: ${DAYS_LEFT} 天 (请立即续签)${RESET}"
            fi
        else
            echo -e "${RED}证书文件不存在${RESET}"
        fi
        
        echo ""
        echo -e "${CYAN}自动续签状态:${RESET}"
        if crontab -l 2>/dev/null | grep -q "acme.sh.*--cron"; then
            echo -e "${GREEN}✓ 已启用 (每天自动检查)${RESET}"
        else
            echo -e "${RED}✗ 未启用${RESET}"
        fi
    else
        echo -e "${CYAN}证书类型: ${YELLOW}自签名证书${RESET}"
        echo ""
        
        if [ -f /etc/hysteria2/server.crt ]; then
            echo -e "${CYAN}证书信息:${RESET}"
            openssl x509 -in /etc/hysteria2/server.crt -noout -dates -subject
        else
            echo -e "${RED}证书文件不存在${RESET}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
}
# 安装 Snell Server（已集成安全配置和断联修复）
install_snell() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 Snell + Shadow-TLS${RESET}"
    echo -e "${GREEN}   (已集成安全配置和断联修复)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 检查是否已安装
    if check_snell_installed; then
        echo -e "${YELLOW}检测到 Snell 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        uninstall_snell
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    # ==================== Snell Server 部分 ====================
    echo -e "${GREEN}正在安装 Snell Server...${RESET}"

    # 获取最新的 Snell 版本
    echo -e "${CYAN}正在获取最新的 Snell 版本...${RESET}"
    SNELL_VERSION=$(curl -s https://kb.nssurge.com/surge-knowledge-base/release-notes/snell | grep -oP 'snell-server-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [ -z "$SNELL_VERSION" ]; then
        SNELL_VERSION=$(curl -s https://manual.nssurge.com/others/snell.html | grep -oP 'snell-server-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi

    if [ -z "$SNELL_VERSION" ]; then
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 v5.0.1${RESET}"
        SNELL_VERSION="5.0.1"
    fi

    echo -e "${GREEN}最新 Snell 版本: v${SNELL_VERSION}${RESET}"

    # 构建下载链接
    SNELL_DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${SNELL_ARCH}.zip"

    # 下载 Snell Server
    echo -e "${CYAN}正在从以下地址下载 Snell Server: ${SNELL_DOWNLOAD_URL}${RESET}"
    wget "$SNELL_DOWNLOAD_URL" -O snell-server.zip

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 Snell Server 失败${RESET}"
        exit 1
    fi

    # 解压 Snell Server 到指定目录
    unzip -o snell-server.zip -d /usr/local/bin

    # 赋予服务器权限
    chmod +x /usr/local/bin/snell-server

    # 清理下载文件
    rm snell-server.zip

    # 创建配置文件夹
    mkdir -p /etc/snell

    # 使用 Snell 的 wizard 生成配置文件
    echo -e "${CYAN}正在生成 Snell 配置文件...${RESET}"
    echo "y" | /usr/local/bin/snell-server --wizard -c /etc/snell/snell-server.conf

    # 🔒 安全配置：将监听地址改为仅本地（自动集成）
    echo -e "${CYAN}正在应用安全配置（仅监听本地 127.0.0.1）...${RESET}"
    sed -i 's/listen = 0.0.0.0:/listen = 127.0.0.1:/' /etc/snell/snell-server.conf

    # 获取 Snell Server 端口号和 PSK 值
    SNELL_PORT=$(grep "listen" /etc/snell/snell-server.conf | cut -d ':' -f 2 | tr -d ' ')
    SNELL_PSK=$(grep "psk" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')

    # 创建用户和组
    if ! id -u snell > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin snell
    fi

    # 创建 Systemd 服务文件（已集成断联修复）
    cat <<EOF > /lib/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=snell
Group=nogroup
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    # 重载服务
    systemctl daemon-reload

    # 开机运行 Snell
    systemctl enable snell

    # ==================== Shadow-TLS 部分 (Snell) ====================
    download_shadow_tls

    # 生成 Shadow-TLS 密码
    SNELL_SHADOW_TLS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    # 选择 TLS 域名
    select_tls_domain
    SNELL_TLS_DOMAIN=$TLS_DOMAIN

    # 询问用户输入自定义端口号
    read -p "请输入 Shadow-TLS 监听端口 (默认: 8443): " SNELL_SHADOW_TLS_PORT
    SNELL_SHADOW_TLS_PORT=${SNELL_SHADOW_TLS_PORT:-8443}

    # 创建 Shadow-TLS 的 Systemd 服务文件（已集成断联修复）
    cat <<EOF > /etc/systemd/system/shadow-tls-snell.service
[Unit]
Description=Shadow-TLS Server Service for Snell
Documentation=man:sstls-server
After=network-online.target snell.service
Wants=network-online.target
Requires=snell.service

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen ::0:$SNELL_SHADOW_TLS_PORT --server 127.0.0.1:$SNELL_PORT --tls $SNELL_TLS_DOMAIN --password $SNELL_SHADOW_TLS_PASSWORD
StandardOutput=journal
StandardError=journal
SyslogIdentifier=shadow-tls-snell

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

# 防止频繁重启
RestartPreventExitStatus=SIGKILL

[Install]
WantedBy=multi-user.target
EOF

    # 重载服务
    echo -e "${CYAN}正在重载 Systemd 守护进程...${RESET}"
    systemctl daemon-reload

    # 开机运行 Shadow-TLS
    echo -e "${CYAN}正在设置 Shadow-TLS 开机自启...${RESET}"
    systemctl enable shadow-tls-snell.service

    # 启动服务
    echo -e "${CYAN}正在启动服务...${RESET}"
    systemctl start snell
    systemctl start shadow-tls-snell.service

    # 等待服务启动
    sleep 2

    # 检查服务状态
    SNELL_STATUS=$(systemctl is-active snell)
    SNELL_SHADOW_TLS_STATUS=$(systemctl is-active shadow-tls-snell)

    # 创建健康检查脚本（自动集成）
    create_healthcheck_script

    # 保存配置信息
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

    # 输出配置信息
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Snell 配置:${RESET}"
    echo -e "  版本: ${YELLOW}v${SNELL_VERSION}${RESET}"
    echo -e "  监听地址: ${GREEN}127.0.0.1:${SNELL_PORT}${RESET} ${GREEN}(仅本地，安全)${RESET}"
    echo -e "  PSK: ${YELLOW}${SNELL_PSK}${RESET}"
    echo -e "  状态: ${YELLOW}${SNELL_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SHADOW_TLS_VERSION}${RESET}"
    echo -e "  外部端口: ${YELLOW}${SNELL_SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${SNELL_SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "  伪装域名: ${YELLOW}${SNELL_TLS_DOMAIN}${RESET}"
    echo -e "  状态: ${YELLOW}${SNELL_SHADOW_TLS_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置 (Snell v4):${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SNELL_SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=4, reuse=true, tfo=true, shadow-tls-password=${SNELL_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SNELL_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置 (Snell v5):${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SNELL_SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SNELL_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SNELL_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - 安全配置: Snell 仅监听本地 (127.0.0.1)${RESET}"
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}  - 服务依赖管理${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
}
# 安装 Sing-box (SS-2022 + Shadow-TLS)（已集成安全配置和断联修复）
install_singbox() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 Sing-box (SS-2022 + Shadow-TLS)${RESET}"
    echo -e "${GREEN}   (已集成安全配置和断联修复)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 检查是否已安装
    if check_singbox_installed; then
        echo -e "${YELLOW}检测到 Sing-box 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        uninstall_singbox
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    # ==================== Sing-box 部分 ====================
    download_singbox

    # 选择加密方法
    select_ss_method

    # 询问端口
    read -p "请输入 Shadowsocks 监听端口 (默认: 8388): " SS_PORT
    SS_PORT=${SS_PORT:-8388}

    # 选择 TLS 域名
    select_tls_domain
    SINGBOX_TLS_DOMAIN=$TLS_DOMAIN

    # 询问 Shadow-TLS 端口
    read -p "请输入 Shadow-TLS 监听端口 (默认: 9443): " SINGBOX_SHADOW_TLS_PORT
    SINGBOX_SHADOW_TLS_PORT=${SINGBOX_SHADOW_TLS_PORT:-9443}

    # 生成 Shadow-TLS 密码
    SINGBOX_SHADOW_TLS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    # 创建配置文件夹
    mkdir -p /etc/sing-box

    # 创建 Sing-box 配置文件（已集成安全配置：仅监听本地）
    cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "127.0.0.1",
      "listen_port": $SS_PORT,
      "method": "$SS_METHOD",
      "password": "$SS_PASSWORD"
    },
    {
      "type": "shadowtls",
      "tag": "st-in",
      "listen": "::",
      "listen_port": $SINGBOX_SHADOW_TLS_PORT,
      "version": 3,
      "users": [
        {
          "name": "user1",
          "password": "$SINGBOX_SHADOW_TLS_PASSWORD"
        }
      ],
      "handshake": {
        "server": "$SINGBOX_TLS_DOMAIN",
        "server_port": 443
      },
      "strict_mode": true,
      "detour": "ss-in"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${GREEN}配置文件已创建: /etc/sing-box/config.json${RESET}"

    # 创建用户和组
    if ! id -u sing-box > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin sing-box
    fi

    # 创建 Systemd 服务文件（已集成断联修复）
    cat <<EOF > /lib/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=sing-box
Group=nogroup
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sing-box

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    # 重载服务
    systemctl daemon-reload

    # 开机运行 Sing-box
    systemctl enable sing-box

    # 启动服务
    echo -e "${CYAN}正在启动服务...${RESET}"
    systemctl start sing-box

    # 等待服务启动
    sleep 2

    # 检查服务状态
    SINGBOX_STATUS=$(systemctl is-active sing-box)

    # 如果服务启动失败，显示详细错误信息
    if [ "$SINGBOX_STATUS" != "active" ]; then
        echo -e "${RED}Sing-box 服务启动失败${RESET}"
        echo -e "${YELLOW}查看详细日志:${RESET}"
        journalctl -u sing-box -n 30 --no-pager
    fi

    # 创建健康检查脚本（自动集成）
    create_healthcheck_script

    # 保存配置信息
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

    # 输出配置信息
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${SINGBOX_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadowsocks-2022 配置:${RESET}"
    echo -e "  内部端口: ${YELLOW}${SS_PORT}${RESET} ${GREEN}(仅本地，安全)${RESET}"
    echo -e "  密码: ${YELLOW}${SS_PASSWORD}${RESET}"
    echo -e "  加密方式: ${YELLOW}${SS_METHOD}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  外部端口: ${YELLOW}${SINGBOX_SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${SINGBOX_SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "  伪装域名: ${YELLOW}${SINGBOX_TLS_DOMAIN}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = ss, ${SERVER_IP}, ${SINGBOX_SHADOW_TLS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${SINGBOX_SHADOW_TLS_PASSWORD}, shadow-tls-sni=${SINGBOX_TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - 安全配置: Shadowsocks 仅监听本地 (127.0.0.1)${RESET}"
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    # 如果服务未正常运行，提示用户
    if [ "$SINGBOX_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: Sing-box 服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看日志: ${CYAN}journalctl -u sing-box -f${RESET}"
        echo -e "  2. 检查配置: ${CYAN}cat /etc/sing-box/config.json${RESET}"
        echo -e "  3. 测试配置: ${CYAN}/usr/local/bin/sing-box check -c /etc/sing-box/config.json${RESET}"
        echo ""
    fi
}
# 安装 VLESS Reality
install_reality() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 VLESS Reality${RESET}"
    echo -e "${GREEN}   (已集成安全配置和断联修复)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 检查是否已安装
    if check_reality_installed; then
        echo -e "${YELLOW}检测到 VLESS Reality 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        uninstall_reality
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    # ==================== Sing-box Reality 部分 ====================
    download_singbox

    # 生成 Reality 密钥对
    generate_reality_keypair

    # 生成 UUID
    REALITY_UUID=$(cat /proc/sys/kernel/random/uuid)

    # 生成短 ID
    REALITY_SHORT_ID=$(generate_short_id)

    # 选择目标网站
    select_reality_dest

    # 询问端口
    read -p "请输入 VLESS Reality 监听端口 (默认: 443): " REALITY_PORT
    REALITY_PORT=${REALITY_PORT:-443}

    # 创建配置文件夹
    mkdir -p /etc/sing-box-reality

    # 创建 Reality 配置文件
    cat <<EOF > /etc/sing-box-reality/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $REALITY_PORT,
      "users": [
        {
          "uuid": "$REALITY_UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_DEST",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$REALITY_DEST",
            "server_port": 443
          },
          "private_key": "$REALITY_PRIVATE_KEY",
          "short_id": [
            "$REALITY_SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${GREEN}配置文件已创建: /etc/sing-box-reality/config.json${RESET}"

    # 创建用户和组
    if ! id -u sing-box-reality > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin sing-box-reality
    fi

    # 创建 Systemd 服务文件（已集成断联修复）
    cat <<EOF > /lib/systemd/system/sing-box-reality.service
[Unit]
Description=Sing-box Reality Service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=sing-box-reality
Group=nogroup
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box-reality/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sing-box-reality

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    # 重载服务
    systemctl daemon-reload

    # 开机运行 Reality
    systemctl enable sing-box-reality

    # 启动服务
    echo -e "${CYAN}正在启动服务...${RESET}"
    systemctl start sing-box-reality

    # 等待服务启动
    sleep 2

    # 检查服务状态
    REALITY_STATUS=$(systemctl is-active sing-box-reality)

    # 如果服务启动失败，显示详细错误信息
    if [ "$REALITY_STATUS" != "active" ]; then
        echo -e "${RED}Reality 服务启动失败${RESET}"
        echo -e "${YELLOW}查看详细日志:${RESET}"
        journalctl -u sing-box-reality -n 30 --no-pager
    fi

    # 创建健康检查脚本（自动集成）
    create_healthcheck_script

    # 保存配置信息
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

    # 生成分享链接
    REALITY_LINK="vless://${REALITY_UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-${SERVER_IP}"

    # 输出配置信息
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${REALITY_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}VLESS Reality 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${REALITY_PORT}${RESET}"
    echo -e "  UUID: ${YELLOW}${REALITY_UUID}${RESET}"
    echo -e "  Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${RESET}"
    echo -e "  Short ID: ${YELLOW}${REALITY_SHORT_ID}${RESET}"
    echo -e "  目标网站: ${YELLOW}${REALITY_DEST}${RESET}"
    echo -e "  Flow: ${YELLOW}xtls-rprx-vision${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${REALITY_LINK}${RESET}"
    echo ""
    echo -e "${CYAN}二维码:${RESET}"
    qrencode -t ANSIUTF8 "$REALITY_LINK"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - Reality 协议 (抗审查能力强)${RESET}"
    echo -e "${GREEN}  - XTLS Vision 流控${RESET}"
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    # 如果服务未正常运行，提示用户
    if [ "$REALITY_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: Reality 服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看日志: ${CYAN}journalctl -u sing-box-reality -f${RESET}"
        echo -e "  2. 检查配置: ${CYAN}cat /etc/sing-box-reality/config.json${RESET}"
        echo -e "  3. 测试配置: ${CYAN}/usr/local/bin/sing-box check -c /etc/sing-box-reality/config.json${RESET}"
        echo ""
    fi
}
# 安装 Hysteria2（基于 sing-box 内核 + Let's Encrypt 证书）
install_hysteria2() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在安装 Hysteria2 (Sing-box 内核)${RESET}"
    echo -e "${GREEN}   (Let's Encrypt 证书 + 自动续签)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 检查是否已安装
    if check_hysteria2_installed; then
        echo -e "${YELLOW}检测到 Hysteria2 已安装${RESET}"
        read -p "是否要重新安装？(y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            echo -e "${CYAN}取消安装${RESET}"
            return
        fi
        uninstall_hysteria2
    fi

    install_dependencies
    detect_architecture
    get_server_ip

    # ==================== Sing-box Hysteria2 部分 ====================
    download_singbox

    # 生成密码
    HYSTERIA2_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

    # 询问端口
    read -p "请输入 Hysteria2 监听端口 (默认: 443): " HYSTERIA2_PORT
    HYSTERIA2_PORT=${HYSTERIA2_PORT:-443}

    # 询问是否启用混淆
    echo ""
    echo -e "${CYAN}是否启用混淆 (Obfuscation)?${RESET}"
    echo -e "${YELLOW}1.${RESET} 启用混淆 ${GREEN}(推荐 - 增强抗审查能力)${RESET}"
    echo -e "${YELLOW}2.${RESET} 不启用混淆"
    echo ""
    
    while true; do
        read -p "请选择 [1-2] (默认: 1): " obfs_choice
        obfs_choice=${obfs_choice:-1}
        
        case $obfs_choice in
            1)
                ENABLE_OBFS=true
                OBFS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
                break
                ;;
            2)
                ENABLE_OBFS=false
                break
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${RESET}"
                ;;
        esac
    done

    # 询问域名
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   配置域名和证书${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    echo -e "${YELLOW}请输入您的域名 (必须已解析到此服务器):${RESET}"
    read -p "域名: " HYSTERIA2_DOMAIN
    
    if [ -z "$HYSTERIA2_DOMAIN" ]; then
        echo -e "${RED}域名不能为空${RESET}"
        return
    fi
    
    echo ""
    echo -e "${CYAN}域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo -e "${YELLOW}请确保域名已正确解析到: ${GREEN}${SERVER_IP}${RESET}"
    echo ""
    read -p "确认继续？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${CYAN}取消安装${RESET}"
        return
    fi

    # ==================== 先创建目录和用户 ====================
    echo ""
    echo -e "${CYAN}正在准备安装环境...${RESET}"
    
    # 创建配置文件夹
    mkdir -p /etc/hysteria2
    echo -e "${GREEN}✓ 已创建配置目录${RESET}"

    # 创建用户和组
    if ! id -u hysteria2 > /dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin hysteria2
        echo -e "${GREEN}✓ 已创建 hysteria2 用户${RESET}"
    else
        echo -e "${GREEN}✓ hysteria2 用户已存在${RESET}"
    fi

    # ==================== 安装 acme.sh 和申请证书 ====================
    # 安装 acme.sh
    install_acme

    # 申请证书
    if ! issue_letsencrypt_cert "$HYSTERIA2_DOMAIN"; then
        echo -e "${RED}证书申请失败，安装终止${RESET}"
        return
    fi

    # 安装证书
    if ! install_cert_to_hysteria2 "$HYSTERIA2_DOMAIN"; then
        echo -e "${RED}证书安装失败，安装终止${RESET}"
        return
    fi

    # 再次确保权限正确
    chown hysteria2:nogroup /etc/hysteria2/server.key /etc/hysteria2/server.crt
    chmod 600 /etc/hysteria2/server.key
    chmod 644 /etc/hysteria2/server.crt
    echo -e "${GREEN}✓ 证书权限设置完成${RESET}"

    # ==================== 创建配置文件 ====================
    echo ""
    echo -e "${CYAN}正在创建 Hysteria2 配置文件...${RESET}"
    
    # 创建 Hysteria2 配置文件
    if [ "$ENABLE_OBFS" = true ]; then
        cat <<EOF > /etc/hysteria2/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $HYSTERIA2_PORT,
      "users": [
        {
          "name": "user1",
          "password": "$HYSTERIA2_PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$HYSTERIA2_DOMAIN",
        "key_path": "/etc/hysteria2/server.key",
        "certificate_path": "/etc/hysteria2/server.crt"
      },
      "obfs": {
        "type": "salamander",
        "password": "$OBFS_PASSWORD"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    else
        cat <<EOF > /etc/hysteria2/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $HYSTERIA2_PORT,
      "users": [
        {
          "name": "user1",
          "password": "$HYSTERIA2_PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$HYSTERIA2_DOMAIN",
        "key_path": "/etc/hysteria2/server.key",
        "certificate_path": "/etc/hysteria2/server.crt"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    fi

    echo -e "${GREEN}✓ 配置文件已创建: /etc/hysteria2/config.json${RESET}"

    # ==================== 创建 Systemd 服务 ====================
    echo ""
    echo -e "${CYAN}正在创建 Systemd 服务...${RESET}"
    
    # 创建 Systemd 服务文件（已集成断联修复）
    cat <<EOF > /lib/systemd/system/hysteria2.service
[Unit]
Description=Hysteria2 Service (Sing-box)
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=hysteria2
Group=nogroup
LimitNOFILE=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/hysteria2/config.json
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hysteria2

# 自动重启配置（断联修复）
Restart=always
RestartSec=10s
StartLimitInterval=60s
StartLimitBurst=3

# 超时设置
TimeoutStartSec=30s
TimeoutStopSec=30s

# 进程管理
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✓ Systemd 服务文件已创建${RESET}"

    # 重载服务
    systemctl daemon-reload

    # 开机运行 Hysteria2
    systemctl enable hysteria2
    echo -e "${GREEN}✓ 已设置开机自启${RESET}"

    # ==================== 启动服务 ====================
    echo ""
    echo -e "${CYAN}正在启动 Hysteria2 服务...${RESET}"
    systemctl start hysteria2

    # 等待服务启动
    sleep 3

    # 检查服务状态
    HYSTERIA2_STATUS=$(systemctl is-active hysteria2)

    # 如果服务启动失败，显示详细错误信息
    if [ "$HYSTERIA2_STATUS" != "active" ]; then
        echo -e "${RED}Hysteria2 服务启动失败${RESET}"
        echo -e "${YELLOW}查看详细日志:${RESET}"
        journalctl -u hysteria2 -n 30 --no-pager
        echo ""
        echo -e "${YELLOW}可能的原因:${RESET}"
        echo -e "  1. 端口 $HYSTERIA2_PORT 已被占用"
        echo -e "  2. 证书文件权限不正确"
        echo -e "  3. 配置文件格式错误"
        echo ""
        echo -e "${CYAN}调试命令:${RESET}"
        echo -e "  查看端口占用: ${YELLOW}netstat -tulpn | grep $HYSTERIA2_PORT${RESET}"
        echo -e "  检查证书权限: ${YELLOW}ls -la /etc/hysteria2/${RESET}"
        echo -e "  测试配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/hysteria2/config.json${RESET}"
        echo ""
    fi

    # 创建健康检查脚本（自动集成）
    create_healthcheck_script

    # ==================== 保存配置信息 ====================
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

    # 生成分享链接
    if [ "$ENABLE_OBFS" = true ]; then
        HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
    else
        HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
    fi

    # ==================== 输出配置信息 ====================
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   安装完成！配置信息如下   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo -e "  域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${HYSTERIA2_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Hysteria2 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${HYSTERIA2_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${HYSTERIA2_PASSWORD}${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "  混淆: ${GREEN}已启用 (salamander)${RESET}"
        echo -e "  混淆密码: ${YELLOW}${OBFS_PASSWORD}${RESET}"
    else
        echo -e "  混淆: ${YELLOW}未启用${RESET}"
    fi
    echo -e "  TLS: ${GREEN}Let's Encrypt 证书 (自动续签)${RESET}"
    echo ""
    
    # 显示证书信息
    if [ -f /etc/hysteria2/server.crt ]; then
        CERT_EXPIRY=$(openssl x509 -in /etc/hysteria2/server.crt -noout -enddate | cut -d= -f2)
        echo -e "${CYAN}证书信息:${RESET}"
        echo -e "  颁发者: ${GREEN}Let's Encrypt${RESET}"
        echo -e "  到期时间: ${YELLOW}${CERT_EXPIRY}${RESET}"
        echo ""
    fi
    
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${HYSTERIA2_LINK}${RESET}"
    echo ""
    echo -e "${CYAN}二维码:${RESET}"
    qrencode -t ANSIUTF8 "$HYSTERIA2_LINK"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
    else
        echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}${RESET}"
    fi
        echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}✓ 已自动启用以下功能${RESET}"
    echo -e "${GREEN}  - Hysteria2 协议 (高速、抗丢包)${RESET}"
    echo -e "${GREEN}  - Let's Encrypt 证书 (自动续签)${RESET}"
    if [ "$ENABLE_OBFS" = true ]; then
        echo -e "${GREEN}  - Salamander 混淆 (增强抗审查)${RESET}"
    fi
    echo -e "${GREEN}  - 服务自动重启 (Restart=always)${RESET}"
    echo -e "${GREEN}  - 健康检查 (每5分钟)${RESET}"
    echo -e "${GREEN}  - 文件描述符限制 (65535)${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    
    # 如果服务未正常运行，提示用户
    if [ "$HYSTERIA2_STATUS" != "active" ]; then
        echo -e "${YELLOW}⚠️  警告: Hysteria2 服务未正常启动${RESET}"
        echo -e "${YELLOW}调试步骤:${RESET}"
        echo -e "  1. 查看日志: ${CYAN}journalctl -u hysteria2 -f${RESET}"
        echo -e "  2. 检查配置: ${CYAN}cat /etc/hysteria2/config.json${RESET}"
        echo -e "  3. 测试配置: ${CYAN}/usr/local/bin/sing-box check -c /etc/hysteria2/config.json${RESET}"
        echo -e "  4. 检查证书权限: ${CYAN}ls -la /etc/hysteria2/${RESET}"
        echo -e "  5. 检查端口占用: ${CYAN}netstat -tulpn | grep ${HYSTERIA2_PORT}${RESET}"
        echo ""
    else
        echo -e "${GREEN}🎉 Hysteria2 安装成功并正常运行！${RESET}"
        echo ""
        echo -e "${CYAN}证书管理提示:${RESET}"
        echo -e "  - 证书有效期: ${YELLOW}90 天${RESET}"
        echo -e "  - 自动续签: ${GREEN}已启用 (到期前 30 天自动续签)${RESET}"
        echo -e "  - 查看证书状态: ${YELLOW}选择菜单选项 22${RESET}"
        echo -e "  - 手动续签: ${YELLOW}选择菜单选项 21${RESET}"
        echo ""
    fi
}
# 更新 Snell
update_snell() {
    if ! check_snell_installed; then
        echo -e "${RED}Snell 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Snell${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 读取当前配置
    source /etc/snell-proxy-config.txt
    CURRENT_VERSION=$SNELL_VERSION

    detect_architecture

    # 获取最新版本
    echo -e "${CYAN}正在获取最新的 Snell 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://kb.nssurge.com/surge-knowledge-base/release-notes/snell | grep -oP 'snell-server-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(curl -s https://manual.nssurge.com/others/snell.html | grep -oP 'snell-server-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}无法获取最新版本${RESET}"
        return
    fi

    echo -e "${CYAN}当前版本: ${YELLOW}v${CURRENT_VERSION}${RESET}"
    echo -e "${CYAN}最新版本: ${YELLOW}v${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    # 停止服务
    systemctl stop snell

    # 备份当前配置
    cp /etc/snell/snell-server.conf /etc/snell/snell-server.conf.bak

    # 下载新版本
    SNELL_DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v${LATEST_VERSION}-linux-${SNELL_ARCH}.zip"
    echo -e "${CYAN}正在下载: ${SNELL_DOWNLOAD_URL}${RESET}"
    
    wget "$SNELL_DOWNLOAD_URL" -O /tmp/snell-server.zip

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${RESET}"
        systemctl start snell
        return
    fi

    # 解压并安装
    unzip -o /tmp/snell-server.zip -d /usr/local/bin
    chmod +x /usr/local/bin/snell-server
    rm /tmp/snell-server.zip

    # 更新配置文件中的版本号
    sed -i "s/SNELL_VERSION=.*/SNELL_VERSION=$LATEST_VERSION/" /etc/snell-proxy-config.txt

    # 启动服务
    systemctl start snell

    # 检查状态
    sleep 2
    SNELL_STATUS=$(systemctl is-active snell)

    if [ "$SNELL_STATUS" == "active" ]; then
        echo -e "${GREEN}Snell 更新成功！${RESET}"
        echo -e "${CYAN}新版本: ${YELLOW}v${LATEST_VERSION}${RESET}"
    else
        echo -e "${RED}Snell 启动失败${RESET}"
        journalctl -u snell -n 20 --no-pager
    fi
}

# 更新 Sing-box
update_singbox() {
    if ! check_singbox_installed; then
        echo -e "${RED}Sing-box 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Sing-box${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 读取当前配置
    source /etc/singbox-proxy-config.txt
    CURRENT_VERSION=$SINGBOX_VERSION

    detect_architecture

    # 获取最新版本
    echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}无法获取最新版本${RESET}"
        return
    fi

    echo -e "${CYAN}当前版本: ${YELLOW}${CURRENT_VERSION}${RESET}"
    echo -e "${CYAN}最新版本: ${YELLOW}${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    # 停止服务
    systemctl stop sing-box

    # 备份当前配置
    cp /etc/sing-box/config.json /etc/sing-box/config.json.bak

    # 下载新版本
    SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
    echo -e "${CYAN}正在下载: ${SINGBOX_DOWNLOAD_URL}${RESET}"
    
    cd /tmp
    wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${RESET}"
        systemctl start sing-box
        return
    fi

    # 解压并安装
    tar -xzf sing-box.tar.gz
    SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
    
    if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
        mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
    else
        echo -e "${RED}解压失败${RESET}"
        systemctl start sing-box
        return
    fi

    # 清理临时文件
    rm -rf /tmp/sing-box*

    # 更新配置文件中的版本号
    sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$LATEST_VERSION/" /etc/singbox-proxy-config.txt

    # 启动服务
    systemctl start sing-box

    # 检查状态
    sleep 2
    SINGBOX_STATUS=$(systemctl is-active sing-box)

    if [ "$SINGBOX_STATUS" == "active" ]; then
        echo -e "${GREEN}Sing-box 更新成功！${RESET}"
        echo -e "${CYAN}新版本: ${YELLOW}${LATEST_VERSION}${RESET}"
    else
        echo -e "${RED}Sing-box 启动失败${RESET}"
        journalctl -u sing-box -n 20 --no-pager
    fi
}

# 更新 Reality
update_reality() {
    if ! check_reality_installed; then
        echo -e "${RED}Reality 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Reality${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 读取当前配置
    source /etc/reality-proxy-config.txt
    CURRENT_VERSION=$SINGBOX_VERSION

    detect_architecture

    # 获取最新版本
    echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}无法获取最新版本${RESET}"
        return
    fi

    echo -e "${CYAN}当前版本: ${YELLOW}${CURRENT_VERSION}${RESET}"
    echo -e "${CYAN}最新版本: ${YELLOW}${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    # 停止服务
    systemctl stop sing-box-reality

    # 备份当前配置
    cp /etc/sing-box-reality/config.json /etc/sing-box-reality/config.json.bak

    # 下载新版本
    SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
    echo -e "${CYAN}正在下载: ${SINGBOX_DOWNLOAD_URL}${RESET}"
    
    cd /tmp
    wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${RESET}"
        systemctl start sing-box-reality
        return
    fi

    # 解压并安装
    tar -xzf sing-box.tar.gz
    SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
    
    if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
        mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
    else
        echo -e "${RED}解压失败${RESET}"
        systemctl start sing-box-reality
        return
    fi

    # 清理临时文件
    rm -rf /tmp/sing-box*

    # 更新配置文件中的版本号
    sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$LATEST_VERSION/" /etc/reality-proxy-config.txt

    # 启动服务
    systemctl start sing-box-reality

    # 检查状态
    sleep 2
    REALITY_STATUS=$(systemctl is-active sing-box-reality)

    if [ "$REALITY_STATUS" == "active" ]; then
        echo -e "${GREEN}Reality 更新成功！${RESET}"
        echo -e "${CYAN}新版本: ${YELLOW}${LATEST_VERSION}${RESET}"
    else
        echo -e "${RED}Reality 启动失败${RESET}"
        journalctl -u sing-box-reality -n 20 --no-pager
    fi
}

# 更新 Hysteria2
update_hysteria2() {
    if ! check_hysteria2_installed; then
        echo -e "${RED}Hysteria2 未安装，无法更新${RESET}"
        return
    fi

    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新 Hysteria2${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    # 读取当前配置
    source /etc/hysteria2-proxy-config.txt
    CURRENT_VERSION=$SINGBOX_VERSION

    detect_architecture

    # 获取最新版本
    echo -e "${CYAN}正在获取最新的 Sing-box 版本...${RESET}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}无法获取最新版本${RESET}"
        return
    fi

    echo -e "${CYAN}当前版本: ${YELLOW}${CURRENT_VERSION}${RESET}"
    echo -e "${CYAN}最新版本: ${YELLOW}${LATEST_VERSION}${RESET}"

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo -e "${GREEN}已经是最新版本，无需更新${RESET}"
        return
    fi

    echo -e "${YELLOW}发现新版本，开始更新...${RESET}"

    # 停止服务
    systemctl stop hysteria2

    # 备份当前配置
    cp /etc/hysteria2/config.json /etc/hysteria2/config.json.bak

    # 下载新版本
    SINGBOX_DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${SINGBOX_ARCH}.tar.gz"
    echo -e "${CYAN}正在下载: ${SINGBOX_DOWNLOAD_URL}${RESET}"
    
    cd /tmp
    wget "$SINGBOX_DOWNLOAD_URL" -O sing-box.tar.gz

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${RESET}"
        systemctl start hysteria2
        return
    fi

    # 解压并安装
    tar -xzf sing-box.tar.gz
    SINGBOX_DIR=$(find /tmp -type d -name "sing-box-*-linux-${SINGBOX_ARCH}" | head -n 1)
    
    if [ -n "$SINGBOX_DIR" ] && [ -f "$SINGBOX_DIR/sing-box" ]; then
        mv "$SINGBOX_DIR/sing-box" /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
    else
        echo -e "${RED}解压失败${RESET}"
        systemctl start hysteria2
        return
    fi

    # 清理临时文件
    rm -rf /tmp/sing-box*

    # 更新配置文件中的版本号
    sed -i "s/SINGBOX_VERSION=.*/SINGBOX_VERSION=$LATEST_VERSION/" /etc/hysteria2-proxy-config.txt

    # 启动服务
    systemctl start hysteria2

    # 检查状态
    sleep 2
    HYSTERIA2_STATUS=$(systemctl is-active hysteria2)

    if [ "$HYSTERIA2_STATUS" == "active" ]; then
        echo -e "${GREEN}Hysteria2 更新成功！${RESET}"
        echo -e "${CYAN}新版本: ${YELLOW}${LATEST_VERSION}${RESET}"
    else
        echo -e "${RED}Hysteria2 启动失败${RESET}"
        journalctl -u hysteria2 -n 20 --no-pager
    fi
}

# 更新所有服务
update_all() {
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   正在更新所有服务${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""

    if check_snell_installed; then
        update_snell
        echo ""
    fi

    if check_singbox_installed; then
        update_singbox
        echo ""
    fi

    if check_reality_installed; then
        update_reality
        echo ""
    fi

    if check_hysteria2_installed; then
        update_hysteria2
        echo ""
    fi

    if ! check_snell_installed && ! check_singbox_installed && ! check_reality_installed && ! check_hysteria2_installed; then
        echo -e "${RED}没有已安装的服务${RESET}"
    fi
}
# 卸载 Snell + Shadow-TLS
uninstall_snell() {
    echo -e "${YELLOW}正在卸载 Snell + Shadow-TLS...${RESET}"

    # 停止服务
    systemctl stop snell 2>/dev/null
    systemctl stop shadow-tls-snell 2>/dev/null

    # 禁用服务
    systemctl disable snell 2>/dev/null
    systemctl disable shadow-tls-snell 2>/dev/null

    # 删除服务文件
    rm -f /lib/systemd/system/snell.service
    rm -f /etc/systemd/system/shadow-tls-snell.service

    # 删除二进制文件
    rm -f /usr/local/bin/snell-server

    # 删除配置文件
    rm -rf /etc/snell
    rm -f /etc/snell-proxy-config.txt

    # 删除用户
    userdel snell 2>/dev/null

    # 重载 systemd
    systemctl daemon-reload

    echo -e "${GREEN}Snell + Shadow-TLS 已成功卸载！${RESET}"
}

# 卸载 Sing-box
uninstall_singbox() {
    echo -e "${YELLOW}正在卸载 Sing-box...${RESET}"

    # 停止服务
    systemctl stop sing-box 2>/dev/null

    # 禁用服务
    systemctl disable sing-box 2>/dev/null

    # 删除服务文件
    rm -f /lib/systemd/system/sing-box.service

    # 删除配置文件
    rm -rf /etc/sing-box
    rm -f /etc/singbox-proxy-config.txt

    # 删除用户
    userdel sing-box 2>/dev/null

    # 重载 systemd
    systemctl daemon-reload

    echo -e "${GREEN}Sing-box 已成功卸载！${RESET}"
}

# 卸载 Reality
uninstall_reality() {
    echo -e "${YELLOW}正在卸载 VLESS Reality...${RESET}"

    # 停止服务
    systemctl stop sing-box-reality 2>/dev/null

    # 禁用服务
    systemctl disable sing-box-reality 2>/dev/null

    # 删除服务文件
    rm -f /lib/systemd/system/sing-box-reality.service

    # 删除配置文件
    rm -rf /etc/sing-box-reality
    rm -f /etc/reality-proxy-config.txt

    # 删除用户
    userdel sing-box-reality 2>/dev/null

    # 重载 systemd
    systemctl daemon-reload

    echo -e "${GREEN}VLESS Reality 已成功卸载！${RESET}"
}

# 卸载 Hysteria2
uninstall_hysteria2() {
    echo -e "${YELLOW}正在卸载 Hysteria2...${RESET}"

    # 读取配置以获取域名信息
    if [ -f /etc/hysteria2-proxy-config.txt ]; then
        source /etc/hysteria2-proxy-config.txt
        
        # 如果使用 Let's Encrypt 证书，询问是否删除证书
        if [ "$CERT_TYPE" == "letsencrypt" ]; then
            echo ""
            read -p "是否同时删除 Let's Encrypt 证书？(y/n): " remove_cert
            if [ "$remove_cert" == "y" ] || [ "$remove_cert" == "Y" ]; then
                if [ -n "$HYSTERIA2_DOMAIN" ]; then
                    echo -e "${CYAN}正在删除域名 ${YELLOW}${HYSTERIA2_DOMAIN}${CYAN} 的证书...${RESET}"
                    ~/.acme.sh/acme.sh --remove -d "$HYSTERIA2_DOMAIN" --ecc 2>/dev/null
                    echo -e "${GREEN}✓ 证书已删除${RESET}"
                fi
            fi
        fi
    fi

    # 停止服务
    systemctl stop hysteria2 2>/dev/null

    # 禁用服务
    systemctl disable hysteria2 2>/dev/null

    # 删除服务文件
    rm -f /lib/systemd/system/hysteria2.service

    # 删除配置文件
    rm -rf /etc/hysteria2
    rm -f /etc/hysteria2-proxy-config.txt

    # 删除用户
    userdel hysteria2 2>/dev/null

    # 重载 systemd
    systemctl daemon-reload

    echo -e "${GREEN}Hysteria2 已成功卸载！${RESET}"
}

# 卸载所有服务
uninstall_all() {
    echo -e "${YELLOW}正在卸载所有服务...${RESET}"
    
    uninstall_snell
    uninstall_singbox
    uninstall_reality
    uninstall_hysteria2
    
    # 删除共享二进制文件（只有在所有服务都卸载后才删除）
    if ! check_snell_installed && ! check_singbox_installed && ! check_reality_installed && ! check_hysteria2_installed; then
        rm -f /usr/local/bin/shadow-tls
        rm -f /usr/local/bin/sing-box
        echo -e "${GREEN}共享二进制文件已删除${RESET}"
        
        # 删除健康检查脚本和 cron 任务
        rm -f /usr/local/bin/snell-healthcheck.sh
        rm -f /var/log/snell-healthcheck.log
        crontab -l 2>/dev/null | grep -v "snell-healthcheck.sh" | crontab -
        echo -e "${GREEN}健康检查脚本已删除${RESET}"
        
        # 询问是否删除 acme.sh
        if [ -d ~/.acme.sh ]; then
            echo ""
            read -p "是否同时删除 acme.sh？(y/n): " remove_acme
            if [ "$remove_acme" == "y" ] || [ "$remove_acme" == "Y" ]; then
                ~/.acme.sh/acme.sh --uninstall 2>/dev/null
                rm -rf ~/.acme.sh
                echo -e "${GREEN}acme.sh 已删除${RESET}"
            fi
        fi
    fi
    
    echo -e "${GREEN}所有服务已成功卸载！${RESET}"
}
# 查看 Snell 配置
view_snell_config() {
    if [ ! -f /etc/snell-proxy-config.txt ]; then
        echo -e "${RED}未找到 Snell 配置文件。请先安装 Snell 服务。${RESET}"
        return
    fi

    source /etc/snell-proxy-config.txt

    SNELL_STATUS=$(systemctl is-active snell 2>/dev/null || echo "未运行")
    SHADOW_TLS_STATUS=$(systemctl is-active shadow-tls-snell 2>/dev/null || echo "未运行")

    # 检查监听地址
    if [ -f /etc/snell/snell-server.conf ]; then
        SNELL_LISTEN=$(grep "listen" /etc/snell/snell-server.conf | cut -d '=' -f 2 | tr -d ' ')
        if [[ $SNELL_LISTEN == 127.0.0.1:* ]]; then
            SECURITY_INFO="${GREEN}(仅本地，安全)${RESET}"
        else
            SECURITY_INFO="${RED}(公网可访问，不安全！)${RESET}"
        fi
    else
        SECURITY_INFO=""
    fi

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}      Snell + Shadow-TLS 配置信息        ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Snell 配置:${RESET}"
    echo -e "  版本: ${YELLOW}v${SNELL_VERSION}${RESET}"
    echo -e "  监听地址: ${YELLOW}${SNELL_LISTEN:-未知}${RESET} ${SECURITY_INFO}"
    echo -e "  PSK: ${YELLOW}${SNELL_PSK}${RESET}"
    echo -e "  状态: ${YELLOW}${SNELL_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SHADOW_TLS_VERSION}${RESET}"
    echo -e "  外部端口: ${YELLOW}${SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "  伪装域名: ${YELLOW}${TLS_DOMAIN}${RESET}"
    echo -e "  状态: ${YELLOW}${SHADOW_TLS_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置 (Snell v4):${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=4, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置 (Snell v5):${RESET}"
    echo -e "${GREEN}Proxy = snell, ${SERVER_IP}, ${SHADOW_TLS_PORT}, psk=${SNELL_PSK}, version=5, reuse=true, tfo=true, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Snell 状态: ${YELLOW}systemctl status snell${RESET}"
    echo -e "  重启 Snell: ${YELLOW}systemctl restart snell${RESET}"
    echo -e "  查看 Snell 日志: ${YELLOW}journalctl -u snell -f${RESET}"
    echo -e "  查看 Shadow-TLS 状态: ${YELLOW}systemctl status shadow-tls-snell${RESET}"
    echo -e "  重启 Shadow-TLS: ${YELLOW}systemctl restart shadow-tls-snell${RESET}"
    echo -e "  查看 Shadow-TLS 日志: ${YELLOW}journalctl -u shadow-tls-snell -f${RESET}"
    echo ""
}

# 查看 Sing-box 配置
view_singbox_config() {
    if [ ! -f /etc/singbox-proxy-config.txt ]; then
        echo -e "${RED}未找到 Sing-box 配置文件。请先安装 Sing-box 服务。${RESET}"
        return
    fi

    source /etc/singbox-proxy-config.txt

    SINGBOX_STATUS=$(systemctl is-active sing-box 2>/dev/null || echo "未运行")

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}   Sing-box (SS-2022 + Shadow-TLS) 配置信息   ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${SINGBOX_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Shadowsocks-2022 配置:${RESET}"
    echo -e "  内部端口: ${YELLOW}${SS_PORT}${RESET} ${GREEN}(仅本地，安全)${RESET}"
    echo -e "  密码: ${YELLOW}${SS_PASSWORD}${RESET}"
    echo -e "  加密方式: ${YELLOW}${SS_METHOD}${RESET}"
    echo ""
    echo -e "${CYAN}Shadow-TLS 配置:${RESET}"
    echo -e "  外部端口: ${YELLOW}${SHADOW_TLS_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${SHADOW_TLS_PASSWORD}${RESET}"
    echo -e "  伪装域名: ${YELLOW}${TLS_DOMAIN}${RESET}"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    echo -e "${GREEN}Proxy = ss, ${SERVER_IP}, ${SHADOW_TLS_PORT}, encrypt-method=${SS_METHOD}, password=${SS_PASSWORD}, shadow-tls-password=${SHADOW_TLS_PASSWORD}, shadow-tls-sni=${TLS_DOMAIN}, shadow-tls-version=3${RESET}"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Sing-box 状态: ${YELLOW}systemctl status sing-box${RESET}"
    echo -e "  重启 Sing-box: ${YELLOW}systemctl restart sing-box${RESET}"
    echo -e "  查看 Sing-box 日志: ${YELLOW}journalctl -u sing-box -f${RESET}"
    echo -e "  检查配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/sing-box/config.json${RESET}"
    echo ""
}

# 查看 Reality 配置
view_reality_config() {
    if [ ! -f /etc/reality-proxy-config.txt ]; then
        echo -e "${RED}未找到 Reality 配置文件。请先安装 Reality 服务。${RESET}"
        return
    fi

    source /etc/reality-proxy-config.txt

    REALITY_STATUS=$(systemctl is-active sing-box-reality 2>/dev/null || echo "未运行")

    # 生成分享链接
    REALITY_LINK="vless://${REALITY_UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-${SERVER_IP}"

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}      VLESS Reality 配置信息        ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${REALITY_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}VLESS Reality 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${REALITY_PORT}${RESET}"
    echo -e "  UUID: ${YELLOW}${REALITY_UUID}${RESET}"
    echo -e "  Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${RESET}"
    echo -e "  Short ID: ${YELLOW}${REALITY_SHORT_ID}${RESET}"
    echo -e "  目标网站: ${YELLOW}${REALITY_DEST}${RESET}"
    echo -e "  Flow: ${YELLOW}xtls-rprx-vision${RESET}"
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${REALITY_LINK}${RESET}"
    echo ""
    echo -e "${CYAN}二维码:${RESET}"
    qrencode -t ANSIUTF8 "$REALITY_LINK"
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Reality 状态: ${YELLOW}systemctl status sing-box-reality${RESET}"
    echo -e "  重启 Reality: ${YELLOW}systemctl restart sing-box-reality${RESET}"
    echo -e "  查看 Reality 日志: ${YELLOW}journalctl -u sing-box-reality -f${RESET}"
    echo -e "  检查配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/sing-box-reality/config.json${RESET}"
    echo ""
}
# 查看 Hysteria2 配置
view_hysteria2_config() {
    if [ ! -f /etc/hysteria2-proxy-config.txt ]; then
        echo -e "${RED}未找到 Hysteria2 配置文件。请先安装 Hysteria2 服务。${RESET}"
        return
    fi

    source /etc/hysteria2-proxy-config.txt

    HYSTERIA2_STATUS=$(systemctl is-active hysteria2 2>/dev/null || echo "未运行")

    # 生成分享链接
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        if [ "$ENABLE_OBFS" = "true" ]; then
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
        else
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${HYSTERIA2_DOMAIN}:${HYSTERIA2_PORT}?sni=${HYSTERIA2_DOMAIN}#Hysteria2-${HYSTERIA2_DOMAIN}"
        fi
    else
        if [ "$ENABLE_OBFS" = "true" ]; then
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${SERVER_IP}:${HYSTERIA2_PORT}?insecure=1&obfs=salamander&obfs-password=${OBFS_PASSWORD}&sni=bing.com#Hysteria2-${SERVER_IP}"
        else
            HYSTERIA2_LINK="hysteria2://${HYSTERIA2_PASSWORD}@${SERVER_IP}:${HYSTERIA2_PORT}?insecure=1&sni=bing.com#Hysteria2-${SERVER_IP}"
        fi
    fi

    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo -e "${GREEN}      Hysteria2 配置信息        ${RESET}"
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务器信息:${RESET}"
    echo -e "  服务器 IP: ${YELLOW}${SERVER_IP}${RESET} ${CYAN}(${IP_VERSION})${RESET}"
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo -e "  域名: ${YELLOW}${HYSTERIA2_DOMAIN}${RESET}"
    fi
    echo ""
    echo -e "${CYAN}Sing-box 配置:${RESET}"
    echo -e "  版本: ${YELLOW}${SINGBOX_VERSION}${RESET}"
    echo -e "  状态: ${YELLOW}${HYSTERIA2_STATUS}${RESET}"
    echo ""
    echo -e "${CYAN}Hysteria2 配置:${RESET}"
    echo -e "  端口: ${YELLOW}${HYSTERIA2_PORT}${RESET}"
    echo -e "  密码: ${YELLOW}${HYSTERIA2_PASSWORD}${RESET}"
    if [ "$ENABLE_OBFS" = "true" ]; then
        echo -e "  混淆: ${GREEN}已启用 (salamander)${RESET}"
        echo -e "  混淆密码: ${YELLOW}${OBFS_PASSWORD}${RESET}"
    else
        echo -e "  混淆: ${YELLOW}未启用${RESET}"
    fi
    
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo -e "  TLS: ${GREEN}Let's Encrypt 证书 (自动续签)${RESET}"
    else
        echo -e "  TLS: ${YELLOW}自签名证书${RESET}"
    fi
    echo ""
    echo -e "${CYAN}分享链接:${RESET}"
    echo -e "${GREEN}${HYSTERIA2_LINK}${RESET}"
    echo ""
    echo -e "${CYAN}二维码:${RESET}"
    qrencode -t ANSIUTF8 "$HYSTERIA2_LINK"
    echo ""
    echo -e "${CYAN}Surge 配置:${RESET}"
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        if [ "$ENABLE_OBFS" = "true" ]; then
            echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
        else
            echo -e "${GREEN}Proxy = hysteria2, ${HYSTERIA2_DOMAIN}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, sni=${HYSTERIA2_DOMAIN}${RESET}"
        fi
    else
        if [ "$ENABLE_OBFS" = "true" ]; then
            echo -e "${GREEN}Proxy = hysteria2, ${SERVER_IP}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, skip-cert-verify=true, sni=bing.com, obfs=salamander, obfs-password=${OBFS_PASSWORD}${RESET}"
        else
            echo -e "${GREEN}Proxy = hysteria2, ${SERVER_IP}, ${HYSTERIA2_PORT}, password=${HYSTERIA2_PASSWORD}, skip-cert-verify=true, sni=bing.com${RESET}"
        fi
    fi
    echo ""
    echo -e "${GREEN}=========================================${RESET}"
    echo ""
    echo -e "${CYAN}服务管理命令:${RESET}"
    echo -e "  查看 Hysteria2 状态: ${YELLOW}systemctl status hysteria2${RESET}"
    echo -e "  重启 Hysteria2: ${YELLOW}systemctl restart hysteria2${RESET}"
    echo -e "  查看 Hysteria2 日志: ${YELLOW}journalctl -u hysteria2 -f${RESET}"
    echo -e "  检查配置文件: ${YELLOW}/usr/local/bin/sing-box check -c /etc/hysteria2/config.json${RESET}"
    if [ "$CERT_TYPE" == "letsencrypt" ]; then
        echo ""
        echo -e "${CYAN}证书管理命令:${RESET}"
        echo -e "  查看证书状态: ${YELLOW}选择菜单选项 22${RESET}"
        echo -e "  手动续签证书: ${YELLOW}选择菜单选项 21${RESET}"
    fi
    echo ""
}

# 查看所有配置
view_all_config() {
    local has_config=false
    
    if check_snell_installed; then
        view_snell_config
        has_config=true
    fi
    
    if check_singbox_installed; then
        if [ "$has_config" = true ]; then
            echo ""
            echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        view_singbox_config
        has_config=true
    fi
    
    if check_reality_installed; then
        if [ "$has_config" = true ]; then
            echo ""
            echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        view_reality_config
        has_config=true
    fi
    
    if check_hysteria2_installed; then
        if [ "$has_config" = true ]; then
            echo ""
            echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo ""
        fi
        view_hysteria2_config
        has_config=true
    fi
    
    if [ "$has_config" = false ]; then
        echo -e "${RED}未找到任何配置文件。请先安装代理服务。${RESET}"
    fi
}

# 查看服务日志
view_logs() {
    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}   选择要查看的日志${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    
    local options=()
    local services=()
    
    if check_snell_installed; then
        options+=("1. Snell 服务日志")
        services+=("snell")
        options+=("2. Shadow-TLS (Snell) 服务日志")
        services+=("shadow-tls-snell")
    fi
    
    if check_singbox_installed; then
        local num=$((${#options[@]} + 1))
        options+=("$num. Sing-box 服务日志")
        services+=("sing-box")
    fi
    
    if check_reality_installed; then
        local num=$((${#options[@]} + 1))
        options+=("$num. Reality 服务日志")
        services+=("sing-box-reality")
    fi
    
    if check_hysteria2_installed; then
        local num=$((${#options[@]} + 1))
        options+=("$num. Hysteria2 服务日志")
        services+=("hysteria2")
    fi
    
    if [ ${#options[@]} -eq 0 ]; then
        echo -e "${RED}没有已安装的服务${RESET}"
        return
    fi
    
    for opt in "${options[@]}"; do
        echo -e "${YELLOW}$opt${RESET}"
    done
    
    local health_num=$((${#options[@]} + 1))
    echo -e "${YELLOW}$health_num. 健康检查日志${RESET}"
    echo -e "${YELLOW}0. 返回主菜单${RESET}"
    echo ""
    
    read -p "请选择 [0-$health_num]: " log_choice
    
    case $log_choice in
        0)
            return
            ;;
        $health_num)
            if [ -f /var/log/snell-healthcheck.log ]; then
                echo -e "${CYAN}显示最近 50 行健康检查日志 (Ctrl+C 退出):${RESET}"
                tail -n 50 /var/log/snell-healthcheck.log
            else
                echo -e "${RED}健康检查日志文件不存在${RESET}"
            fi
            ;;
        *)
            if [ "$log_choice" -ge 1 ] && [ "$log_choice" -le ${#services[@]} ]; then
                local service="${services[$((log_choice-1))]}"
                echo -e "${CYAN}显示 $service 服务日志 (Ctrl+C 退出):${RESET}"
                journalctl -u "$service" -n 50 --no-pager
                echo ""
                read -p "是否实时查看日志？(y/n): " realtime
                if [ "$realtime" == "y" ] || [ "$realtime" == "Y" ]; then
                    journalctl -u "$service" -f
                fi
            else
                echo -e "${RED}无效的选择${RESET}"
            fi
            ;;
    esac
}
# 主程序
main() {
    check_root

    while true; do
        show_menu
        read -p "请选择操作 [0-22]: " choice

        case $choice in
            1)
                install_snell
                read -p "按回车键继续..."
                ;;
            2)
                install_singbox
                read -p "按回车键继续..."
                ;;
            3)
                install_reality
                read -p "按回车键继续..."
                ;;
            4)
                install_hysteria2
                read -p "按回车键继续..."
                ;;
            5)
                update_snell
                read -p "按回车键继续..."
                ;;
            6)
                update_singbox
                read -p "按回车键继续..."
                ;;
            7)
                update_reality
                read -p "按回车键继续..."
                ;;
            8)
                update_hysteria2
                read -p "按回车键继续..."
                ;;
            9)
                update_all
                read -p "按回车键继续..."
                ;;
            10)
                if ! check_snell_installed; then
                    echo -e "${RED}Snell 未安装${RESET}"
                    read -p "按回车键继续..."
                    continue
                fi
                read -p "确定要卸载 Snell + Shadow-TLS 吗？(y/n): " confirm
                if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                    uninstall_snell
                fi
                read -p "按回车键继续..."
                ;;
            11)
                if ! check_singbox_installed; then
                    echo -e "${RED}Sing-box 未安装${RESET}"
                    read -p "按回车键继续..."
                    continue
                fi
                read -p "确定要卸载 Sing-box 吗？(y/n): " confirm
                if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                    uninstall_singbox
                fi
                read -p "按回车键继续..."
                ;;
            12)
                if ! check_reality_installed; then
                    echo -e "${RED}Reality 未安装${RESET}"
                    read -p "按回车键继续..."
                    continue
                fi
                read -p "确定要卸载 VLESS Reality 吗？(y/n): " confirm
                if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                    uninstall_reality
                fi
                read -p "按回车键继续..."
                ;;
            13)
                if ! check_hysteria2_installed; then
                    echo -e "${RED}Hysteria2 未安装${RESET}"
                    read -p "按回车键继续..."
                    continue
                fi
                read -p "确定要卸载 Hysteria2 吗？(y/n): " confirm
                if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                    uninstall_hysteria2
                fi
                read -p "按回车键继续..."
                ;;
            14)
                read -p "确定要卸载所有服务吗？(y/n): " confirm
                if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
                    uninstall_all
                fi
                read -p "按回车键继续..."
                ;;
            15)
                view_snell_config
                read -p "按回车键继续..."
                ;;
            16)
                view_singbox_config
                read -p "按回车键继续..."
                ;;
            17)
                view_reality_config
                read -p "按回车键继续..."
                ;;
            18)
                view_hysteria2_config
                read -p "按回车键继续..."
                ;;
            19)
                view_all_config
                read -p "按回车键继续..."
                ;;
            20)
                view_logs
                read -p "按回车键继续..."
                ;;
            21)
                renew_hysteria2_cert
                read -p "按回车键继续..."
                ;;
            22)
                view_cert_status
                read -p "按回车键继续..."
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项，请重新选择${RESET}"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main
