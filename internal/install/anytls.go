package install

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// AnyTLS 安装 (使用 sing-box 内核)
// =========================================

const (
	AnyTLSConfigDir       = "/etc/anytls"
	AnyTLSConfigPath      = "/etc/anytls/config.json"
	AnyTLSProxyConfigPath = "/etc/anytls-proxy-config.txt"
	AnyTLSCertPath        = "/etc/anytls/server.crt"
	AnyTLSKeyPath         = "/etc/anytls/server.key"
)

// AnyTLSConfig AnyTLS 配置
type AnyTLSConfig struct {
	ServerIP      string
	IPVersion     string
	Port          int
	Password      string
	Domain        string
	PaddingScheme string
	PaddingName   string
	SingboxVer    string
}

// 填充方案定义
var PaddingSchemes = map[string]struct {
	Name   string
	Scheme []string
}{
	"default": {
		Name: "默认",
		Scheme: []string{
			"stop=8", "0=30-30", "1=100-400",
			"2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
			"3=9-9,500-1000", "4=500-1000", "5=500-1000", "6=500-1000", "7=500-1000",
		},
	},
	"aggressive": {
		Name: "激进",
		Scheme: []string{
			"stop=12", "0=50-100", "1=200-600",
			"2=500-800,c,800-1200,c,800-1200,c,800-1200,c,800-1200,c,800-1200",
			"3=15-15,600-1200", "4=600-1200", "5=600-1200", "6=600-1200",
			"7=600-1200", "8=600-1200", "9=600-1200", "10=600-1200", "11=600-1200",
		},
	},
	"minimal": {
		Name: "最小",
		Scheme: []string{
			"stop=4", "0=10-20", "1=50-150", "2=100-300", "3=5-5,200-400",
		},
	},
}

// InstallAnyTLS 安装 AnyTLS (使用 sing-box 内核)
func InstallAnyTLS() (*InstallResult, error) {
	utils.PrintInfo("开始安装 AnyTLS (sing-box 内核)...")

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

	// 获取 sing-box 版本 (需要 v1.12.0+)
	singboxVersion := utils.GetLatestVersion("SagerNet/sing-box", utils.DefaultSingboxVersion)
	utils.PrintInfo("Sing-box 版本: %s", singboxVersion)

	// 检查版本是否支持 AnyTLS
	if !checkSingboxVersion(singboxVersion) {
		return nil, fmt.Errorf("sing-box 版本需要 v1.12.0+，当前: %s", singboxVersion)
	}

	// 下载 sing-box
	if err := downloadSingbox(singboxVersion, arch); err != nil {
		return nil, fmt.Errorf("下载 sing-box 失败: %v", err)
	}

	// 获取配置参数
	port := promptPort("请输入 AnyTLS 端口", 443)

	// 选择填充方案
	paddingKey := selectPaddingScheme()
	padding := PaddingSchemes[paddingKey]

	// 获取域名
	fmt.Println()
	utils.PrintInfo("AnyTLS 需要域名来申请 Let's Encrypt 证书")
	utils.PrintWarn("请确保域名已解析到此服务器")
	domain := utils.PromptInput("请输入域名", "")
	if domain == "" {
		return nil, fmt.Errorf("域名不能为空")
	}

	// 生成密码
	password := utils.GeneratePassword(32)

	config := AnyTLSConfig{
		ServerIP:    serverIP,
		IPVersion:   ipVersion,
		Port:        port,
		Password:    password,
		Domain:      domain,
		PaddingName: padding.Name,
		SingboxVer:  singboxVersion,
	}

	// 安装 acme.sh 并申请证书
	utils.PrintInfo("安装 acme.sh 并申请证书...")
	if err := installAcmeAndCert(domain); err != nil {
		return nil, fmt.Errorf("证书申请失败: %v", err)
	}

	// 创建配置目录
	if err := os.MkdirAll(AnyTLSConfigDir, 0755); err != nil {
		return nil, err
	}

	// 安装证书到 anytls 目录
	if err := installCertToAnyTLS(domain); err != nil {
		return nil, fmt.Errorf("证书安装失败: %v", err)
	}

	// 创建 sing-box 配置
	if err := createAnyTLSSingboxConfig(config, padding.Scheme); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建系统用户
	utils.CreateSystemUser("anytls")

	// 创建 systemd 服务
	if err := createAnyTLSService(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("anytls")
	utils.ServiceStart("anytls")

	// 验证服务
	if !utils.VerifyServiceStarted("anytls", 15) {
		utils.PrintWarn("AnyTLS 服务启动可能需要一些时间...")
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

// checkSingboxVersion 检查 sing-box 版本是否支持 AnyTLS
func checkSingboxVersion(version string) bool {
	// 移除 v 前缀
	if len(version) > 0 && version[0] == 'v' {
		version = version[1:]
	}

	// 解析版本号
	var major, minor int
	fmt.Sscanf(version, "%d.%d", &major, &minor)

	// 需要 1.12.0 或更高
	return major > 1 || (major == 1 && minor >= 12)
}

// selectPaddingScheme 选择填充方案
func selectPaddingScheme() string {
	fmt.Println()
	fmt.Printf("%s选择填充方案:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s1.%s 默认方案 %s(推荐)%s\n", utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Println("   适合大多数场景，平衡性能和隐蔽性")
	fmt.Printf("%s2.%s 激进方案\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println("   更多填充，更强隐蔽性，略影响性能")
	fmt.Printf("%s3.%s 最小方案\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println("   最少填充，性能最优，隐蔽性较低")
	fmt.Println()

	var choice int
	fmt.Print("请选择 [1-3] (默认: 1): ")
	fmt.Scanln(&choice)

	switch choice {
	case 2:
		return "aggressive"
	case 3:
		return "minimal"
	default:
		return "default"
	}
}

// installAcmeAndCert 安装 acme.sh 并申请证书
func installAcmeAndCert(domain string) error {
	// 检查 acme.sh 是否已安装
	acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
	if !utils.FileExists(acmePath) {
		utils.PrintInfo("安装 acme.sh...")
		cmd := exec.Command("bash", "-c", "curl -sL https://get.acme.sh | sh -s email=admin@"+domain)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("安装 acme.sh 失败: %v", err)
		}
	}

	// 申请证书 (添加 --force 处理已存在的密钥)
	utils.PrintInfo("申请 Let's Encrypt 证书...")
	cmd := exec.Command(acmePath, "--issue", "-d", domain, "--standalone", "--keylength", "ec-256", "--force")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		// 尝试使用 webroot 模式
		utils.PrintWarn("standalone 模式失败，尝试 webroot 模式...")
		os.MkdirAll("/var/www/html", 0755)
		cmd = exec.Command(acmePath, "--issue", "-d", domain, "--webroot", "/var/www/html", "--keylength", "ec-256", "--force")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("证书申请失败，请确保域名已解析且端口 80 可用")
		}
	}

	return nil
}

// installCertToAnyTLS 安装证书到 AnyTLS 目录
func installCertToAnyTLS(domain string) error {
	acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
	defaultGroup := utils.GetDefaultGroup()

	cmd := exec.Command(acmePath, "--install-cert", "-d", domain, "--ecc",
		"--key-file", AnyTLSKeyPath,
		"--fullchain-file", AnyTLSCertPath,
		"--reloadcmd", fmt.Sprintf("chown anytls:%s %s %s && chmod 600 %s && systemctl restart anytls 2>/dev/null || true",
			defaultGroup, AnyTLSKeyPath, AnyTLSCertPath, AnyTLSKeyPath))

	if err := cmd.Run(); err != nil {
		return err
	}

	// 设置权限
	os.Chown(AnyTLSKeyPath, -1, -1) // 由 reloadcmd 处理
	os.Chmod(AnyTLSKeyPath, 0600)
	os.Chmod(AnyTLSCertPath, 0644)

	utils.PrintSuccess("证书安装成功")
	return nil
}

// createAnyTLSSingboxConfig 创建 sing-box 配置
func createAnyTLSSingboxConfig(cfg AnyTLSConfig, paddingScheme []string) error {
	config := map[string]interface{}{
		"log": map[string]interface{}{
			"level":     "info",
			"timestamp": true,
		},
		"inbounds": []map[string]interface{}{
			{
				"type":        "anytls",
				"tag":         "anytls-in",
				"listen":      "::",
				"listen_port": cfg.Port,
				"users": []map[string]interface{}{
					{"password": cfg.Password},
				},
				"padding_scheme": paddingScheme,
				"tls": map[string]interface{}{
					"enabled":          true,
					"server_name":      cfg.Domain,
					"key_path":         AnyTLSKeyPath,
					"certificate_path": AnyTLSCertPath,
				},
			},
		},
		"outbounds": []map[string]interface{}{
			{"type": "direct", "tag": "direct"},
		},
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}

	if err := utils.WriteFile(AnyTLSConfigPath, string(data), 0644); err != nil {
		return err
	}

	// 验证配置
	cmd := exec.Command(SingboxBinaryPath, "check", "-c", AnyTLSConfigPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("配置验证失败: %s", string(output))
	}

	utils.PrintSuccess("配置文件创建成功")
	return nil
}

func createAnyTLSService() error {
	defaultGroup := utils.GetDefaultGroup()
	return CreateSystemdService(SystemdServiceConfig{
		Name:         "anytls",
		Description:  "AnyTLS Service (sing-box)",
		User:         "anytls",
		Group:        defaultGroup,
		ExecStart:    fmt.Sprintf("%s run -c %s", SingboxBinaryPath, AnyTLSConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveAnyTLSConfig(cfg AnyTLSConfig) {
	config := map[string]string{
		"TYPE":            "anytls",
		"SERVER_IP":       cfg.ServerIP,
		"IP_VERSION":      cfg.IPVersion,
		"SINGBOX_VERSION": cfg.SingboxVer,
		"ANYTLS_PORT":     strconv.Itoa(cfg.Port),
		"ANYTLS_PASSWORD": cfg.Password,
		"ANYTLS_DOMAIN":   cfg.Domain,
		"CERT_TYPE":       "letsencrypt",
		"PADDING_NAME":    cfg.PaddingName,
	}
	SaveConfigFile(AnyTLSProxyConfigPath, config)
}

func printAnyTLSSuccess(cfg AnyTLSConfig, surgeProxy string) {
	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   安装完成！%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ServerIP)
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.Domain)
	fmt.Printf("%s端口:%s %d\n", utils.ColorCyan, utils.ColorReset, cfg.Port)
	fmt.Printf("%s密码:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.Password)
	fmt.Printf("%s填充方案:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.PaddingName)
	fmt.Printf("%sSing-box 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.SingboxVer)
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
	fmt.Printf("%s   AnyTLS 配置 (sing-box 内核)%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SERVER_IP"])
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, config["ANYTLS_DOMAIN"])
	fmt.Printf("%s端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["ANYTLS_PORT"])
	if paddingName := config["PADDING_NAME"]; paddingName != "" {
		fmt.Printf("%s填充方案:%s %s\n", utils.ColorCyan, utils.ColorReset, paddingName)
	}
	fmt.Printf("%sSing-box 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SINGBOX_VERSION"])
	fmt.Println()

	surgeProxy := fmt.Sprintf(
		"AnyTLS = anytls, %s, %s, password=%s, sni=%s",
		config["ANYTLS_DOMAIN"], config["ANYTLS_PORT"], config["ANYTLS_PASSWORD"], config["ANYTLS_DOMAIN"],
	)
	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// AnyTLS 更新 (更新 sing-box 内核)
// =========================================

// UpdateAnyTLS 更新 AnyTLS (sing-box 内核)
func UpdateAnyTLS() error {
	if !utils.FileExists(AnyTLSProxyConfigPath) {
		return fmt.Errorf("AnyTLS 未安装")
	}

	config, err := ParseConfigFile(AnyTLSProxyConfigPath)
	if err != nil {
		return err
	}

	currentVersion := config["SINGBOX_VERSION"]
	latestVersion := utils.GetLatestVersion("SagerNet/sing-box", utils.DefaultSingboxVersion)

	fmt.Printf("%s当前 sing-box 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, currentVersion)
	fmt.Printf("%s最新 sing-box 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, latestVersion)

	if currentVersion == latestVersion {
		utils.PrintSuccess("已是最新版本")
		return nil
	}

	if !utils.PromptConfirm("确认更新？") {
		return nil
	}

	utils.ServiceStop("anytls")

	// 备份旧版本
	os.Rename(SingboxBinaryPath, SingboxBinaryPath+".bak")

	arch, _ := utils.DetectArch()
	os.Remove(SingboxBinaryPath)

	if err := downloadSingbox(latestVersion, arch); err != nil {
		os.Rename(SingboxBinaryPath+".bak", SingboxBinaryPath)
		utils.ServiceStart("anytls")
		return fmt.Errorf("更新失败: %v", err)
	}

	config["SINGBOX_VERSION"] = latestVersion
	SaveConfigFile(AnyTLSProxyConfigPath, config)

	utils.ServiceStart("anytls")

	os.Remove(SingboxBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// AnyTLS 续签证书
// =========================================

// RenewAnyTLSCert 续签 AnyTLS 证书
func RenewAnyTLSCert() error {
	if !utils.FileExists(AnyTLSProxyConfigPath) {
		return fmt.Errorf("AnyTLS 未安装")
	}

	config, err := ParseConfigFile(AnyTLSProxyConfigPath)
	if err != nil {
		return err
	}

	domain := config["ANYTLS_DOMAIN"]
	if domain == "" {
		return fmt.Errorf("未找到域名配置")
	}

	utils.PrintInfo("正在续签证书: %s", domain)

	acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
	cmd := exec.Command(acmePath, "--renew", "-d", domain, "--ecc", "--force")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("证书续签失败: %v", err)
	}

	if err := installCertToAnyTLS(domain); err != nil {
		return err
	}

	utils.ServiceRestart("anytls")
	utils.PrintSuccess("证书续签成功")
	return nil
}

// =========================================
// AnyTLS 卸载
// =========================================

// UninstallAnyTLS 卸载 AnyTLS
func UninstallAnyTLS() error {
	utils.PrintInfo("正在卸载 AnyTLS...")

	// 读取配置以获取域名
	if utils.FileExists(AnyTLSProxyConfigPath) {
		config, _ := ParseConfigFile(AnyTLSProxyConfigPath)
		domain := config["ANYTLS_DOMAIN"]
		certType := config["CERT_TYPE"]

		if certType == "letsencrypt" && domain != "" {
			if utils.PromptConfirm("是否删除证书？") {
				acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
				exec.Command(acmePath, "--remove", "-d", domain, "--ecc").Run()
			}
		}
	}

	RemoveSystemdService("anytls")

	os.RemoveAll(AnyTLSConfigDir)
	os.Remove(AnyTLSProxyConfigPath)

	utils.DeleteSystemUser("anytls")

	utils.PrintSuccess("AnyTLS 已卸载")
	return nil
}

// IsAnyTLSInstalled 检查是否已安装
func IsAnyTLSInstalled() bool {
	return utils.FileExists(AnyTLSProxyConfigPath)
}
