package install

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// Hysteria2 安装 (使用 sing-box 内核)
// =========================================

const (
	Hysteria2ConfigDir       = "/etc/hysteria2"
	Hysteria2ConfigPath      = "/etc/hysteria2/config.json"
	Hysteria2ProxyConfigPath = "/etc/hysteria2-proxy-config.txt"
	Hysteria2CertPath        = "/etc/hysteria2/server.crt"
	Hysteria2KeyPath         = "/etc/hysteria2/server.key"
)

// Hysteria2Config Hysteria2 配置
type Hysteria2Config struct {
	ServerIP     string
	IPVersion    string
	Port         int
	Password     string
	Domain       string
	EnableObfs   bool
	ObfsPassword string
	SingboxVer   string
}

// InstallHysteria2 安装 Hysteria2 (使用 sing-box 内核)
func InstallHysteria2() (*InstallResult, error) {
	utils.PrintInfo("开始安装 Hysteria2 (sing-box 内核)...")

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

	// 获取 sing-box 版本
	singboxVersion := utils.GetLatestVersion("SagerNet/sing-box", utils.DefaultSingboxVersion)
	utils.PrintInfo("Sing-box 版本: %s", singboxVersion)

	// 下载 sing-box
	if err := downloadSingbox(singboxVersion, arch); err != nil {
		return nil, fmt.Errorf("下载 sing-box 失败: %v", err)
	}

	// 获取配置参数
	port := promptPort("请输入 Hysteria2 端口", 443)

	// 混淆配置
	enableObfs := false
	obfsPassword := ""
	fmt.Println()
	if utils.PromptConfirm("是否启用混淆？(增强隐蔽性，略影响性能)") {
		enableObfs = true
		obfsPassword = utils.GeneratePassword(16)
		utils.PrintSuccess("混淆密码: %s", obfsPassword)
	}

	// 获取域名
	fmt.Println()
	utils.PrintInfo("Hysteria2 需要域名来申请 Let's Encrypt 证书")
	utils.PrintWarn("请确保域名已解析到此服务器")
	domain := utils.PromptInput("请输入域名", "")
	if domain == "" {
		return nil, fmt.Errorf("域名不能为空")
	}

	// 生成密码
	password := utils.GeneratePassword(16)

	config := Hysteria2Config{
		ServerIP:     serverIP,
		IPVersion:    ipVersion,
		Port:         port,
		Password:     password,
		Domain:       domain,
		EnableObfs:   enableObfs,
		ObfsPassword: obfsPassword,
		SingboxVer:   singboxVersion,
	}

	// 安装 acme.sh 并申请证书
	utils.PrintInfo("安装 acme.sh 并申请证书...")
	if err := installAcmeAndCert(domain); err != nil {
		return nil, fmt.Errorf("证书申请失败: %v", err)
	}

	// 创建配置目录
	if err := os.MkdirAll(Hysteria2ConfigDir, 0755); err != nil {
		return nil, err
	}

	// 安装证书到 hysteria2 目录
	if err := installCertToHysteria2(domain); err != nil {
		return nil, fmt.Errorf("证书安装失败: %v", err)
	}

	// 创建 sing-box 配置
	if err := createHysteria2SingboxConfig(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建系统用户
	utils.CreateSystemUser("hysteria2")

	// 创建 systemd 服务
	if err := createHysteria2Service(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("hysteria2")
	utils.ServiceStart("hysteria2")

	// 验证服务
	if !utils.VerifyServiceStarted("hysteria2", 15) {
		utils.PrintWarn("Hysteria2 服务启动可能需要一些时间...")
	}

	// 保存配置
	saveHysteria2Config(config)

	// 生成客户端配置
	surgeProxy := generateHysteria2SurgeProxy(config)

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

// installCertToHysteria2 安装证书到 Hysteria2 目录
func installCertToHysteria2(domain string) error {
	acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
	defaultGroup := utils.GetDefaultGroup()

	cmd := exec.Command(acmePath, "--install-cert", "-d", domain, "--ecc",
		"--key-file", Hysteria2KeyPath,
		"--fullchain-file", Hysteria2CertPath,
		"--reloadcmd", fmt.Sprintf("chown hysteria2:%s %s %s && chmod 600 %s && systemctl restart hysteria2 2>/dev/null || true",
			defaultGroup, Hysteria2KeyPath, Hysteria2CertPath, Hysteria2KeyPath))

	if err := cmd.Run(); err != nil {
		return err
	}

	os.Chmod(Hysteria2KeyPath, 0600)
	os.Chmod(Hysteria2CertPath, 0644)

	utils.PrintSuccess("证书安装成功")
	return nil
}

// createHysteria2SingboxConfig 创建 sing-box 配置
func createHysteria2SingboxConfig(cfg Hysteria2Config) error {
	inbound := map[string]interface{}{
		"type":        "hysteria2",
		"tag":         "hy2-in",
		"listen":      "::",
		"listen_port": cfg.Port,
		"users": []map[string]interface{}{
			{"name": "user1", "password": cfg.Password},
		},
		"tls": map[string]interface{}{
			"enabled":          true,
			"server_name":      cfg.Domain,
			"key_path":         Hysteria2KeyPath,
			"certificate_path": Hysteria2CertPath,
		},
	}

	// 添加混淆配置
	if cfg.EnableObfs {
		inbound["obfs"] = map[string]interface{}{
			"type":     "salamander",
			"password": cfg.ObfsPassword,
		}
	}

	config := map[string]interface{}{
		"log": map[string]interface{}{
			"level":     "info",
			"timestamp": true,
		},
		"inbounds": []map[string]interface{}{inbound},
		"outbounds": []map[string]interface{}{
			{"type": "direct", "tag": "direct"},
		},
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}

	if err := utils.WriteFile(Hysteria2ConfigPath, string(data), 0600); err != nil {
		return err
	}

	// 验证配置
	cmd := exec.Command(SingboxBinaryPath, "check", "-c", Hysteria2ConfigPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("配置验证失败: %s", string(output))
	}

	utils.PrintSuccess("配置文件创建成功")
	return nil
}

func createHysteria2Service() error {
	defaultGroup := utils.GetDefaultGroup()
	return CreateSystemdService(SystemdServiceConfig{
		Name:         "hysteria2",
		Description:  "Hysteria2 Service (sing-box)",
		User:         "hysteria2",
		Group:        defaultGroup,
		ExecStart:    fmt.Sprintf("%s run -c %s", SingboxBinaryPath, Hysteria2ConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveHysteria2Config(cfg Hysteria2Config) {
	config := map[string]string{
		"TYPE":               "hysteria2",
		"SERVER_IP":          cfg.ServerIP,
		"IP_VERSION":         cfg.IPVersion,
		"SINGBOX_VERSION":    cfg.SingboxVer,
		"HYSTERIA2_PORT":     strconv.Itoa(cfg.Port),
		"HYSTERIA2_PASSWORD": cfg.Password,
		"HYSTERIA2_DOMAIN":   cfg.Domain,
		"CERT_TYPE":          "letsencrypt",
		"ENABLE_OBFS":        strconv.FormatBool(cfg.EnableObfs),
	}
	if cfg.EnableObfs {
		config["OBFS_PASSWORD"] = cfg.ObfsPassword
	}
	SaveConfigFile(Hysteria2ProxyConfigPath, config)
}

func generateHysteria2SurgeProxy(cfg Hysteria2Config) string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Hysteria2 = hysteria2, %s, %d, password=%s, sni=%s",
		cfg.Domain, cfg.Port, cfg.Password, cfg.Domain))
	if cfg.EnableObfs {
		sb.WriteString(fmt.Sprintf(", obfs=salamander, obfs-password=%s", cfg.ObfsPassword))
	}
	return sb.String()
}

func generateHysteria2ShareLink(cfg Hysteria2Config) string {
	var link strings.Builder
	link.WriteString(fmt.Sprintf("hysteria2://%s@%s:%d?sni=%s",
		cfg.Password, cfg.Domain, cfg.Port, cfg.Domain))
	if cfg.EnableObfs {
		link.WriteString(fmt.Sprintf("&obfs=salamander&obfs-password=%s", cfg.ObfsPassword))
	}
	link.WriteString(fmt.Sprintf("#Hysteria2-%s", cfg.Domain))
	return link.String()
}

func printHysteria2Success(cfg Hysteria2Config, surgeProxy string) {
	shareLink := generateHysteria2ShareLink(cfg)

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   安装完成！%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ServerIP)
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.Domain)
	fmt.Printf("%s端口:%s %d\n", utils.ColorCyan, utils.ColorReset, cfg.Port)
	fmt.Printf("%s密码:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.Password)
	if cfg.EnableObfs {
		fmt.Printf("%s混淆:%s 已启用 (salamander)\n", utils.ColorCyan, utils.ColorReset)
		fmt.Printf("%s混淆密码:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ObfsPassword)
	}
	fmt.Printf("%sSing-box 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.SingboxVer)
	fmt.Println()
	fmt.Printf("%s分享链接:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, shareLink, utils.ColorReset)
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

	enableObfs := config["ENABLE_OBFS"] == "true"

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   Hysteria2 配置 (sing-box 内核)%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SERVER_IP"])
	fmt.Printf("%s域名:%s %s\n", utils.ColorCyan, utils.ColorReset, config["HYSTERIA2_DOMAIN"])
	fmt.Printf("%s端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["HYSTERIA2_PORT"])
	if enableObfs {
		fmt.Printf("%s混淆:%s 已启用\n", utils.ColorCyan, utils.ColorReset)
	}
	fmt.Printf("%sSing-box 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SINGBOX_VERSION"])
	fmt.Println()

	// 生成分享链接
	var shareLink strings.Builder
	shareLink.WriteString(fmt.Sprintf("hysteria2://%s@%s:%s?sni=%s",
		config["HYSTERIA2_PASSWORD"], config["HYSTERIA2_DOMAIN"],
		config["HYSTERIA2_PORT"], config["HYSTERIA2_DOMAIN"]))
	if enableObfs {
		shareLink.WriteString(fmt.Sprintf("&obfs=salamander&obfs-password=%s", config["OBFS_PASSWORD"]))
	}
	shareLink.WriteString("#Hysteria2")

	fmt.Printf("%s分享链接:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, shareLink.String(), utils.ColorReset)
	fmt.Println()

	// Surge 配置
	var surgeProxy strings.Builder
	surgeProxy.WriteString(fmt.Sprintf("Hysteria2 = hysteria2, %s, %s, password=%s, sni=%s",
		config["HYSTERIA2_DOMAIN"], config["HYSTERIA2_PORT"],
		config["HYSTERIA2_PASSWORD"], config["HYSTERIA2_DOMAIN"]))
	if enableObfs {
		surgeProxy.WriteString(fmt.Sprintf(", obfs=salamander, obfs-password=%s", config["OBFS_PASSWORD"]))
	}

	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy.String(), utils.ColorReset)
	fmt.Println()
}

// =========================================
// Hysteria2 更新 (更新 sing-box 内核)
// =========================================

// UpdateHysteria2 更新 Hysteria2 (sing-box 内核)
func UpdateHysteria2() error {
	if !utils.FileExists(Hysteria2ProxyConfigPath) {
		return fmt.Errorf("Hysteria2 未安装")
	}

	config, err := ParseConfigFile(Hysteria2ProxyConfigPath)
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

	utils.ServiceStop("hysteria2")

	// 备份旧版本
	os.Rename(SingboxBinaryPath, SingboxBinaryPath+".bak")

	arch, _ := utils.DetectArch()
	os.Remove(SingboxBinaryPath)

	if err := downloadSingbox(latestVersion, arch); err != nil {
		os.Rename(SingboxBinaryPath+".bak", SingboxBinaryPath)
		utils.ServiceStart("hysteria2")
		return fmt.Errorf("更新失败: %v", err)
	}

	config["SINGBOX_VERSION"] = latestVersion
	SaveConfigFile(Hysteria2ProxyConfigPath, config)

	utils.ServiceStart("hysteria2")

	os.Remove(SingboxBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// Hysteria2 续签证书
// =========================================

// RenewHysteria2Cert 续签 Hysteria2 证书
func RenewHysteria2Cert() error {
	if !utils.FileExists(Hysteria2ProxyConfigPath) {
		return fmt.Errorf("Hysteria2 未安装")
	}

	config, err := ParseConfigFile(Hysteria2ProxyConfigPath)
	if err != nil {
		return err
	}

	domain := config["HYSTERIA2_DOMAIN"]
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

	if err := installCertToHysteria2(domain); err != nil {
		return err
	}

	utils.ServiceRestart("hysteria2")
	utils.PrintSuccess("证书续签成功")
	return nil
}

// =========================================
// Hysteria2 卸载
// =========================================

// UninstallHysteria2 卸载 Hysteria2
func UninstallHysteria2() error {
	utils.PrintInfo("正在卸载 Hysteria2...")

	// 读取配置以获取域名
	if utils.FileExists(Hysteria2ProxyConfigPath) {
		config, _ := ParseConfigFile(Hysteria2ProxyConfigPath)
		domain := config["HYSTERIA2_DOMAIN"]
		certType := config["CERT_TYPE"]

		if certType == "letsencrypt" && domain != "" {
			if utils.PromptConfirm("是否删除证书？") {
				acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
				exec.Command(acmePath, "--remove", "-d", domain, "--ecc").Run()
			}
		}
	}

	RemoveSystemdService("hysteria2")

	os.RemoveAll(Hysteria2ConfigDir)
	os.Remove(Hysteria2ProxyConfigPath)

	utils.DeleteSystemUser("hysteria2")

	utils.PrintSuccess("Hysteria2 已卸载")
	return nil
}

// IsHysteria2Installed 检查是否已安装
func IsHysteria2Installed() bool {
	return utils.FileExists(Hysteria2ProxyConfigPath)
}
