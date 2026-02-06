package install

import (
	"fmt"
	"os"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// Hysteria2 安装
// =========================================

const (
	Hysteria2BinaryPath      = "/usr/local/bin/hysteria"
	Hysteria2ConfigDir       = "/etc/hysteria2"
	Hysteria2ConfigPath      = "/etc/hysteria2/config.yaml"
	Hysteria2ProxyConfigPath = "/etc/hysteria2-proxy-config.txt"
	Hysteria2CertDir         = "/etc/hysteria2/certs"
)

// Hysteria2Config Hysteria2 配置
type Hysteria2Config struct {
	ServerIP  string
	IPVersion string
	Port      int
	Password  string
	Domain    string
	Email     string
	Version   string
	UpMbps    int
	DownMbps  int
}

// InstallHysteria2 安装 Hysteria2
func InstallHysteria2() (*InstallResult, error) {
	utils.PrintInfo("开始安装 Hysteria2...")

	// 检查是否已安装
	if utils.FileExists(Hysteria2ProxyConfigPath) {
		if !utils.PromptConfirm("Hysteria2 已安装，是否重新安装？") {
			return nil, fmt.Errorf("安装已取消")
		}
		UninstallHysteria2()
	}

	// 检查依赖
	if err := CheckDependencies(); err != nil {
		return nil, err
	}

	// 获取服务器 IP
	serverIP, ipVersion, err := utils.GetServerIP()
	if err != nil {
		return nil, fmt.Errorf("获取服务器 IP 失败: %v", err)
	}
	utils.PrintSuccess("服务器 IP: %s (IPv%s)", serverIP, ipVersion)

	// 检测架构
	arch, err := utils.DetectArch()
	if err != nil {
		return nil, err
	}

	// 获取版本
	version := utils.GetLatestVersion("apernet/hysteria", utils.DefaultHysteria2Version)
	utils.PrintInfo("Hysteria2 版本: %s", version)

	// 下载 Hysteria2
	if err := downloadHysteria2(version, arch); err != nil {
		return nil, fmt.Errorf("下载 Hysteria2 失败: %v", err)
	}

	// 获取配置参数
	port := promptPort("请输入 Hysteria2 监听端口", 443)

	// 获取域名和邮箱 (用于 Let's Encrypt)
	fmt.Println()
	utils.PrintInfo("Hysteria2 需要域名来申请 Let's Encrypt 证书")
	domain := utils.PromptInput("请输入域名", "")
	if domain == "" {
		return nil, fmt.Errorf("域名不能为空")
	}
	email := utils.PromptInput("请输入邮箱 (用于 Let's Encrypt)", "admin@"+domain)

	password := utils.GeneratePassword(16)

	config := Hysteria2Config{
		ServerIP:  serverIP,
		IPVersion: ipVersion,
		Port:      port,
		Password:  password,
		Domain:    domain,
		Email:     email,
		Version:   version,
		UpMbps:    100,
		DownMbps:  100,
	}

	// 创建配置
	if err := createHysteria2Config(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建 systemd 服务
	if err := createHysteria2Service(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("hysteria2")
	utils.ServiceStart("hysteria2")

	// 验证服务
	if !utils.VerifyServiceStarted("hysteria2", 15) {
		utils.PrintWarn("Hysteria2 服务启动较慢，可能正在申请证书...")
	}

	// 保存配置
	saveHysteria2Config(config)

	// 生成客户端配置
	surgeProxy := fmt.Sprintf(
		"Hysteria2 = hysteria2, %s, %d, password=%s, sni=%s, download-bandwidth=100",
		domain, port, password, domain,
	)

	result := &InstallResult{
		Success:    true,
		ServerIP:   serverIP,
		IPVersion:  ipVersion,
		Port:       port,
		SurgeProxy: surgeProxy,
	}

	printHysteria2Success(config, surgeProxy)

	return result, nil
}

func downloadHysteria2(version, arch string) error {
	if utils.FileExists(Hysteria2BinaryPath) {
		return nil
	}

	url := fmt.Sprintf(
		"https://github.com/apernet/hysteria/releases/download/app/%s/hysteria-linux-%s",
		version, arch,
	)

	if err := utils.DownloadFile(url, Hysteria2BinaryPath, 3); err != nil {
		return err
	}

	os.Chmod(Hysteria2BinaryPath, 0755)
	utils.PrintSuccess("Hysteria2 下载成功")
	return nil
}

func createHysteria2Config(cfg Hysteria2Config) error {
	if err := os.MkdirAll(Hysteria2ConfigDir, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(Hysteria2CertDir, 0755); err != nil {
		return err
	}

	content := fmt.Sprintf(`listen: :%d

acme:
  domains:
    - %s
  email: %s

auth:
  type: password
  password: %s

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true
`, cfg.Port, cfg.Domain, cfg.Email, cfg.Password)

	return utils.WriteFile(Hysteria2ConfigPath, content, 0600)
}

func createHysteria2Service() error {
	return CreateSystemdService(SystemdServiceConfig{
		Name:         "hysteria2",
		Description:  "Hysteria2 Server",
		User:         "root",
		ExecStart:    fmt.Sprintf("%s server -c %s", Hysteria2BinaryPath, Hysteria2ConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveHysteria2Config(cfg Hysteria2Config) {
	config := map[string]string{
		"TYPE":       "hysteria2",
		"SERVER_IP":  cfg.ServerIP,
		"IP_VERSION": cfg.IPVersion,
		"VERSION":    cfg.Version,
		"PORT":       strconv.Itoa(cfg.Port),
		"PASSWORD":   cfg.Password,
		"DOMAIN":     cfg.Domain,
		"EMAIL":      cfg.Email,
	}
	SaveConfigFile(Hysteria2ProxyConfigPath, config)
}

func printHysteria2Success(cfg Hysteria2Config, surgeProxy string) {
	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   安装完成！%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.Domain)
	fmt.Printf("%s端口:%s %d\n", utils.ColorCyan, utils.ColorReset, cfg.Port)
	fmt.Printf("%s密码:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.Password)
	fmt.Println()
	fmt.Printf("%s注意:%s 首次启动需要申请 Let's Encrypt 证书，可能需要几分钟\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%sSurge 配置:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Hysteria2 查看配置
// =========================================

// ViewHysteria2Config 查看 Hysteria2 配置
func ViewHysteria2Config() {
	if !utils.FileExists(Hysteria2ProxyConfigPath) {
		utils.PrintError("Hysteria2 未安装")
		return
	}

	config, err := ParseConfigFile(Hysteria2ProxyConfigPath)
	if err != nil {
		utils.PrintError("读取配置失败: %v", err)
		return
	}

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   Hysteria2 配置%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, config["DOMAIN"])
	fmt.Printf("%s端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["PORT"])
	fmt.Printf("%s密码:%s %s\n", utils.ColorCyan, utils.ColorReset, config["PASSWORD"])
	fmt.Println()

	surgeProxy := fmt.Sprintf(
		"Hysteria2 = hysteria2, %s, %s, password=%s, sni=%s, download-bandwidth=100",
		config["DOMAIN"], config["PORT"], config["PASSWORD"], config["DOMAIN"],
	)
	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Hysteria2 更新
// =========================================

// UpdateHysteria2 更新 Hysteria2
func UpdateHysteria2() error {
	if !utils.FileExists(Hysteria2ProxyConfigPath) {
		return fmt.Errorf("Hysteria2 未安装")
	}

	config, err := ParseConfigFile(Hysteria2ProxyConfigPath)
	if err != nil {
		return err
	}

	currentVersion := config["VERSION"]
	latestVersion := utils.GetLatestVersion("apernet/hysteria", utils.DefaultHysteria2Version)

	fmt.Printf("%s当前版本:%s %s\n", utils.ColorCyan, utils.ColorReset, currentVersion)
	fmt.Printf("%s最新版本:%s %s\n", utils.ColorCyan, utils.ColorReset, latestVersion)

	if currentVersion == latestVersion {
		utils.PrintSuccess("已是最新版本")
		return nil
	}

	if !utils.PromptConfirm("确认更新？") {
		return nil
	}

	utils.ServiceStop("hysteria2")

	os.Rename(Hysteria2BinaryPath, Hysteria2BinaryPath+".bak")
	arch, _ := utils.DetectArch()
	os.Remove(Hysteria2BinaryPath)

	if err := downloadHysteria2(latestVersion, arch); err != nil {
		os.Rename(Hysteria2BinaryPath+".bak", Hysteria2BinaryPath)
		utils.ServiceStart("hysteria2")
		return fmt.Errorf("更新失败: %v", err)
	}

	config["VERSION"] = latestVersion
	SaveConfigFile(Hysteria2ProxyConfigPath, config)

	utils.ServiceStart("hysteria2")

	os.Remove(Hysteria2BinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// Hysteria2 卸载
// =========================================

// UninstallHysteria2 卸载 Hysteria2
func UninstallHysteria2() error {
	utils.PrintInfo("正在卸载 Hysteria2...")

	RemoveSystemdService("hysteria2")

	os.Remove(Hysteria2BinaryPath)
	os.RemoveAll(Hysteria2ConfigDir)
	os.Remove(Hysteria2ProxyConfigPath)

	utils.PrintSuccess("Hysteria2 已卸载")
	return nil
}

// IsHysteria2Installed 检查是否已安装
func IsHysteria2Installed() bool {
	return utils.FileExists(Hysteria2ProxyConfigPath)
}
