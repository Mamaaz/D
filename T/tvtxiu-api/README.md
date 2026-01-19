# Tvtxiu API

婚纱影楼后期管理系统后端 API

## 🚀 快速启动

### VPS 一键部署（推荐）

```bash
# 1. 上传代码到 VPS
scp -r tvtxiu-api/* root@YOUR_VPS_IP:/opt/tvtxiu/

# 2. SSH 登录 VPS
ssh root@YOUR_VPS_IP

# 3. 安装依赖
cd /opt/tvtxiu
chmod +x install.sh
./install.sh install

# 4. 部署应用
./install.sh deploy
```

### 管理命令

```bash
./install.sh status    # 查看状态
./install.sh logs      # 查看日志
./install.sh errors    # 查看错误日志
./install.sh restart   # 重启服务
./install.sh backup    # 备份数据库
./install.sh update    # 代码更新后重新部署
./install.sh uninstall # 卸载
```

### 本地开发

```bash
# 启动数据库
docker-compose up -d db

# 运行 API
go run .
```

API 运行在 `http://localhost:8080`

---

## 🔐 默认账号

| 用户名 | 密码 | 角色 |
|--------|------|------|
| admin | admin | 主管理员 |

---

## 📡 API 端点

### 认证
```
POST /api/auth/login     登录
GET  /api/auth/me        获取当前用户
```

### 用户管理（管理员）
```
GET    /api/users            用户列表
GET    /api/users/:id        获取用户
POST   /api/users            创建用户
PUT    /api/users/:id        更新用户
DELETE /api/users/:id        删除用户
POST   /api/users/:id/avatar 上传头像
```

### 订单管理
```
GET    /api/orders              订单列表
GET    /api/orders/:id          获取订单
POST   /api/orders              创建订单
PUT    /api/orders/:id          更新订单
DELETE /api/orders/:id          删除订单
POST   /api/orders/:id/complete 标记完成
POST   /api/orders/:id/archive  归档
POST   /api/orders/:id/unarchive 取消归档
```

### 拍摄统计（管理员）
```
GET    /api/shooting/orders          拍摄订单列表（支持筛选、分页）
PUT    /api/shooting/orders/:id      更新拍摄订单（同步后期分配）
GET    /api/shooting/orders/export   导出 CSV
POST   /api/shooting/sync-matches    批量同步匹配
GET    /api/shooting/stats           获取统计数据
POST   /api/shooting/excel           上传 Excel 导入拍摄订单
```

**查询参数：**
| 参数 | 说明 | 示例 |
|------|------|------|
| `year` | 年份 | `2026` |
| `matched` | 匹配状态 | `true` / `false` |
| `completed` | 完成状态 | `true` |
| `search` | 模糊搜索 | `订单号/地点/摄影师` |
| `sort` | 排序 | `asc` / `desc` |
| `limit` | 分页数量 | `20` |
| `offset` | 偏移量 | `0` |

### 数据导入/导出（管理员）
```
POST   /api/import/excel       Excel 导入
POST   /api/import/migration   JSON 迁移导入
DELETE /api/data/delete-all    删除所有订单
```

---

## 📊 Excel 导入格式

后期表格式（腾讯文档）：

| 列 | 字段 |
|----|------|
| A | 后期（负责人） |
| B | 订单编号（必填） |
| C | 拍摄时间 |
| D | 拍摄地点 |
| E | 顾问 |
| F | 张数 |
| G | 分配时间 |
| H | 试修交付时间 |
| I | 结片时间 |
| J | 是否交付精修 |
| K | 投诉原因 |

> 第一行是公告，第二行是表头，从第三行开始解析

**导入特性：**
- ✅ 自动创建不存在的用户（默认密码：123456）
- ✅ 自动跳过重复订单号
- ✅ 返回详细导入结果

---

## ⏰ 定时任务

### 自动清理归档订单

- **执行时间**：每天凌晨 3:00
- **清理规则**：删除归档超过 12 个月的订单
- **配置位置**：`scheduler/scheduler.go`

```go
const ArchiveRetentionMonths = 12  // 修改此值调整保留时长
```

---

## 📁 项目结构

```
tvtxiu-api/
├── main.go           # 入口
├── config/           # 配置管理
├── database/         # 数据库连接
├── handlers/         # 请求处理器
├── middleware/       # 中间件（认证、权限）
├── models/           # 数据模型
├── scheduler/        # 定时任务
├── uploads/          # 上传文件目录
├── install.sh        # 一键部署脚本
└── docker-compose.yml
```

---

## ⚙️ 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DATABASE_URL` | PostgreSQL 连接字符串 | - |
| `JWT_SECRET` | JWT 签名密钥 | - |
| `PORT` | 服务端口 | 8080 |

---

## 🔧 系统要求

### VPS 最低配置
| 配置 | 要求 |
|------|------|
| 内存 | 1 GB |
| CPU | 1 核 |
| 硬盘 | 10 GB |
| 系统 | Debian 12 / Ubuntu 22.04+ |

### 安装脚本功能
- ✅ 自动安装 Go 1.22
- ✅ 自动安装 PostgreSQL
- ✅ 自动配置 2GB Swap
- ✅ 自动创建 systemd 服务
- ✅ 自动配置日志轮动（保留 7 天）

---

## 📝 更新日志

### v1.1.0 (2026-01-19)
- ✅ 拍摄统计页面（可点击筛选）
- ✅ 拍摄订单编辑（同步后期分配）
- ✅ 批量同步匹配功能
- ✅ 订单创建/更新自动同步拍摄订单
- ✅ 已完成/已分配/待分配筛选
- ✅ 导出 CSV 功能
- ✅ 分页加载优化

### v1.0.0 (2026-01-14)
- ✅ 用户认证与 JWT
- ✅ 用户 CRUD + 头像上传
- ✅ 订单 CRUD + 归档管理
- ✅ Excel 批量导入
- ✅ JSON 迁移导入/导出
- ✅ 删除所有数据功能
- ✅ 归档订单自动清理
- ✅ VPS 一键部署脚本
- ✅ 日志轮动配置

---

## 📄 许可证

MIT License

