#!/bin/bash

#######################################
# Tvtxiu API 一键安装和管理脚本
# 适用于 Debian 12 / Ubuntu 22.04+
#######################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
APP_NAME="tvtxiu-api"
APP_DIR="/opt/tvtxiu"
DATA_DIR="/opt/tvtxiu"
LOG_DIR="/var/log/tvtxiu"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

# 数据库配置
DB_NAME="tvtxiu"
DB_USER="tvtxiu"
DB_PASSWORD=""  # 将在安装时生成

# 服务配置
PORT="8080"
JWT_SECRET=""  # 将在安装时生成

#######################################
# 辅助函数
#######################################

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║     Tvtxiu API 管理脚本 v1.1        ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✔ $1${NC}"
}

print_error() {
    echo -e "${RED}✘ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

generate_password() {
    openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        echo "请使用: sudo $0 $1"
        exit 1
    fi
}

#######################################
# 安装函数
#######################################

install_dependencies() {
    print_info "更新系统包..."
    apt-get update -qq
    
    print_info "安装基础依赖..."
    apt-get install -y -qq curl wget git build-essential postgresql postgresql-contrib
    
    print_info "安装 Go..."
    if ! command -v go &> /dev/null; then
        GO_VERSION="1.22.0"
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        
        # 添加到 PATH
        if ! grep -q '/usr/local/go/bin' /etc/profile; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
        fi
        export PATH=$PATH:/usr/local/go/bin
    fi
    
    print_success "依赖安装完成"
}

setup_database() {
    print_info "配置 PostgreSQL..."
    
    # 生成数据库密码
    DB_PASSWORD=$(generate_password)
    
    # 启动 PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql
    
    # 创建数据库和用户
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS ${DB_USER};" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
    
    print_success "数据库配置完成"
}

setup_directories() {
    print_info "创建目录结构..."
    
    mkdir -p "${APP_DIR}"
    mkdir -p "${DATA_DIR}/uploads"
    mkdir -p "${LOG_DIR}"
    
    print_success "目录创建完成"
}

setup_swap() {
    print_info "配置 Swap..."
    
    if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        print_success "Swap 配置完成 (2GB)"
    else
        print_warning "Swap 已存在，跳过"
    fi
}

deploy_application() {
    print_info "部署应用..."
    
    # 如果目录存在代码则更新，否则提示上传
    if [ -f "${APP_DIR}/main.go" ]; then
        cd "${APP_DIR}"
        
        # 生成 JWT 密钥
        JWT_SECRET=$(generate_password)
        
        # 创建环境配置
        cat > "${APP_DIR}/.env" << EOF
DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}?sslmode=disable
JWT_SECRET=${JWT_SECRET}
PORT=${PORT}
EOF
        
        # 构建应用
        export PATH=$PATH:/usr/local/go/bin
        go build -o ${APP_NAME} .
        
        # 创建上传目录软链接
        ln -sf "${DATA_DIR}/uploads" "${APP_DIR}/uploads"
        
        print_success "应用构建完成"
    else
        print_warning "请先上传代码到 ${APP_DIR}"
        print_info "使用 scp 或 rsync 上传后端代码"
        return 1
    fi
}

create_service() {
    print_info "创建 systemd 服务..."
    
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Tvtxiu API Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/${APP_NAME}
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/app.log
StandardError=append:${LOG_DIR}/error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${APP_NAME}
    
    print_success "服务创建完成"
}

setup_logrotate() {
    print_info "配置日志轮动..."
    
    cat > "/etc/logrotate.d/tvtxiu" << EOF
${LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        systemctl reload ${APP_NAME} > /dev/null 2>&1 || true
    endscript
}
EOF

    print_success "日志轮动配置完成 (保留7天)"
}

#######################################
# 管理函数
#######################################

start_service() {
    systemctl start ${APP_NAME}
    print_success "服务已启动"
}

stop_service() {
    systemctl stop ${APP_NAME}
    print_success "服务已停止"
}

restart_service() {
    systemctl restart ${APP_NAME}
    print_success "服务已重启"
}

show_status() {
    echo ""
    echo "========== 服务状态 =========="
    systemctl status ${APP_NAME} --no-pager || true
    echo ""
    echo "========== 资源使用 =========="
    echo "内存: $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
    echo "磁盘: $(df -h ${APP_DIR} | awk 'NR==2{print $3 "/" $2}')"
    echo ""
}

show_logs() {
    tail -f "${LOG_DIR}/app.log"
}

show_error_logs() {
    tail -f "${LOG_DIR}/error.log"
}

update_application() {
    print_info "更新应用..."
    
    stop_service 2>/dev/null || true
    
    cd "${APP_DIR}"
    export PATH=$PATH:/usr/local/go/bin
    go build -o ${APP_NAME} .
    
    start_service
    print_success "应用更新完成"
}

backup_database() {
    BACKUP_FILE="${DATA_DIR}/backup_$(date +%Y%m%d_%H%M%S).sql"
    sudo -u postgres pg_dump ${DB_NAME} > "${BACKUP_FILE}"
    gzip "${BACKUP_FILE}"
    print_success "数据库备份完成: ${BACKUP_FILE}.gz"
}

restore_database() {
    BACKUP_FILE=$1
    
    if [ -z "$BACKUP_FILE" ]; then
        # 列出所有备份文件
        echo ""
        echo "========== 可用备份文件 =========="
        ls -la ${DATA_DIR}/backup_*.sql.gz 2>/dev/null || print_warning "没有找到备份文件"
        echo ""
        print_error "请指定备份文件: $0 restore <备份文件路径>"
        exit 1
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "备份文件不存在: $BACKUP_FILE"
        exit 1
    fi
    
    print_warning "即将恢复数据库，这将覆盖当前数据！"
    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "取消恢复"
        exit 0
    fi
    
    print_info "恢复数据库..."
    
    # 解压缩备份文件
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        gunzip -c "$BACKUP_FILE" | sudo -u postgres psql ${DB_NAME}
    else
        sudo -u postgres psql ${DB_NAME} < "$BACKUP_FILE"
    fi
    
    print_success "数据库恢复完成"
}

show_config() {
    echo ""
    echo "========== 配置信息 =========="
    echo "应用目录: ${APP_DIR}"
    echo "数据目录: ${DATA_DIR}"
    echo "日志目录: ${LOG_DIR}"
    echo "服务端口: ${PORT}"
    echo ""
    if [ -f "${APP_DIR}/.env" ]; then
        echo "环境配置:"
        cat "${APP_DIR}/.env"
    fi
    echo ""
}

uninstall() {
    print_warning "即将卸载 Tvtxiu API..."
    read -p "确定要卸载吗？(输入 'yes' 确认): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "取消卸载"
        exit 0
    fi
    
    systemctl stop ${APP_NAME} 2>/dev/null || true
    systemctl disable ${APP_NAME} 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
    
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
    sudo -u postgres psql -c "DROP USER IF EXISTS ${DB_USER};" 2>/dev/null || true
    
    rm -rf "${APP_DIR}"
    rm -rf "${LOG_DIR}"
    
    print_success "卸载完成"
    print_warning "数据目录 ${DATA_DIR} 已保留，如需删除请手动执行: rm -rf ${DATA_DIR}"
}

#######################################
# SSL 证书相关函数
#######################################

install_ssl_dependencies() {
    local email=$1
    if [ -z "$email" ]; then
        email="admin@example.com"
    fi

    print_info "安装 SSL 相关依赖..."
    
    # 安装 Nginx
    apt-get update -qq
    apt-get install -y -qq nginx socat
    
    # 安装 acme.sh
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        print_info "安装 acme.sh (使用邮箱: ${email})..."
        curl -s https://get.acme.sh | sh -s email="${email}"
    fi
    
    print_success "SSL 依赖安装完成"
}

setup_ssl() {
    DOMAIN=$1
    EMAIL=$2
    
    if [ -z "$DOMAIN" ]; then
        print_error "请指定域名: $0 ssl <域名> [邮箱]"
        exit 1
    fi
    
    # 如果未提供邮箱，提示用户输入
    if [ -z "$EMAIL" ]; then
        read -p "请输入联系邮箱 (用于证书提醒): " EMAIL
    fi
    
    # 清理邮箱变量（去除前后空格）
    EMAIL=$(echo "$EMAIL" | xargs)
    
    if [ -z "$EMAIL" ]; then
        print_error "邮箱不能为空"
        exit 1
    fi
    
    print_header
    print_info "配置 SSL 证书: ${DOMAIN}"
    print_info "联系邮箱: [${EMAIL}]"
    echo ""
    
    check_root "ssl"
    
    # 安装依赖 (传入邮箱)
    install_ssl_dependencies "${EMAIL}"
    
    # 停止 Nginx 以释放 80 端口
    systemctl stop nginx 2>/dev/null || true
    
    # 强制清理旧的 account.conf 能够解决之前的配置残留问题
    if [ -f ~/.acme.sh/account.conf ]; then
        sed -i "/ACCOUNT_EMAIL/d" ~/.acme.sh/account.conf
    fi
    
    # 注册/更新 acme.sh 账号邮箱
    print_info "注册 Let's Encrypt 账号..."
    ~/.acme.sh/acme.sh --register-account -m "${EMAIL}" --server letsencrypt
    
    # 使用 acme.sh 申请证书 (standalone 模式)
    print_info "申请 Let's Encrypt 证书..."
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    
    # 检查证书是否已存在
    if [ -f ~/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]; then
        print_info "证书已存在，跳过申请步骤"
    else
        ~/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone --keylength ec-256 --server letsencrypt || {
            print_error "证书申请失败，请检查："
            echo "  1. 域名 ${DOMAIN} 是否已正确解析到此服务器 IP"
            echo "  2. 80 端口是否开放"
            exit 1
        }
    fi
    
    # 创建证书目录
    SSL_DIR="/etc/nginx/ssl/${DOMAIN}"
    mkdir -p "${SSL_DIR}"
    
    # 安装证书
    print_info "安装证书..."
    ~/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" --ecc \
        --key-file "${SSL_DIR}/key.pem" \
        --fullchain-file "${SSL_DIR}/cert.pem" \
        --reloadcmd "systemctl reload nginx" || true
    
    # 配置 Nginx
    print_info "配置 Nginx..."
    cat > "/etc/nginx/sites-available/${DOMAIN}" << EOF
# HTTP -> HTTPS 重定向
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

# HTTPS
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL 证书
    ssl_certificate ${SSL_DIR}/cert.pem;
    ssl_certificate_key ${SSL_DIR}/key.pem;
    
    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 上传文件大小限制
    client_max_body_size 50M;
    
    # 反向代理到后端
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # 静态文件（上传的头像等）
    location /uploads {
        alias ${DATA_DIR}/uploads;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # 启用站点
    ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/"
    
    # 删除默认站点
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试 Nginx 配置
    nginx -t || {
        print_error "Nginx 配置错误"
        exit 1
    }
    
    # 启动 Nginx
    systemctl start nginx
    systemctl enable nginx
    
    # 配置防火墙 (如果有 ufw)
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        print_info "防火墙已开放 80/443 端口"
    fi
    
    echo ""
    print_success "SSL 配置完成！"
    echo ""
    echo "========== 配置信息 =========="
    echo "域名: https://${DOMAIN}"
    echo "证书: ${SSL_DIR}/cert.pem"
    echo "证书有效期: 90天 (自动续签)"
    echo ""
    echo "API 地址已变更为: https://${DOMAIN}"
    echo "请在 App 设置中更新服务器地址"
    echo ""
}

renew_ssl() {
    print_info "手动续签所有证书..."
    ~/.acme.sh/acme.sh --renew-all --ecc
    print_success "证书续签完成"
}

show_ssl_status() {
    echo ""
    echo "========== SSL 证书状态 =========="
    if [ -f ~/.acme.sh/acme.sh ]; then
        ~/.acme.sh/acme.sh --list
    else
        print_warning "acme.sh 未安装"
    fi
    echo ""
    echo "========== Nginx 状态 =========="
    systemctl status nginx --no-pager || true
    echo ""
}

#######################################
# 完整安装流程
#######################################

full_install() {
    print_header
    print_info "开始完整安装..."
    echo ""
    
    check_root "install"
    
    install_dependencies
    setup_swap
    setup_directories
    setup_database
    
    echo ""
    print_warning "请上传后端代码到 ${APP_DIR}"
    echo ""
    echo "使用以下命令上传代码:"
    echo "  scp -r /path/to/tvtxiu-api/* root@YOUR_VPS_IP:${APP_DIR}/"
    echo ""
    echo "上传完成后，运行以下命令完成部署:"
    echo "  $0 deploy"
    echo ""
    
    # 保存数据库密码
    echo "DB_PASSWORD=${DB_PASSWORD}" > "${DATA_DIR}/.db_credentials"
    chmod 600 "${DATA_DIR}/.db_credentials"
    
    print_success "基础安装完成！"
    echo ""
    echo "数据库密码已保存到: ${DATA_DIR}/.db_credentials"
}

deploy() {
    print_header
    check_root "deploy"
    
    # 读取数据库密码
    if [ -f "${DATA_DIR}/.db_credentials" ]; then
        source "${DATA_DIR}/.db_credentials"
    else
        print_error "找不到数据库凭据，请先运行: $0 install"
        exit 1
    fi
    
    deploy_application
    create_service
    setup_logrotate
    start_service
    
    echo ""
    print_success "部署完成！"
    echo ""
    echo "API 地址: http://YOUR_VPS_IP:${PORT}"
    echo "默认管理员: admin / admin"
    echo ""
    echo "管理命令:"
    echo "  $0 status   - 查看状态"
    echo "  $0 logs     - 查看日志"
    echo "  $0 restart  - 重启服务"
}

#######################################
# 主入口
#######################################

show_help() {
    print_header
    echo "用法: $0 <命令>"
    echo ""
    echo "安装命令:"
    echo "  install     完整安装 (依赖 + 数据库 + Swap)"
    echo "  deploy      部署应用 (构建 + 启动服务)"
    echo "  update      更新应用 (重新构建并重启)"
    echo "  uninstall   卸载应用"
    echo ""
    echo "管理命令:"
    echo "  start       启动服务"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看状态"
    echo "  logs        查看日志"
    echo "  errors      查看错误日志"
    echo "  config      查看配置"
    echo ""
    echo "数据库命令:"
    echo "  backup               备份数据库"
    echo "  restore <备份文件>   恢复数据库"
    echo ""
    echo "SSL 命令:"
    echo "  ssl <域名> [邮箱]  申请证书并配置 HTTPS"
    echo "  ssl-renew          手动续签证书"
    echo "  ssl-status         查看证书状态"
    echo ""
}

case "$1" in
    install)
        full_install
        ;;
    deploy)
        deploy
        ;;
    update)
        check_root "update"
        update_application
        ;;
    start)
        check_root "start"
        start_service
        ;;
    stop)
        check_root "stop"
        stop_service
        ;;
    restart)
        check_root "restart"
        restart_service
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    errors)
        show_error_logs
        ;;
    config)
        show_config
        ;;
    backup)
        check_root "backup"
        backup_database
        ;;
    restore)
        check_root "restore"
        restore_database "$2"
        ;;
    uninstall)
        check_root "uninstall"
        uninstall
        ;;
    ssl)
        setup_ssl "$2" "$3"
        ;;
    ssl-renew)
        check_root "ssl-renew"
        renew_ssl
        ;;
    ssl-status)
        show_ssl_status
        ;;
    *)
        show_help
        ;;
esac
