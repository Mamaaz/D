package handlers

import (
	"net/http"
	"time"

	"tvtxiu-api/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// StatisticsHandler 统计处理器
type StatisticsHandler struct {
	DB *gorm.DB
}

// NewStatisticsHandler 创建统计处理器
func NewStatisticsHandler(db *gorm.DB) *StatisticsHandler {
	return &StatisticsHandler{DB: db}
}

// DepartmentOverview 部门概览
type DepartmentOverview struct {
	Name           string  `json:"name"`
	DisplayName    string  `json:"display_name"`
	Icon           string  `json:"icon"`
	TodayOrders    int     `json:"today_orders"`
	PendingCount   int     `json:"pending_count"`
	CompletionRate float64 `json:"completion_rate"`
	AlertCount     int     `json:"alert_count"`
	IsActive       bool    `json:"is_active"`
}

// GetOverview 获取所有部门概览
func (h *StatisticsHandler) GetOverview(c *gin.Context) {
	today := time.Now().Truncate(24 * time.Hour)

	// 后期部门统计
	var todayOrders int64
	var pendingCount int64
	var completedCount int64
	var alertCount int64

	h.DB.Model(&models.Order{}).Where("created_at >= ?", today).Count(&todayOrders)
	h.DB.Model(&models.Order{}).Where("is_completed = ?", false).Where("is_archived = ?", false).Count(&pendingCount)
	h.DB.Model(&models.Order{}).Where("is_completed = ?", true).Count(&completedCount)

	// 延迟预警：试修或结片日期已过但未完成
	h.DB.Model(&models.Order{}).
		Where("is_completed = ?", false).
		Where("is_archived = ?", false).
		Where("(trial_deadline < ? OR final_deadline < ?)", time.Now(), time.Now()).
		Count(&alertCount)

	var total int64
	h.DB.Model(&models.Order{}).Where("is_archived = ?", false).Count(&total)

	completionRate := 0.0
	if total > 0 {
		completionRate = float64(completedCount) / float64(total)
	}

	departments := []DepartmentOverview{
		{
			Name:           "post-production",
			DisplayName:    "后期部门",
			Icon:           "photo.stack.fill",
			TodayOrders:    int(todayOrders),
			PendingCount:   int(pendingCount),
			CompletionRate: completionRate,
			AlertCount:     int(alertCount),
			IsActive:       true,
		},
		{
			Name:        "sales",
			DisplayName: "销售部门",
			Icon:        "dollarsign.circle.fill",
			IsActive:    false,
		},
		{
			Name:        "photography",
			DisplayName: "摄影部门",
			Icon:        "camera.fill",
			IsActive:    false,
		},
		{
			Name:        "editing",
			DisplayName: "剪辑部门",
			Icon:        "film.stack.fill",
			IsActive:    false,
		},
	}

	c.JSON(http.StatusOK, gin.H{"departments": departments})
}

// PostProductionStats 后期部门详细统计
type PostProductionStats struct {
	TotalOrders     int     `json:"total_orders"`
	CompletedOrders int     `json:"completed_orders"`
	CompletionRate  float64 `json:"completion_rate"`
	AlertCount      int     `json:"alert_count"`
	TotalPhotos     int     `json:"total_photos"`
	CompletedPhotos int     `json:"completed_photos"`
}

// GetDepartmentStats 获取部门详细统计
func (h *StatisticsHandler) GetDepartmentStats(c *gin.Context) {
	name := c.Param("name")
	period := c.DefaultQuery("period", "today")

	if name != "post-production" {
		c.JSON(http.StatusOK, PostProductionStats{})
		return
	}

	var startDate time.Time
	now := time.Now()

	switch period {
	case "today":
		startDate = now.Truncate(24 * time.Hour)
	case "week":
		startDate = now.AddDate(0, 0, -7)
	case "month":
		startDate = now.AddDate(0, -1, 0)
	default:
		startDate = now.Truncate(24 * time.Hour)
	}

	var totalOrders int64
	var completedOrders int64
	var alertCount int64

	query := h.DB.Model(&models.Order{}).Where("created_at >= ?", startDate)
	query.Count(&totalOrders)

	h.DB.Model(&models.Order{}).
		Where("created_at >= ?", startDate).
		Where("is_completed = ?", true).
		Count(&completedOrders)

	h.DB.Model(&models.Order{}).
		Where("is_completed = ?", false).
		Where("is_archived = ?", false).
		Where("(trial_deadline < ? OR final_deadline < ?)", now, now).
		Count(&alertCount)

	// 计算总张数
	var totalPhotos int64
	var completedPhotos int64

	h.DB.Model(&models.Order{}).
		Where("created_at >= ?", startDate).
		Select("COALESCE(SUM(total_count), 0)").
		Scan(&totalPhotos)

	h.DB.Model(&models.Order{}).
		Where("created_at >= ?", startDate).
		Where("is_completed = ?", true).
		Select("COALESCE(SUM(total_count), 0)").
		Scan(&completedPhotos)

	completionRate := 0.0
	if totalOrders > 0 {
		completionRate = float64(completedOrders) / float64(totalOrders)
	}

	c.JSON(http.StatusOK, PostProductionStats{
		TotalOrders:     int(totalOrders),
		CompletedOrders: int(completedOrders),
		CompletionRate:  completionRate,
		AlertCount:      int(alertCount),
		TotalPhotos:     int(totalPhotos),
		CompletedPhotos: int(completedPhotos),
	})
}

// StaffRankingItem 人员排行项
type StaffRankingItem struct {
	UserID         string  `json:"user_id"`
	Name           string  `json:"name"`
	PhotoCount     int     `json:"photo_count"`
	OrderCount     int     `json:"order_count"`
	CompletionRate float64 `json:"completion_rate"`
}

// GetStaffRanking 获取人员工作量排行
func (h *StatisticsHandler) GetStaffRanking(c *gin.Context) {
	period := c.DefaultQuery("period", "month")

	var startDate time.Time
	now := time.Now()

	switch period {
	case "today":
		startDate = now.Truncate(24 * time.Hour)
	case "week":
		startDate = now.AddDate(0, 0, -7)
	case "month":
		startDate = now.AddDate(0, -1, 0)
	default:
		startDate = now.AddDate(0, -1, 0)
	}

	type RankResult struct {
		AssignedTo     string
		PhotoCount     int
		OrderCount     int
		CompletedCount int
	}

	var results []RankResult

	h.DB.Model(&models.Order{}).
		Select("assigned_to, SUM(total_count) as photo_count, COUNT(*) as order_count, SUM(CASE WHEN is_completed = true THEN 1 ELSE 0 END) as completed_count").
		Where("created_at >= ?", startDate).
		Where("assigned_to IS NOT NULL").
		Group("assigned_to").
		Order("photo_count DESC").
		Scan(&results)

	// 获取用户名
	var userIDs []string
	for _, r := range results {
		userIDs = append(userIDs, r.AssignedTo)
	}

	var users []models.User
	h.DB.Where("id IN ?", userIDs).Find(&users)

	userMap := make(map[string]string)
	for _, u := range users {
		name := u.Nickname
		if name == "" {
			name = u.Username
		}
		userMap[u.ID.String()] = name
	}

	var rankings []StaffRankingItem
	for _, r := range results {
		rate := 0.0
		if r.OrderCount > 0 {
			rate = float64(r.CompletedCount) / float64(r.OrderCount)
		}
		rankings = append(rankings, StaffRankingItem{
			UserID:         r.AssignedTo,
			Name:           userMap[r.AssignedTo],
			PhotoCount:     r.PhotoCount,
			OrderCount:     r.OrderCount,
			CompletionRate: rate,
		})
	}

	c.JSON(http.StatusOK, gin.H{"rankings": rankings})
}

// OrderAlertItem 订单预警项
type OrderAlertItem struct {
	OrderID     string `json:"order_id"`
	OrderNumber string `json:"order_number"`
	Deadline    string `json:"deadline"`
	DaysOverdue int    `json:"days_overdue"`
	AssignedTo  string `json:"assigned_to"`
}

// GetAlerts 获取延迟预警
func (h *StatisticsHandler) GetAlerts(c *gin.Context) {
	now := time.Now()

	var orders []models.Order
	h.DB.Where("is_completed = ?", false).
		Where("is_archived = ?", false).
		Where("(trial_deadline < ? OR final_deadline < ?)", now, now).
		Preload("AssignedUser").
		Order("final_deadline ASC").
		Limit(20).
		Find(&orders)

	var alerts []OrderAlertItem
	for _, o := range orders {
		deadline := o.FinalDeadline
		if deadline == nil {
			deadline = o.TrialDeadline
		}

		daysOverdue := 0
		if deadline != nil {
			daysOverdue = int(now.Sub(*deadline).Hours() / 24)
		}

		assignedName := ""
		if o.AssignedUser != nil {
			assignedName = o.AssignedUser.Nickname
			if assignedName == "" {
				assignedName = o.AssignedUser.Username
			}
		}

		deadlineStr := ""
		if deadline != nil {
			deadlineStr = deadline.Format(time.RFC3339)
		}

		alerts = append(alerts, OrderAlertItem{
			OrderID:     o.ID.String(),
			OrderNumber: o.OrderNumber,
			Deadline:    deadlineStr,
			DaysOverdue: daysOverdue,
			AssignedTo:  assignedName,
		})
	}

	c.JSON(http.StatusOK, gin.H{"alerts": alerts})
}
