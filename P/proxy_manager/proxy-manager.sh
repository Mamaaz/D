#!/bin/bash
# =========================================
# Proxy Manager v3.0 (Modular)
# 多协议代理服务器一键管理脚本（模块化版本）
# 支持: Snell + Shadow-TLS, SS-2022, VLESS Reality, Hysteria2
# =========================================

set -o pipefail
set -u

# =========================================
# 脚本路径设置（正确处理软链接）
# =========================================
# 获取真实脚本路径，处理软链接情况
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
MODULE_DIR="${SCRIPT_DIR}/modules"

# =========================================
# 加载库文件
# =========================================
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/routing.sh"
source "${LIB_DIR}/outbound.sh"
source "${LIB_DIR}/geo-update.sh"
source "${LIB_DIR}/subscriptions.sh"

# =========================================
# 加载服务模块
# =========================================
source "${MODULE_DIR}/snell.sh"
source "${MODULE_DIR}/singbox.sh"
source "${MODULE_DIR}/reality.sh"
source "${MODULE_DIR}/cert.sh"
source "${MODULE_DIR}/hysteria2.sh"
source "${MODULE_DIR}/routing-menu.sh"

# =========================================
# 版本信息
# =========================================
SCRIPT_VERSION="3.3"

# =========================================
# 信号处理
# =========================================
cleanup() {
    echo ""
    echo -e "${YELLOW}正在退出...${RESET}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# =========================================
# 菜单函数
# =========================================

show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}       ${GREEN}Proxy Manager v${SCRIPT_VERSION}${RESET} - ${YELLOW}多协议代理管理${RESET}          ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

show_status() {
    get_all_service_status
    
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET}  ${YELLOW}服务状态${RESET}                                                 ${CYAN}│${RESET}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${RESET}"
    
    local services=("snell:Snell + Shadow-TLS" "sing-box:Sing-box (SS)" "sing-box-reality:VLESS Reality" "hysteria2:Hysteria2")
    
    for item in "${services[@]}"; do
        local service_name="${item%%:*}"
        local display_name="${item#*:}"
        local status="${SERVICE_STATUS_CACHE[$service_name]:-未知}"
        
        local status_color
        case $status in
            active) status_color="${GREEN}运行中${RESET}" ;;
            inactive|failed) status_color="${RED}已停止${RESET}" ;;
            未安装) status_color="${YELLOW}未安装${RESET}" ;;
            *) status_color="${YELLOW}${status}${RESET}" ;;
        esac
        
        printf "${CYAN}│${RESET}  %-20s: %b                           ${CYAN}│${RESET}\n" "$display_name" "$status_color"
    done
    
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

show_menu() {
    echo -e "${GREEN}┌─────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${GREEN}│${RESET}  ${YELLOW}安装服务${RESET}                                                 ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}1.${RESET} 安装 Snell + Shadow-TLS                              ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}2.${RESET} 安装 Sing-box (SS-2022 + Shadow-TLS)                 ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}3.${RESET} 安装 VLESS Reality                                   ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}4.${RESET} 安装 Hysteria2 (Let's Encrypt)                       ${GREEN}│${RESET}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${GREEN}│${RESET}  ${YELLOW}管理服务${RESET}                                                 ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}5.${RESET} 查看服务配置                                         ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}6.${RESET} 查看服务日志                                         ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}7.${RESET} 更新服务                                             ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}8.${RESET} 卸载服务                                             ${GREEN}│${RESET}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${GREEN}│${RESET}  ${YELLOW}证书管理${RESET}                                                 ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}9.${RESET} 续签 Hysteria2 证书                                  ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}10.${RESET} 查看证书状态                                        ${GREEN}│${RESET}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${GREEN}│${RESET}  ${YELLOW}分流管理${RESET}                                                 ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}11.${RESET} 高级分流管理 (落地代理/规则/订阅)                   ${GREEN}│${RESET}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${GREEN}│${RESET}  ${YELLOW}系统管理${RESET}                                                 ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}12.${RESET} 更新 Proxy Manager                                  ${GREEN}│${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}13.${RESET} 完全卸载 Proxy Manager                              ${GREEN}│${RESET}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${GREEN}│${RESET}    ${CYAN}0.${RESET} 退出                                                 ${GREEN}│${RESET}"
    echo -e "${GREEN}└─────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

show_config_submenu() {
    echo ""
    echo -e "${CYAN}选择要查看的配置:${RESET}"
    echo -e "${YELLOW}1.${RESET} Snell + Shadow-TLS"
    echo -e "${YELLOW}2.${RESET} Sing-box (SS-2022)"
    echo -e "${YELLOW}3.${RESET} VLESS Reality"
    echo -e "${YELLOW}4.${RESET} Hysteria2"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1) view_snell_config ;;
        2) view_singbox_config ;;
        3) view_reality_config ;;
        4) view_hysteria2_config ;;
        0) return ;;
        *) echo -e "${RED}无效选择${RESET}" ;;
    esac
    
    read -p "按回车键继续..."
}

show_log_submenu() {
    echo ""
    echo -e "${CYAN}选择要查看的日志:${RESET}"
    echo -e "${YELLOW}1.${RESET} Snell"
    echo -e "${YELLOW}2.${RESET} Sing-box"
    echo -e "${YELLOW}3.${RESET} Reality"
    echo -e "${YELLOW}4.${RESET} Hysteria2"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1) journalctl -u snell -n 50 --no-pager 2>/dev/null || echo -e "${RED}服务未安装${RESET}" ;;
        2) journalctl -u sing-box -n 50 --no-pager 2>/dev/null || echo -e "${RED}服务未安装${RESET}" ;;
        3) journalctl -u sing-box-reality -n 50 --no-pager 2>/dev/null || echo -e "${RED}服务未安装${RESET}" ;;
        4) journalctl -u hysteria2 -n 50 --no-pager 2>/dev/null || echo -e "${RED}服务未安装${RESET}" ;;
        0) return ;;
        *) echo -e "${RED}无效选择${RESET}" ;;
    esac
    
    read -p "按回车键继续..."
}

show_update_submenu() {
    echo ""
    echo -e "${CYAN}选择要更新的服务:${RESET}"
    echo -e "${YELLOW}1.${RESET} Snell + Shadow-TLS"
    echo -e "${YELLOW}2.${RESET} Sing-box (SS-2022)"
    echo -e "${YELLOW}3.${RESET} VLESS Reality"
    echo -e "${YELLOW}4.${RESET} Hysteria2"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1) update_snell ;;
        2) update_singbox ;;
        3) update_reality ;;
        4) update_hysteria2 ;;
        0) return ;;
        *) echo -e "${RED}无效选择${RESET}" ;;
    esac
    
    read -p "按回车键继续..."
}

show_uninstall_submenu() {
    echo ""
    echo -e "${CYAN}选择要卸载的服务:${RESET}"
    echo -e "${YELLOW}1.${RESET} Snell + Shadow-TLS"
    echo -e "${YELLOW}2.${RESET} Sing-box (SS-2022)"
    echo -e "${YELLOW}3.${RESET} VLESS Reality"
    echo -e "${YELLOW}4.${RESET} Hysteria2"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1) read -p "确认卸载 Snell？(y/n): " confirm; [ "$confirm" == "y" ] && uninstall_snell ;;
        2) read -p "确认卸载 Sing-box？(y/n): " confirm; [ "$confirm" == "y" ] && uninstall_singbox ;;
        3) read -p "确认卸载 Reality？(y/n): " confirm; [ "$confirm" == "y" ] && uninstall_reality ;;
        4) read -p "确认卸载 Hysteria2？(y/n): " confirm; [ "$confirm" == "y" ] && uninstall_hysteria2 ;;
        0) return ;;
        *) echo -e "${RED}无效选择${RESET}" ;;
    esac
    
    clear_status_cache
    read -p "按回车键继续..."
}

# 更新 Proxy Manager
update_proxy_manager() {
    echo ""
    echo -e "${CYAN}正在更新 Proxy Manager...${RESET}"
    echo ""
    
    local install_url="https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh"
    
    bash <(curl -sL "${install_url}?t=$(date +%s)") update
    
    echo ""
    echo -e "${GREEN}✓ 更新完成，请重新运行 proxy-manager${RESET}"
    exit 0
}

# 完全卸载 Proxy Manager
uninstall_proxy_manager() {
    echo ""
    echo -e "${RED}═══════════════════════════════════════${RESET}"
    echo -e "${RED}   警告: 完全卸载 Proxy Manager${RESET}"
    echo -e "${RED}═══════════════════════════════════════${RESET}"
    echo ""
    echo -e "${YELLOW}这将删除:${RESET}"
    echo -e "  - Proxy Manager 管理脚本"
    echo -e "  - Agent 探针 (如果已安装)"
    echo -e "${YELLOW}以下不会被删除:${RESET}"
    echo -e "  - 已安装的代理服务 (Snell/Hysteria2 等)"
    echo -e "  - 代理服务配置文件"
    echo ""
    
    read -p "确认卸载？输入 'yes' 继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${GREEN}已取消${RESET}"
        return
    fi
    
    echo ""
    echo -e "${CYAN}正在卸载...${RESET}"
    
    # 卸载 Agent
    if [ -f /etc/systemd/system/proxy-agent.service ]; then
        systemctl stop proxy-agent 2>/dev/null || true
        systemctl disable proxy-agent 2>/dev/null || true
        rm -f /etc/systemd/system/proxy-agent.service
        rm -rf /opt/proxy-manager-agent
    fi
    
    # 删除管理脚本
    rm -f /usr/local/bin/proxy-manager
    rm -rf /opt/proxy-manager
    rm -rf /etc/proxy-manager
    
    systemctl daemon-reload
    
    echo ""
    echo -e "${GREEN}✓ Proxy Manager 已完全卸载${RESET}"
    echo ""
    echo -e "${CYAN}重新安装:${RESET}"
    echo -e "${YELLOW}bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/install.sh)${RESET}"
    echo ""
    
    exit 0
}

# =========================================
# 帮助信息
# =========================================
show_help() {
    echo -e "${CYAN}Proxy Manager v${SCRIPT_VERSION}${RESET}"
    echo ""
    echo -e "多协议代理服务器一键管理脚本"
    echo ""
    echo -e "${YELLOW}用法:${RESET}"
    echo -e "  proxy-manager              运行交互式管理界面"
    echo -e "  proxy-manager --help       显示此帮助信息"
    echo -e "  proxy-manager update       更新 Proxy Manager"
    echo ""
    echo -e "${YELLOW}支持的协议:${RESET}"
    echo -e "  - Snell + Shadow-TLS"
    echo -e "  - SS-2022 + Shadow-TLS (Sing-box)"
    echo -e "  - VLESS Reality"
    echo -e "  - Hysteria2"
    echo ""
    echo -e "${YELLOW}文档:${RESET}"
    echo -e "  https://github.com/Mamaaz/D"
    echo ""
}

# =========================================
# 主循环
# =========================================
main() {
    # 处理命令行参数
    case "${1:-}" in
        --help|-h|help)
            show_help
            exit 0
            ;;
        update)
            check_root
            update_proxy_manager
            exit 0
            ;;
    esac
    
    check_root
    
    # 启动时检查版本更新
    check_version_updates
    
    while true; do
        show_header
        show_status
        show_menu
        
        read -p "请选择 [0-13]: " choice
        
        case $choice in
            1) install_snell; clear_status_cache; read -p "按回车键继续..." ;;
            2) install_singbox; clear_status_cache; read -p "按回车键继续..." ;;
            3) install_reality; clear_status_cache; read -p "按回车键继续..." ;;
            4) install_hysteria2; clear_status_cache; read -p "按回车键继续..." ;;
            5) show_config_submenu ;;
            6) show_log_submenu ;;
            7) show_update_submenu ;;
            8) show_uninstall_submenu ;;
            9) renew_hysteria2_cert; read -p "按回车键继续..." ;;
            10) view_cert_status; read -p "按回车键继续..." ;;
            11) routing_main_menu ;;
            12) update_proxy_manager ;;
            13) uninstall_proxy_manager ;;
            0) cleanup ;;
            *) echo -e "${RED}无效选择${RESET}"; sleep 1 ;;
        esac
    done
}

# =========================================
# 启动脚本
# =========================================
main "$@"
