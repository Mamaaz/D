package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// OrderArchive 历史订单模型（冷数据）
// 结构与 Order 完全相同，用于存储超过保留期限的归档订单
type OrderArchive struct {
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
	RemarksHistory   string     `json:"remarksHistory" gorm:"type:text"`
	IsCompleted      bool       `json:"isCompleted" gorm:"default:false"`
	CompletedAt      *time.Time `json:"completedAt"`
	ShootType        ShootType  `json:"shootType" gorm:"size:20;default:'婚纱'"`
	IsInGroup        bool       `json:"isInGroup" gorm:"default:true"`
	IsUrgent         bool       `json:"isUrgent" gorm:"default:false"`
	IsComplaint      bool       `json:"isComplaint" gorm:"default:false"`
	IsArchived       bool       `json:"isArchived" gorm:"default:true"`
	ArchiveMonth     string     `json:"archiveMonth" gorm:"size:7"`
	CreatedBy        *uuid.UUID `json:"createdBy" gorm:"type:uuid"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`
	// 迁移时间
	ArchivedToHistoryAt time.Time `json:"archivedToHistoryAt"`

	// 关联
	AssignedUser *User `json:"assignedUser,omitempty" gorm:"foreignKey:AssignedTo"`
	Creator      *User `json:"creator,omitempty" gorm:"foreignKey:CreatedBy"`
}

// BeforeCreate 创建前保持原 UUID
func (o *OrderArchive) BeforeCreate(tx *gorm.DB) error {
	// 历史订单保持原 ID，不生成新的
	return nil
}

// TableName 指定表名
func (OrderArchive) TableName() string {
	return "orders_archive"
}

// ToOrder 转换为 Order 结构（用于统计等场景）
func (o *OrderArchive) ToOrder() Order {
	return Order{
		ID:               o.ID,
		OrderNumber:      o.OrderNumber,
		ShootDate:        o.ShootDate,
		ShootLocation:    o.ShootLocation,
		Photographer:     o.Photographer,
		Consultant:       o.Consultant,
		TotalCount:       o.TotalCount,
		ExtraCount:       o.ExtraCount,
		HasProduct:       o.HasProduct,
		TrialDeadline:    o.TrialDeadline,
		FinalDeadline:    o.FinalDeadline,
		WeddingDate:      o.WeddingDate,
		IsRepeatCustomer: o.IsRepeatCustomer,
		Requirements:     o.Requirements,
		PanLink:          o.PanLink,
		PanCode:          o.PanCode,
		AssignedTo:       o.AssignedTo,
		AssignedAt:       o.AssignedAt,
		Remarks:          o.Remarks,
		RemarksHistory:   o.RemarksHistory,
		IsCompleted:      o.IsCompleted,
		CompletedAt:      o.CompletedAt,
		ShootType:        o.ShootType,
		IsInGroup:        o.IsInGroup,
		IsUrgent:         o.IsUrgent,
		IsComplaint:      o.IsComplaint,
		IsArchived:       o.IsArchived,
		ArchiveMonth:     o.ArchiveMonth,
		CreatedBy:        o.CreatedBy,
		CreatedAt:        o.CreatedAt,
		UpdatedAt:        o.UpdatedAt,
	}
}
