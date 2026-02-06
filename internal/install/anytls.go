package install

import (
	"fmt"
	"os"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// AnyTLS 安装
// =========================================

const (
	AnyTLSBinaryPath      = "/usr/local/bin/anytls-server"
	AnyTLSConfigDir       = "/etc/anytls"
	AnyTLSConfigPath      = "/etc/anytls/config.yaml"
	AnyTLSProxyConfigPath = "/etc/anytls-proxy-config.txt"
	AnyTLSCertDir         = "/etc/anytls/certs"
)

// AnyTLSConfig AnyTLS 配置
type AnyTLSConfig struct {
	ServerIP  string
	IPVersion string
	Port      int
	Password  string
	Domain    string
	Email     string
	Version   string
}

// InstallAnyTLS 安装 AnyTLS
func InstallAnyTLS() (*InstallResult, error) {
	utils.PrintInfo("开始安装 AnyTLS...")

	// 检查是否已安装
	if utils.FileExists(AnyTLSProxyConfigPath) {
		if !utils.PromptConfirm("AnyTLS 已安装，是否重新安装？") {
			return nil, fmt.Errorf("安装已取消")
		}
		UninstallAnyTLS()
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
	version := utils.GetLatestVersion("anytls/anytls", utils.DefaultAnyTLSVersion)
	utils.PrintInfo("AnyTLS 版本: %s", version)

	// 下载 AnyTLS
	if err := downloadAnyTLS(version, arch); err != nil {
		return nil, fmt.Errorf("下载 AnyTLS 失败: %v", err)
	}

	// 获取配置参数
	port := promptPort("请输入 AnyTLS 监听端口", 443)

	// 获取域名和邮箱 (用于 Let's Encrypt)
	fmt.Println()
	utils.PrintInfo("AnyTLS 需要域名来申请 Let's Encrypt 证书")
	domain := utils.PromptInput("请输入域名", "")
	if domain == "" {
		return nil, fmt.Errorf("域名不能为空")
	}
	email := utils.PromptInput("请输入邮箱 (用于 Let's Encrypt)", "admin@"+domain)

	password := utils.GeneratePassword(16)

	config := AnyTLSConfig{
		ServerIP:  serverIP,
		IPVersion: ipVersion,
		Port:      port,
		Password:  password,
		Domain:    domain,
		Email:     email,
		Version:   version,
	}

	// 创建配置
	if err := createAnyTLSConfig(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建 systemd 服务
	if err := createAnyTLSService(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("anytls")
	utils.ServiceStart("anytls")

	// 验证服务
	if !utils.VerifyServiceStarted("anytls", 15) {
		utils.PrintWarn("AnyTLS 服务启动较慢，可能正在申请证书...")
	}

	// 保存配置
	saveAnyTLSConfig(config)

	// 生成客户端配置
	surgeProxy := fmt.Sprintf(
		"AnyTLS = anytls, %s, %d, password=%s, sni=%s",
		domain, port, password, domain,
	)

	result := &InstallResult{
		Success:    true,
		ServerIP:   serverIP,
		IPVersion:  ipVersion,
		Port:       port,
		SurgeProxy: surgeProxy,
	}

	printAnyTLSSuccess(config, surgeProxy)

	return result, nil
}

func downloadAnyTLS(version, arch string) error {
	if utils.FileExists(AnyTLSBinaryPath) {
		return nil
	}

	// 去掉版本号前的 v
	versionNum := version
	if len(version) > 0 && version[0] == 'v' {
		versionNum = version[1:]
	}

	anytlsArch := arch
	if arch == "arm64" {
		anytlsArch = "aarch64"
	}

	url := fmt.Sprintf(
		"https://github.com/anytls/anytls/releases/download/%s/anytls-server-%s-linux-%s",
		version, versionNum, anytlsArch,
	)

	if err := utils.DownloadFile(url, AnyTLSBinaryPath, 3); err != nil {
		return err
	}

	os.Chmod(AnyTLSBinaryPath, 0755)
	utils.PrintSuccess("AnyTLS 下载成功")
	return nil
}

func createAnyTLSConfig(cfg AnyTLSConfig) error {
	if err := os.MkdirAll(AnyTLSConfigDir, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(AnyTLSCertDir, 0755); err != nil {
		return err
	}

	content := fmt.Sprintf(`listen: :%d

acme:
  domain: %s
  email: %s
  cache_dir: %s

password: %s

log:
  level: info
`, cfg.Port, cfg.Domain, cfg.Email, AnyTLSCertDir, cfg.Password)

	return utils.WriteFile(AnyTLSConfigPath, content, 0600)
}

func createAnyTLSService() error {
	return CreateSystemdService(SystemdServiceConfig{
		Name:         "anytls",
		Description:  "AnyTLS Server",
		User:         "root",
		ExecStart:    fmt.Sprintf("%s -c %s", AnyTLSBinaryPath, AnyTLSConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveAnyTLSConfig(cfg AnyTLSConfig) {
	config := map[string]string{
		"TYPE":       "anytls",
		"SERVER_IP":  cfg.ServerIP,
		"IP_VERSION": cfg.IPVersion,
		"VERSION":    cfg.Version,
		"PORT":       strconv.Itoa(cfg.Port),
		"PASSWORD":   cfg.Password,
		"DOMAIN":     cfg.Domain,
		"EMAIL":      cfg.Email,
	}
	SaveConfigFile(AnyTLSProxyConfigPath, config)
}

func printAnyTLSSuccess(cfg AnyTLSConfig, surgeProxy string) {
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
// AnyTLS 查看配置
// =========================================

// ViewAnyTLSConfig 查看 AnyTLS 配置
func ViewAnyTLSConfig() {
	if !utils.FileExists(AnyTLSProxyConfigPath) {
		utils.PrintError("AnyTLS 未安装")
		return
	}

	config, err := ParseConfigFile(AnyTLSProxyConfigPath)
	if err != nil {
		utils.PrintError("读取配置失败: %v", err)
		return
	}

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   AnyTLS 配置%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, config["DOMAIN"])
	fmt.Printf("%s端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["PORT"])
	fmt.Printf("%s密码:%s %s\n", utils.ColorCyan, utils.ColorReset, config["PASSWORD"])
	fmt.Println()

	surgeProxy := fmt.Sprintf(
		"AnyTLS = anytls, %s, %s, password=%s, sni=%s",
		config["DOMAIN"], config["PORT"], config["PASSWORD"], config["DOMAIN"],
	)
	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// AnyTLS 更新
// =========================================

// UpdateAnyTLS 更新 AnyTLS
func UpdateAnyTLS() error {
	if !utils.FileExists(AnyTLSProxyConfigPath) {
		return fmt.Errorf("AnyTLS 未安装")
	}

	config, err := ParseConfigFile(AnyTLSProxyConfigPath)
	if err != nil {
		return err
	}

	currentVersion := config["VERSION"]
	latestVersion := utils.GetLatestVersion("anytls/anytls", utils.DefaultAnyTLSVersion)

	fmt.Printf("%s当前版本:%s %s\n", utils.ColorCyan, utils.ColorReset, currentVersion)
	fmt.Printf("%s最新版本:%s %s\n", utils.ColorCyan, utils.ColorReset, latestVersion)

	if currentVersion == latestVersion {
		utils.PrintSuccess("已是最新版本")
		return nil
	}

	if !utils.PromptConfirm("确认更新？") {
		return nil
	}

	utils.ServiceStop("anytls")

	os.Rename(AnyTLSBinaryPath, AnyTLSBinaryPath+".bak")
	arch, _ := utils.DetectArch()
	os.Remove(AnyTLSBinaryPath)

	if err := downloadAnyTLS(latestVersion, arch); err != nil {
		os.Rename(AnyTLSBinaryPath+".bak", AnyTLSBinaryPath)
		utils.ServiceStart("anytls")
		return fmt.Errorf("更新失败: %v", err)
	}

	config["VERSION"] = latestVersion
	SaveConfigFile(AnyTLSProxyConfigPath, config)

	utils.ServiceStart("anytls")

	os.Remove(AnyTLSBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// AnyTLS 卸载
// =========================================

// UninstallAnyTLS 卸载 AnyTLS
func UninstallAnyTLS() error {
	utils.PrintInfo("正在卸载 AnyTLS...")

	RemoveSystemdService("anytls")

	os.Remove(AnyTLSBinaryPath)
	os.RemoveAll(AnyTLSConfigDir)
	os.Remove(AnyTLSProxyConfigPath)

	utils.PrintSuccess("AnyTLS 已卸载")
	return nil
}

// IsAnyTLSInstalled 检查是否已安装
func IsAnyTLSInstalled() bool {
	return utils.FileExists(AnyTLSProxyConfigPath)
}
