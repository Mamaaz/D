package install

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// Sing-box (SS-2022 + Shadow-TLS) 安装
// =========================================

const (
	SingboxBinaryPath      = "/usr/local/bin/sing-box"
	SingboxConfigDir       = "/etc/sing-box"
	SingboxConfigPath      = "/etc/sing-box/config.json"
	SingboxProxyConfigPath = "/etc/singbox-proxy-config.txt"
)

// SS2022Methods 支持的 SS-2022 加密方式
var SS2022Methods = []string{
	"2022-blake3-aes-256-gcm",
	"2022-blake3-aes-128-gcm",
	"2022-blake3-chacha20-poly1305",
}

// SingboxConfig Sing-box 配置
type SingboxConfig struct {
	ServerIP          string
	IPVersion         string
	SSPort            int
	SSMethod          string
	SSPassword        string
	ShadowTLSPort     int
	ShadowTLSPassword string
	TLSDomain         string
	SingboxVersion    string
}

// InstallSingbox 安装 Sing-box (SS-2022 + Shadow-TLS)
func InstallSingbox() (*InstallResult, error) {
	utils.PrintInfo("开始安装 Sing-box (SS-2022 + Shadow-TLS)...")

	// 检查是否已安装
	if utils.FileExists(SingboxProxyConfigPath) {
		if !utils.PromptConfirm("Sing-box 已安装，是否重新安装？") {
			return nil, fmt.Errorf("安装已取消")
		}
		UninstallSingbox()
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

	// 下载 Sing-box
	if err := downloadSingbox(singboxVersion, arch); err != nil {
		return nil, fmt.Errorf("下载 Sing-box 失败: %v", err)
	}

	// 选择加密方式
	ssMethod := selectSSMethod()
	ssPassword := generateSSPassword(ssMethod)

	// 获取配置参数
	ssPort := promptPort("请输入 SS 监听端口", 8388)
	tlsDomain := utils.SelectTLSDomain()
	shadowTLSPort := promptPort("请输入 Shadow-TLS 监听端口", 9443)
	shadowTLSPassword := utils.GeneratePassword(16)

	config := SingboxConfig{
		ServerIP:          serverIP,
		IPVersion:         ipVersion,
		SSPort:            ssPort,
		SSMethod:          ssMethod,
		SSPassword:        ssPassword,
		ShadowTLSPort:     shadowTLSPort,
		ShadowTLSPassword: shadowTLSPassword,
		TLSDomain:         tlsDomain,
		SingboxVersion:    singboxVersion,
	}

	// 创建配置
	if err := createSingboxConfig(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建系统用户
	utils.CreateSystemUser("sing-box")

	// 创建 systemd 服务
	if err := createSingboxService(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("sing-box")
	utils.ServiceStart("sing-box")

	// 验证服务
	if !utils.VerifyServiceStarted("sing-box", 10) {
		return nil, fmt.Errorf("Sing-box 服务启动失败")
	}

	// 保存配置
	saveSingboxConfig(config)

	// 生成客户端配置
	surgeProxy := fmt.Sprintf(
		"Proxy = ss, %s, %d, encrypt-method=%s, password=%s, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=3",
		serverIP, shadowTLSPort, ssMethod, ssPassword, shadowTLSPassword, tlsDomain,
	)

	result := &InstallResult{
		Success:    true,
		ServerIP:   serverIP,
		IPVersion:  ipVersion,
		Port:       shadowTLSPort,
		SurgeProxy: surgeProxy,
	}

	printSingboxSuccess(config, surgeProxy)

	return result, nil
}

func downloadSingbox(version, arch string) error {
	if utils.FileExists(SingboxBinaryPath) {
		return nil
	}

	// 去掉版本号前的 v
	versionNum := version
	if len(version) > 0 && version[0] == 'v' {
		versionNum = version[1:]
	}

	url := fmt.Sprintf(
		"https://github.com/SagerNet/sing-box/releases/download/%s/sing-box-%s-linux-%s.tar.gz",
		version, versionNum, arch,
	)

	tempFile := "/tmp/sing-box.tar.gz"
	if err := utils.DownloadFile(url, tempFile, 3); err != nil {
		return err
	}
	defer os.Remove(tempFile)

	// 解压
	if err := utils.ExtractTarGz(tempFile, "/tmp"); err != nil {
		return fmt.Errorf("解压失败: %v", err)
	}

	// 查找并移动二进制文件
	extractDir := fmt.Sprintf("/tmp/sing-box-%s-linux-%s", versionNum, arch)
	srcPath := extractDir + "/sing-box"

	if utils.FileExists(srcPath) {
		if err := os.Rename(srcPath, SingboxBinaryPath); err != nil {
			// 尝试复制
			cmd := newCommand("cp", srcPath, SingboxBinaryPath)
			if err := cmd.Run(); err != nil {
				return err
			}
		}
	} else {
		return fmt.Errorf("找不到 sing-box 二进制文件")
	}

	os.Chmod(SingboxBinaryPath, 0755)
	os.RemoveAll(extractDir)

	utils.PrintSuccess("Sing-box 下载成功")
	return nil
}

func selectSSMethod() string {
	fmt.Println()
	fmt.Printf("%s选择 Shadowsocks 加密方式:%s\n", utils.ColorCyan, utils.ColorReset)
	for i, method := range SS2022Methods {
		suffix := ""
		if i == 0 {
			suffix = utils.ColorGreen + " (推荐)" + utils.ColorReset
		}
		fmt.Printf("  %d. %s%s\n", i+1, method, suffix)
	}
	fmt.Println()

	var choice int
	fmt.Print("请选择 (默认: 1): ")
	fmt.Scanln(&choice)

	if choice < 1 || choice > len(SS2022Methods) {
		choice = 1
	}

	return SS2022Methods[choice-1]
}

func generateSSPassword(method string) string {
	switch method {
	case "2022-blake3-aes-128-gcm":
		return utils.GenerateBase64Key(16)
	default:
		return utils.GenerateBase64Key(32)
	}
}

func createSingboxConfig(cfg SingboxConfig) error {
	if err := os.MkdirAll(SingboxConfigDir, 0755); err != nil {
		return err
	}

	config := map[string]interface{}{
		"log": map[string]interface{}{
			"level":     "info",
			"timestamp": true,
		},
		"inbounds": []map[string]interface{}{
			{
				"type":          "shadowsocks",
				"tag":           "ss-in",
				"listen":        "127.0.0.1",
				"listen_port":   cfg.SSPort,
				"method":        cfg.SSMethod,
				"password":      cfg.SSPassword,
				"tcp_fast_open": true,
				"udp_fragment":  true,
			},
			{
				"type":        "shadowtls",
				"tag":         "st-in",
				"listen":      "::",
				"listen_port": cfg.ShadowTLSPort,
				"version":     3,
				"users": []map[string]interface{}{
					{
						"name":     "user1",
						"password": cfg.ShadowTLSPassword,
					},
				},
				"handshake": map[string]interface{}{
					"server":      cfg.TLSDomain,
					"server_port": 443,
				},
				"strict_mode": true,
				"detour":      "ss-in",
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

	return utils.WriteFile(SingboxConfigPath, string(data), PermConfigFile)
}

func createSingboxService() error {
	return CreateSystemdService(SystemdServiceConfig{
		Name:        "sing-box",
		Description: "Sing-box Service",
		User:        "sing-box",
		ExecStart:   fmt.Sprintf("%s run -c %s", SingboxBinaryPath, SingboxConfigPath),
	})
}

func saveSingboxConfig(cfg SingboxConfig) {
	config := map[string]string{
		"TYPE":                "singbox",
		"SERVER_IP":           cfg.ServerIP,
		"IP_VERSION":          cfg.IPVersion,
		"SINGBOX_VERSION":     cfg.SingboxVersion,
		"SS_PORT":             strconv.Itoa(cfg.SSPort),
		"SS_PASSWORD":         cfg.SSPassword,
		"SS_METHOD":           cfg.SSMethod,
		"SHADOW_TLS_PORT":     strconv.Itoa(cfg.ShadowTLSPort),
		"SHADOW_TLS_PASSWORD": cfg.ShadowTLSPassword,
		"TLS_DOMAIN":          cfg.TLSDomain,
	}
	SaveConfigFile(SingboxProxyConfigPath, config)
}

func printSingboxSuccess(cfg SingboxConfig, surgeProxy string) {
	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   安装完成！%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ServerIP)
	fmt.Printf("%sSS 加密方式:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.SSMethod)
	fmt.Printf("%sShadow-TLS 端口:%s %d\n", utils.ColorCyan, utils.ColorReset, cfg.ShadowTLSPort)
	fmt.Println()
	fmt.Printf("%sSurge 配置:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Sing-box 查看配置
// =========================================

// ViewSingboxConfig 查看 Sing-box 配置
func ViewSingboxConfig() {
	if !utils.FileExists(SingboxProxyConfigPath) {
		utils.PrintError("Sing-box 未安装")
		return
	}

	config, err := ParseConfigFile(SingboxProxyConfigPath)
	if err != nil {
		utils.PrintError("读取配置失败: %v", err)
		return
	}

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   Sing-box (SS-2022) 配置%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SERVER_IP"])
	fmt.Printf("%s加密方式:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SS_METHOD"])
	fmt.Printf("%sShadow-TLS 端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SHADOW_TLS_PORT"])
	fmt.Println()

	surgeProxy := fmt.Sprintf(
		"Proxy = ss, %s, %s, encrypt-method=%s, password=%s, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=3",
		config["SERVER_IP"], config["SHADOW_TLS_PORT"], config["SS_METHOD"],
		config["SS_PASSWORD"], config["SHADOW_TLS_PASSWORD"], config["TLS_DOMAIN"],
	)
	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Sing-box 更新
// =========================================

// UpdateSingbox 更新 Sing-box
func UpdateSingbox() error {
	if !utils.FileExists(SingboxProxyConfigPath) {
		return fmt.Errorf("Sing-box 未安装")
	}

	config, err := ParseConfigFile(SingboxProxyConfigPath)
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
	utils.ServiceStop("sing-box")

	// 备份旧版本
	os.Rename(SingboxBinaryPath, SingboxBinaryPath+".bak")

	// 下载新版本
	arch, _ := utils.DetectArch()
	os.Remove(SingboxBinaryPath) // 确保下载新版本
	if err := downloadSingbox(latestVersion, arch); err != nil {
		// 回滚
		os.Rename(SingboxBinaryPath+".bak", SingboxBinaryPath)
		utils.ServiceStart("sing-box")
		return fmt.Errorf("更新失败: %v", err)
	}

	// 更新配置中的版本
	config["SINGBOX_VERSION"] = latestVersion
	SaveConfigFile(SingboxProxyConfigPath, config)

	// 启动服务
	utils.ServiceStart("sing-box")

	os.Remove(SingboxBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// Sing-box 卸载
// =========================================

// UninstallSingbox 卸载 Sing-box
func UninstallSingbox() error {
	utils.PrintInfo("正在卸载 Sing-box...")

	// 删除服务
	RemoveSystemdService("sing-box")

	// 删除配置
	os.RemoveAll(SingboxConfigDir)
	os.Remove(SingboxProxyConfigPath)

	// 如果没有其他服务使用 sing-box，删除二进制和用户
	if !IsSingboxShared(SingboxProxyConfigPath) {
		os.Remove(SingboxBinaryPath)
		utils.DeleteSystemUser("sing-box")
	} else {
		utils.PrintInfo("其他服务仍在使用 sing-box，保留二进制文件")
	}

	utils.PrintSuccess("Sing-box 已卸载")
	return nil
}

// IsSingboxInstalled 检查是否已安装
func IsSingboxInstalled() bool {
	return utils.FileExists(SingboxProxyConfigPath)
}
