package handlers

import (
	"bytes"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"tvtxiu-api/models"
	"tvtxiu-api/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// SyncHandler 同步处理器
type SyncHandler struct {
	DB          *gorm.DB
	syncMutex   sync.Mutex
	isRunning   bool
	lastSyncAt  *time.Time
	lastError   string
	totalSynced int
}

// NewSyncHandler 创建同步处理器
func NewSyncHandler(db *gorm.DB) *SyncHandler {
	return &SyncHandler{DB: db}
}

// GetSyncStatus 获取同步状态
// GET /api/sync/status
func (h *SyncHandler) GetSyncStatus(c *gin.Context) {
	var nextSync *time.Time
	if h.lastSyncAt != nil {
		next := h.lastSyncAt.Add(6 * time.Hour)
		nextSync = &next
	}

	status := models.SyncStatus{
		LastSyncAt:  h.lastSyncAt,
		TotalSynced: h.totalSynced,
		LastError:   h.lastError,
		IsRunning:   h.isRunning,
		NextSyncAt:  nextSync,
	}

	c.JSON(http.StatusOK, status)
}

// TriggerSync 触发立即同步
// POST /api/sync/trigger
func (h *SyncHandler) TriggerSync(c *gin.Context) {
	if h.isRunning {
		c.JSON(http.StatusConflict, gin.H{"error": "同步正在进行中"})
		return
	}

	// 获取同步配置
	var config models.SyncConfig
	if err := h.DB.First(&config).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "未配置同步设置，请先设置 Cookie"})
		return
	}

	// 异步执行同步
	go h.runSync(config)

	c.JSON(http.StatusOK, gin.H{"message": "同步已启动"})
}

// UpdateCookie 更新 Cookie
// PUT /api/sync/cookie
func (h *SyncHandler) UpdateCookie(c *gin.Context) {
	var request struct {
		Cookie   string `json:"cookie" binding:"required"`
		DocURL   string `json:"docUrl"`
		TabID    string `json:"tabId"`
		SyncYear int    `json:"syncYear"`
	}

	if err := c.ShouldBindJSON(&request); err != nil {
		log.Printf("[SyncHandler] Cookie 绑定失败: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求数据无效: " + err.Error()})
		return
	}

	log.Printf("[SyncHandler] 收到 Cookie 更新请求, SyncYear=%d, Cookie长度=%d", request.SyncYear, len(request.Cookie))

	// 默认值
	if request.DocURL == "" {
		request.DocURL = "https://docs.qq.com/sheet/DY1B6ZEV6c3BxUkNR?tab=rq41oz"
	}
	if request.TabID == "" {
		request.TabID = "rq41oz"
	}
	if request.SyncYear == 0 {
		request.SyncYear = time.Now().Year()
	}

	// 测试连接
	log.Printf("[SyncHandler] 测试连接: DocURL=%s", request.DocURL)
	svc := services.NewTencentDocsService(request.Cookie, request.DocURL, request.TabID)
	if err := svc.TestConnection(); err != nil {
		log.Printf("[SyncHandler] TestConnection 失败: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cookie 验证失败: " + err.Error()})
		return
	}
	log.Printf("[SyncHandler] TestConnection 成功")

	// 保存或更新配置
	var config models.SyncConfig
	if err := h.DB.First(&config).Error; err != nil {
		// 创建新配置
		config = models.SyncConfig{
			ID:        uuid.New(),
			DocURL:    request.DocURL,
			TabID:     request.TabID,
			Cookie:    request.Cookie,
			SyncYear:  request.SyncYear,
			IsEnabled: true,
		}
		h.DB.Create(&config)
	} else {
		// 更新配置
		h.DB.Model(&config).Updates(map[string]interface{}{
			"cookie":     request.Cookie,
			"doc_url":    request.DocURL,
			"tab_id":     request.TabID,
			"sync_year":  request.SyncYear,
			"is_enabled": true,
			"updated_at": time.Now(),
		})
	}

	c.JSON(http.StatusOK, gin.H{"message": "Cookie 已保存并验证成功"})
}

// runSync 执行同步任务
func (h *SyncHandler) runSync(config models.SyncConfig) {
	h.syncMutex.Lock()
	h.isRunning = true
	h.lastError = ""
	h.syncMutex.Unlock()

	defer func() {
		h.syncMutex.Lock()
		h.isRunning = false
		now := time.Now()
		h.lastSyncAt = &now
		h.syncMutex.Unlock()
	}()

	// 创建服务
	svc := services.NewTencentDocsService(config.Cookie, config.DocURL, config.TabID)

	// 获取数据
	orders, err := svc.FetchShootingOrders(config.SyncYear)
	if err != nil {
		h.syncMutex.Lock()
		h.lastError = err.Error()
		h.syncMutex.Unlock()
		return
	}

	// 增量同步：按订单编号更新或插入
	synced := 0
	for _, order := range orders {
		var existing models.ShootingOrder
		if err := h.DB.Where("order_number = ?", order.OrderNumber).First(&existing).Error; err == nil {
			// 更新已存在的记录
			h.DB.Model(&existing).Updates(map[string]interface{}{
				"shoot_year":   order.ShootYear,
				"shoot_month":  order.ShootMonth,
				"shoot_day":    order.ShootDay,
				"shoot_date":   order.ShootDate,
				"location":     order.Location,
				"country":      order.Country,
				"order_type":   order.OrderType,
				"photographer": order.Photographer,
				"raw_data":     order.RawData,
				"synced_at":    time.Now(),
			})
		} else {
			// 插入新记录
			h.DB.Create(&order)
		}
		synced++
	}

	h.syncMutex.Lock()
	h.totalSynced = synced
	h.syncMutex.Unlock()
}

// RunScheduledSync 定时同步（每6小时调用一次）
func (h *SyncHandler) RunScheduledSync() {
	var config models.SyncConfig
	if err := h.DB.Where("is_enabled = ?", true).First(&config).Error; err != nil {
		return // 没有启用的配置
	}

	h.runSync(config)
}

// GetShootingOrders 获取拍摄订单列表
// GET /api/shooting/orders?year=2026&matched=false&completed=true&search=关键词&sort=asc&limit=20&offset=0
func (h *SyncHandler) GetShootingOrders(c *gin.Context) {
	year := c.DefaultQuery("year", "")
	matched := c.DefaultQuery("matched", "")
	completed := c.DefaultQuery("completed", "")
	search := c.DefaultQuery("search", "")
	sortOrder := c.DefaultQuery("sort", "desc") // asc or desc
	limitStr := c.DefaultQuery("limit", "0")    // 0 = 不限制
	offsetStr := c.DefaultQuery("offset", "0")

	limit, _ := strconv.Atoi(limitStr)
	offset, _ := strconv.Atoi(offsetStr)

	// 构建基础筛选条件
	baseQuery := h.DB.Model(&models.ShootingOrder{})

	// 年份筛选
	if year != "" {
		baseQuery = baseQuery.Where("shoot_year = ?", year)
	}

	// 匹配状态筛选
	if matched == "true" {
		baseQuery = baseQuery.Where("matched_order_id IS NOT NULL")
	} else if matched == "false" {
		baseQuery = baseQuery.Where("matched_order_id IS NULL")
	}

	// 已完成筛选（通过关联订单的 is_completed 状态）
	if completed == "true" {
		baseQuery = baseQuery.Where("matched_order_id IN (SELECT id FROM orders WHERE is_completed = true)")
	}

	// 搜索（模糊匹配订单号、地点、摄影师）
	if search != "" {
		searchPattern := "%" + search + "%"
		baseQuery = baseQuery.Where("order_number ILIKE ? OR location ILIKE ? OR photographer ILIKE ?",
			searchPattern, searchPattern, searchPattern)
	}

	// 获取总数（使用单独的查询）
	var total int64
	baseQuery.Count(&total)

	// 构建数据查询（带 Preload）
	dataQuery := h.DB.
		Preload("MatchedOrder").
		Preload("MatchedOrder.AssignedUser")

	// 复制筛选条件
	if year != "" {
		dataQuery = dataQuery.Where("shoot_year = ?", year)
	}
	if matched == "true" {
		dataQuery = dataQuery.Where("matched_order_id IS NOT NULL")
	} else if matched == "false" {
		dataQuery = dataQuery.Where("matched_order_id IS NULL")
	}
	if completed == "true" {
		dataQuery = dataQuery.Where("matched_order_id IN (SELECT id FROM orders WHERE is_completed = true)")
	}
	if search != "" {
		searchPattern := "%" + search + "%"
		dataQuery = dataQuery.Where("order_number ILIKE ? OR location ILIKE ? OR photographer ILIKE ?",
			searchPattern, searchPattern, searchPattern)
	}

	// 排序
	if sortOrder == "asc" {
		dataQuery = dataQuery.Order("shoot_date ASC")
	} else {
		dataQuery = dataQuery.Order("shoot_date DESC")
	}

	// 分页
	if limit > 0 {
		dataQuery = dataQuery.Limit(limit).Offset(offset)
	}

	var orders []models.ShootingOrder
	if err := dataQuery.Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"orders": orders,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// GetShootingStats 获取拍摄统计
// GET /api/stats/shooting?year=2026
func (h *SyncHandler) GetShootingStats(c *gin.Context) {
	yearStr := c.DefaultQuery("year", "")
	if yearStr == "" {
		yearStr = time.Now().Format("2006")
	}

	var stats models.ShootingStats

	// 拍摄订单总数
	var totalShooting int64
	h.DB.Model(&models.ShootingOrder{}).Where("shoot_year = ?", yearStr).Count(&totalShooting)
	stats.TotalShooting = int(totalShooting)

	// 已匹配的订单数（已分配后期）
	var totalAssigned int64
	h.DB.Model(&models.ShootingOrder{}).Where("shoot_year = ? AND matched_order_id IS NOT NULL", yearStr).Count(&totalAssigned)
	stats.TotalAssigned = int(totalAssigned)

	// 已完成的订单数（需要关联查询）
	h.DB.Raw(`
		SELECT COUNT(*) FROM shooting_orders s
		JOIN orders o ON s.matched_order_id = o.id
		WHERE s.shoot_year = ? AND o.is_completed = true
	`, yearStr).Scan(&stats.TotalCompleted)

	// 待分配 = 拍摄 - 已匹配
	stats.TotalPending = stats.TotalShooting - stats.TotalAssigned

	c.JSON(http.StatusOK, stats)
}

// UploadExcel 上传 Excel 文件并导入拍摄订单
// POST /api/sync/upload
func (h *SyncHandler) UploadExcel(c *gin.Context) {
	// 获取上传的文件
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请选择要上传的文件"})
		return
	}

	// 验证文件类型
	if !strings.HasSuffix(strings.ToLower(file.Filename), ".xlsx") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "仅支持 .xlsx 格式的 Excel 文件"})
		return
	}

	// 保存文件到临时目录
	tempPath := "/tmp/tvtxiu_upload_" + time.Now().Format("20060102150405") + ".xlsx"
	if err := c.SaveUploadedFile(file, tempPath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存文件失败: " + err.Error()})
		return
	}
	defer os.Remove(tempPath) // 处理完后删除临时文件

	// 获取要导入的年份（可选参数）
	yearsParam := c.Query("years")
	var targetYears []int
	if yearsParam != "" {
		for _, yearStr := range strings.Split(yearsParam, ",") {
			if year, err := strconv.Atoi(strings.TrimSpace(yearStr)); err == nil {
				targetYears = append(targetYears, year)
			}
		}
	}

	log.Printf("[UploadExcel] 开始解析文件: %s, 目标年份: %v", file.Filename, targetYears)

	// 解析 Excel 文件
	parser := services.NewExcelParserService()
	result, err := parser.ParseExcelFile(tempPath, targetYears)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "解析文件失败: " + err.Error()})
		return
	}

	// 增量导入数据库
	imported := 0
	updated := 0
	skipped := 0

	for _, order := range result.Orders {
		// 查找是否已存在（按订单编号 + 地点 + 日期）
		var existing models.ShootingOrder
		err := h.DB.Where("order_number = ? AND location = ? AND shoot_year = ? AND shoot_month = ?",
			order.OrderNumber, order.Location, order.ShootYear, order.ShootMonth).First(&existing).Error

		if err == gorm.ErrRecordNotFound {
			// 新记录，插入
			if err := h.DB.Create(&order).Error; err != nil {
				log.Printf("[UploadExcel] 插入失败: %v", err)
				skipped++
			} else {
				imported++
			}
		} else if err == nil {
			// 已存在，更新
			h.DB.Model(&existing).Updates(map[string]interface{}{
				"shoot_day":    order.ShootDay,
				"country":      order.Country,
				"order_type":   order.OrderType,
				"photographer": order.Photographer,
				"sales":        order.Sales,
				"consultant":   order.Consultant,
				"synced_at":    time.Now(),
			})
			updated++
		} else {
			skipped++
		}
	}

	// 更新同步状态
	now := time.Now()
	h.lastSyncAt = &now
	h.totalSynced = imported + updated

	log.Printf("[UploadExcel] 导入完成: 新增 %d, 更新 %d, 跳过 %d", imported, updated, skipped)

	c.JSON(http.StatusOK, gin.H{
		"message":  "导入完成",
		"imported": imported,
		"updated":  updated,
		"skipped":  skipped,
		"total":    result.TotalRows,
		"valid":    result.ValidRows,
		"byYear":   result.ByYear,
	})
}

// UpdateShootingOrder 更新拍摄订单
// PUT /api/shooting/orders/:id
func (h *SyncHandler) UpdateShootingOrder(c *gin.Context) {
	id := c.Param("id")

	var order models.ShootingOrder
	if err := h.DB.First(&order, "id = ?", id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	var request struct {
		OrderNumber     string  `json:"orderNumber"`
		ShootYear       int     `json:"shootYear"`
		ShootMonth      int     `json:"shootMonth"`
		ShootDay        string  `json:"shootDay"`
		Location        string  `json:"location"`
		Country         string  `json:"country"`
		OrderType       string  `json:"orderType"`
		Photographer    string  `json:"photographer"`
		Sales           string  `json:"sales"`
		Consultant      string  `json:"consultant"`
		MatchedOrderId  *string `json:"matchedOrderId"`
		AssignedStaffId *string `json:"assignedStaffId"` // 新增：后期人员ID
	}

	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求数据无效"})
		return
	}

	// 更新字段
	updates := map[string]interface{}{
		"order_number": request.OrderNumber,
		"shoot_year":   request.ShootYear,
		"shoot_month":  request.ShootMonth,
		"shoot_day":    request.ShootDay,
		"location":     request.Location,
		"country":      request.Country,
		"order_type":   request.OrderType,
		"photographer": request.Photographer,
		"sales":        request.Sales,
		"consultant":   request.Consultant,
		"updated_at":   time.Now(),
	}

	// 处理后期匹配
	if request.MatchedOrderId != nil {
		if *request.MatchedOrderId == "" {
			updates["matched_order_id"] = nil
		} else {
			updates["matched_order_id"] = *request.MatchedOrderId
		}
	}

	if err := h.DB.Model(&order).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	// 重新计算拍摄日期
	order.ShootYear = request.ShootYear
	order.ShootMonth = request.ShootMonth
	order.ShootDay = request.ShootDay
	order.ComputeShootDate()
	h.DB.Model(&order).Update("shoot_date", order.ShootDate)

	// 处理后期人员分配（同步更新关联的 Order）
	if request.AssignedStaffId != nil {
		// 查找关联的 Order
		var linkedOrder models.Order
		if order.MatchedOrderID != nil {
			h.DB.First(&linkedOrder, "id = ?", *order.MatchedOrderID)
		} else {
			// 按订单编号查找
			h.DB.First(&linkedOrder, "order_number = ?", request.OrderNumber)
		}

		if linkedOrder.ID != uuid.Nil {
			if *request.AssignedStaffId == "" {
				// 取消分配
				h.DB.Model(&linkedOrder).Update("assigned_to", nil)
			} else {
				// 分配后期人员
				staffId, err := uuid.Parse(*request.AssignedStaffId)
				if err == nil {
					h.DB.Model(&linkedOrder).Update("assigned_to", staffId)
					// 同时更新拍摄订单的关联
					if order.MatchedOrderID == nil {
						h.DB.Model(&order).Update("matched_order_id", linkedOrder.ID)
					}
				}
			}
		}
	}

	// 返回更新后的订单（带 Preload）
	h.DB.Preload("MatchedOrder").Preload("MatchedOrder.AssignedUser").First(&order, "id = ?", id)
	c.JSON(http.StatusOK, order)
}

// ExportShootingOrders 导出拍摄订单为 CSV
// GET /api/shooting/orders/export?year=2026&matched=false&search=关键词
func (h *SyncHandler) ExportShootingOrders(c *gin.Context) {
	year := c.DefaultQuery("year", "")
	matched := c.DefaultQuery("matched", "")
	search := c.DefaultQuery("search", "")

	query := h.DB.Model(&models.ShootingOrder{})

	if year != "" {
		query = query.Where("shoot_year = ?", year)
	}

	if matched == "true" {
		query = query.Where("matched_order_id IS NOT NULL")
	} else if matched == "false" {
		query = query.Where("matched_order_id IS NULL")
	}

	if search != "" {
		searchPattern := "%" + search + "%"
		query = query.Where("order_number ILIKE ? OR location ILIKE ? OR photographer ILIKE ?",
			searchPattern, searchPattern, searchPattern)
	}

	var orders []models.ShootingOrder
	query.Order("shoot_date DESC").Find(&orders)

	// 生成 CSV
	var buf bytes.Buffer
	buf.WriteString("\xEF\xBB\xBF") // UTF-8 BOM for Excel
	buf.WriteString("订单编号,年,月,日,地点,国家,类型,摄影师,销售,顾问,是否匹配\n")

	for _, order := range orders {
		matched := "否"
		if order.MatchedOrderID != nil {
			matched = "是"
		}
		line := fmt.Sprintf("%s,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s\n",
			order.OrderNumber,
			order.ShootYear,
			order.ShootMonth,
			order.ShootDay,
			order.Location,
			order.Country,
			order.OrderType,
			order.Photographer,
			order.Sales,
			order.Consultant,
			matched,
		)
		buf.WriteString(line)
	}

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=shooting_orders_%s.csv", time.Now().Format("20060102")))
	c.Data(http.StatusOK, "text/csv", buf.Bytes())
}

// SyncShootingOrderMatches 批量同步拍摄订单匹配状态
// POST /api/shooting/sync-matches
// 支持多级匹配策略：精确匹配 -> 模糊匹配（去除末尾字母）-> 前缀匹配
func (h *SyncHandler) SyncShootingOrderMatches(c *gin.Context) {
	var exactMatched, fuzzyMatched, prefixMatched int64

	// 策略1: 精确匹配（订单编号完全相同）
	result1 := h.DB.Exec(`
		UPDATE shooting_orders so
		SET matched_order_id = o.id
		FROM orders o
		WHERE so.order_number = o.order_number
		AND so.matched_order_id IS NULL
	`)
	if result1.Error == nil {
		exactMatched = result1.RowsAffected
	}

	// 策略2: 模糊匹配（去除末尾的字母后匹配，如 CS02420241231A 和 CS02420241231 匹配）
	result2 := h.DB.Exec(`
		UPDATE shooting_orders so
		SET matched_order_id = o.id
		FROM orders o
		WHERE REGEXP_REPLACE(so.order_number, '[A-Za-z]$', '') = 
		      REGEXP_REPLACE(o.order_number, '[A-Za-z]$', '')
		AND so.matched_order_id IS NULL
		AND LENGTH(so.order_number) > 5
	`)
	if result2.Error == nil {
		fuzzyMatched = result2.RowsAffected
	}

	// 策略3: 前缀匹配（拍摄订单编号包含后期订单编号）
	result3 := h.DB.Exec(`
		UPDATE shooting_orders so
		SET matched_order_id = o.id
		FROM orders o
		WHERE so.order_number LIKE o.order_number || '%'
		AND so.matched_order_id IS NULL
		AND LENGTH(o.order_number) >= 10
	`)
	if result3.Error == nil {
		prefixMatched = result3.RowsAffected
	}

	totalMatched := exactMatched + fuzzyMatched + prefixMatched

	c.JSON(http.StatusOK, gin.H{
		"message":       "智能匹配完成",
		"totalMatched":  totalMatched,
		"exactMatched":  exactMatched,
		"fuzzyMatched":  fuzzyMatched,
		"prefixMatched": prefixMatched,
	})
}
