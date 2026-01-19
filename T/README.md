# Tvtxiu 婚纱影楼后期管理系统

<p align="center">
  <img src="Tvtxiu/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Tvtxiu Logo">
</p>

<p align="center">
  <strong>专为婚纱影楼后期部门设计的订单管理和绩效统计系统</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20iOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/Backend-Go%20%7C%20PostgreSQL-00ADD8" alt="Backend">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## ✨ 功能特性

### 📋 订单管理
- **微信消息解析** - 一键从群消息解析订单信息（18个字段）
- **订单分配** - 管理员分配订单给后期人员
- **状态追踪** - 待完成/已完成 Tab 切换
- **日期识别** - 智能解析多种日期格式（`25/9/6-7`、`250906-07`）

### 🏷️ 订单标签
| 标签 | 说明 | 绩效影响 |
|------|------|----------|
| 婚纱/婚礼 | 拍摄类型 | 婚礼 ×0.8 |
| 进群 | 客户已进群 | +2 元/张 |
| 加急 | 橙色高亮 | +5 元/张 |
| 投诉 | 深红色高亮 | +8 元/张 |

### 📅 日历视图
- 月历展示待交付订单
- 按交付日期分组
- 点击查看当日订单详情

### 📊 绩效统计
- 人员完成张数排行榜
- 月度趋势图表
- 单张成本计算
- 投诉/加急统计

### 👥 权限控制
| 角色 | 权限 |
|------|------|
| 主管理员 | 全部功能 + 人员绩效配置 |
| 副管理员 | 录入、分配、编辑订单 |
| 后期人员 | 查看自己订单、标记完成 |

### 📦 数据管理
- **Excel 导入** - 从腾讯文档批量导入拍摄订单
- **JSON 导出/导入** - 数据备份与迁移
- **自动清理** - 每天凌晨自动删除 12 个月前的归档订单

---

## 📥 拍摄订单导入流程

### 工作流程

```
腾讯文档 → 导出 Excel → App 上传 → 自动解析/合并 → 数据库存储
     ↓                                        ↓
   多年份 Sheet                      同一订单多日拍摄合并
```

### 操作步骤

1. **导出 Excel**：从腾讯文档导出 `.xlsx` 文件
2. **打开 App**：设置 → 拍摄订单导入
3. **选择年份**：勾选要导入的年份（支持多选）
4. **上传文件**：点击"选择 Excel 文件上传"
5. **查看结果**：显示新增/更新/跳过数量

### 智能合并规则

同一订单号的多行会自动合并：

```
原始 Excel:
CS01320240809A | 1月 | 6日  | 上海      | 璟仁
CS01320240809A | 1月 | 15日 | 云南大理  | 蛙蛙

合并后:
CS01320240809A | 1月 | 6+15日 | 上海+云南大理 | 璟仁+蛙蛙
               连续日期用-   不连续用+    人员合并
```

### 支持的表格格式

| 列名 | 必填 | 说明 |
|------|------|------|
| 订单编号 | ✓ | CS/FG/FE 开头 |
| 拍月 | ✓ | 数字 |
| 拍日 | ✓ | 数字或范围 |
| 实时地点 | ✓ | 拍摄地点 |
| 实时国家 | | 国家/地区 |
| 拍摄类型 | | 纱/礼/商业 |
| 销售 | | 销售人员 |
| p/摄影 | | 摄影师 |
| 修图师 | | 后期人员 |

> ⚠️ 系统会自动识别表头行（查找包含"订单编号"的行）

## 🛠 技术栈

| 组件 | 技术 |
|------|------|
| 客户端 | SwiftUI (macOS/iOS) |
| 后端 | Go + Gin |
| 数据库 | PostgreSQL |
| 项目生成 | XcodeGen |

---

## 📂 项目结构

```
Tvtxiu/
├── project.yml              # XcodeGen 配置
├── Tvtxiu/                   # 客户端代码
│   ├── App/                  # 应用入口
│   ├── Models/               # 数据模型
│   ├── Services/             # 服务层
│   └── Views/                # UI 视图
└── tvtxiu-api/               # 后端 API
    ├── handlers/             # 请求处理
    ├── models/               # 数据模型
    ├── middleware/           # 中间件
    ├── database/             # 数据库连接
    ├── scheduler/            # 定时任务
    └── install.sh            # VPS 一键部署脚本
```

---

## 🚀 快速开始

### 客户端开发

```bash
# 1. 安装 XcodeGen
brew install xcodegen

# 2. 生成 Xcode 项目
cd Tvtxiu
xcodegen generate

# 3. 打开并运行
open Tvtxiu.xcodeproj
# 选择 Scheme: Tvtxiu-macOS，Cmd+R 运行
```

### 后端开发（本地）

```bash
cd tvtxiu-api

# 使用 Docker Compose 启动数据库
docker-compose up -d db

# 运行 API
go run .
```

API 运行在 `http://localhost:8080`

### VPS 部署

```bash
# 1. 上传代码到 VPS
scp -r tvtxiu-api/* root@YOUR_VPS_IP:/opt/tvtxiu/

# 2. SSH 登录 VPS
ssh root@YOUR_VPS_IP

# 3. 一键安装
cd /opt/tvtxiu
chmod +x install.sh
./install.sh install   # 安装依赖
./install.sh deploy    # 部署应用
```

**管理命令：**
```bash
./install.sh status    # 查看状态
./install.sh logs      # 查看日志
./install.sh restart   # 重启服务
./install.sh backup    # 备份数据库
./install.sh update    # 代码更新后重新部署
```

---

## 🔐 默认账号

| 用户名 | 密码 | 角色 |
|--------|------|------|
| admin | admin | 主管理员 |

> ⚠️ 首次登录后请修改默认密码

---

## 📡 API 端点

### 认证
| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/auth/login` | 登录 |
| GET | `/api/auth/me` | 获取当前用户 |

### 用户管理（管理员）
| 方法 | 端点 | 说明 |
|------|------|------|
| GET | `/api/users` | 用户列表 |
| POST | `/api/users` | 创建用户 |
| PUT | `/api/users/:id` | 更新用户 |
| DELETE | `/api/users/:id` | 删除用户 |
| POST | `/api/users/:id/avatar` | 上传头像 |

### 订单管理
| 方法 | 端点 | 说明 |
|------|------|------|
| GET | `/api/orders` | 订单列表 |
| POST | `/api/orders` | 创建订单 |
| PUT | `/api/orders/:id` | 更新订单 |
| DELETE | `/api/orders/:id` | 删除订单 |
| POST | `/api/orders/:id/complete` | 标记完成 |
| POST | `/api/orders/:id/archive` | 归档 |
| POST | `/api/orders/:id/unarchive` | 取消归档 |

### 数据导入/导出（管理员）
| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/import/excel` | Excel 导入（后期订单） |
| POST | `/api/import/migration` | JSON 迁移导入 |
| DELETE | `/api/data/delete-all` | 删除所有订单 |

### 拍摄订单同步（管理员）
| 方法 | 端点 | 说明 |
|------|------|------|
| POST | `/api/sync/upload?years=2025,2026` | 上传 Excel 拍摄订单 |
| GET | `/api/sync/status` | 获取同步状态 |
| GET | `/api/shooting/orders?year=2025` | 查询拍摄订单列表 |
| GET | `/api/shooting/stats?year=2025` | 拍摄订单统计 |

---

## 📊 绩效计算公式

```
单张绩效 = (基础绩效 + 加项) × 类型系数

基础绩效（按职级）：
- 初级: 6 元/张
- 中级: 8 元/张
- 高级: 10 元/张
- 外援: 15 元/张

加项规则：
- 进群: +2（有加急/投诉时失效）
- 加急: +5（有投诉时失效）
- 投诉: +8

类型系数：
- 婚纱: ×1.0
- 婚礼: ×0.8

单张成本 = (工资社保 + 修图绩效) ÷ 完成张数
```

---

## ⚙️ 系统配置

### VPS 最低要求
| 配置 | 要求 |
|------|------|
| 内存 | 1 GB |
| CPU | 1 核 |
| 硬盘 | 10 GB |
| 系统 | Debian 12 / Ubuntu 22.04+ |

### 自动清理规则
- **执行时间**：每天凌晨 3:00
- **清理条件**：归档超过 12 个月的订单
- **配置位置**：`scheduler/scheduler.go`

---

## 📝 更新日志

### v1.3.0 (2026-01-18)
- ✅ **拍摄订单导入**
  - 支持腾讯文档 Excel 上传
  - 智能识别表头行
  - 自动合并多日/多地订单
  - 日期连续用 `-`，不连续用 `+`
  - 人员、地点自动去重合并
- ✅ **数据清洗**
  - 按订单编号去重
  - 支持多 Sheet 年份筛选
- ✅ **新 API 端点**
  - `POST /api/sync/upload` 上传拍摄订单

### v1.2.0 (2026-01-16)
- ✅ **AI 智能解析**
  - 集成 OpenAI 兼容 API（支持 OpenRouter）
  - AI 自动解析微信订单消息为结构化数据
  - 支持动态模型选择和浏览
  - API Key 使用 Keychain 安全存储
- ✅ **统计 API 扩展**
  - 新增 `/api/stats/overview` 部门概览接口
  - 新增 `/api/stats/department/:name` 部门详情接口
  - 新增 `/api/stats/staff-ranking` 人员排行接口
  - 新增 `/api/stats/alerts` 延迟预警接口
- ✅ **Boss 角色**
  - 新增 `boss` 用户角色
  - 支持 TvTBoss 老板监控 App 数据对接
- ✅ **Mac App 公证**
  - 支持 Developer ID 签名
  - Apple Notarization 公证分发

### v1.1.0 (2026-01-15)
- ✅ **工作台优化**
  - 删除快捷操作区域
  - 卡片可点击弹窗显示订单列表
  - 年度趋势图（13个月，当前月居中）
  - 近期到期提醒列表
  - 人名使用自定义颜色显示
  - 日期显示中文格式（2025年9月7日）
- ✅ **用户名称简化**
  - 统一为一个名称字段（名称 = 登录名 = 显示名）
  - 编辑界面只保留"名称"字段
  - 后端支持更新用户名并检查唯一性
- 🔒 **安全优化**
  - API Key 使用 Keychain 安全存储
  - 移除代码中的重复 `convertAPIUser` 函数

### v1.0.0 (2026-01-14)
- ✅ 客户端 macOS/iOS 全功能实现
- ✅ Go 后端 API 完成
- ✅ 用户认证与权限控制
- ✅ 订单 CRUD 与状态管理
- ✅ Excel 批量导入
- ✅ JSON 数据迁移
- ✅ 绩效统计与计算
- ✅ VPS 一键部署脚本
- ✅ 归档订单自动清理

---

## 🔗 关联项目

| 项目 | 说明 |
|------|------|
| [TvTBoss](../TvTBoss) | 老板数据监控 App（iOS） |

---

## 📄 许可证

MIT License

---

## 👤 联系方式

如有问题或建议，请联系项目负责人。
