package utils

import (
	"archive/tar"
	"compress/gzip"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// =========================================
// 颜色输出
// =========================================

const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorCyan   = "\033[36m"
)

func PrintInfo(format string, args ...interface{}) {
	fmt.Printf(ColorCyan+"[INFO] "+ColorReset+format+"\n", args...)
}

func PrintSuccess(format string, args ...interface{}) {
	fmt.Printf(ColorGreen+"[✓] "+ColorReset+format+"\n", args...)
}

func PrintError(format string, args ...interface{}) {
	fmt.Printf(ColorRed+"[ERROR] "+ColorReset+format+"\n", args...)
}

func PrintWarn(format string, args ...interface{}) {
	fmt.Printf(ColorYellow+"[WARN] "+ColorReset+format+"\n", args...)
}

// =========================================
// 版本常量
// =========================================

const (
	DefaultSnellVersion     = "4.1.1" // Stable, v5 is beta
	DefaultSingboxVersion   = "v1.12.0"
	DefaultShadowTLSVersion = "v0.2.25"
	DefaultHysteria2Version = "v2.6.1"
	DefaultAnyTLSVersion    = "v0.0.12"
)

// =========================================
// 系统检测
// =========================================

// DetectArch 检测系统架构
func DetectArch() (string, error) {
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
		return "amd64", nil
	case "arm64":
		return "arm64", nil
	default:
		return "", fmt.Errorf("不支持的架构: %s", arch)
	}
}

// GetServerIP 获取服务器 IP
func GetServerIP() (string, string, error) {
	// 尝试获取 IPv4
	ipv4, err := getPublicIP("https://api.ipify.org")
	if err == nil && ipv4 != "" {
		return ipv4, "4", nil
	}

	// 尝试获取 IPv6
	ipv6, err := getPublicIP("https://api6.ipify.org")
	if err == nil && ipv6 != "" {
		return ipv6, "6", nil
	}

	return "", "", fmt.Errorf("无法获取公网 IP")
}

func getPublicIP(url string) (string, error) {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(string(body)), nil
}

// =========================================
// 版本获取
// =========================================

// GitHubRelease GitHub Release 结构
type GitHubRelease struct {
	TagName string `json:"tag_name"`
}

// GetLatestVersion 从 GitHub 获取最新版本
func GetLatestVersion(repo, defaultVersion string) string {
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", repo)

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return defaultVersion
	}
	defer resp.Body.Close()

	var release GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return defaultVersion
	}

	if release.TagName != "" {
		return release.TagName
	}
	return defaultVersion
}

// GetSnellLatestVersion 获取 Snell 最新版本
func GetSnellLatestVersion() string {
	// Snell 没有公开的版本 API，使用默认版本
	return DefaultSnellVersion
}

// =========================================
// 下载函数
// =========================================

// DownloadFile 下载文件（带重试）
func DownloadFile(url, dest string, retries int) error {
	var lastErr error

	for i := 0; i < retries; i++ {
		PrintInfo("下载尝试 %d/%d: %s", i+1, retries, url)

		err := downloadFileOnce(url, dest)
		if err == nil {
			return nil
		}

		lastErr = err
		PrintWarn("下载失败: %v", err)

		if i < retries-1 {
			time.Sleep(3 * time.Second)
		}
	}

	return fmt.Errorf("下载失败（已重试 %d 次）: %v", retries, lastErr)
}

func downloadFileOnce(url, dest string) error {
	// 确保目标目录存在
	if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
		return err
	}

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	return err
}

// ExtractTarGz 解压 tar.gz 文件
func ExtractTarGz(src, dest string) error {
	file, err := os.Open(src)
	if err != nil {
		return err
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		target := filepath.Join(dest, header.Name)

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			outFile, err := os.Create(target)
			if err != nil {
				return err
			}
			if _, err := io.Copy(outFile, tr); err != nil {
				outFile.Close()
				return err
			}
			outFile.Close()
			os.Chmod(target, os.FileMode(header.Mode))
		}
	}

	return nil
}

// =========================================
// 端口和验证
// =========================================

// ValidatePort 验证端口号
func ValidatePort(port int) error {
	if port < 1 || port > 65535 {
		return fmt.Errorf("端口必须在 1-65535 之间")
	}
	return nil
}

// IsPortInUse 检查端口是否被占用
func IsPortInUse(port int) bool {
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return true
	}
	listener.Close()
	return false
}

// =========================================
// 密码和密钥生成
// =========================================

// GeneratePassword 生成随机密码
func GeneratePassword(length int) string {
	bytes := make([]byte, length)
	rand.Read(bytes)
	return base64.StdEncoding.EncodeToString(bytes)[:length]
}

// GenerateBase64Key 生成 Base64 密钥
func GenerateBase64Key(byteLength int) string {
	bytes := make([]byte, byteLength)
	rand.Read(bytes)
	return base64.StdEncoding.EncodeToString(bytes)
}

// =========================================
// 服务管理
// =========================================

// ServiceAction 执行 systemctl 操作
func ServiceAction(service, action string) error {
	cmd := exec.Command("systemctl", action, service)
	return cmd.Run()
}

// ServiceStart 启动服务
func ServiceStart(service string) error {
	return ServiceAction(service, "start")
}

// ServiceStop 停止服务
func ServiceStop(service string) error {
	return ServiceAction(service, "stop")
}

// ServiceRestart 重启服务
func ServiceRestart(service string) error {
	return ServiceAction(service, "restart")
}

// ServiceEnable 启用服务
func ServiceEnable(service string) error {
	return ServiceAction(service, "enable")
}

// ServiceDisable 禁用服务
func ServiceDisable(service string) error {
	return ServiceAction(service, "disable")
}

// DaemonReload 重载 systemd
func DaemonReload() error {
	cmd := exec.Command("systemctl", "daemon-reload")
	return cmd.Run()
}

// VerifyServiceStarted 验证服务是否启动
func VerifyServiceStarted(service string, maxWait int) bool {
	PrintInfo("正在验证服务 %s 启动状态...", service)

	for i := 0; i < maxWait; i++ {
		cmd := exec.Command("systemctl", "is-active", service)
		output, _ := cmd.Output()
		if strings.TrimSpace(string(output)) == "active" {
			PrintSuccess("服务 %s 启动成功", service)
			return true
		}
		time.Sleep(time.Second)
	}

	PrintError("服务 %s 启动失败", service)
	return false
}

// =========================================
// 文件操作
// =========================================

// FileExists 检查文件是否存在
func FileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// WriteFile 写入文件
func WriteFile(path, content string, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), perm)
}

// ReadFile 读取文件
func ReadFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// RemoveFile 删除文件
func RemoveFile(path string) error {
	return os.Remove(path)
}

// RemoveDir 删除目录
func RemoveDir(path string) error {
	return os.RemoveAll(path)
}

// =========================================
// 用户管理
// =========================================

// CreateSystemUser 创建系统用户
func CreateSystemUser(username string) error {
	// 检查用户是否存在
	cmd := exec.Command("id", "-u", username)
	if cmd.Run() == nil {
		return nil // 用户已存在
	}

	// 创建用户
	cmd = exec.Command("useradd", "-r", "-s", "/usr/sbin/nologin", username)
	return cmd.Run()
}

// DeleteSystemUser 删除系统用户
func DeleteSystemUser(username string) error {
	cmd := exec.Command("userdel", username)
	return cmd.Run()
}

// GetDefaultGroup 获取默认用户组
func GetDefaultGroup() string {
	cmd := exec.Command("getent", "group", "nogroup")
	if cmd.Run() == nil {
		return "nogroup"
	}
	return "nobody"
}

// =========================================
// 交互输入
// =========================================

// PromptInput 获取用户输入
func PromptInput(prompt, defaultValue string) string {
	if defaultValue != "" {
		fmt.Printf("%s (默认: %s): ", prompt, defaultValue)
	} else {
		fmt.Printf("%s: ", prompt)
	}

	var input string
	fmt.Scanln(&input)

	if input == "" {
		return defaultValue
	}
	return input
}

// PromptConfirm 确认提示
func PromptConfirm(prompt string) bool {
	fmt.Printf("%s (y/n): ", prompt)
	var input string
	fmt.Scanln(&input)
	return strings.ToLower(input) == "y"
}

// PromptSelect 选择菜单
func PromptSelect(prompt string, options []string) int {
	fmt.Println()
	fmt.Println(prompt)
	for i, opt := range options {
		fmt.Printf("  %d. %s\n", i+1, opt)
	}
	fmt.Println()

	var choice int
	fmt.Print("请选择: ")
	fmt.Scanln(&choice)

	if choice < 1 || choice > len(options) {
		return 1
	}
	return choice
}

// =========================================
// TLS 域名选项
// =========================================

var TLSDomains = []string{
	"gateway.icloud.com",
	"www.microsoft.com",
	"www.apple.com",
	"cloudflare.com",
	"www.amazon.com",
	"www.google.com",
}

// SelectTLSDomain 选择 TLS 伪装域名
func SelectTLSDomain() string {
	fmt.Println()
	fmt.Println(ColorCyan + "选择 TLS 伪装域名:" + ColorReset)
	for i, domain := range TLSDomains {
		suffix := ""
		if i == 0 {
			suffix = ColorGreen + " (推荐)" + ColorReset
		}
		fmt.Printf("  %d. %s%s\n", i+1, domain, suffix)
	}
	fmt.Println("  0. 自定义域名")
	fmt.Println()

	var choice int
	fmt.Print("请选择 (默认: 1): ")
	fmt.Scanln(&choice)

	if choice == 0 {
		return PromptInput("请输入自定义域名", "")
	}

	if choice < 1 || choice > len(TLSDomains) {
		choice = 1
	}

	return TLSDomains[choice-1]
}
