package scheduler

import (
	"log"
	"time"

	"tvtxiu-api/database"
	"tvtxiu-api/models"
)

// 保留归档订单的月数（超过此时间迁移到历史表）
const ArchiveRetentionMonths = 12

// StartScheduler 启动定时任务
func StartScheduler() {
	// 归档迁移任务
	go func() {
		// 启动时先执行一次迁移
		migrateOldArchivedOrders()

		// 创建定时器，每天凌晨 3 点检查
		for {
			now := time.Now()
			// 计算下一个凌晨 3 点
			nextRun := time.Date(now.Year(), now.Month(), now.Day(), 3, 0, 0, 0, now.Location())
			if nextRun.Before(now) {
				nextRun = nextRun.Add(24 * time.Hour)
			}

			duration := nextRun.Sub(now)
			log.Printf("[Scheduler] 下次迁移任务将在 %v 后执行 (%s)", duration.Round(time.Minute), nextRun.Format("2006-01-02 15:04"))

			time.Sleep(duration)
			migrateOldArchivedOrders()
		}
	}()

	// 腾讯文档同步任务（每6小时）
	go func() {
		// 启动后等待1分钟再开始
		time.Sleep(1 * time.Minute)

		for {
			syncTencentDocs()

			// 等待6小时
			log.Println("[Scheduler] 下次腾讯文档同步将在 6 小时后执行")
			time.Sleep(6 * time.Hour)
		}
	}()
}

// syncTencentDocs 同步腾讯文档数据
func syncTencentDocs() {
	log.Println("[Scheduler] 开始同步腾讯文档...")

	var config models.SyncConfig
	if err := database.DB.Where("is_enabled = ?", true).First(&config).Error; err != nil {
		log.Println("[Scheduler] 腾讯文档同步未启用或未配置")
		return
	}

	// 这里调用同步服务
	// 注意：实际同步逻辑在 SyncHandler.runSync 中
	// 这里只是触发检查，避免循环依赖
	log.Printf("[Scheduler] 腾讯文档同步配置已找到，同步年份: %d", config.SyncYear)
}

// migrateOldArchivedOrders 将超过保留期限的归档订单迁移到历史表
func migrateOldArchivedOrders() {
	log.Println("[Scheduler] 开始检查待迁移的归档订单...")

	// 计算截止日期（12 个月前）
	cutoffDate := time.Now().AddDate(0, -ArchiveRetentionMonths, 0)
	cutoffMonth := cutoffDate.Format("2006-01") // 格式如 "2024-01"

	// 查找需要迁移的订单
	var ordersToMigrate []models.Order
	if err := database.DB.Where(
		"is_archived = ? AND archive_month < ? AND archive_month != ''",
		true,
		cutoffMonth,
	).Find(&ordersToMigrate).Error; err != nil {
		log.Printf("[Scheduler] 查询待迁移订单失败: %v", err)
		return
	}

	if len(ordersToMigrate) == 0 {
		log.Println("[Scheduler] 没有需要迁移的归档订单")
		return
	}

	log.Printf("[Scheduler] 找到 %d 条待迁移订单", len(ordersToMigrate))

	migratedCount := 0
	failedCount := 0
	now := time.Now()

	for _, order := range ordersToMigrate {
		// 创建历史订单记录
		archiveOrder := models.OrderArchive{
			ID:                  order.ID,
			OrderNumber:         order.OrderNumber,
			ShootDate:           order.ShootDate,
			ShootLocation:       order.ShootLocation,
			Photographer:        order.Photographer,
			Consultant:          order.Consultant,
			TotalCount:          order.TotalCount,
			ExtraCount:          order.ExtraCount,
			HasProduct:          order.HasProduct,
			TrialDeadline:       order.TrialDeadline,
			FinalDeadline:       order.FinalDeadline,
			WeddingDate:         order.WeddingDate,
			IsRepeatCustomer:    order.IsRepeatCustomer,
			Requirements:        order.Requirements,
			PanLink:             order.PanLink,
			PanCode:             order.PanCode,
			AssignedTo:          order.AssignedTo,
			AssignedAt:          order.AssignedAt,
			Remarks:             order.Remarks,
			RemarksHistory:      order.RemarksHistory,
			IsCompleted:         order.IsCompleted,
			CompletedAt:         order.CompletedAt,
			ShootType:           order.ShootType,
			IsInGroup:           order.IsInGroup,
			IsUrgent:            order.IsUrgent,
			IsComplaint:         order.IsComplaint,
			IsArchived:          order.IsArchived,
			ArchiveMonth:        order.ArchiveMonth,
			CreatedBy:           order.CreatedBy,
			CreatedAt:           order.CreatedAt,
			UpdatedAt:           order.UpdatedAt,
			ArchivedToHistoryAt: now,
		}

		// 使用事务：先插入历史表，再从主表删除
		tx := database.DB.Begin()

		if err := tx.Create(&archiveOrder).Error; err != nil {
			tx.Rollback()
			log.Printf("[Scheduler] 迁移订单 %s 失败（插入历史表）: %v", order.OrderNumber, err)
			failedCount++
			continue
		}

		if err := tx.Delete(&order).Error; err != nil {
			tx.Rollback()
			log.Printf("[Scheduler] 迁移订单 %s 失败（删除主表）: %v", order.OrderNumber, err)
			failedCount++
			continue
		}

		tx.Commit()
		migratedCount++
	}

	log.Printf("[Scheduler] 迁移完成: 成功 %d 条, 失败 %d 条", migratedCount, failedCount)
}
