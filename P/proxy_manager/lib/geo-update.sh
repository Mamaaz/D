#!/bin/bash
# =========================================
# Proxy Manager - GeoIP/GeoSite Update Library
# GeoIP/GeoSite 数据库自动更新
# 数据源: Loyalsoldier/v2ray-rules-dat
# =========================================

# 防止重复加载
[[ -n "${_GEO_UPDATE_LOADED:-}" ]] && return 0
_GEO_UPDATE_LOADED=1

# =========================================
# 配置路径
# =========================================
UNIFIED_CONFIG_DIR="${UNIFIED_CONFIG_DIR:-/etc/unified-singbox}"
GEOIP_FILE="$UNIFIED_CONFIG_DIR/geoip.db"
GEOSITE_FILE="$UNIFIED_CONFIG_DIR/geosite.db"
GEO_VERSION_FILE="$UNIFIED_CONFIG_DIR/geo-version.json"

# 数据源 URL (Loyalsoldier sing-box 格式)
GEOIP_URL="https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db"
GEOSITE_URL="https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db"

# Loyalsoldier 规则集 (可选备用)
LOYALSOLDIER_GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
LOYALSOLDIER_GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

# =========================================
# 初始化版本文件
# =========================================
init_geo_version_file() {
    if [ ! -f "$GEO_VERSION_FILE" ]; then
        mkdir -p "$UNIFIED_CONFIG_DIR"
        cat > "$GEO_VERSION_FILE" <<'EOF'
{
  "geoip": {
    "version": "",
    "last_updated": "",
    "source": "SagerNet/sing-geoip"
  },
  "geosite": {
    "version": "",
    "last_updated": "",
    "source": "SagerNet/sing-geosite"
  },
  "auto_update": {
    "enabled": false,
    "interval": "daily"
  }
}
EOF
        chmod 600 "$GEO_VERSION_FILE"
    fi
}

# =========================================
# 获取远程最新版本
# =========================================
get_remote_geo_version() {
    local type=$1  # geoip or geosite
    local repo=""
    
    case $type in
        geoip) repo="SagerNet/sing-geoip" ;;
        geosite) repo="SagerNet/sing-geosite" ;;
    esac
    
    local version=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
        grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
    
    echo "$version"
}

# =========================================
# 查看 GeoIP/GeoSite 状态
# =========================================
view_geo_status() {
    init_geo_version_file
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}                       🌍 GeoIP/GeoSite 状态                                 ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # GeoIP 状态
    local geoip_exists="否"
    local geoip_size="-"
    local geoip_time="-"
    local geoip_version=$(jq -r '.geoip.version // "-"' "$GEO_VERSION_FILE" 2>/dev/null)
    
    if [ -f "$GEOIP_FILE" ]; then
        geoip_exists="是"
        geoip_size=$(ls -lh "$GEOIP_FILE" 2>/dev/null | awk '{print $5}')
        geoip_time=$(stat -c %y "$GEOIP_FILE" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$GEOIP_FILE" 2>/dev/null || echo "-")
    fi
    
    echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  ${YELLOW}GeoIP 数据库${RESET}                                                          ${CYAN}║${RESET}"
    printf "${CYAN}║${RESET}    已安装: %-10s  大小: %-10s  更新日期: %-15s ${CYAN}║${RESET}\n" "$geoip_exists" "$geoip_size" "$geoip_time"
    printf "${CYAN}║${RESET}    版本: %-60s ${CYAN}║${RESET}\n" "$geoip_version"
    echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
    
    # GeoSite 状态
    local geosite_exists="否"
    local geosite_size="-"
    local geosite_time="-"
    local geosite_version=$(jq -r '.geosite.version // "-"' "$GEO_VERSION_FILE" 2>/dev/null)
    
    if [ -f "$GEOSITE_FILE" ]; then
        geosite_exists="是"
        geosite_size=$(ls -lh "$GEOSITE_FILE" 2>/dev/null | awk '{print $5}')
        geosite_time=$(stat -c %y "$GEOSITE_FILE" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$GEOSITE_FILE" 2>/dev/null || echo "-")
    fi
    
    echo -e "${CYAN}║${RESET}  ${YELLOW}GeoSite 数据库${RESET}                                                        ${CYAN}║${RESET}"
    printf "${CYAN}║${RESET}    已安装: %-10s  大小: %-10s  更新日期: %-15s ${CYAN}║${RESET}\n" "$geosite_exists" "$geosite_size" "$geosite_time"
    printf "${CYAN}║${RESET}    版本: %-60s ${CYAN}║${RESET}\n" "$geosite_version"
    echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
    
    # 自动更新状态
    local auto_enabled=$(jq -r '.auto_update.enabled // false' "$GEO_VERSION_FILE" 2>/dev/null)
    local auto_interval=$(jq -r '.auto_update.interval // "daily"' "$GEO_VERSION_FILE" 2>/dev/null)
    local auto_status="${RED}未启用${RESET}"
    [ "$auto_enabled" = "true" ] && auto_status="${GREEN}已启用 ($auto_interval)${RESET}"
    
    echo -e "${CYAN}║${RESET}  ${YELLOW}自动更新${RESET}: $auto_status                                              ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# =========================================
# 检查更新
# =========================================
check_geo_updates() {
    init_geo_version_file
    
    echo ""
    echo -e "${CYAN}正在检查 GeoIP/GeoSite 更新...${RESET}"
    echo ""
    
    local has_update=false
    
    # 检查 GeoIP
    local local_geoip=$(jq -r '.geoip.version // ""' "$GEO_VERSION_FILE" 2>/dev/null)
    local remote_geoip=$(get_remote_geo_version "geoip")
    
    echo -n "  GeoIP: "
    if [ -n "$remote_geoip" ]; then
        if [ "$local_geoip" != "$remote_geoip" ]; then
            echo -e "${YELLOW}有更新可用${RESET} ($local_geoip → $remote_geoip)"
            has_update=true
        else
            echo -e "${GREEN}已是最新${RESET} ($local_geoip)"
        fi
    else
        echo -e "${RED}无法获取版本信息${RESET}"
    fi
    
    # 检查 GeoSite
    local local_geosite=$(jq -r '.geosite.version // ""' "$GEO_VERSION_FILE" 2>/dev/null)
    local remote_geosite=$(get_remote_geo_version "geosite")
    
    echo -n "  GeoSite: "
    if [ -n "$remote_geosite" ]; then
        if [ "$local_geosite" != "$remote_geosite" ]; then
            echo -e "${YELLOW}有更新可用${RESET} ($local_geosite → $remote_geosite)"
            has_update=true
        else
            echo -e "${GREEN}已是最新${RESET} ($local_geosite)"
        fi
    else
        echo -e "${RED}无法获取版本信息${RESET}"
    fi
    
    echo ""
    
    if [ "$has_update" = true ]; then
        return 0
    else
        return 1
    fi
}

# =========================================
# 更新 GeoIP/GeoSite 数据库
# =========================================
update_geo_databases() {
    init_geo_version_file
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   更新 GeoIP/GeoSite 数据库${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    mkdir -p "$UNIFIED_CONFIG_DIR"
    
    local success=true
    local geoip_version=""
    local geosite_version=""
    
    # 获取最新版本号
    geoip_version=$(get_remote_geo_version "geoip")
    geosite_version=$(get_remote_geo_version "geosite")
    
    # 下载 GeoIP
    echo -e "${YELLOW}[1/2] 下载 GeoIP 数据库...${RESET}"
    local temp_geoip=$(mktemp)
    
    if wget -q --show-progress --progress=bar:force:noscroll \
           --timeout=60 --tries=3 \
           "$GEOIP_URL" -O "$temp_geoip" 2>&1; then
        if [ -s "$temp_geoip" ]; then
            mv "$temp_geoip" "$GEOIP_FILE"
            chmod 644 "$GEOIP_FILE"
            echo -e "${GREEN}✓ GeoIP 下载成功${RESET}"
            
            # 更新版本信息
            local temp_file=$(mktemp)
            jq --arg v "$geoip_version" --arg t "$(date -Iseconds)" \
               '.geoip.version = $v | .geoip.last_updated = $t' \
               "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
        else
            echo -e "${RED}✗ GeoIP 下载失败: 文件为空${RESET}"
            success=false
        fi
    else
        echo -e "${RED}✗ GeoIP 下载失败${RESET}"
        success=false
    fi
    rm -f "$temp_geoip"
    
    # 下载 GeoSite
    echo ""
    echo -e "${YELLOW}[2/2] 下载 GeoSite 数据库...${RESET}"
    local temp_geosite=$(mktemp)
    
    if wget -q --show-progress --progress=bar:force:noscroll \
           --timeout=60 --tries=3 \
           "$GEOSITE_URL" -O "$temp_geosite" 2>&1; then
        if [ -s "$temp_geosite" ]; then
            mv "$temp_geosite" "$GEOSITE_FILE"
            chmod 644 "$GEOSITE_FILE"
            echo -e "${GREEN}✓ GeoSite 下载成功${RESET}"
            
            # 更新版本信息
            local temp_file=$(mktemp)
            jq --arg v "$geosite_version" --arg t "$(date -Iseconds)" \
               '.geosite.version = $v | .geosite.last_updated = $t' \
               "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
        else
            echo -e "${RED}✗ GeoSite 下载失败: 文件为空${RESET}"
            success=false
        fi
    else
        echo -e "${RED}✗ GeoSite 下载失败${RESET}"
        success=false
    fi
    rm -f "$temp_geosite"
    
    echo ""
    
    if [ "$success" = true ]; then
        echo -e "${GREEN}✓ GeoIP/GeoSite 更新完成${RESET}"
        
        # 询问是否重载服务
        if systemctl is-active --quiet sing-box 2>/dev/null || \
           systemctl is-active --quiet sing-box-reality 2>/dev/null; then
            echo ""
            read -p "是否重载 sing-box 服务以应用更新? (y/n): " reload
            if [[ "$reload" =~ ^[Yy]$ ]]; then
                reload_singbox_services
            fi
        fi
    else
        echo -e "${YELLOW}⚠ 部分更新失败，请稍后重试${RESET}"
    fi
    
    echo ""
}

# =========================================
# 重载 sing-box 服务
# =========================================
reload_singbox_services() {
    echo ""
    echo -e "${CYAN}正在重载 sing-box 服务...${RESET}"
    
    local reloaded=false
    
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl reload sing-box 2>/dev/null || systemctl restart sing-box
        echo -e "${GREEN}✓ sing-box 已重载${RESET}"
        reloaded=true
    fi
    
    if systemctl is-active --quiet sing-box-reality 2>/dev/null; then
        systemctl reload sing-box-reality 2>/dev/null || systemctl restart sing-box-reality
        echo -e "${GREEN}✓ sing-box-reality 已重载${RESET}"
        reloaded=true
    fi
    
    if [ "$reloaded" = false ]; then
        echo -e "${YELLOW}没有运行中的 sing-box 服务${RESET}"
    fi
}

# =========================================
# 配置自动更新
# =========================================
setup_auto_update() {
    init_geo_version_file
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo -e "${CYAN}   配置 GeoIP/GeoSite 自动更新${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════${RESET}"
    echo ""
    
    local current_enabled=$(jq -r '.auto_update.enabled // false' "$GEO_VERSION_FILE" 2>/dev/null)
    local current_interval=$(jq -r '.auto_update.interval // "daily"' "$GEO_VERSION_FILE" 2>/dev/null)
    
    echo -e "当前状态: $([ "$current_enabled" = "true" ] && echo "${GREEN}已启用${RESET}" || echo "${RED}未启用${RESET}")"
    echo -e "更新频率: ${YELLOW}$current_interval${RESET}"
    echo ""
    
    echo -e "${YELLOW}1.${RESET} 启用自动更新"
    echo -e "${YELLOW}2.${RESET} 禁用自动更新"
    echo -e "${YELLOW}3.${RESET} 修改更新频率"
    echo -e "${YELLOW}0.${RESET} 返回"
    echo ""
    
    read -p "请选择 [0-3]: " choice
    
    case $choice in
        1)
            # 创建 systemd timer
            create_geo_update_timer
            
            # 更新配置
            local temp_file=$(mktemp)
            jq '.auto_update.enabled = true' "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
            
            echo -e "${GREEN}✓ 自动更新已启用${RESET}"
            ;;
        2)
            # 禁用 systemd timer
            systemctl stop geo-update.timer 2>/dev/null || true
            systemctl disable geo-update.timer 2>/dev/null || true
            
            # 更新配置
            local temp_file=$(mktemp)
            jq '.auto_update.enabled = false' "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
            
            echo -e "${YELLOW}✓ 自动更新已禁用${RESET}"
            ;;
        3)
            echo ""
            echo -e "${YELLOW}选择更新频率:${RESET}"
            echo -e "  1. 每天 (daily)"
            echo -e "  2. 每周 (weekly)"
            echo -e "  3. 每两周 (biweekly)"
            echo ""
            read -p "请选择 [1-3]: " interval_choice
            
            local new_interval=""
            local timer_calendar=""
            case $interval_choice in
                1) new_interval="daily"; timer_calendar="daily" ;;
                2) new_interval="weekly"; timer_calendar="weekly" ;;
                3) new_interval="biweekly"; timer_calendar="Mon *-*-1,15" ;;
                *) new_interval="daily"; timer_calendar="daily" ;;
            esac
            
            # 更新配置
            local temp_file=$(mktemp)
            jq --arg i "$new_interval" '.auto_update.interval = $i' "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
            
            # 如果已启用，重新创建 timer
            if [ "$current_enabled" = "true" ]; then
                create_geo_update_timer "$timer_calendar"
            fi
            
            echo -e "${GREEN}✓ 更新频率已设置为: $new_interval${RESET}"
            ;;
        0) return 0 ;;
    esac
}

# =========================================
# 创建 systemd timer
# =========================================
create_geo_update_timer() {
    local calendar=${1:-"daily"}
    
    # 创建更新服务
    cat > /etc/systemd/system/geo-update.service <<EOF
[Unit]
Description=Update GeoIP and GeoSite databases
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'source /opt/proxy-manager/lib/common.sh && source /opt/proxy-manager/lib/geo-update.sh && update_geo_databases_silent'
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

    # 创建定时器
    cat > /etc/systemd/system/geo-update.timer <<EOF
[Unit]
Description=GeoIP/GeoSite Auto Update Timer

[Timer]
OnCalendar=$calendar
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

    chmod 644 /etc/systemd/system/geo-update.service
    chmod 644 /etc/systemd/system/geo-update.timer
    
    systemctl daemon-reload
    systemctl enable geo-update.timer
    systemctl start geo-update.timer
    
    log_message "INFO" "已创建 GeoIP/GeoSite 自动更新定时器: $calendar"
}

# =========================================
# 静默更新 (用于定时任务)
# =========================================
update_geo_databases_silent() {
    init_geo_version_file
    
    mkdir -p "$UNIFIED_CONFIG_DIR"
    
    local geoip_version=$(get_remote_geo_version "geoip")
    local geosite_version=$(get_remote_geo_version "geosite")
    
    # 下载 GeoIP
    local temp_geoip=$(mktemp)
    if wget -q --timeout=60 --tries=3 "$GEOIP_URL" -O "$temp_geoip" 2>/dev/null; then
        if [ -s "$temp_geoip" ]; then
            mv "$temp_geoip" "$GEOIP_FILE"
            chmod 644 "$GEOIP_FILE"
            
            local temp_file=$(mktemp)
            jq --arg v "$geoip_version" --arg t "$(date -Iseconds)" \
               '.geoip.version = $v | .geoip.last_updated = $t' \
               "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
            
            log_message "INFO" "GeoIP 更新成功: $geoip_version"
        fi
    fi
    rm -f "$temp_geoip"
    
    # 下载 GeoSite
    local temp_geosite=$(mktemp)
    if wget -q --timeout=60 --tries=3 "$GEOSITE_URL" -O "$temp_geosite" 2>/dev/null; then
        if [ -s "$temp_geosite" ]; then
            mv "$temp_geosite" "$GEOSITE_FILE"
            chmod 644 "$GEOSITE_FILE"
            
            local temp_file=$(mktemp)
            jq --arg v "$geosite_version" --arg t "$(date -Iseconds)" \
               '.geosite.version = $v | .geosite.last_updated = $t' \
               "$GEO_VERSION_FILE" > "$temp_file" && mv "$temp_file" "$GEO_VERSION_FILE"
            chmod 600 "$GEO_VERSION_FILE"
            
            log_message "INFO" "GeoSite 更新成功: $geosite_version"
        fi
    fi
    rm -f "$temp_geosite"
    
    # 重载服务
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl reload sing-box 2>/dev/null || true
    fi
    if systemctl is-active --quiet sing-box-reality 2>/dev/null; then
        systemctl reload sing-box-reality 2>/dev/null || true
    fi
}

# =========================================
# GeoIP/GeoSite 管理菜单
# =========================================
geo_update_menu() {
    while true; do
        init_geo_version_file
        
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                       🌍 GeoIP/GeoSite 管理                                 ${CYAN}║${RESET}"
        echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}1.${RESET} 查看状态                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}2.${RESET} 检查更新                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}3.${RESET} 立即更新                                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}4.${RESET} 配置自动更新                                                      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}0.${RESET} 返回上级菜单                                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        
        read -p "请选择 [0-4]: " choice
        
        case $choice in
            1) view_geo_status ;;
            2) check_geo_updates ;;
            3) update_geo_databases ;;
            4) setup_auto_update ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}
