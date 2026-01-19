package handlers

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"tvtxiu-api/database"
	"tvtxiu-api/middleware"
	"tvtxiu-api/models"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/xuri/excelize/v2"
)

// ImportExcel 从 Excel 导入订单
func ImportExcel(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请上传文件"})
		return
	}

	src, err := file.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "打开文件失败"})
		return
	}
	defer src.Close()

	f, err := excelize.OpenReader(src)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "解析 Excel 失败"})
		return
	}
	defer f.Close()

	// 获取第一个工作表
	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Excel 没有工作表"})
		return
	}

	rows, err := f.GetRows(sheets[0])
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "读取工作表失败"})
		return
	}

	userID, _ := middleware.GetCurrentUserID(c)

	var imported, failed, skipped, usersCreated int
	var errors []string

	// 跳过前两行（第一行是公告，第二行是表头）
	for i, row := range rows {
		if i <= 1 {
			continue // 跳过公告和表头
		}
		if len(row) < 5 {
			continue // 跳过不完整的行
		}

		order, staffName, err := parseExcelRowWithStaff(row)
		if err != nil {
			failed++
			errors = append(errors, fmt.Sprintf("行 %d: %s", i+1, err.Error()))
			continue
		}

		// 检查订单号是否已存在
		var existingOrder models.Order
		if err := database.DB.Where("order_number = ?", order.OrderNumber).First(&existingOrder).Error; err == nil {
			skipped++
			continue // 静默跳过重复订单
		}

		order.CreatedBy = &userID

		// 如果有后期人员名称，查找或创建用户
		if staffName != "" {
			user, created := findOrCreateUser(staffName)
			if user != nil {
				order.AssignedTo = &user.ID
				// 只在 Excel 没有提供分配时间时才使用当前时间
				if order.AssignedAt == nil {
					now := time.Now()
					order.AssignedAt = &now
				}
				if created {
					usersCreated++
				}
			}
		}

		if err := database.DB.Create(&order).Error; err != nil {
			failed++
			errors = append(errors, fmt.Sprintf("行 %d: 保存失败", i+1))
			continue
		}

		imported++
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      fmt.Sprintf("导入完成: 成功 %d 条, 跳过重复 %d 条, 失败 %d 条, 新建用户 %d 个", imported, skipped, failed, usersCreated),
		"imported":     imported,
		"skipped":      skipped,
		"failed":       failed,
		"usersCreated": usersCreated,
		"errors":       errors,
	})
}

// findOrCreateUser 根据名称查找或创建用户
func findOrCreateUser(name string) (*models.User, bool) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, false
	}

	// 先按昵称查找
	var user models.User
	if err := database.DB.Where("nickname = ?", name).First(&user).Error; err == nil {
		return &user, false
	}

	// 按用户名查找
	if err := database.DB.Where("username = ?", name).First(&user).Error; err == nil {
		return &user, false
	}

	// 创建新用户（使用默认绩效配置）
	newUser := models.User{
		Username:          name,
		Nickname:          name,
		Role:              models.RoleStaff,
		BasePrice:         8.0, // 默认基础单价
		GroupBonus:        2.0,
		UrgentBonus:       5.0,
		ComplaintBonus:    8.0,
		WeddingMultiplier: 0.8,
	}
	newUser.SetPassword("123456") // 默认密码

	if err := database.DB.Create(&newUser).Error; err != nil {
		return nil, false
	}

	return &newUser, true
}

// parseExcelRowWithStaff 解析 Excel 行，返回订单和后期人员名称
// 实际列顺序: 后期, 订单编号, 拍摄时间, 拍摄地点, 顾问, 张数, 分配时间, 试修交付时间, 结片时间, 是否交付精修, 投诉原因
func parseExcelRowWithStaff(row []string) (*models.Order, string, error) {
	order := &models.Order{
		IsInGroup: true, // 默认进群
		ShootType: models.ShootTypeWedding,
	}

	var staffName string

	// 第0列：后期人员名称
	if len(row) > 0 {
		staffName = strings.TrimSpace(row[0])
	}

	// 第1列：订单编号（必填）
	if len(row) > 1 {
		order.OrderNumber = strings.TrimSpace(row[1])
	}
	if order.OrderNumber == "" {
		return nil, "", fmt.Errorf("订单编号不能为空")
	}

	// 第2列：拍摄时间
	if len(row) > 2 {
		order.ShootDate = strings.TrimSpace(row[2])
	}

	// 第3列：拍摄地点
	if len(row) > 3 {
		order.ShootLocation = strings.TrimSpace(row[3])
	}

	// 第4列：顾问
	if len(row) > 4 {
		order.Consultant = strings.TrimSpace(row[4])
	}

	// 第5列：张数
	if len(row) > 5 {
		if count, err := strconv.Atoi(strings.TrimSpace(row[5])); err == nil {
			order.TotalCount = count
		}
	}

	// 第6列：分配时间 - 解析为 AssignedAt
	if len(row) > 6 {
		rawAssignedAt := row[6]
		fmt.Printf("[DEBUG] 订单 %s 分配时间原始值: %q\n", order.OrderNumber, rawAssignedAt)
		if t := parseDate(rawAssignedAt); t != nil {
			order.AssignedAt = t
			fmt.Printf("[DEBUG] 订单 %s 分配时间解析成功: %s\n", order.OrderNumber, t.Format("2006-01-02"))
		} else {
			fmt.Printf("[DEBUG] 订单 %s 分配时间解析失败\n", order.OrderNumber)
		}
	}

	// 第7列：试修交付时间
	if len(row) > 7 {
		if t := parseDate(row[7]); t != nil {
			order.TrialDeadline = t
		}
	}

	// 第8列：结片时间
	if len(row) > 8 {
		if t := parseDate(row[8]); t != nil {
			order.FinalDeadline = t
		}
	}

	// 第9列：是否交付精修 -> isCompleted
	if len(row) > 9 {
		order.IsCompleted = parseBool(row[9])
		if order.IsCompleted {
			now := time.Now()
			order.CompletedAt = &now
		}
	}

	// 第10列：投诉原因 -> remarks
	if len(row) > 10 {
		remarks := strings.TrimSpace(row[10])
		if remarks != "" && remarks != "NaN" {
			order.Remarks = remarks
			order.IsComplaint = true // 有投诉原因则标记为投诉
		}
	}

	return order, staffName, nil
}

// parseBool 解析布尔值
func parseBool(s string) bool {
	s = strings.TrimSpace(strings.ToLower(s))
	return s == "是" || s == "yes" || s == "true" || s == "1" || s == "有"
}

// parseDate 解析日期
func parseDate(s string) *time.Time {
	s = strings.TrimSpace(s)
	if s == "" || s == "-" {
		return nil
	}

	formats := []string{
		"2006-01-02",
		"2006/01/02",
		"2006.01.02",
		"2006-1-2", // 支持单位数月日
		"2006/1/2", // 支持单位数月日
		"2006.1.2", // 支持单位数月日
		"06-01-02",
		"06/01/02",
		"06-1-2",
		"06/1/2",
		"Jan 2, 2006",
		"2 Jan 2006",
	}

	for _, format := range formats {
		if t, err := time.Parse(format, s); err == nil {
			return &t
		}
	}

	return nil
}

// MigrationData 迁移数据结构
type MigrationData struct {
	ExportDate     string                 `json:"exportDate"`
	Orders         []MigrationOrder       `json:"orders"`
	StaffList      []MigrationUser        `json:"staffList"`
	ShootingOrders []models.ShootingOrder `json:"shootingOrders"`
}

type MigrationOrder struct {
	ID               string  `json:"id"`
	OrderNumber      string  `json:"orderNumber"`
	ShootDate        string  `json:"shootDate"`
	ShootLocation    string  `json:"shootLocation"`
	Photographer     string  `json:"photographer"`
	Consultant       string  `json:"consultant"`
	TotalCount       int     `json:"totalCount"`
	ExtraCount       int     `json:"extraCount"`
	HasProduct       bool    `json:"hasProduct"`
	TrialDeadline    *string `json:"trialDeadline"`
	FinalDeadline    *string `json:"finalDeadline"`
	WeddingDate      string  `json:"weddingDate"`
	IsRepeatCustomer bool    `json:"isRepeatCustomer"`
	Requirements     string  `json:"requirements"`
	PanLink          string  `json:"panLink"`
	PanCode          string  `json:"panCode"`
	AssignedTo       *string `json:"assignedTo"`
	AssignedAt       *string `json:"assignedAt"`
	Remarks          string  `json:"remarks"`
	RemarksHistory   string  `json:"remarksHistory"`
	IsCompleted      bool    `json:"isCompleted"`
	CompletedAt      *string `json:"completedAt"`
	ShootType        string  `json:"shootType"`
	IsInGroup        bool    `json:"isInGroup"`
	IsUrgent         bool    `json:"isUrgent"`
	IsComplaint      bool    `json:"isComplaint"`
	IsArchived       bool    `json:"isArchived"`
	ArchiveMonth     *string `json:"archiveMonth"`
	CreatedAt        *string `json:"createdAt"`
	UpdatedAt        *string `json:"updatedAt"`
}

type MigrationUser struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
	RealName string `json:"realName"`
	Role     string `json:"role"`
	// 新绩效字段
	BasePrice         float64 `json:"basePrice"`
	GroupBonus        float64 `json:"groupBonus"`
	UrgentBonus       float64 `json:"urgentBonus"`
	ComplaintBonus    float64 `json:"complaintBonus"`
	WeddingMultiplier float64 `json:"weddingMultiplier"`
	// 兼容旧数据
	Level               string  `json:"level,omitempty"`
	BasePerformanceRate float64 `json:"basePerformanceRate,omitempty"`
	// 日历颜色
	CalendarColorRed   float64 `json:"calendarColorRed"`
	CalendarColorGreen float64 `json:"calendarColorGreen"`
	CalendarColorBlue  float64 `json:"calendarColorBlue"`
	AvatarUrl          string  `json:"avatarUrl"`
	// 离职状态
	IsHidden bool    `json:"isHidden"`
	LeftAt   *string `json:"leftAt"`
}

// ImportMigration 导入迁移数据
func ImportMigration(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请上传迁移数据文件"})
		return
	}

	src, err := file.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "打开文件失败"})
		return
	}
	defer src.Close()

	var migrationData MigrationData
	decoder := json.NewDecoder(src)
	if err := decoder.Decode(&migrationData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "解析 JSON 失败: " + err.Error()})
		return
	}

	var usersImported, usersFailed, ordersImported, ordersFailed int
	userIDMap := make(map[string]string) // 老 ID -> 新 ID 映射

	// 1. 首先导入用户（跳过已存在的用户）
	for _, mu := range migrationData.StaffList {
		// 检查用户名是否已存在
		var existingUser models.User
		if err := database.DB.Where("username = ?", mu.Username).First(&existingUser).Error; err == nil {
			// 用户已存在，记录映射
			userIDMap[mu.ID] = existingUser.ID.String()
			continue
		}

		// 创建新用户（使用新绩效字段）
		user := models.User{
			Username:           mu.Username,
			Nickname:           mu.Nickname,
			RealName:           mu.RealName,
			BasePrice:          mu.BasePrice,
			GroupBonus:         mu.GroupBonus,
			UrgentBonus:        mu.UrgentBonus,
			ComplaintBonus:     mu.ComplaintBonus,
			WeddingMultiplier:  mu.WeddingMultiplier,
			CalendarColorRed:   mu.CalendarColorRed,
			CalendarColorGreen: mu.CalendarColorGreen,
			CalendarColorBlue:  mu.CalendarColorBlue,
			AvatarURL:          mu.AvatarUrl,
		}

		// 设置角色
		switch mu.Role {
		case "admin":
			user.Role = models.RoleAdmin
		case "sub_admin":
			user.Role = models.RoleSubAdmin
		case "outsource":
			user.Role = models.RoleOutsource
		default:
			user.Role = models.RoleStaff
		}

		// 兼容旧数据：如果新字段为0，尝试从旧字段恢复
		if user.BasePrice == 0 {
			// 根据老数据的 Level 设置默认绩效配置
			switch mu.Level {
			case "初级":
				user.BasePrice = 6.0
			case "高级":
				user.BasePrice = 10.0
			case "外援":
				user.BasePrice = 15.0
			default:
				user.BasePrice = 8.0
			}
			// 如果老数据有 BasePerformanceRate 则使用它
			if mu.BasePerformanceRate > 0 {
				user.BasePrice = mu.BasePerformanceRate
			}
		}
		// 设置其他默认值
		if user.GroupBonus == 0 {
			user.GroupBonus = 2.0
		}
		if user.UrgentBonus == 0 {
			user.UrgentBonus = 5.0
		}
		if user.ComplaintBonus == 0 {
			user.ComplaintBonus = 8.0
		}
		if user.WeddingMultiplier == 0 {
			user.WeddingMultiplier = 0.8
		}

		// 默认密码
		user.SetPassword("123456")

		if err := database.DB.Create(&user).Error; err != nil {
			usersFailed++
		} else {
			usersImported++
			userIDMap[mu.ID] = user.ID.String()
		}
	}

	// 2. 导入订单
	for _, mo := range migrationData.Orders {
		// 检查订单号是否已存在
		var existingOrder models.Order
		if err := database.DB.Where("order_number = ?", mo.OrderNumber).First(&existingOrder).Error; err == nil {
			// 订单已存在，跳过
			ordersFailed++
			continue
		}

		order := models.Order{
			OrderNumber:      mo.OrderNumber,
			ShootDate:        mo.ShootDate,
			ShootLocation:    mo.ShootLocation,
			Photographer:     mo.Photographer,
			Consultant:       mo.Consultant,
			TotalCount:       mo.TotalCount,
			ExtraCount:       mo.ExtraCount,
			HasProduct:       mo.HasProduct,
			WeddingDate:      mo.WeddingDate,
			IsRepeatCustomer: mo.IsRepeatCustomer,
			Requirements:     mo.Requirements,
			PanLink:          mo.PanLink,
			PanCode:          mo.PanCode,
			Remarks:          mo.Remarks,
			IsCompleted:      mo.IsCompleted,
			IsInGroup:        mo.IsInGroup,
			IsUrgent:         mo.IsUrgent,
			IsComplaint:      mo.IsComplaint,
			IsArchived:       mo.IsArchived,
		}

		// 设置归档月份
		if mo.ArchiveMonth != nil {
			order.ArchiveMonth = *mo.ArchiveMonth
		}

		// 设置拍摄类型
		switch mo.ShootType {
		case "婚礼":
			order.ShootType = models.ShootTypeCeremony
		default:
			order.ShootType = models.ShootTypeWedding
		}

		// 解析日期
		if mo.TrialDeadline != nil {
			order.TrialDeadline = parseISO8601(*mo.TrialDeadline)
		}
		if mo.FinalDeadline != nil {
			order.FinalDeadline = parseISO8601(*mo.FinalDeadline)
		}

		// 映射分配用户 ID
		if mo.AssignedTo != nil && *mo.AssignedTo != "" {
			if newID, ok := userIDMap[*mo.AssignedTo]; ok {
				uid, _ := uuid.Parse(newID)
				order.AssignedTo = &uid
				// 使用 JSON 中的分配时间，如果没有则使用当前时间
				if mo.AssignedAt != nil && *mo.AssignedAt != "" {
					order.AssignedAt = parseISO8601(*mo.AssignedAt)
				} else {
					now := time.Now()
					order.AssignedAt = &now
				}
			}
		}

		if err := database.DB.Create(&order).Error; err != nil {
			ordersFailed++
		} else {
			ordersImported++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":        fmt.Sprintf("迁移完成: 用户 %d/%d, 订单 %d/%d", usersImported, len(migrationData.StaffList), ordersImported, len(migrationData.Orders)),
		"usersImported":  usersImported,
		"usersFailed":    usersFailed,
		"ordersImported": ordersImported,
		"ordersFailed":   ordersFailed,
	})
}

// parseISO8601 解析 ISO8601 日期
func parseISO8601(s string) *time.Time {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}

	formats := []string{
		time.RFC3339,
		"2006-01-02T15:04:05Z",
		"2006-01-02T15:04:05.000Z",
		"2006-01-02",
	}

	for _, format := range formats {
		if t, err := time.Parse(format, s); err == nil {
			return &t
		}
	}

	return nil
}

// DeleteAllData 删除所有订单数据（危险操作）
func DeleteAllData(c *gin.Context) {
	// 1. 先清除拍摄订单的外键关联
	if err := database.DB.Exec("UPDATE shooting_orders SET matched_order_id = NULL").Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "清除关联失败: " + err.Error()})
		return
	}

	// 2. 删除所有订单
	result := database.DB.Exec("DELETE FROM orders")
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败: " + result.Error.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("已删除 %d 条订单", result.RowsAffected),
		"deleted": result.RowsAffected,
	})
}

// ExportFullBackup 导出完整备份（JSON + 头像 ZIP）
func ExportFullBackup(c *gin.Context) {
	// 1. 获取所有订单
	var orders []models.Order
	if err := database.DB.Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取订单失败"})
		return
	}

	// 2. 获取所有用户
	var users []models.User
	if err := database.DB.Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取用户失败"})
		return
	}

	// 3. 获取所有拍摄订单
	var shootingOrders []models.ShootingOrder
	if err := database.DB.Find(&shootingOrders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取拍摄订单失败"})
		return
	}

	// 4. 构建导出数据
	type ExportUser struct {
		ID                 string  `json:"id"`
		Username           string  `json:"username"`
		Nickname           string  `json:"nickname"`
		RealName           string  `json:"realName"`
		Role               string  `json:"role"`
		BasePrice          float64 `json:"basePrice"`
		GroupBonus         float64 `json:"groupBonus"`
		UrgentBonus        float64 `json:"urgentBonus"`
		ComplaintBonus     float64 `json:"complaintBonus"`
		WeddingMultiplier  float64 `json:"weddingMultiplier"`
		CalendarColorRed   float64 `json:"calendarColorRed"`
		CalendarColorGreen float64 `json:"calendarColorGreen"`
		CalendarColorBlue  float64 `json:"calendarColorBlue"`
		AvatarUrl          string  `json:"avatarUrl"`
		// 离职状态
		IsHidden bool    `json:"isHidden"`
		LeftAt   *string `json:"leftAt"`
	}

	type ExportData struct {
		ExportDate     string                 `json:"exportDate"`
		Orders         []models.Order         `json:"orders"`
		StaffList      []ExportUser           `json:"staffList"`
		ShootingOrders []models.ShootingOrder `json:"shootingOrders"`
	}

	exportUsers := make([]ExportUser, len(users))
	for i, u := range users {
		var leftAtStr *string
		if u.LeftAt != nil {
			s := u.LeftAt.Format(time.RFC3339)
			leftAtStr = &s
		}

		exportUsers[i] = ExportUser{
			ID:                 u.ID.String(),
			Username:           u.Username,
			Nickname:           u.Nickname,
			RealName:           u.RealName,
			Role:               string(u.Role),
			BasePrice:          u.BasePrice,
			GroupBonus:         u.GroupBonus,
			UrgentBonus:        u.UrgentBonus,
			ComplaintBonus:     u.ComplaintBonus,
			WeddingMultiplier:  u.WeddingMultiplier,
			CalendarColorRed:   u.CalendarColorRed,
			CalendarColorGreen: u.CalendarColorGreen,
			CalendarColorBlue:  u.CalendarColorBlue,
			AvatarUrl:          u.AvatarURL,
			IsHidden:           u.IsHidden,
			LeftAt:             leftAtStr,
		}
	}

	exportData := ExportData{
		ExportDate:     time.Now().Format("2006-01-02 15:04:05"),
		Orders:         orders,
		StaffList:      exportUsers,
		ShootingOrders: shootingOrders,
	}

	// 5. 创建 ZIP 缓冲区
	buf := new(bytes.Buffer)
	zipWriter := zip.NewWriter(buf)

	// 6. 添加 data.json
	jsonData, err := json.MarshalIndent(exportData, "", "  ")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "JSON 序列化失败"})
		return
	}

	jsonFile, err := zipWriter.Create("data.json")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建 ZIP 文件失败"})
		return
	}
	jsonFile.Write(jsonData)

	// 7. 添加头像文件
	avatarDir := "./uploads/avatars"
	if _, err := os.Stat(avatarDir); err == nil {
		filepath.Walk(avatarDir, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return nil
			}

			// 读取文件
			fileData, err := os.ReadFile(path)
			if err != nil {
				return nil
			}

			// 添加到 ZIP（保持相对路径 avatars/xxx.jpg）
			relPath := strings.TrimPrefix(path, "./uploads/")
			zipFile, err := zipWriter.Create(relPath)
			if err != nil {
				return nil
			}
			zipFile.Write(fileData)
			return nil
		})
	}

	// 8. 关闭 ZIP
	zipWriter.Close()

	// 9. 返回下载
	filename := fmt.Sprintf("tvtxiu_backup_%s.zip", time.Now().Format("20060102_150405"))
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Data(http.StatusOK, "application/zip", buf.Bytes())
}

// ImportFullBackup 导入完整备份（ZIP 包含 JSON + 头像）
func ImportFullBackup(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请上传文件"})
		return
	}

	// 检查是否为 ZIP 文件
	if !strings.HasSuffix(strings.ToLower(file.Filename), ".zip") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请上传 ZIP 格式的备份文件"})
		return
	}

	// 打开上传的文件
	src, err := file.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "打开文件失败"})
		return
	}
	defer src.Close()

	// 读取到内存
	fileBytes, err := io.ReadAll(src)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取文件失败"})
		return
	}

	// 打开 ZIP
	zipReader, err := zip.NewReader(bytes.NewReader(fileBytes), int64(len(fileBytes)))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的 ZIP 文件"})
		return
	}

	var jsonData []byte
	avatarsRestored := 0

	// 遍历 ZIP 内容
	for _, zipFile := range zipReader.File {
		if zipFile.Name == "data.json" {
			// 读取 JSON 数据
			rc, err := zipFile.Open()
			if err != nil {
				continue
			}
			jsonData, _ = io.ReadAll(rc)
			rc.Close()
		} else if strings.HasPrefix(zipFile.Name, "avatars/") {
			// 恢复头像文件
			rc, err := zipFile.Open()
			if err != nil {
				continue
			}
			avatarData, _ := io.ReadAll(rc)
			rc.Close()

			// 保存头像
			destPath := "./uploads/" + zipFile.Name
			os.MkdirAll(filepath.Dir(destPath), 0755)
			if err := os.WriteFile(destPath, avatarData, 0644); err == nil {
				avatarsRestored++
			}
		}
	}

	if len(jsonData) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ZIP 中未找到 data.json"})
		return
	}

	// 解析 JSON（复用 MigrationData 结构）
	var data MigrationData
	if err := json.Unmarshal(jsonData, &data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "JSON 解析失败: " + err.Error()})
		return
	}

	// 使用现有的导入逻辑（通过创建临时文件调用 ImportMigration 或直接处理）
	usersImported := 0
	usersFailed := 0
	ordersImported := 0
	ordersFailed := 0
	userIDMap := make(map[string]string)

	// 导入用户
	for _, mu := range data.StaffList {
		var existingUser models.User
		if err := database.DB.Where("username = ?", mu.Username).First(&existingUser).Error; err == nil {
			userIDMap[mu.ID] = existingUser.ID.String()
			continue
		}

		user := models.User{
			Username:           mu.Username,
			Nickname:           mu.Nickname,
			RealName:           mu.RealName,
			BasePrice:          mu.BasePrice,
			GroupBonus:         mu.GroupBonus,
			UrgentBonus:        mu.UrgentBonus,
			ComplaintBonus:     mu.ComplaintBonus,
			WeddingMultiplier:  mu.WeddingMultiplier,
			CalendarColorRed:   mu.CalendarColorRed,
			CalendarColorGreen: mu.CalendarColorGreen,
			CalendarColorBlue:  mu.CalendarColorBlue,
			AvatarURL:          mu.AvatarUrl,
			IsHidden:           mu.IsHidden,
		}

		// 解析离职时间
		if mu.LeftAt != nil {
			user.LeftAt = parseISO8601(*mu.LeftAt)
		}

		switch mu.Role {
		case "admin":
			user.Role = models.RoleAdmin
		case "sub_admin":
			user.Role = models.RoleSubAdmin
		case "outsource":
			user.Role = models.RoleOutsource
		default:
			user.Role = models.RoleStaff
		}

		// 设置默认值
		if user.BasePrice == 0 {
			user.BasePrice = 8.0
		}
		if user.GroupBonus == 0 {
			user.GroupBonus = 2.0
		}
		if user.UrgentBonus == 0 {
			user.UrgentBonus = 5.0
		}
		if user.ComplaintBonus == 0 {
			user.ComplaintBonus = 8.0
		}
		if user.WeddingMultiplier == 0 {
			user.WeddingMultiplier = 0.8
		}

		user.SetPassword("123456")

		if err := database.DB.Create(&user).Error; err != nil {
			usersFailed++
		} else {
			usersImported++
			userIDMap[mu.ID] = user.ID.String()
		}
	}

	// 导入订单（复用现有逻辑）
	for _, mo := range data.Orders {
		var existingOrder models.Order
		if err := database.DB.Where("order_number = ?", mo.OrderNumber).First(&existingOrder).Error; err == nil {
			continue
		}

		// 转换 ShootType
		var shootType models.ShootType = models.ShootTypeWedding
		if mo.ShootType == "婚礼" || mo.ShootType == "ceremony" {
			shootType = models.ShootTypeCeremony
		}

		order := models.Order{
			OrderNumber:      mo.OrderNumber,
			ShootDate:        mo.ShootDate,
			ShootLocation:    mo.ShootLocation,
			Photographer:     mo.Photographer,
			Consultant:       mo.Consultant,
			TotalCount:       mo.TotalCount,
			ExtraCount:       mo.ExtraCount,
			HasProduct:       mo.HasProduct,
			WeddingDate:      mo.WeddingDate,
			IsRepeatCustomer: mo.IsRepeatCustomer,
			Requirements:     mo.Requirements,
			PanLink:          mo.PanLink,
			PanCode:          mo.PanCode,
			Remarks:          mo.Remarks,
			IsCompleted:      mo.IsCompleted,
			ShootType:        shootType,
			IsInGroup:        mo.IsInGroup,
			IsUrgent:         mo.IsUrgent,
			IsComplaint:      mo.IsComplaint,
			IsArchived:       mo.IsArchived,
		}

		if mo.AssignedTo != nil && *mo.AssignedTo != "" {
			if newID, ok := userIDMap[*mo.AssignedTo]; ok {
				parsedID, _ := uuid.Parse(newID)
				order.AssignedTo = &parsedID
			}
		}

		// 解析日期（处理 *string 到 string 转换）
		if mo.TrialDeadline != nil {
			order.TrialDeadline = parseISO8601(*mo.TrialDeadline)
		}
		if mo.FinalDeadline != nil {
			order.FinalDeadline = parseISO8601(*mo.FinalDeadline)
		}
		if mo.AssignedAt != nil {
			order.AssignedAt = parseISO8601(*mo.AssignedAt)
		}
		if mo.CompletedAt != nil {
			order.CompletedAt = parseISO8601(*mo.CompletedAt)
		}

		// 恢复其他字段
		if mo.RemarksHistory != "" {
			order.RemarksHistory = mo.RemarksHistory
		}
		if mo.ArchiveMonth != nil {
			order.ArchiveMonth = *mo.ArchiveMonth
		}
		if mo.CreatedAt != nil {
			if t := parseISO8601(*mo.CreatedAt); t != nil {
				order.CreatedAt = *t
			}
		}
		if mo.UpdatedAt != nil {
			if t := parseISO8601(*mo.UpdatedAt); t != nil {
				order.UpdatedAt = *t
			}
		}

		if err := database.DB.Create(&order).Error; err != nil {
			ordersFailed++
		} else {
			ordersImported++
		}
	}

	// 导入拍摄订单
	shootingOrdersImported := 0
	shootingOrdersFailed := 0
	for _, so := range data.ShootingOrders {
		// 检查是否已存在（按订单号和年份）
		var existingShootingOrder models.ShootingOrder
		if err := database.DB.Where("order_number = ? AND shoot_year = ?", so.OrderNumber, so.ShootYear).First(&existingShootingOrder).Error; err == nil {
			continue // 已存在，跳过
		}

		// 创建新的拍摄订单（直接使用原结构）
		newShootingOrder := models.ShootingOrder{
			OrderNumber:    so.OrderNumber,
			ShootYear:      so.ShootYear,
			ShootMonth:     so.ShootMonth,
			ShootDay:       so.ShootDay,
			ShootDate:      so.ShootDate,
			Location:       so.Location,
			Country:        so.Country,
			OrderType:      so.OrderType,
			Photographer:   so.Photographer,
			Sales:          so.Sales,
			Consultant:     so.Consultant,
			PostProducer:   so.PostProducer,
			RawData:        so.RawData,
			MatchedOrderID: so.MatchedOrderID,
		}

		if err := database.DB.Create(&newShootingOrder).Error; err != nil {
			shootingOrdersFailed++
		} else {
			shootingOrdersImported++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":                "备份恢复完成",
		"usersImported":          usersImported,
		"usersFailed":            usersFailed,
		"ordersImported":         ordersImported,
		"ordersFailed":           ordersFailed,
		"avatarsRestored":        avatarsRestored,
		"shootingOrdersImported": shootingOrdersImported,
		"shootingOrdersFailed":   shootingOrdersFailed,
	})
}
