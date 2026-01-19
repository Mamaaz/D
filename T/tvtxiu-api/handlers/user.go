package handlers

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"tvtxiu-api/database"
	"tvtxiu-api/middleware"
	"tvtxiu-api/models"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// CreateUserRequest 创建用户请求
type CreateUserRequest struct {
	Username           string          `json:"username" binding:"required"`
	Password           string          `json:"password" binding:"required"`
	Nickname           string          `json:"nickname"`
	RealName           string          `json:"realName"`
	Role               models.UserRole `json:"role"`
	BasePrice          float64         `json:"basePrice"`
	GroupBonus         float64         `json:"groupBonus"`
	UrgentBonus        float64         `json:"urgentBonus"`
	ComplaintBonus     float64         `json:"complaintBonus"`
	WeddingMultiplier  float64         `json:"weddingMultiplier"`
	CalendarColorRed   float64         `json:"calendarColorRed"`
	CalendarColorGreen float64         `json:"calendarColorGreen"`
	CalendarColorBlue  float64         `json:"calendarColorBlue"`
}

// UpdateUserRequest 更新用户请求
type UpdateUserRequest struct {
	Username           *string          `json:"username"`
	Nickname           *string          `json:"nickname"`
	RealName           *string          `json:"realName"`
	Password           *string          `json:"password"`
	Role               *models.UserRole `json:"role"`
	BasePrice          *float64         `json:"basePrice"`
	GroupBonus         *float64         `json:"groupBonus"`
	UrgentBonus        *float64         `json:"urgentBonus"`
	ComplaintBonus     *float64         `json:"complaintBonus"`
	WeddingMultiplier  *float64         `json:"weddingMultiplier"`
	CalendarColorRed   *float64         `json:"calendarColorRed"`
	CalendarColorGreen *float64         `json:"calendarColorGreen"`
	CalendarColorBlue  *float64         `json:"calendarColorBlue"`
}

// GetUsers 获取所有用户
func GetUsers(c *gin.Context) {
	var users []models.User
	if err := database.DB.Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取用户列表失败"})
		return
	}

	response := make([]models.UserResponse, len(users))
	for i, user := range users {
		response[i] = user.ToResponse()
	}

	c.JSON(http.StatusOK, response)
}

// GetUser 获取单个用户
func GetUser(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户 ID"})
		return
	}

	var user models.User
	if err := database.DB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	c.JSON(http.StatusOK, user.ToResponse())
}

// CreateUser 创建用户
func CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	user := models.User{
		Username:           req.Username,
		Nickname:           req.Nickname,
		RealName:           req.RealName,
		Role:               req.Role,
		BasePrice:          req.BasePrice,
		GroupBonus:         req.GroupBonus,
		UrgentBonus:        req.UrgentBonus,
		ComplaintBonus:     req.ComplaintBonus,
		WeddingMultiplier:  req.WeddingMultiplier,
		CalendarColorRed:   req.CalendarColorRed,
		CalendarColorGreen: req.CalendarColorGreen,
		CalendarColorBlue:  req.CalendarColorBlue,
	}

	if user.Role == "" {
		user.Role = models.RoleStaff
	}
	// 设置默认绩效配置
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

	if err := user.SetPassword(req.Password); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码加密失败"})
		return
	}

	if err := database.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建用户失败"})
		return
	}

	c.JSON(http.StatusCreated, user.ToResponse())
}

// UpdateUser 更新用户
func UpdateUser(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户 ID"})
		return
	}

	var user models.User
	if err := database.DB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	var req UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	// 更新字段
	if req.Username != nil && *req.Username != "" {
		// 检查用户名是否已存在
		var existingUser models.User
		if err := database.DB.Where("username = ? AND id != ?", *req.Username, id).First(&existingUser).Error; err == nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "用户名已存在"})
			return
		}
		user.Username = *req.Username
	}
	if req.Nickname != nil {
		user.Nickname = *req.Nickname
	}
	if req.RealName != nil {
		user.RealName = *req.RealName
	}
	if req.Password != nil {
		user.SetPassword(*req.Password)
	}
	if req.Role != nil {
		user.Role = *req.Role
	}
	// 绩效配置
	if req.BasePrice != nil {
		user.BasePrice = *req.BasePrice
	}
	if req.GroupBonus != nil {
		user.GroupBonus = *req.GroupBonus
	}
	if req.UrgentBonus != nil {
		user.UrgentBonus = *req.UrgentBonus
	}
	if req.ComplaintBonus != nil {
		user.ComplaintBonus = *req.ComplaintBonus
	}
	if req.WeddingMultiplier != nil {
		user.WeddingMultiplier = *req.WeddingMultiplier
	}
	// 日历颜色
	if req.CalendarColorRed != nil {
		user.CalendarColorRed = *req.CalendarColorRed
	}
	if req.CalendarColorGreen != nil {
		user.CalendarColorGreen = *req.CalendarColorGreen
	}
	if req.CalendarColorBlue != nil {
		user.CalendarColorBlue = *req.CalendarColorBlue
	}

	if err := database.DB.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新用户失败"})
		return
	}

	c.JSON(http.StatusOK, user.ToResponse())
}

// DeleteUser 删除用户
func DeleteUser(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户 ID"})
		return
	}

	// 检查是否是自己
	currentUserID, _ := middleware.GetCurrentUserID(c)
	if id == currentUserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不能删除自己"})
		return
	}

	// 检查是否有关联订单
	var orderCount int64
	database.DB.Model(&models.Order{}).Where("assigned_to = ?", id).Count(&orderCount)
	if orderCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":      fmt.Sprintf("该用户有 %d 条关联订单，无法删除。建议使用「隐藏」功能", orderCount),
			"orderCount": orderCount,
		})
		return
	}

	if err := database.DB.Delete(&models.User{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除用户失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "用户已删除"})
}

// HideUser 隐藏用户（离职）
func HideUser(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户 ID"})
		return
	}

	var user models.User
	if err := database.DB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	// 不能隐藏管理员
	if user.Role == models.RoleAdmin || user.Role == models.RoleBoss {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不能隐藏管理员"})
		return
	}

	// 设置隐藏状态和离职时间
	now := time.Now()
	user.IsHidden = true
	user.LeftAt = &now

	if err := database.DB.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "隐藏用户失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("用户「%s」已隐藏", user.Nickname),
		"user":    user.ToResponse(),
	})
}

// UnhideUser 取消隐藏用户
func UnhideUser(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户 ID"})
		return
	}

	var user models.User
	if err := database.DB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	// 取消隐藏
	user.IsHidden = false
	user.LeftAt = nil

	if err := database.DB.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "取消隐藏失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("用户「%s」已恢复显示", user.Nickname),
		"user":    user.ToResponse(),
	})
}

// UploadAvatar 上传用户头像 (仅管理员)
func UploadAvatar(c *gin.Context) {
	// 检查权限
	currentUser, exists := middleware.GetCurrentUser(c)
	if !exists || !currentUser.HasAdminPrivilege() {
		c.JSON(http.StatusForbidden, gin.H{"error": "只有管理员可以更换头像"})
		return
	}

	// 获取目标用户 ID
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户 ID"})
		return
	}

	var user models.User
	if err := database.DB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	// 获取上传的文件
	file, err := c.FormFile("avatar")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请选择头像文件"})
		return
	}

	// 验证文件类型
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".gif" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "只支持 jpg, jpeg, png, gif 格式"})
		return
	}

	// 验证文件大小 (最大 5MB)
	if file.Size > 5*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "文件大小不能超过 5MB"})
		return
	}

	// 创建上传目录
	uploadDir := "./uploads/avatars"
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建上传目录失败"})
		return
	}

	// 生成唯一文件名
	filename := fmt.Sprintf("%s_%d%s", id.String(), time.Now().Unix(), ext)
	filepath := filepath.Join(uploadDir, filename)

	// 保存文件
	if err := c.SaveUploadedFile(file, filepath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存文件失败"})
		return
	}

	// 删除旧头像文件
	if user.AvatarURL != "" {
		oldPath := "." + user.AvatarURL
		os.Remove(oldPath)
	}

	// 更新用户头像 URL
	user.AvatarURL = "/uploads/avatars/" + filename
	if err := database.DB.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新用户头像失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "头像上传成功",
		"avatarUrl": user.AvatarURL,
	})
}
