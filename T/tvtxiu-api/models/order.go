package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ShootType 拍摄类型
type ShootType string

const (
	ShootTypeWedding  ShootType = "婚纱"
	ShootTypeCeremony ShootType = "婚礼"
)

// Order 订单模型
type Order struct {
	ID               uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	OrderNumber      string     `json:"orderNumber" gorm:"size:50;not null"`
	ShootDate        string     `json:"shootDate" gorm:"size:50"`
	ShootLocation    string     `json:"shootLocation" gorm:"size:100"`
	Photographer     string     `json:"photographer" gorm:"size:100"`
	Consultant       string     `json:"consultant" gorm:"size:50"`
	TotalCount       int        `json:"totalCount" gorm:"default:0"`
	ExtraCount       int        `json:"extraCount" gorm:"default:0"`
	HasProduct       bool       `json:"hasProduct" gorm:"default:false"`
	TrialDeadline    *time.Time `json:"trialDeadline"`
	FinalDeadline    *time.Time `json:"finalDeadline"`
	WeddingDate      string     `json:"weddingDate" gorm:"size:50"`
	IsRepeatCustomer bool       `json:"isRepeatCustomer" gorm:"default:false"`
	Requirements     string     `json:"requirements" gorm:"type:text"`
	PanLink          string     `json:"panLink" gorm:"type:text"`
	PanCode          string     `json:"panCode" gorm:"size:20"`
	AssignedTo       *uuid.UUID `json:"assignedTo" gorm:"type:uuid"`
	AssignedAt       *time.Time `json:"assignedAt"`
	Remarks          string     `json:"remarks" gorm:"type:text"`
	RemarksHistory   string     `json:"remarksHistory" gorm:"type:text"` // JSON array of timestamps
	IsCompleted      bool       `json:"isCompleted" gorm:"default:false"`
	CompletedAt      *time.Time `json:"completedAt"`
	ShootType        ShootType  `json:"shootType" gorm:"size:20;default:'婚纱'"`
	IsInGroup        bool       `json:"isInGroup" gorm:"default:true"`
	IsUrgent         bool       `json:"isUrgent" gorm:"default:false"`
	IsComplaint      bool       `json:"isComplaint" gorm:"default:false"`
	IsArchived       bool       `json:"isArchived" gorm:"default:false"`
	ArchiveMonth     string     `json:"archiveMonth" gorm:"size:7"`
	CreatedBy        *uuid.UUID `json:"createdBy" gorm:"type:uuid"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`

	// 关联
	AssignedUser *User `json:"assignedUser,omitempty" gorm:"foreignKey:AssignedTo"`
	Creator      *User `json:"creator,omitempty" gorm:"foreignKey:CreatedBy"`
}

// BeforeCreate 创建前生成 UUID
func (o *Order) BeforeCreate(tx *gorm.DB) error {
	if o.ID == uuid.Nil {
		o.ID = uuid.New()
	}
	return nil
}

// PerformanceMultiplier 类型绩效系数
func (s ShootType) PerformanceMultiplier() float64 {
	if s == ShootTypeCeremony {
		return 0.8
	}
	return 1.0
}

// PerformancePerPhoto 计算单张绩效
func (o *Order) PerformancePerPhoto(baseRate float64) float64 {
	rate := baseRate

	// 加急或投诉加成（二选一，投诉优先）
	if o.IsComplaint {
		rate += 8.0
	} else if o.IsUrgent {
		rate += 5.0
	} else if o.IsInGroup {
		// 只有没有加急/投诉时，进群才生效
		rate += 2.0
	}

	// 婚礼类型打折
	rate *= o.ShootType.PerformanceMultiplier()

	return rate
}

// TotalPerformance 计算订单总绩效
func (o *Order) TotalPerformance(baseRate float64) float64 {
	return o.PerformancePerPhoto(baseRate) * float64(o.TotalCount)
}
