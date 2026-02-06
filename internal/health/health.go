package health

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/services"
)

const logFile = "/var/log/proxy-manager-health.log"

// Logger 健康检查日志
type Logger struct {
	file *os.File
}

// NewLogger 创建日志器
func NewLogger() (*Logger, error) {
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return nil, err
	}
	return &Logger{file: f}, nil
}

// Log 写入日志
func (l *Logger) Log(level, message string) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	fmt.Fprintf(l.file, "[%s] %s: %s\n", timestamp, level, message)
}

// Close 关闭日志文件
func (l *Logger) Close() {
	if l.file != nil {
		l.file.Close()
	}
}

// Check 执行健康检查
func Check() error {
	logger, err := NewLogger()
	if err != nil {
		log.Printf("无法创建日志: %v", err)
	} else {
		defer logger.Close()
	}

	hasError := false

	for name, svc := range services.Services {
		if !svc.IsInstalled() {
			continue
		}

		status := svc.GetStatus()
		if status != services.StatusActive {
			if logger != nil {
				logger.Log("WARNING", fmt.Sprintf("%s 服务异常，正在重启...", svc.DisplayName))
			}

			if err := svc.Restart(); err != nil {
				if logger != nil {
					logger.Log("ERROR", fmt.Sprintf("%s 重启失败: %v", svc.DisplayName, err))
				}
				hasError = true
				continue
			}

			// 等待服务启动
			time.Sleep(2 * time.Second)

			// 再次检查状态
			newStatus := svc.GetStatus()
			if newStatus == services.StatusActive {
				if logger != nil {
					logger.Log("INFO", fmt.Sprintf("%s 重启成功", svc.DisplayName))
				}
			} else {
				if logger != nil {
					logger.Log("ERROR", fmt.Sprintf("%s 重启后仍然失败", svc.DisplayName))
				}
				hasError = true
			}
		}

		_ = name // 使用变量避免编译警告
	}

	if hasError {
		return fmt.Errorf("部分服务健康检查失败")
	}

	return nil
}

// RunDaemon 作为守护进程运行健康检查
func RunDaemon(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			_ = Check()
		}
	}
}
