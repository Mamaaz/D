package install

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// 权限常量
// =========================================

const (
	SystemdPath = "/lib/systemd/system"

	// 文件权限
	PermConfigFile = 0644 // 配置文件 (服务用户可读)
	PermKeyFile    = 0600 // 密钥文件 (仅所有者可读)
	PermCertFile   = 0644 // 证书文件 (公开可读)
	PermProxyConf  = 0600 // 代理配置文件 (含密码)
)

// =========================================
// 通用证书管理
// =========================================

// InstallAcme 安装 acme.sh 并申请证书
func InstallAcme(domain string) error {
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

	utils.PrintInfo("申请 Let's Encrypt 证书...")
	cmd := exec.Command(acmePath, "--issue", "-d", domain, "--standalone", "--keylength", "ec-256", "--force")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
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

// InstallCertForService 安装证书到指定服务目录
func InstallCertForService(domain, serviceName, keyPath, certPath string) error {
	acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"
	defaultGroup := utils.GetDefaultGroup()

	cmd := exec.Command(acmePath, "--install-cert", "-d", domain, "--ecc",
		"--key-file", keyPath,
		"--fullchain-file", certPath,
		"--reloadcmd", fmt.Sprintf("chown %s:%s %s %s && chmod 600 %s && chmod 644 %s && systemctl restart %s 2>/dev/null || true",
			serviceName, defaultGroup, keyPath, certPath, keyPath, certPath, serviceName))

	if err := cmd.Run(); err != nil {
		return err
	}

	// 立即设置权限 (首次安装时 reloadcmd 不会执行)
	os.Chmod(keyPath, PermKeyFile)
	os.Chmod(certPath, PermCertFile)

	// 设置正确的所有权
	chownCmd := exec.Command("chown", fmt.Sprintf("%s:%s", serviceName, defaultGroup), keyPath, certPath)
	if err := chownCmd.Run(); err != nil {
		utils.PrintWarn("设置证书所有权失败: %v", err)
	}

	utils.PrintSuccess("证书安装成功")
	return nil
}

// RenewCertForService 续签指定服务的证书
func RenewCertForService(serviceName, configPath, domainKey, keyPath, certPath string) error {
	if !utils.FileExists(configPath) {
		return fmt.Errorf("%s 未安装", serviceName)
	}

	config, err := ParseConfigFile(configPath)
	if err != nil {
		return err
	}

	domain := config[domainKey]
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

	if err := InstallCertForService(domain, serviceName, keyPath, certPath); err != nil {
		return err
	}

	utils.ServiceRestart(serviceName)
	utils.PrintSuccess("证书续签成功")
	return nil
}

// =========================================
// 配置文件解析
// =========================================

// ParseConfigFile 解析配置文件 (KEY=VALUE 格式)
func ParseConfigFile(path string) (map[string]string, error) {
	content, err := utils.ReadFile(path)
	if err != nil {
		return nil, err
	}

	config := make(map[string]string)
	lines := strings.Split(content, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			config[parts[0]] = parts[1]
		}
	}

	return config, nil
}

// SaveConfigFile 保存配置文件
func SaveConfigFile(path string, config map[string]string) error {
	var lines []string
	for k, v := range config {
		lines = append(lines, fmt.Sprintf("%s=%s", k, v))
	}
	return utils.WriteFile(path, strings.Join(lines, "\n")+"\n", 0600)
}

// =========================================
// Systemd 服务创建
// =========================================

// SystemdServiceConfig systemd 服务配置
type SystemdServiceConfig struct {
	Name         string
	Description  string
	User         string
	Group        string
	ExecStart    string
	After        string
	Capabilities string
}

// CreateSystemdService 创建 systemd 服务
func CreateSystemdService(cfg SystemdServiceConfig) error {
	if cfg.After == "" {
		cfg.After = "network-online.target"
	}
	if cfg.Group == "" {
		cfg.Group = utils.GetDefaultGroup()
	}

	capLine := ""
	if cfg.Capabilities != "" {
		capLine = fmt.Sprintf("AmbientCapabilities=%s", cfg.Capabilities)
	}

	content := fmt.Sprintf(`[Unit]
Description=%s
After=%s

[Service]
Type=simple
User=%s
Group=%s
LimitNOFILE=65535
ExecStart=%s
%s
Restart=always
RestartSec=10s

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/etc /var/log

[Install]
WantedBy=multi-user.target
`, cfg.Description, cfg.After, cfg.User, cfg.Group, cfg.ExecStart, capLine)

	servicePath := fmt.Sprintf("%s/%s.service", SystemdPath, cfg.Name)
	if err := utils.WriteFile(servicePath, content, 0644); err != nil {
		return err
	}

	return utils.DaemonReload()
}

// RemoveSystemdService 删除 systemd 服务
func RemoveSystemdService(name string) error {
	_ = utils.ServiceStop(name)
	_ = utils.ServiceDisable(name)

	servicePath := fmt.Sprintf("%s/%s.service", SystemdPath, name)
	if utils.FileExists(servicePath) {
		if err := utils.RemoveFile(servicePath); err != nil {
			return err
		}
	}

	return utils.DaemonReload()
}

// =========================================
// 依赖检查
// =========================================

// CheckDependencies 检查并安装依赖
func CheckDependencies() error {
	deps := []string{"curl", "wget", "jq"}

	var missing []string
	for _, dep := range deps {
		if !commandExists(dep) {
			missing = append(missing, dep)
		}
	}

	if len(missing) == 0 {
		return nil
	}

	utils.PrintInfo("正在安装依赖: %s", strings.Join(missing, ", "))

	// 尝试不同的包管理器
	if commandExists("apt-get") {
		return runCommand("apt-get", append([]string{"install", "-y", "-qq"}, missing...)...)
	}
	if commandExists("yum") {
		return runCommand("yum", append([]string{"install", "-y", "-q"}, missing...)...)
	}
	if commandExists("dnf") {
		return runCommand("dnf", append([]string{"install", "-y", "-q"}, missing...)...)
	}
	if commandExists("pacman") {
		return runCommand("pacman", append([]string{"-Sy", "--noconfirm"}, missing...)...)
	}

	return fmt.Errorf("无法安装依赖，请手动安装: %s", strings.Join(missing, ", "))
}

func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

func runCommand(name string, args ...string) error {
	cmd := newCommand(name, args...)
	return cmd.Run()
}

// =========================================
// 安装结果
// =========================================

// InstallResult 安装结果
type InstallResult struct {
	Success    bool
	ServerIP   string
	IPVersion  string
	Port       int
	Config     map[string]string
	SurgeProxy string
	ClashProxy string
}

// PrintSurgeConfig 打印 Surge 配置
func (r *InstallResult) PrintSurgeConfig() {
	if r.SurgeProxy != "" {
		fmt.Println()
		fmt.Printf("%sSurge 配置:%s\n", utils.ColorCyan, utils.ColorReset)
		fmt.Printf("%s%s%s\n", utils.ColorGreen, r.SurgeProxy, utils.ColorReset)
	}
}

// PrintClashConfig 打印 Clash 配置
func (r *InstallResult) PrintClashConfig() {
	if r.ClashProxy != "" {
		fmt.Println()
		fmt.Printf("%sClash 配置:%s\n", utils.ColorCyan, utils.ColorReset)
		fmt.Printf("%s%s%s\n", utils.ColorGreen, r.ClashProxy, utils.ColorReset)
	}
}
