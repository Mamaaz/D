package install

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// Snell + Shadow-TLS 安装
// =========================================

const (
	SnellConfigPath      = "/etc/snell/snell-server.conf"
	SnellBinaryPath      = "/usr/local/bin/snell-server"
	ShadowTLSBinaryPath  = "/usr/local/bin/shadow-tls"
	SnellProxyConfigPath = "/etc/snell-proxy-config.txt"
)

// SnellConfig Snell 配置
type SnellConfig struct {
	ServerIP          string
	IPVersion         string
	SnellPort         int
	SnellPSK          string
	ShadowTLSPort     int
	ShadowTLSPassword string
	TLSDomain         string
	SnellVersion      string
	ShadowTLSVersion  string
}

// InstallSnell 安装 Snell + Shadow-TLS
func InstallSnell() (*InstallResult, error) {
	utils.PrintInfo("开始安装 Snell + Shadow-TLS...")

	// 检查是否已安装
	if utils.FileExists(SnellProxyConfigPath) {
		if !utils.PromptConfirm("Snell 已安装，是否重新安装？") {
			return nil, fmt.Errorf("安装已取消")
		}
		UninstallSnell()
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
	snellVersion := utils.GetSnellLatestVersion()
	shadowTLSVersion := utils.GetLatestVersion("ihciah/shadow-tls", utils.DefaultShadowTLSVersion)

	utils.PrintInfo("Snell 版本: %s", snellVersion)
	utils.PrintInfo("Shadow-TLS 版本: %s", shadowTLSVersion)

	// 下载 Snell
	if err := downloadSnell(snellVersion, arch); err != nil {
		return nil, fmt.Errorf("下载 Snell 失败: %v", err)
	}

	// 下载 Shadow-TLS
	if err := downloadShadowTLS(shadowTLSVersion, arch); err != nil {
		return nil, fmt.Errorf("下载 Shadow-TLS 失败: %v", err)
	}

	// 获取配置参数
	snellPort := promptPort("请输入 Snell 监听端口", 10086)
	tlsDomain := utils.SelectTLSDomain()
	shadowTLSPort := promptPort("请输入 Shadow-TLS 监听端口", 8443)

	// 生成密码
	snellPSK := utils.GeneratePassword(16)
	shadowTLSPassword := utils.GeneratePassword(16)

	config := SnellConfig{
		ServerIP:          serverIP,
		IPVersion:         ipVersion,
		SnellPort:         snellPort,
		SnellPSK:          snellPSK,
		ShadowTLSPort:     shadowTLSPort,
		ShadowTLSPassword: shadowTLSPassword,
		TLSDomain:         tlsDomain,
		SnellVersion:      snellVersion,
		ShadowTLSVersion:  shadowTLSVersion,
	}

	// 创建配置
	if err := createSnellConfig(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	// 创建系统用户
	utils.CreateSystemUser("snell")

	// 创建 systemd 服务
	if err := createSnellServices(config); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	// 启动服务
	utils.ServiceEnable("snell")
	utils.ServiceEnable("shadow-tls")
	utils.ServiceStart("snell")
	utils.ServiceStart("shadow-tls")

	// 验证服务
	if !utils.VerifyServiceStarted("snell", 10) {
		return nil, fmt.Errorf("Snell 服务启动失败")
	}
	if !utils.VerifyServiceStarted("shadow-tls", 10) {
		return nil, fmt.Errorf("Shadow-TLS 服务启动失败")
	}

	// 保存配置
	saveSnellConfig(config)

	// 生成客户端配置
	surgeProxy := fmt.Sprintf(
		"Snell = snell, %s, %d, psk=%s, version=4, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=3",
		serverIP, shadowTLSPort, snellPSK, shadowTLSPassword, tlsDomain,
	)

	result := &InstallResult{
		Success:    true,
		ServerIP:   serverIP,
		IPVersion:  ipVersion,
		Port:       shadowTLSPort,
		SurgeProxy: surgeProxy,
		Config: map[string]string{
			"snell_port":          strconv.Itoa(snellPort),
			"snell_psk":           snellPSK,
			"shadow_tls_port":     strconv.Itoa(shadowTLSPort),
			"shadow_tls_password": shadowTLSPassword,
			"tls_domain":          tlsDomain,
		},
	}

	printSnellSuccess(config, surgeProxy)

	return result, nil
}

func downloadSnell(version, arch string) error {
	if utils.FileExists(SnellBinaryPath) {
		return nil
	}

	snellArch := arch
	if arch == "arm64" {
		snellArch = "aarch64"
	}

	url := fmt.Sprintf(
		"https://dl.nssurge.com/snell/snell-server-v%s-linux-%s.zip",
		version, snellArch,
	)

	tempFile := "/tmp/snell.zip"
	if err := utils.DownloadFile(url, tempFile, 3); err != nil {
		return err
	}
	defer os.Remove(tempFile)

	// 解压
	cmd := exec.Command("unzip", "-o", tempFile, "-d", "/tmp/snell")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("解压失败: %v", err)
	}

	// 移动二进制文件
	files, _ := filepath.Glob("/tmp/snell/snell-server*")
	if len(files) > 0 {
		if err := os.Rename(files[0], SnellBinaryPath); err != nil {
			// 尝试复制
			cmd = exec.Command("cp", files[0], SnellBinaryPath)
			if err := cmd.Run(); err != nil {
				return err
			}
		}
	} else {
		// 直接查找
		cmd = exec.Command("mv", "/tmp/snell/snell-server", SnellBinaryPath)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("找不到 snell-server 二进制文件")
		}
	}

	os.Chmod(SnellBinaryPath, 0755)
	os.RemoveAll("/tmp/snell")

	utils.PrintSuccess("Snell 下载成功")
	return nil
}

func downloadShadowTLS(version, arch string) error {
	if utils.FileExists(ShadowTLSBinaryPath) {
		return nil
	}

	shadowArch := arch
	if arch == "arm64" {
		shadowArch = "aarch64"
	}

	url := fmt.Sprintf(
		"https://github.com/ihciah/shadow-tls/releases/download/%s/shadow-tls-%s-unknown-linux-musl",
		version, shadowArch,
	)

	if err := utils.DownloadFile(url, ShadowTLSBinaryPath, 3); err != nil {
		return err
	}

	os.Chmod(ShadowTLSBinaryPath, 0755)
	utils.PrintSuccess("Shadow-TLS 下载成功")
	return nil
}

func createSnellConfig(cfg SnellConfig) error {
	if err := os.MkdirAll("/etc/snell", 0755); err != nil {
		return err
	}

	listenAddr := "127.0.0.1"
	content := fmt.Sprintf(`[snell-server]
listen = %s:%d
psk = %s
ipv6 = false
`, listenAddr, cfg.SnellPort, cfg.SnellPSK)

	return utils.WriteFile(SnellConfigPath, content, 0600)
}

func createSnellServices(cfg SnellConfig) error {
	// Snell 服务
	if err := CreateSystemdService(SystemdServiceConfig{
		Name:        "snell",
		Description: "Snell Proxy Server",
		User:        "snell",
		ExecStart:   fmt.Sprintf("%s -c %s", SnellBinaryPath, SnellConfigPath),
	}); err != nil {
		return err
	}

	// Shadow-TLS 服务
	shadowTLSCmd := fmt.Sprintf(
		"%s --fastopen --v3 server --listen [::]:%d --server 127.0.0.1:%d --tls %s:443 --password %s",
		ShadowTLSBinaryPath, cfg.ShadowTLSPort, cfg.SnellPort, cfg.TLSDomain, cfg.ShadowTLSPassword,
	)

	return CreateSystemdService(SystemdServiceConfig{
		Name:         "shadow-tls",
		Description:  "Shadow-TLS Server",
		User:         "root",
		ExecStart:    shadowTLSCmd,
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveSnellConfig(cfg SnellConfig) {
	config := map[string]string{
		"TYPE":                "snell",
		"SERVER_IP":           cfg.ServerIP,
		"IP_VERSION":          cfg.IPVersion,
		"SNELL_VERSION":       cfg.SnellVersion,
		"SNELL_PORT":          strconv.Itoa(cfg.SnellPort),
		"SNELL_PSK":           cfg.SnellPSK,
		"SHADOW_TLS_VERSION":  cfg.ShadowTLSVersion,
		"SHADOW_TLS_PORT":     strconv.Itoa(cfg.ShadowTLSPort),
		"SHADOW_TLS_PASSWORD": cfg.ShadowTLSPassword,
		"TLS_DOMAIN":          cfg.TLSDomain,
	}
	SaveConfigFile(SnellProxyConfigPath, config)
}

func printSnellSuccess(cfg SnellConfig, surgeProxy string) {
	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   安装完成！%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.ServerIP)
	fmt.Printf("%sSnell 端口:%s %d (内部)\n", utils.ColorCyan, utils.ColorReset, cfg.SnellPort)
	fmt.Printf("%sShadow-TLS 端口:%s %d (对外)\n", utils.ColorCyan, utils.ColorReset, cfg.ShadowTLSPort)
	fmt.Printf("%sTLS 域名:%s %s\n", utils.ColorCyan, utils.ColorReset, cfg.TLSDomain)
	fmt.Println()
	fmt.Printf("%sSurge 配置:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

func promptPort(prompt string, defaultPort int) int {
	for {
		input := utils.PromptInput(prompt, strconv.Itoa(defaultPort))
		port, err := strconv.Atoi(input)
		if err != nil {
			utils.PrintError("请输入有效的端口号")
			continue
		}
		if err := utils.ValidatePort(port); err != nil {
			utils.PrintError("%v", err)
			continue
		}
		return port
	}
}

// =========================================
// Snell 查看配置
// =========================================

// ViewSnellConfig 查看 Snell 配置
func ViewSnellConfig() {
	if !utils.FileExists(SnellProxyConfigPath) {
		utils.PrintError("Snell 未安装")
		return
	}

	config, err := ParseConfigFile(SnellProxyConfigPath)
	if err != nil {
		utils.PrintError("读取配置失败: %v", err)
		return
	}

	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s   Snell + Shadow-TLS 配置%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s服务器 IP:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SERVER_IP"])
	fmt.Printf("%sSnell 端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SNELL_PORT"])
	fmt.Printf("%sShadow-TLS 端口:%s %s\n", utils.ColorCyan, utils.ColorReset, config["SHADOW_TLS_PORT"])
	fmt.Printf("%sTLS 域名:%s %s\n", utils.ColorCyan, utils.ColorReset, config["TLS_DOMAIN"])
	fmt.Println()

	surgeProxy := fmt.Sprintf(
		"Snell = snell, %s, %s, psk=%s, version=4, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=3",
		config["SERVER_IP"], config["SHADOW_TLS_PORT"], config["SNELL_PSK"],
		config["SHADOW_TLS_PASSWORD"], config["TLS_DOMAIN"],
	)
	fmt.Printf("%sSurge:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s%s%s\n", utils.ColorGreen, surgeProxy, utils.ColorReset)
	fmt.Println()
}

// =========================================
// Snell 更新
// =========================================

// UpdateSnell 更新 Snell
func UpdateSnell() error {
	if !utils.FileExists(SnellProxyConfigPath) {
		return fmt.Errorf("Snell 未安装")
	}

	config, err := ParseConfigFile(SnellProxyConfigPath)
	if err != nil {
		return err
	}

	currentVersion := config["SNELL_VERSION"]
	latestVersion := utils.GetSnellLatestVersion()

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
	utils.ServiceStop("shadow-tls")
	utils.ServiceStop("snell")

	// 备份旧版本
	os.Rename(SnellBinaryPath, SnellBinaryPath+".bak")

	// 下载新版本
	arch, _ := utils.DetectArch()
	if err := downloadSnell(latestVersion, arch); err != nil {
		// 回滚
		os.Rename(SnellBinaryPath+".bak", SnellBinaryPath)
		utils.ServiceStart("snell")
		utils.ServiceStart("shadow-tls")
		return fmt.Errorf("更新失败: %v", err)
	}

	// 更新配置中的版本
	config["SNELL_VERSION"] = latestVersion
	SaveConfigFile(SnellProxyConfigPath, config)

	// 启动服务
	utils.ServiceStart("snell")
	utils.ServiceStart("shadow-tls")

	os.Remove(SnellBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// Snell 卸载
// =========================================

// UninstallSnell 卸载 Snell
func UninstallSnell() error {
	utils.PrintInfo("正在卸载 Snell + Shadow-TLS...")

	// 删除服务
	RemoveSystemdService("shadow-tls")
	RemoveSystemdService("snell")

	// 删除文件
	os.Remove(SnellBinaryPath)
	os.Remove(ShadowTLSBinaryPath)
	os.RemoveAll("/etc/snell")
	os.Remove(SnellProxyConfigPath)

	// 删除用户
	utils.DeleteSystemUser("snell")

	utils.PrintSuccess("Snell + Shadow-TLS 已卸载")
	return nil
}

// newCommand 创建命令（辅助函数）
func newCommand(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}

// IsSnellInstalled 检查是否已安装
func IsSnellInstalled() bool {
	return utils.FileExists(SnellProxyConfigPath)
}
