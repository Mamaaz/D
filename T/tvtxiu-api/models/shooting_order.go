package models

import (
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ShootingOrder 拍摄订单（来自腾讯文档）
type ShootingOrder struct {
	ID             uuid.UUID  `json:"id" gorm:"type:uuid;primary_key"`
	OrderNumber    string     `json:"orderNumber" gorm:"index"`                                // 订单编号（如 CS0620250914A）
	ShootYear      int        `json:"shootYear" gorm:"index"`                                  // 拍摄年份
	ShootMonth     int        `json:"shootMonth" gorm:"index"`                                 // 拍摄月份
	ShootDay       string     `json:"shootDay"`                                                // 拍摄日（支持 "8" 或 "3-4"）
	ShootDate      *time.Time `json:"shootDate"`                                               // 合并后的拍摄日期（取第一天）
	Location       string     `json:"location"`                                                // 地点
	Country        string     `json:"country"`                                                 // 国家
	OrderType      string     `json:"orderType"`                                               // 类型（纱/礼/商业等）
	Photographer   string     `json:"photographer"`                                            // 摄影师
	Sales          string     `json:"sales"`                                                   // 销售
	Consultant     string     `json:"consultant"`                                              // 顾问
	PostProducer   string     `json:"postProducer"`                                            // 后期师
	RawData        string     `json:"rawData" gorm:"type:text"`                                // 原始行数据（JSON）
	SyncedAt       time.Time  `json:"syncedAt"`                                                // 同步时间
	MatchedOrderID *uuid.UUID `json:"matchedOrderId" gorm:"type:uuid"`                         // 匹配的后期订单ID
	MatchedOrder   *Order     `json:"matchedOrder,omitempty" gorm:"foreignKey:MatchedOrderID"` // 关联的后期订单
	CreatedAt      time.Time  `json:"createdAt"`
	UpdatedAt      time.Time  `json:"updatedAt"`
}

// BeforeCreate 创建前生成 UUID
func (s *ShootingOrder) BeforeCreate() error {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	s.CreatedAt = time.Now()
	s.UpdatedAt = time.Now()
	return nil
}

// BeforeUpdate 更新前更新时间
func (s *ShootingOrder) BeforeUpdate() error {
	s.UpdatedAt = time.Now()
	return nil
}

// ComputeShootDate 计算拍摄日期（取第一天）
func (s *ShootingOrder) ComputeShootDate() {
	if s.ShootYear > 0 && s.ShootMonth > 0 && s.ShootDay != "" {
		// 提取第一个日期数字（如 "3-4" -> 3, "8" -> 8）
		dayStr := s.ShootDay
		if idx := strings.Index(dayStr, "-"); idx > 0 {
			dayStr = dayStr[:idx]
		}
		if idx := strings.Index(dayStr, "、"); idx > 0 {
			dayStr = dayStr[:idx]
		}
		day, err := strconv.Atoi(strings.TrimSpace(dayStr))
		if err == nil && day > 0 && day <= 31 {
			date := time.Date(s.ShootYear, time.Month(s.ShootMonth), day, 0, 0, 0, 0, time.Local)
			s.ShootDate = &date
		}
	}
}

// SyncStatus 同步状态
type SyncStatus struct {
	LastSyncAt  *time.Time `json:"lastSyncAt"`
	TotalSynced int        `json:"totalSynced"`
	LastError   string     `json:"lastError,omitempty"`
	IsRunning   bool       `json:"isRunning"`
	NextSyncAt  *time.Time `json:"nextSyncAt"`
}

// SyncConfig 同步配置
type SyncConfig struct {
	ID        uuid.UUID `json:"id" gorm:"type:uuid;primary_key"`
	DocURL    string    `json:"docUrl"`             // 腾讯文档URL
	TabID     string    `json:"tabId"`              // 表格Tab ID
	Cookie    string    `json:"-" gorm:"type:text"` // Cookie（不返回给前端）
	SyncYear  int       `json:"syncYear"`           // 同步年份
	IsEnabled bool      `json:"isEnabled"`          // 是否启用自动同步
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// BeforeCreate 创建前生成 UUID
func (c *SyncConfig) BeforeCreate() error {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	c.CreatedAt = time.Now()
	c.UpdatedAt = time.Now()
	return nil
}

// ShootingStats 拍摄统计
type ShootingStats struct {
	Year           int `json:"year"`
	Month          int `json:"month,omitempty"`
	TotalShooting  int `json:"totalShooting"`  // 拍摄订单总数
	TotalAssigned  int `json:"totalAssigned"`  // 已分配后期
	TotalCompleted int `json:"totalCompleted"` // 已完成
	TotalPending   int `json:"totalPending"`   // 待分配（拍摄了但没分配后期）
}
