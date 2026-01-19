package handlers

import (
	"net/http"
	"strconv"
	"time"

	"tvtxiu-api/database"
	"tvtxiu-api/middleware"
	"tvtxiu-api/models"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// OrderListResponse 订单列表响应
type OrderListResponse struct {
	Orders []models.Order `json:"orders"`
	Total  int64          `json:"total"`
	Limit  int            `json:"limit"`
	Offset int            `json:"offset"`
}

// GetOrders 获取订单列表
func GetOrders(c *gin.Context) {
	// 分页参数
	limitStr := c.DefaultQuery("limit", "50")
	offsetStr := c.DefaultQuery("offset", "0")
	limit, _ := strconv.Atoi(limitStr)
	offset, _ := strconv.Atoi(offsetStr)

	userID, _ := middleware.GetCurrentUserID(c)
	isAdmin := middleware.IsAdmin(c)

	query := database.DB.Model(&models.Order{}).Preload("AssignedUser")

	// 非管理员只能看自己的订单
	if !isAdmin {
		query = query.Where("assigned_to = ?", userID)
	}

	// 筛选条件
	if completed := c.Query("completed"); completed != "" {
		if completed == "true" {
			query = query.Where("is_completed = ?", true)
		} else {
			query = query.Where("is_completed = ?", false)
		}
	}

	if archived := c.Query("archived"); archived != "" {
		if archived == "true" {
			query = query.Where("is_archived = ?", true)
		} else {
			query = query.Where("is_archived = ?", false)
		}
	}

	if month := c.Query("month"); month != "" {
		query = query.Where("archive_month = ?", month)
	}

	// 计算总数（在分页之前）
	var total int64
	query.Count(&total)

	// 应用排序（紧急截止日期优先）
	query = query.Order("CASE WHEN is_completed = false AND final_deadline IS NOT NULL THEN 0 ELSE 1 END, final_deadline ASC, created_at DESC")

	// 应用分页
	if limit > 0 {
		query = query.Limit(limit).Offset(offset)
	}

	var orders []models.Order
	if err := query.Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取订单列表失败"})
		return
	}

	c.JSON(http.StatusOK, OrderListResponse{
		Orders: orders,
		Total:  total,
		Limit:  limit,
		Offset: offset,
	})
}

// GetOrder 获取单个订单
func GetOrder(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的订单 ID"})
		return
	}

	var order models.Order
	if err := database.DB.Preload("AssignedUser").First(&order, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	c.JSON(http.StatusOK, order)
}

// CreateOrder 创建订单
func CreateOrder(c *gin.Context) {
	var order models.Order
	if err := c.ShouldBindJSON(&order); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	userID, _ := middleware.GetCurrentUserID(c)
	order.CreatedBy = &userID

	if order.ShootType == "" {
		order.ShootType = models.ShootTypeWedding
	}

	if err := database.DB.Create(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建订单失败"})
		return
	}

	// 创建订单时自动匹配拍摄订单
	if order.AssignedTo != nil {
		syncShootingOrderMatch(order)
	}

	c.JSON(http.StatusCreated, order)
}

// UpdateOrder 更新订单
func UpdateOrder(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的订单 ID"})
		return
	}

	var order models.Order
	if err := database.DB.First(&order, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	// 记录更新前的分配状态
	wasAssigned := order.AssignedTo != nil

	// 已归档的订单只有管理员能修改
	if order.IsArchived && !middleware.IsAdmin(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "已归档订单只有管理员可以修改"})
		return
	}

	if err := c.ShouldBindJSON(&order); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	order.ID = id // 确保 ID 不变
	if err := database.DB.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新订单失败"})
		return
	}

	// 自动同步匹配拍摄订单：当订单被分配后期人员时
	if order.AssignedTo != nil && (!wasAssigned || order.OrderNumber != "") {
		syncShootingOrderMatch(order)
	}

	c.JSON(http.StatusOK, order)
}

// syncShootingOrderMatch 同步拍摄订单匹配状态
func syncShootingOrderMatch(order models.Order) {
	if order.OrderNumber == "" {
		return
	}

	// 查找匹配的拍摄订单（按订单编号）
	database.DB.Model(&models.ShootingOrder{}).
		Where("order_number = ?", order.OrderNumber).
		Update("matched_order_id", order.ID)
}

// DeleteOrder 删除订单
func DeleteOrder(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的订单 ID"})
		return
	}

	if err := database.DB.Delete(&models.Order{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除订单失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "订单已删除"})
}

// CompleteOrder 标记订单完成
func CompleteOrder(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的订单 ID"})
		return
	}

	var order models.Order
	if err := database.DB.First(&order, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	// 检查权限（管理员或订单负责人）
	userID, _ := middleware.GetCurrentUserID(c)
	if !middleware.IsAdmin(c) && (order.AssignedTo == nil || *order.AssignedTo != userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "权限不足"})
		return
	}

	now := time.Now()
	order.IsCompleted = true
	order.CompletedAt = &now

	if err := database.DB.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新订单失败"})
		return
	}

	c.JSON(http.StatusOK, order)
}

// ArchiveOrder 归档订单
func ArchiveOrder(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的订单 ID"})
		return
	}

	var order models.Order
	if err := database.DB.First(&order, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	// 检查权限（管理员或订单负责人）
	userID, _ := middleware.GetCurrentUserID(c)
	if !middleware.IsAdmin(c) && (order.AssignedTo == nil || *order.AssignedTo != userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "权限不足"})
		return
	}

	now := time.Now()
	order.IsArchived = true
	order.ArchiveMonth = now.Format("2006-01")

	if err := database.DB.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "归档订单失败"})
		return
	}

	c.JSON(http.StatusOK, order)
}

// UnarchiveOrder 取消归档
func UnarchiveOrder(c *gin.Context) {
	// 只有管理员可以操作
	if !middleware.IsAdmin(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "只有管理员可以取消归档"})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的订单 ID"})
		return
	}

	var order models.Order
	if err := database.DB.First(&order, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	order.IsArchived = false
	order.ArchiveMonth = ""

	if err := database.DB.Save(&order).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "取消归档失败"})
		return
	}

	c.JSON(http.StatusOK, order)
}

// HistoryOrderListResponse 历史订单列表响应
type HistoryOrderListResponse struct {
	Orders []models.OrderArchive `json:"orders"`
	Total  int64                 `json:"total"`
}

// GetHistoryOrders 获取历史订单（从 orders_archive 表查询）
func GetHistoryOrders(c *gin.Context) {
	userID, _ := middleware.GetCurrentUserID(c)
	isAdmin := middleware.IsAdmin(c)

	query := database.DB.Model(&models.OrderArchive{}).Preload("AssignedUser")

	// 非管理员只能看自己的订单
	if !isAdmin {
		query = query.Where("assigned_to = ?", userID)
	}

	// 年份筛选（可选）
	if year := c.Query("year"); year != "" {
		query = query.Where("archive_month LIKE ?", year+"%")
	}

	// 月份筛选（可选）
	if month := c.Query("month"); month != "" {
		query = query.Where("archive_month = ?", month)
	}

	var total int64
	query.Count(&total)

	var orders []models.OrderArchive
	if err := query.Order("archive_month DESC, created_at DESC").Find(&orders).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取历史订单失败"})
		return
	}

	c.JSON(http.StatusOK, HistoryOrderListResponse{
		Orders: orders,
		Total:  total,
	})
}
