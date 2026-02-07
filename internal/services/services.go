package services

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// ServiceStatus 服务状态
type ServiceStatus string

const (
	StatusActive   ServiceStatus = "active"
	StatusInactive ServiceStatus = "inactive"
	StatusFailed   ServiceStatus = "failed"
	StatusNotFound ServiceStatus = "not_installed"
)

// Service 服务定义
type Service struct {
	Name        string
	DisplayName string
	ConfigPath  string
	SystemdName string
}

// 预定义服务列表
var Services = map[string]Service{
	"snell": {
		Name:        "snell",
		DisplayName: "Snell + Shadow-TLS",
		ConfigPath:  "/etc/snell/snell-server.conf",
		SystemdName: "snell",
	},
	"singbox": {
		Name:        "singbox",
		DisplayName: "Sing-box (SS-2022)",
		ConfigPath:  "/etc/sing-box/config.json",
		SystemdName: "sing-box",
	},
	"reality": {
		Name:        "reality",
		DisplayName: "VLESS Reality",
		ConfigPath:  "/etc/sing-box-reality/config.json",
		SystemdName: "sing-box-reality",
	},
	"hysteria2": {
		Name:        "hysteria2",
		DisplayName: "Hysteria2",
		ConfigPath:  "/etc/hysteria2/config.json",
		SystemdName: "hysteria2",
	},
	"anytls": {
		Name:        "anytls",
		DisplayName: "AnyTLS",
		ConfigPath:  "/etc/anytls/config.json",
		SystemdName: "anytls",
	},
}

// IsInstalled 检查服务是否已安装
func (s *Service) IsInstalled() bool {
	_, err := os.Stat(s.ConfigPath)
	return err == nil
}

// GetStatus 获取服务状态
func (s *Service) GetStatus() ServiceStatus {
	if !s.IsInstalled() {
		return StatusNotFound
	}

	cmd := exec.Command("systemctl", "is-active", s.SystemdName)
	output, _ := cmd.Output()
	status := strings.TrimSpace(string(output))

	switch status {
	case "active":
		return StatusActive
	case "inactive":
		return StatusInactive
	case "failed":
		return StatusFailed
	default:
		return StatusInactive
	}
}

// Start 启动服务
func (s *Service) Start() error {
	cmd := exec.Command("systemctl", "start", s.SystemdName)
	return cmd.Run()
}

// Stop 停止服务
func (s *Service) Stop() error {
	cmd := exec.Command("systemctl", "stop", s.SystemdName)
	return cmd.Run()
}

// Restart 重启服务
func (s *Service) Restart() error {
	cmd := exec.Command("systemctl", "restart", s.SystemdName)
	return cmd.Run()
}

// Enable 设置开机自启
func (s *Service) Enable() error {
	cmd := exec.Command("systemctl", "enable", s.SystemdName)
	return cmd.Run()
}

// GetAllStatus 获取所有服务状态
func GetAllStatus() map[string]ServiceStatus {
	result := make(map[string]ServiceStatus)
	for name, svc := range Services {
		result[name] = svc.GetStatus()
	}
	return result
}

// StatusString 状态转字符串
func StatusString(status ServiceStatus) string {
	switch status {
	case StatusActive:
		return "运行中"
	case StatusInactive:
		return "已停止"
	case StatusFailed:
		return "失败"
	case StatusNotFound:
		return "未安装"
	default:
		return "未知"
	}
}

// StatusColor 状态颜色代码
func StatusColor(status ServiceStatus) string {
	switch status {
	case StatusActive:
		return "\033[32m" // 绿色
	case StatusInactive, StatusFailed:
		return "\033[31m" // 红色
	case StatusNotFound:
		return "\033[33m" // 黄色
	default:
		return "\033[0m"
	}
}

// PrintStatus 打印服务状态
func PrintStatus() {
	fmt.Println("\n服务状态:")
	fmt.Println(strings.Repeat("-", 40))

	for _, svc := range Services {
		status := svc.GetStatus()
		color := StatusColor(status)
		reset := "\033[0m"
		fmt.Printf("  %-20s: %s%s%s\n", svc.DisplayName, color, StatusString(status), reset)
	}

	fmt.Println(strings.Repeat("-", 40))
}
