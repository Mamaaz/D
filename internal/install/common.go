package install

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/format"
	"github.com/Mamaaz/proxy-manager/internal/store"
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

// PrintAdditionalFormatsForType 给查看配置流程在 Surge 行之下追加 Mihomo +
// QuantumultX 两段（Mihomo 是 Clash.Meta 接班，accept 标准 Clash YAML；QX
// iOS 主流）。失败静默。
func PrintAdditionalFormatsForType(t store.NodeType) {
	s, err := store.Load()
	if err != nil || s == nil {
		return
	}
	var node *store.Node
	for i := range s.Nodes {
		if s.Nodes[i].Type == t {
			node = &s.Nodes[i]
			break
		}
	}
	if node == nil {
		return
	}
	if entry, err := format.ToClash(node); err == nil {
		// Clash/Mihomo 用 JSON 一行输出，方便用户直接粘到 proxies: 数组里
		if data, err := json.Marshal(entry); err == nil {
			fmt.Printf("%sMihomo / Clash.Meta:%s\n%s%s%s\n\n",
				utils.ColorCyan, utils.ColorReset,
				utils.ColorGreen, string(data), utils.ColorReset)
		}
	}
	if qx, err := format.ToQX(node); err == nil && qx != "" {
		fmt.Printf("%sQuantumultX:%s\n%s%s%s\n\n",
			utils.ColorCyan, utils.ColorReset,
			utils.ColorGreen, qx, utils.ColorReset)
	}
}

// CloudflareTokenPath 是 CF API token 持久化的位置。
// 权限 0600，acme.sh cron 续签时也能读到 (root 身份跑)。
const CloudflareTokenPath = "/etc/proxy-manager/cloudflare.env"

// CertChallengeMode 是用户选的 ACME 验证方式。
type CertChallengeMode int

const (
	ChallengeHTTP01 CertChallengeMode = iota // standalone (port 80) → webroot fallback
	ChallengeDNS01CF                         // Cloudflare DNS API
)

// PromptChallengeMode 让用户选 HTTP-01 还是 DNS-01 (Cloudflare)。
// 默认 HTTP-01——常见情况下能用且零配置；当用户已启用 subscribe service
// 占用 :80 时，HTTP-01 会失败，应选 DNS-01。
func PromptChallengeMode() CertChallengeMode {
	fmt.Println()
	fmt.Printf("%sACME 证书申请方式:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Println("  1. HTTP-01 (端口 80 standalone) — 默认，无需额外配置")
	fmt.Println("       要求 :80 空闲。如已启用 subscribe service 占着 :80，会失败")
	fmt.Println("  2. DNS-01 via Cloudflare API — 推荐有 subscribe 时用")
	fmt.Println("       不碰任何端口；要 Cloudflare API Token (Zone:DNS:Edit 权限)")
	fmt.Println()
	choice := utils.PromptInt("请选择", 1, 1, 2)
	if choice == 2 {
		return ChallengeDNS01CF
	}
	return ChallengeHTTP01
}

// InstallAcme 安装 acme.sh 并申请证书。mode 决定走 HTTP-01 还是 DNS-01。
//
// DNS-01 + Cloudflare 路径完全不碰 :80，subscribe service / 任何 :80
// listener 都不影响。Token 持久化到 CloudflareTokenPath，acme.sh cron
// 自动续签时也能读到。
func InstallAcme(domain string, mode CertChallengeMode) error {
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

	switch mode {
	case ChallengeDNS01CF:
		return issueCertDNS01CF(acmePath, domain)
	default:
		return issueCertHTTP01(acmePath, domain)
	}
}

func issueCertHTTP01(acmePath, domain string) error {
	utils.PrintInfo("申请 Let's Encrypt 证书 (HTTP-01 standalone)...")
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
			return fmt.Errorf("证书申请失败，请确保域名已解析且端口 80 可用 (或换 DNS-01 方式)")
		}
	}
	return nil
}

func issueCertDNS01CF(acmePath, domain string) error {
	cfToken, err := loadOrPromptCloudflareToken()
	if err != nil {
		return err
	}
	utils.PrintInfo("申请 Let's Encrypt 证书 (DNS-01 via Cloudflare)...")
	cmd := exec.Command(acmePath, "--issue", "-d", domain, "--dns", "dns_cf", "--keylength", "ec-256", "--force")
	cmd.Env = append(os.Environ(), "CF_Token="+cfToken)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("DNS-01 证书申请失败: %w", err)
	}
	return nil
}

// loadOrPromptCloudflareToken 优先从 CloudflareTokenPath 读已持久化的 token；
// 没存过 → 交互问 → 写盘 (0600)。每个域名只用问一次。
//
// acme.sh 自己也会把 CF_Token 存到 ~/.acme.sh/account.conf，cron 续签时
// 自动加载。我们额外存一份方便用户审计 / 替换 token。
func loadOrPromptCloudflareToken() (string, error) {
	if data, err := os.ReadFile(CloudflareTokenPath); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "CF_Token=") {
				return strings.TrimPrefix(line, "CF_Token="), nil
			}
		}
	}

	utils.PrintInfo("Cloudflare API Token 未配置——首次需输入。")
	fmt.Println("  生成: https://dash.cloudflare.com/profile/api-tokens → Create Token")
	fmt.Println("  权限: Zone:DNS:Edit (限定要签证的域名 zone)")
	fmt.Println()
	token := utils.PromptInput("Cloudflare API Token", "")
	token = strings.TrimSpace(token)
	if token == "" {
		return "", fmt.Errorf("Cloudflare API Token 不能为空")
	}
	if err := os.MkdirAll("/etc/proxy-manager", 0755); err != nil {
		return "", err
	}
	if err := os.WriteFile(CloudflareTokenPath, []byte("CF_Token="+token+"\n"), 0600); err != nil {
		return "", fmt.Errorf("保存 CF Token 失败: %w", err)
	}
	utils.PrintSuccess("CF Token 已保存到 %s (0600 权限)", CloudflareTokenPath)
	return token, nil
}

// InstallCertForService 安装证书到指定服务目录
//
// 历史 bug：之前用 utils.GetDefaultGroup() 返回 "nogroup"/"nobody"，但
// CreateSystemUser(svc) 建的用户主组是同名 (svc:svc)。chown svc:nogroup
// 在没有 nogroup 的发行版静默失败 → 证书留 root:root → 服务读不了 key
// FATAL "permission denied"。改用 serviceName 同时作 owner + group。
func InstallCertForService(domain, serviceName, keyPath, certPath string) error {
	acmePath := os.Getenv("HOME") + "/.acme.sh/acme.sh"

	cmd := exec.Command(acmePath, "--install-cert", "-d", domain, "--ecc",
		"--key-file", keyPath,
		"--fullchain-file", certPath,
		"--reloadcmd", fmt.Sprintf("chown %s:%s %s %s && chmod 600 %s && chmod 644 %s && systemctl restart %s 2>/dev/null || true",
			serviceName, serviceName, keyPath, certPath, keyPath, certPath, serviceName))

	if err := cmd.Run(); err != nil {
		return err
	}

	// 立即设置权限 (首次安装时 reloadcmd 不会执行)
	os.Chmod(keyPath, PermKeyFile)
	os.Chmod(certPath, PermCertFile)

	// chown serviceName:serviceName (CreateSystemUser 创建的同名 group)
	chownCmd := exec.Command("chown", fmt.Sprintf("%s:%s", serviceName, serviceName), keyPath, certPath)
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

// IsSingboxShared 检查是否有其他服务还在使用 sing-box 二进制
// excludeConfigs 为当前正在卸载的服务的配置路径，应排除在检查之外
//
// 注：v4.0.26 删 SS-2022+STLS / Snell+STLS 后，sing-box 仅供 Hysteria2 /
// AnyTLS / AnyTLS+Reality 用；Reality 已切 xray，不在此列表里。
func IsSingboxShared(excludeConfigs ...string) bool {
	allConfigs := []string{
		Hysteria2ProxyConfigPath,
		AnyTLSProxyConfigPath,
		AnyTLSRealityProxyConfigPath,
	}

	excluded := make(map[string]bool)
	for _, c := range excludeConfigs {
		excluded[c] = true
	}

	for _, cfg := range allConfigs {
		if excluded[cfg] {
			continue
		}
		if utils.FileExists(cfg) {
			return true
		}
	}
	return false
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
	return utils.WriteFile(path, strings.Join(lines, "\n")+"\n", PermProxyConf)
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

// =========================================
// 防火墙提示
// =========================================

// FirewallProto identifies the transport for the firewall hint. Hysteria2
// is UDP, everything else we install is TCP.
type FirewallProto string

const (
	FirewallTCP    FirewallProto = "tcp"
	FirewallUDP    FirewallProto = "udp"
	FirewallTCPUDP FirewallProto = "tcp+udp"
)

// PrintFirewallHint detects the active firewall (UFW or firewalld) and
// prints copy-paste commands to open the listening port. We deliberately
// do NOT execute these — modifying iptables without explicit consent has
// burned too many people; surfacing the commands lets the user decide.
func PrintFirewallHint(port int, proto FirewallProto) {
	fmt.Println()
	fmt.Printf("%s防火墙提示:%s 服务监听端口 %d 需要对外开放。\n", utils.ColorCyan, utils.ColorReset, port)

	if commandExists("ufw") {
		fmt.Printf("  检测到 UFW，可执行：\n")
		switch proto {
		case FirewallUDP:
			fmt.Printf("    sudo ufw allow %d/udp\n", port)
		case FirewallTCPUDP:
			fmt.Printf("    sudo ufw allow %d/tcp\n", port)
			fmt.Printf("    sudo ufw allow %d/udp\n", port)
		default:
			fmt.Printf("    sudo ufw allow %d/tcp\n", port)
		}
	} else if commandExists("firewall-cmd") {
		fmt.Printf("  检测到 firewalld，可执行：\n")
		switch proto {
		case FirewallUDP:
			fmt.Printf("    sudo firewall-cmd --add-port=%d/udp --permanent\n", port)
		case FirewallTCPUDP:
			fmt.Printf("    sudo firewall-cmd --add-port=%d/tcp --permanent\n", port)
			fmt.Printf("    sudo firewall-cmd --add-port=%d/udp --permanent\n", port)
		default:
			fmt.Printf("    sudo firewall-cmd --add-port=%d/tcp --permanent\n", port)
		}
		fmt.Printf("    sudo firewall-cmd --reload\n")
	} else {
		fmt.Printf("  未检测到 UFW/firewalld。如使用云厂商安全组，请记得放行端口 %d (%s)。\n", port, proto)
	}
}
