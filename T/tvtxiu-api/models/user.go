package models

import (
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// UserRole 用户角色
type UserRole string

const (
	RoleAdmin     UserRole = "admin"
	RoleSubAdmin  UserRole = "sub_admin"
	RoleStaff     UserRole = "staff"
	RoleOutsource UserRole = "outsource" // 外包人员
	RoleBoss      UserRole = "boss"      // 老板/超级管理员
)

// User 用户模型
type User struct {
	ID           uuid.UUID `json:"id" gorm:"type:uuid;primaryKey"`
	Username     string    `json:"username" gorm:"uniqueIndex;size:50;not null"`
	PasswordHash string    `json:"-" gorm:"size:255;not null"`
	Nickname     string    `json:"nickname" gorm:"size:100"`
	RealName     string    `json:"realName" gorm:"size:100"`
	Role         UserRole  `json:"role" gorm:"size:20;default:'staff'"`

	// 绩效配置（每人独立配置）
	BasePrice         float64 `json:"basePrice" gorm:"default:8.0"`         // 基础单价 (元/张)
	GroupBonus        float64 `json:"groupBonus" gorm:"default:2.0"`        // 进群加项 (元)
	UrgentBonus       float64 `json:"urgentBonus" gorm:"default:5.0"`       // 加急加项 (元)
	ComplaintBonus    float64 `json:"complaintBonus" gorm:"default:8.0"`    // 投诉加项 (元)
	WeddingMultiplier float64 `json:"weddingMultiplier" gorm:"default:0.8"` // 婚礼系数

	// 兼容旧数据（已废弃，保留以便数据迁移）
	Level               string  `json:"level,omitempty" gorm:"size:20"`
	BasePerformanceRate float64 `json:"basePerformanceRate,omitempty"`

	// 日历颜色
	CalendarColorRed   float64 `json:"calendarColorRed" gorm:"default:0.23"`
	CalendarColorGreen float64 `json:"calendarColorGreen" gorm:"default:0.51"`
	CalendarColorBlue  float64 `json:"calendarColorBlue" gorm:"default:0.84"`

	AvatarURL string `json:"avatarUrl" gorm:"size:500"`

	// 人员状态（用于离职人员管理）
	IsHidden bool       `json:"isHidden" gorm:"default:false"` // 隐藏人员（离职）
	LeftAt   *time.Time `json:"leftAt"`                        // 离职时间

	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// BeforeCreate 创建前生成 UUID
func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.ID == uuid.Nil {
		u.ID = uuid.New()
	}
	return nil
}

// SetPassword 设置密码（加密）
func (u *User) SetPassword(password string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	u.PasswordHash = string(hash)
	return nil
}

// CheckPassword 验证密码
func (u *User) CheckPassword(password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password))
	return err == nil
}

// HasAdminPrivilege 是否有管理权限
func (u *User) HasAdminPrivilege() bool {
	return u.Role == RoleAdmin || u.Role == RoleSubAdmin
}

// IsRegularStaff 是否为普通员工（后期或外包）
func (u *User) IsRegularStaff() bool {
	return u.Role == RoleStaff || u.Role == RoleOutsource
}

// UserResponse 用户响应（不含密码）
type UserResponse struct {
	ID                 uuid.UUID  `json:"id"`
	Username           string     `json:"username"`
	Nickname           string     `json:"nickname"`
	RealName           string     `json:"realName"`
	Role               UserRole   `json:"role"`
	BasePrice          float64    `json:"basePrice"`
	GroupBonus         float64    `json:"groupBonus"`
	UrgentBonus        float64    `json:"urgentBonus"`
	ComplaintBonus     float64    `json:"complaintBonus"`
	WeddingMultiplier  float64    `json:"weddingMultiplier"`
	CalendarColorRed   float64    `json:"calendarColorRed"`
	CalendarColorGreen float64    `json:"calendarColorGreen"`
	CalendarColorBlue  float64    `json:"calendarColorBlue"`
	AvatarURL          string     `json:"avatarUrl"`
	IsHidden           bool       `json:"isHidden"`
	LeftAt             *time.Time `json:"leftAt"`
	CreatedAt          time.Time  `json:"createdAt"`
}

// ToResponse 转换为响应格式
func (u *User) ToResponse() UserResponse {
	return UserResponse{
		ID:                 u.ID,
		Username:           u.Username,
		Nickname:           u.Nickname,
		RealName:           u.RealName,
		Role:               u.Role,
		BasePrice:          u.BasePrice,
		GroupBonus:         u.GroupBonus,
		UrgentBonus:        u.UrgentBonus,
		ComplaintBonus:     u.ComplaintBonus,
		WeddingMultiplier:  u.WeddingMultiplier,
		CalendarColorRed:   u.CalendarColorRed,
		CalendarColorGreen: u.CalendarColorGreen,
		CalendarColorBlue:  u.CalendarColorBlue,
		AvatarURL:          u.AvatarURL,
		IsHidden:           u.IsHidden,
		LeftAt:             u.LeftAt,
		CreatedAt:          u.CreatedAt,
	}
}
