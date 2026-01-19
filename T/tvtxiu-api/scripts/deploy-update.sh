#!/bin/bash

# ============================================
# Tvtxiu API 一键更新脚本 (交互式)
# 双击运行，按提示输入 VPS 信息即可完成更新
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_DIR="$(dirname "$SCRIPT_DIR")"
VPS_PATH="/opt/tvtxiu"

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Tvtxiu API 一键更新部署工具 v2.0                 ║"
echo "║                                                            ║"
echo "║  功能：自动备份 → 上传代码 → 编译 → 重启 → 索引优化        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ============================================
# 交互式输入 VPS 信息
# ============================================

# 读取上次保存的配置
CONFIG_FILE="$SCRIPT_DIR/.deploy_config"
SAVED_IP=""
SAVED_USER="root"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    SAVED_IP="$VPS_IP"
    SAVED_USER="$VPS_USER"
fi

# 输入 VPS IP
echo -e "${BLUE}[1/3] 请输入 VPS IP 地址${NC}"
if [ -n "$SAVED_IP" ]; then
    echo -e "      上次使用: ${GREEN}$SAVED_IP${NC}"
    read -p "      IP 地址 (直接回车使用上次): " INPUT_IP
    VPS_IP="${INPUT_IP:-$SAVED_IP}"
else
    read -p "      IP 地址: " VPS_IP
fi

if [ -z "$VPS_IP" ]; then
    echo -e "${RED}错误: VPS IP 不能为空${NC}"
    exit 1
fi

# 输入用户名
echo ""
echo -e "${BLUE}[2/3] 请输入 SSH 用户名${NC}"
read -p "      用户名 (默认 $SAVED_USER): " INPUT_USER
VPS_USER="${INPUT_USER:-$SAVED_USER}"

# 测试 SSH 连接
echo ""
echo -e "${BLUE}[3/3] 测试 SSH 连接...${NC}"
echo -e "      连接到 ${CYAN}$VPS_USER@$VPS_IP${NC}"
echo -e "      ${YELLOW}(如果需要输入密码，请输入 VPS 密码)${NC}"
echo ""

# 尝试连接（允许交互式密码输入）
if ! ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "$VPS_USER@$VPS_IP" "echo '✓ SSH 连接成功'"; then
    echo ""
    echo -e "${RED}连接失败！请检查:${NC}"
    echo -e "  1. VPS IP 是否正确: $VPS_IP"
    echo -e "  2. 用户名是否正确: $VPS_USER"
    echo -e "  3. 密码是否正确"
    echo -e "  4. VPS 是否开启 SSH 服务"
    echo ""
    echo "按任意键退出..."
    read -n 1
    exit 1
fi

# 保存配置供下次使用
echo "VPS_IP=\"$VPS_IP\"" > "$CONFIG_FILE"
echo "VPS_USER=\"$VPS_USER\"" >> "$CONFIG_FILE"

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}开始部署更新...${NC}"
echo -e "${YELLOW}================================================${NC}"
echo ""

# ============================================
# Step 1: 本地交叉编译 Linux 版本
# ============================================
echo -e "${BLUE}[Step 1/6] 本地交叉编译 Linux 版本...${NC}"
cd "$API_DIR"

# 交叉编译为 Linux amd64 版本
if GOOS=linux GOARCH=amd64 go build -o tvtxiu-api-linux . 2>&1; then
    echo -e "${GREEN}✓ 本地编译成功 (Linux amd64)${NC}"
else
    echo -e "${RED}✗ 本地编译失败，请先修复错误${NC}"
    echo "按任意键退出..."
    read -n 1
    exit 1
fi
echo ""

# ============================================
# Step 2: VPS 上备份数据
# ============================================
echo -e "${BLUE}[Step 2/6] 在 VPS 上备份数据...${NC}"

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_RESULT=$(ssh "$VPS_USER@$VPS_IP" "
cd $VPS_PATH

# 创建备份目录
mkdir -p backups

# 备份二进制文件
if [ -f tvtxiu-api ]; then
    cp tvtxiu-api backups/tvtxiu-api.$BACKUP_DATE
    echo 'binary_backed_up'
fi

# 备份数据库
if command -v docker &> /dev/null && docker ps | grep -q postgres; then
    docker exec \$(docker ps -qf 'ancestor=postgres' | head -1) pg_dump -U postgres tvtxiu > backups/db_backup_$BACKUP_DATE.sql 2>/dev/null
    if [ \$? -eq 0 ]; then
        echo 'database_backed_up'
    fi
elif command -v pg_dump &> /dev/null; then
    PGPASSWORD=postgres pg_dump -h localhost -U postgres tvtxiu > backups/db_backup_$BACKUP_DATE.sql 2>/dev/null
    if [ \$? -eq 0 ]; then
        echo 'database_backed_up'
    fi
fi

# 清理30天前的备份
find backups -name '*.sql' -mtime +30 -delete 2>/dev/null
find backups -name 'tvtxiu-api.*' -mtime +30 -delete 2>/dev/null

echo 'backup_complete'
")

if echo "$BACKUP_RESULT" | grep -q "binary_backed_up"; then
    echo -e "${GREEN}✓ 二进制文件已备份${NC}"
fi
if echo "$BACKUP_RESULT" | grep -q "database_backed_up"; then
    echo -e "${GREEN}✓ 数据库已备份${NC}"
fi
echo -e "${GREEN}✓ 备份位置: $VPS_PATH/backups/${NC}"
echo ""

# ============================================
# Step 3: 上传编译好的二进制文件和配置
# ============================================
echo -e "${BLUE}[Step 3/6] 上传更新文件...${NC}"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; rm -f $API_DIR/tvtxiu-api-linux" EXIT

# 复制编译好的二进制文件（重命名为 tvtxiu-api）
cp "$API_DIR/tvtxiu-api-linux" "$TEMP_DIR/tvtxiu-api"

# 复制需要更新的配置文件
[ -d migrations/ ] && cp -r migrations/ "$TEMP_DIR/"

# 上传文件
scp -r "$TEMP_DIR/"* "$VPS_USER@$VPS_IP:$VPS_PATH/" > /dev/null 2>&1

echo -e "${GREEN}✓ 二进制文件和配置上传完成${NC}"
echo ""

# ============================================
# Step 4: 重启服务
# ============================================
echo -e "${BLUE}[Step 4/6] 重启服务...${NC}"

RESTART_RESULT=$(ssh "$VPS_USER@$VPS_IP" "
cd $VPS_PATH

# 停止旧服务
pkill -f 'tvtxiu-api' 2>/dev/null || true
sleep 2

# 确保新文件有执行权限
chmod +x tvtxiu-api

# 启动新服务
nohup ./tvtxiu-api > api.log 2>&1 &
sleep 3

# 检查是否启动成功
if pgrep -f 'tvtxiu-api' > /dev/null; then
    echo 'service_running'
    # 测试 API
    if curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/auth/login -X POST -H 'Content-Type: application/json' -d '{\"username\":\"test\",\"password\":\"test\"}' | grep -q '401\|200'; then
        echo 'api_responding'
    fi
else
    echo 'service_failed'
    tail -10 api.log
fi
")

if echo "$RESTART_RESULT" | grep -q "service_running"; then
    echo -e "${GREEN}✓ 服务已启动${NC}"
else
    echo -e "${RED}✗ 服务启动失败${NC}"
    echo "$RESTART_RESULT"
    echo "按任意键退出..."
    read -n 1
    exit 1
fi

if echo "$RESTART_RESULT" | grep -q "api_responding"; then
    echo -e "${GREEN}✓ API 响应正常${NC}"
fi
echo ""

# ============================================
# Step 5: 数据库索引优化
# ============================================
echo -e "${BLUE}[Step 5/6] 执行数据库索引优化...${NC}"

if [ -f "$API_DIR/migrations/add_indexes.sql" ]; then
    INDEX_RESULT=$(ssh "$VPS_USER@$VPS_IP" "
cd $VPS_PATH
if [ -f migrations/add_indexes.sql ]; then
    if command -v docker &> /dev/null && docker ps | grep -q postgres; then
        docker exec -i \$(docker ps -qf 'ancestor=postgres' | head -1) psql -U postgres -d tvtxiu < migrations/add_indexes.sql 2>&1
        echo 'index_done_docker'
    elif command -v psql &> /dev/null; then
        PGPASSWORD=postgres psql -h localhost -U postgres -d tvtxiu -f migrations/add_indexes.sql 2>&1
        echo 'index_done_local'
    else
        echo 'index_skipped'
    fi
else
    echo 'index_file_missing'
fi
")

    if echo "$INDEX_RESULT" | grep -q "index_done"; then
        echo -e "${GREEN}✓ 索引优化完成${NC}"
    else
        echo -e "${YELLOW}⚠ 索引优化跳过（手动执行: psql -f migrations/add_indexes.sql）${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 未找到索引脚本${NC}"
fi

# ============================================
# 完成
# ============================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    ✅ 更新部署完成！                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "服务器: ${CYAN}$VPS_USER@$VPS_IP${NC}"
echo -e "API 地址: ${CYAN}http://$VPS_IP:8080${NC}"
echo ""
echo -e "常用命令:"
echo -e "  查看日志: ${YELLOW}ssh $VPS_USER@$VPS_IP 'tail -f $VPS_PATH/api.log'${NC}"
echo -e "  重启服务: ${YELLOW}ssh $VPS_USER@$VPS_IP 'cd $VPS_PATH && pkill tvtxiu-api; nohup ./tvtxiu-api &'${NC}"
echo ""

# macOS 下显示通知
if command -v osascript &> /dev/null; then
    osascript -e 'display notification "API 已成功更新到 VPS" with title "Tvtxiu 部署完成" sound name "Glass"'
fi

echo "按任意键退出..."
read -n 1
