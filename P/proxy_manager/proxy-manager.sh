#!/bin/bash
# =========================================
# Proxy Manager v3.0 (Modular)
# 多协议代理服务器一键管理脚本（模块化版本）
# 支持: Snell + Shadow-TLS, SS-2022, VLESS Reality, Hysteria2
# =========================================

set -o pipefail
set -u

# =========================================
# 脚本路径设置
# =========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
MODULE_DIR="${SCRIPT_DIR}/modules"

# =========================================
# 加载库文件
# =========================================
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/validation.sh"

# =========================================
# 加载服务模块
# =========================================
source "${MODULE_DIR}/snell.sh"
source "${MODULE_DIR}/singbox.sh"
source "${MODULE_DIR}/reality.sh"
source "${MODULE_DIR}/cert.sh"
source "${MODULE_DIR}/hysteria2.sh"

# =========================================
# 版本信息
# =========================================
SCRIPT_VERSION="3.0"

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
        2) echo -e "${YELLOW}Sing-box 更新功能开发中...${RESET}" ;;
        3) echo -e "${YELLOW}Reality 更新功能开发中...${RESET}" ;;
        4) echo -e "${YELLOW}Hysteria2 更新功能开发中...${RESET}" ;;
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

# =========================================
# 主循环
# =========================================
main() {
    check_root
    
    while true; do
        show_header
        show_status
        show_menu
        
        read -p "请选择 [0-10]: " choice
        
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
            0) cleanup ;;
            *) echo -e "${RED}无效选择${RESET}"; sleep 1 ;;
        esac
    done
}

# =========================================
# 启动脚本
# =========================================
main "$@"
