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
// VLESS Reality 安装
// =========================================

const (
	RealityConfigDir       = "/etc/sing-box-reality"
	RealityConfigPath      = "/etc/sing-box-reality/config.json"
	RealityProxyConfigPath = "/etc/reality-proxy-config.txt"
)

// RealityConfig Reality 配置
type RealityConfig struct {
	ServerIP       string
	IPVersion      string
	Port           int
	UUID           string
	PrivateKey     string
	PublicKey      string
	ShortID        string
	ServerName     string
	SingboxVersion string
}

// InstallReality 安装 VLESS Reality
func InstallReality() (*InstallResult, error) {
	utils.PrintInfo("开始安装 VLESS Reality...")

	// 检查是否已安装
	if utils.FileExists(RealityProxyConfigPath) {
		if !utils.PromptConfirm("VLESS Reality 已安装，是否重新安装？") {
			return nil, fmt.Errorf("安装已取消")
		}
		UninstallReality()
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
	singboxVersion := utils.GetLatestVersion("SagerNet/sing-box", utils.DefaultSingboxVersion)
	utils.PrintInfo("Sing-box 版本: %s", singboxVersion)

	// 下载 Sing-box (如果不存在)
	if !utils.FileExists(SingboxBinaryPath) {
		if err := downloadSingbox(singboxVersion, arch); err != nil {
			return nil, fmt.Errorf("下载 Sing-box 失败: %v", err)
		}
	}

	// 获取配置参数
	port := promptPort("请输入 Reality 监听端口", 443)
	serverName := selectRealityServerName()

	// 生成密钥
	uuid := generateUUID()
	privateKey, publicKey := generateRealityKeyPair()
	shortID := generateShortID()

	config := RealityConfig{
		ServerIP:       serverIP,
		IPVersion:      ipVersion,
		Port:           port,
		UUID:           uuid,
		PrivateKey:     privateKey,
		PublicKey:      publicKey,
		ShortID:        shortID,
		ServerName:     serverName,
		SingboxVersion: singboxVersion,
	}

	// 创建配置
	if err := createRealityConfig(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建系统用户
	utils.CreateSystemUser("sing-box")

	// 创建 systemd 服务
	if err := createRealityService(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("sing-box-reality")
	utils.ServiceStart("sing-box-reality")

	// 验证服务
	if !utils.VerifyServiceStarted("sing-box-reality", 10) {
		return nil, fmt.Errorf("Reality 服务启动失败")
	}

	// 保存配置
	saveRealityConfig(config)

	// 生成客户端配置
	surgeProxy := fmt.Sprintf(
		"Reality = vless, %s, %d, username=%s, sni=%s, public-key=%s, short-id=%s, tfo=true, udp-relay=true",
		serverIP, port, uuid, serverName, publicKey, shortID,
	)

	result := &InstallResult{
		Success:    true,
		ServerIP:   serverIP,
		IPVersion:  ipVersion,
		Port:       port,
		SurgeProxy: surgeProxy,
	}

	printRealitySuccess(config, surgeProxy)

	return result, nil
}

func selectRealityServerName() string {
	serverNames := []string{
		"www.apple.com",
		"www.microsoft.com",
		"www.amazon.com",
		"www.cloudflare.com",
		"gateway.icloud.com",
	}

	fmt.Println()
	fmt.Printf("%s选择 Reality 目标服务器:%s\n", utils.ColorCyan, utils.ColorReset)
	for i, name := range serverNames {
		suffix := ""
		if i == 0 {
			suffix = utils.ColorGreen + " (推荐)" + utils.ColorReset
		}
		fmt.Printf("  %d. %s%s\n", i+1, name, suffix)
	}
	fmt.Println("  0. 自定义服务器")
	fmt.Println()

	var choice int
	fmt.Print("请选择 (默认: 1): ")
	fmt.Scanln(&choice)

	if choice == 0 {
		return utils.PromptInput("请输入目标服务器", "")
	}

	if choice < 1 || choice > len(serverNames) {
		choice = 1
	}

	return serverNames[choice-1]
}

func generateUUID() string {
	cmd := exec.Command(SingboxBinaryPath, "generate", "uuid")
	output, err := cmd.Output()
	if err != nil {
		// 使用简单的 UUID 生成
		return utils.GeneratePassword(32)
	}
	return strings.TrimSpace(string(output))
}

func generateRealityKeyPair() (string, string) {
	cmd := exec.Command(SingboxBinaryPath, "generate", "reality-keypair")
	output, err := cmd.Output()
	if err != nil {
		// 返回占位符
		return utils.GeneratePassword(32), utils.GeneratePassword(32)
	}

	lines := strings.Split(string(output), "\n")
	var privateKey, publicKey string
	for _, line := range lines {
		if strings.HasPrefix(line, "PrivateKey:") {
			privateKey = strings.TrimSpace(strings.TrimPrefix(line, "PrivateKey:"))
		}
		if strings.HasPrefix(line, "PublicKey:") {
			publicKey = strings.TrimSpace(strings.TrimPrefix(line, "PublicKey:"))
		}
	}

	return privateKey, publicKey
}

func generateShortID() string {
	cmd := exec.Command(SingboxBinaryPath, "generate", "rand", "--hex", "8")
	output, err := cmd.Output()
	if err != nil {
		return utils.GeneratePassword(8)
	}
	return strings.TrimSpace(string(output))
}

func createRealityConfig(cfg RealityConfig) error {
	if err := os.MkdirAll(RealityConfigDir, 0755); err != nil {
		return err
	}

	config := map[string]interface{}{
		"log": map[string]interface{}{
			"level":     "info",
			"timestamp": true,
		},
		"inbounds": []map[string]interface{}{
			{
				"type":        "vless",
				"tag":         "vless-in",
				"listen":      "::",
				"listen_port": cfg.Port,
				"users": []map[string]interface{}{
					{
						"uuid": cfg.UUID,
						"flow": "xtls-rprx-vision",
					},
				},
				"tls": map[string]interface{}{
					"enabled":     true,
					"server_name": cfg.ServerName,
					"reality": map[string]interface{}{
						"enabled": true,
						"handshake": map[string]interface{}{
							"server":      cfg.ServerName,
							"server_port": 443,
						},
						"private_key": cfg.PrivateKey,
						"short_id":    []string{cfg.ShortID},
					},
				},
			},
		},
		"outbounds": []map[string]interface{}{
			{
				"type": "direct",
				"tag":  "direct",
			},
		},
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}

	return utils.WriteFile(RealityConfigPath, string(data), 0600)
}

func createRealityService() error {
	return CreateSystemdService(SystemdServiceConfig{
		Name:         "sing-box-reality",
		Description:  "Sing-box Reality Service",
		User:         "root",
		ExecStart:    fmt.Sprintf("%s run -c %s", SingboxBinaryPath, RealityConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveRealityConfig(cfg RealityConfig) {
	config := map[string]string{
		"TYPE":            "reality",
		"SERVER_IP":       cfg.ServerIP,
		"IP_VERSION":      cfg.IPVersion,
		"SINGBOX_VERSION": cfg.SingboxVersion,
		"PORT":            strconv.Itoa(cfg.Port),
		"UUID":            cfg.UUID,
		"PRIVATE_KEY":     cfg.PrivateKey,
		"PUBLIC_KEY":      cfg.PublicKey,
		"SHORT_ID":        cfg.ShortID,
		"SERVER_NAME":     cfg.ServerName,
	}
	SaveConfigFile(RealityProxyConfigPath, config)
}

func printRealitySuccess(cfg RealityConfig, surgeProxy string) {
	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   安装完成！%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ServerIP)
	fmt.Printf("%s端口:%s %d\n", utils.ColorCyan, utils.ColorReset, cfg.Port)
	fmt.Printf("%sUUID:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.UUID)
	fmt.Printf("%s目标服务器:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ServerName)
	fmt.Printf("%sPublic Key:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.PublicKey)
	fmt.Printf("%sShort ID:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ShortID)
	fmt.Println()
	fmt.Printf("%sSurge 配置:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Reality 查看配置
// =========================================

// ViewRealityConfig 查看 Reality 配置
func ViewRealityConfig() {
	if !utils.FileExists(RealityProxyConfigPath) {
		utils.PrintError("VLESS Reality 未安装")
		return
	}

	config, err := ParseConfigFile(RealityProxyConfigPath)
	if err != nil {
		utils.PrintError("读取配置失败: %v", err)
		return
	}

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   VLESS Reality 配置%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SERVER_IP"])
	fmt.Printf("%s端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["PORT"])
	fmt.Printf("%sUUID:%s %s\n", utils.ColorCyan, utils.ColorReset, config["UUID"])
	fmt.Printf("%s目标服务器:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SERVER_NAME"])
	fmt.Println()

	surgeProxy := fmt.Sprintf(
		"Reality = vless, %s, %s, username=%s, sni=%s, public-key=%s, short-id=%s, tfo=true, udp-relay=true",
		config["SERVER_IP"], config["PORT"], config["UUID"],
		config["SERVER_NAME"], config["PUBLIC_KEY"], config["SHORT_ID"],
	)
	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Reality 更新
// =========================================

// UpdateReality 更新 Reality
func UpdateReality() error {
	if !utils.FileExists(RealityProxyConfigPath) {
		return fmt.Errorf("VLESS Reality 未安装")
	}

	// Reality 使用和 Singbox 相同的更新逻辑
	config, err := ParseConfigFile(RealityProxyConfigPath)
	if err != nil {
		return err
	}

	currentVersion := config["SINGBOX_VERSION"]
	latestVersion := utils.GetLatestVersion("SagerNet/sing-box", utils.DefaultSingboxVersion)

	fmt.Printf("%s当前版本:%s %s\n", utils.ColorCyan, utils.ColorReset, currentVersion)
	fmt.Printf("%s最新版本:%s %s\n", utils.ColorCyan, utils.ColorReset, latestVersion)

	if currentVersion == latestVersion {
		utils.PrintSuccess("已是最新版本")
		return nil
	}

	if !utils.PromptConfirm("确认更新？") {
		return nil
	}

	// 停止服务
	utils.ServiceStop("sing-box-reality")

	// 更新 Sing-box
	os.Rename(SingboxBinaryPath, SingboxBinaryPath+".bak")
	arch, _ := utils.DetectArch()
	os.Remove(SingboxBinaryPath)

	if err := downloadSingbox(latestVersion, arch); err != nil {
		os.Rename(SingboxBinaryPath+".bak", SingboxBinaryPath)
		utils.ServiceStart("sing-box-reality")
		return fmt.Errorf("更新失败: %v", err)
	}

	config["SINGBOX_VERSION"] = latestVersion
	SaveConfigFile(RealityProxyConfigPath, config)

	utils.ServiceStart("sing-box-reality")

	os.Remove(SingboxBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// Reality 卸载
// =========================================

// UninstallReality 卸载 Reality
func UninstallReality() error {
	utils.PrintInfo("正在卸载 VLESS Reality...")

	RemoveSystemdService("sing-box-reality")

	os.RemoveAll(RealityConfigDir)
	os.Remove(RealityProxyConfigPath)

	// 如果没有其他 sing-box 服务在使用，删除二进制
	if !utils.FileExists(SingboxProxyConfigPath) {
		os.Remove(SingboxBinaryPath)
		utils.DeleteSystemUser("sing-box")
	}

	utils.PrintSuccess("VLESS Reality 已卸载")
	return nil
}

// IsRealityInstalled 检查是否已安装
func IsRealityInstalled() bool {
	return utils.FileExists(RealityProxyConfigPath)
}
