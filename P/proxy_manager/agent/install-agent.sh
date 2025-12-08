#!/bin/bash
# =========================================
# Proxy Manager Agent - Installation Script
# 一键安装 Agent 探针
# =========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Configuration
AGENT_PORT=${AGENT_PORT:-9900}
INSTALL_DIR="/opt/proxy-manager-agent"
GITHUB_RAW="https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager/agent"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}       ${GREEN}Proxy Manager Agent 安装${RESET}                            ${CYAN}║${RESET}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行${RESET}"
    exit 1
fi

# Install Python3 and pip
install_python() {
    echo -e "${CYAN}检查 Python3...${RESET}"
    
    if ! command -v python3 &>/dev/null; then
        echo -e "${YELLOW}正在安装 Python3...${RESET}"
        
        if command -v apt-get &>/dev/null; then
            apt-get update -qq
            apt-get install -y python3 python3-pip python3-venv
        elif command -v yum &>/dev/null; then
            yum install -y python3 python3-pip
        elif command -v dnf &>/dev/null; then
            dnf install -y python3 python3-pip
        else
            echo -e "${RED}无法安装 Python3，请手动安装${RESET}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Python3 已安装${RESET}"
}

# Generate secure token
generate_token() {
    if command -v openssl &>/dev/null; then
        openssl rand -hex 16
    else
        head -c 32 /dev/urandom | md5sum | head -c 32
    fi
}

# Main installation
install_agent() {
    install_python
    
    # Create directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Download agent files
    echo -e "${CYAN}下载 Agent 文件...${RESET}"
    curl -sL "${GITHUB_RAW}/agent.py" -o agent.py
    curl -sL "${GITHUB_RAW}/requirements.txt" -o requirements.txt
    
    # Create virtual environment
    echo -e "${CYAN}创建 Python 虚拟环境...${RESET}"
    python3 -m venv venv
    source venv/bin/activate
    
    # Install dependencies
    pip install --quiet --upgrade pip
    pip install --quiet -r requirements.txt
    
    deactivate
    
    # Generate token
    AGENT_TOKEN=$(generate_token)
    
    # Save token
    echo "AGENT_TOKEN=$AGENT_TOKEN" > "$INSTALL_DIR/.env"
    echo "AGENT_PORT=$AGENT_PORT" >> "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    
    # Create systemd service
    cat > /etc/systemd/system/proxy-agent.service <<EOF
[Unit]
Description=Proxy Manager Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start
    systemctl daemon-reload
    systemctl enable proxy-agent
    systemctl start proxy-agent
    
    sleep 2
    
    # Get server IP
    SERVER_IP=$(curl -s --connect-timeout 2 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}       ${YELLOW}Agent 安装完成！${RESET}                                   ${GREEN}║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${CYAN}服务器 IP: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "${CYAN}Agent 端口: ${YELLOW}${AGENT_PORT}${RESET}"
    echo -e "${CYAN}Token: ${YELLOW}${AGENT_TOKEN}${RESET}"
    echo ""
    echo -e "${GREEN}在控制节点添加此服务器时，请使用以上信息${RESET}"
    echo ""
    echo -e "${CYAN}测试命令:${RESET}"
    echo -e "${YELLOW}curl -H 'Authorization: Bearer ${AGENT_TOKEN}' http://${SERVER_IP}:${AGENT_PORT}/api/status${RESET}"
    echo ""
}

# Uninstall
uninstall_agent() {
    echo -e "${YELLOW}正在卸载 Agent...${RESET}"
    
    systemctl stop proxy-agent 2>/dev/null || true
    systemctl disable proxy-agent 2>/dev/null || true
    rm -f /etc/systemd/system/proxy-agent.service
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Agent 已卸载${RESET}"
}

# Parse arguments
case "${1:-install}" in
    install)
        install_agent
        ;;
    uninstall)
        uninstall_agent
        ;;
    token)
        # Show current token
        if [ -f "$INSTALL_DIR/.env" ]; then
            source "$INSTALL_DIR/.env"
            echo "$AGENT_TOKEN"
        else
            echo "Agent not installed"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {install|uninstall|token}"
        exit 1
        ;;
esac
