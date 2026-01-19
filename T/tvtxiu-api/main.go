package main

import (
	"log"

	"tvtxiu-api/config"
	"tvtxiu-api/database"
	"tvtxiu-api/handlers"
	"tvtxiu-api/middleware"
	"tvtxiu-api/models"
	"tvtxiu-api/scheduler"

	"github.com/gin-contrib/gzip"
	"github.com/gin-gonic/gin"
)

func main() {
	// 加载配置
	cfg := config.Load()

	// 设置 JWT 密钥
	middleware.JWTSecret = []byte(cfg.JWTSecret)

	// 连接数据库
	if err := database.Connect(cfg.DatabaseURL); err != nil {
		log.Fatalf("Database connection failed: %v", err)
	}

	// 自动迁移（包含历史订单表和拍摄订单表）
	if err := database.AutoMigrate(&models.User{}, &models.Order{}, &models.OrderArchive{}, &models.ShootingOrder{}, &models.SyncConfig{}); err != nil {
		log.Fatalf("Database migration failed: %v", err)
	}

	// 创建默认管理员用户
	createDefaultAdmin()

	// 启动定时任务（自动清理旧归档订单）
	scheduler.StartScheduler()

	// 创建 Gin 路由
	r := gin.Default()

	// Gzip 压缩（提升 API 响应性能）
	r.Use(gzip.Gzip(gzip.DefaultCompression))

	// CORS 中间件
	r.Use(corsMiddleware())

	// 静态文件服务 - 头像
	r.Static("/uploads", "./uploads")

	// 公开路由
	r.POST("/api/auth/login", handlers.Login)

	// 需要认证的路由
	auth := r.Group("/api")
	auth.Use(middleware.AuthMiddleware())
	{
		// 当前用户
		auth.GET("/auth/me", handlers.GetCurrentUser)

		// 用户管理（仅管理员）
		users := auth.Group("/users")
		users.Use(middleware.AdminMiddleware())
		{
			users.GET("", handlers.GetUsers)
			users.GET("/:id", handlers.GetUser)
			users.POST("", handlers.CreateUser)
			users.PUT("/:id", handlers.UpdateUser)
			users.DELETE("/:id", handlers.DeleteUser)
			users.POST("/:id/avatar", handlers.UploadAvatar)
			users.POST("/:id/hide", handlers.HideUser)     // 隐藏用户（离职）
			users.POST("/:id/unhide", handlers.UnhideUser) // 取消隐藏
		}

		// 订单管理
		orders := auth.Group("/orders")
		{
			orders.GET("", handlers.GetOrders)
			orders.GET("/history", handlers.GetHistoryOrders) // 历史订单
			orders.GET("/:id", handlers.GetOrder)
			orders.POST("", handlers.CreateOrder)
			orders.PUT("/:id", handlers.UpdateOrder)
			orders.DELETE("/:id", handlers.DeleteOrder)
			orders.POST("/:id/complete", handlers.CompleteOrder)
			orders.POST("/:id/archive", handlers.ArchiveOrder)
			orders.POST("/:id/unarchive", handlers.UnarchiveOrder)
		}

		// 数据导入（仅管理员）
		imports := auth.Group("/import")
		imports.Use(middleware.AdminMiddleware())
		{
			imports.POST("/excel", handlers.ImportExcel)
			imports.POST("/migration", handlers.ImportMigration)
		}

		// 数据管理（仅管理员）
		data := auth.Group("/data")
		data.Use(middleware.AdminMiddleware())
		{
			data.DELETE("/delete-all", handlers.DeleteAllData)
			data.GET("/backup", handlers.ExportFullBackup)   // 导出完整备份（ZIP）
			data.POST("/restore", handlers.ImportFullBackup) // 导入完整备份（ZIP）
		}

		// 统计接口（boss 和 admin 可访问）
		statsHandler := handlers.NewStatisticsHandler(database.DB)
		stats := auth.Group("/stats")
		{
			stats.GET("/overview", statsHandler.GetOverview)
			stats.GET("/department/:name", statsHandler.GetDepartmentStats)
			stats.GET("/staff-ranking", statsHandler.GetStaffRanking)
			stats.GET("/alerts", statsHandler.GetAlerts)
		}

		// 腾讯文档同步（仅管理员）
		syncHandler := handlers.NewSyncHandler(database.DB)
		syncGroup := auth.Group("/sync")
		syncGroup.Use(middleware.AdminMiddleware())
		{
			syncGroup.GET("/status", syncHandler.GetSyncStatus)
			syncGroup.POST("/trigger", syncHandler.TriggerSync)
			syncGroup.PUT("/cookie", syncHandler.UpdateCookie)
			syncGroup.POST("/upload", syncHandler.UploadExcel) // Excel 上传
		}

		// 拍摄订单和统计（仅管理员）
		shooting := auth.Group("/shooting")
		shooting.Use(middleware.AdminMiddleware())
		{
			shooting.GET("/orders", syncHandler.GetShootingOrders)
			shooting.GET("/orders/export", syncHandler.ExportShootingOrders)
			shooting.PUT("/orders/:id", syncHandler.UpdateShootingOrder)
			shooting.POST("/sync-matches", syncHandler.SyncShootingOrderMatches) // 批量同步匹配
			shooting.GET("/stats", syncHandler.GetShootingStats)
		}
	}

	// 启动服务器
	log.Printf("Server starting on port %s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

// corsMiddleware CORS 中间件
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// createDefaultAdmin 创建默认管理员用户
func createDefaultAdmin() {
	var count int64
	database.DB.Model(&models.User{}).Where("username = ?", "admin").Count(&count)
	if count > 0 {
		return
	}

	admin := models.User{
		Username:          "admin",
		Nickname:          "管理员",
		Role:              models.RoleAdmin,
		BasePrice:         10.0,
		GroupBonus:        2.0,
		UrgentBonus:       5.0,
		ComplaintBonus:    8.0,
		WeddingMultiplier: 0.8,
	}
	admin.SetPassword("admin")

	if err := database.DB.Create(&admin).Error; err != nil {
		log.Printf("Failed to create default admin: %v", err)
	} else {
		log.Println("Default admin user created (username: admin, password: admin)")
	}
}
