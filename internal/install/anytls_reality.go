package install

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// AnyTLS + Reality (v4.0.25)
//
// 组合：sing-box anytls inbound + tls.reality 块。不需要 LE 证书/域名，
// 用 xray x25519 生成 keypair。客户端兼容 sing-box / mihomo / NekoBox /
// QuantumultX 测试版，不兼容 Surge / 旧 xray-only 客户端。

const (
	AnyTLSRealityConfigDir       = "/etc/anytls-reality"
	AnyTLSRealityConfigPath      = "/etc/anytls-reality/config.json"
	AnyTLSRealityProxyConfigPath = "/etc/anytls-reality-proxy-config.txt"
	AnyTLSRealityServiceName     = "anytls-reality"
)

type AnyTLSRealityConfig struct {
	ServerIP       string
	IPVersion      string
	Port           int
	Password       string
	PrivateKey     string
	PublicKey      string
	ShortID        string
	ServerName     string
	Padding        string
	SingboxVersion string
}

func InstallAnyTLSReality() (*InstallResult, error) {
	utils.PrintInfo("开始安装 AnyTLS + Reality (sing-box 内核)...")

	if utils.FileExists(AnyTLSRealityProxyConfigPath) {
		if !utils.PromptConfirm("AnyTLS+Reality 已安装，重新安装？") {
			return nil, fmt.Errorf("已取消")
		}
		UninstallAnyTLSReality()
	}

	if err := CheckDependencies(); err != nil {
		return nil, err
	}

	serverIP, ipVersion, err := utils.GetServerIP()
	if err != nil {
		return nil, fmt.Errorf("获取服务器 IP 失败: %v", err)
	}
	utils.PrintSuccess("服务器 IP: %s (IPv%s)", serverIP, ipVersion)

	arch, err := utils.DetectArch()
	if err != nil {
		return nil, err
	}

	// sing-box (服务端协议) + xray (生成 reality keypair)
	singboxVersion := utils.GetLatestVersion("SagerNet/sing-box", utils.DefaultSingboxVersion)
	if !utils.FileExists(SingboxBinaryPath) {
		if err := downloadSingbox(singboxVersion, arch); err != nil {
			return nil, fmt.Errorf("下载 sing-box 失败: %v", err)
		}
	}
	if !utils.FileExists(XrayBinaryPath) {
		if err := downloadXray(utils.GetLatestVersion("XTLS/Xray-core", DefaultXrayVersion), arch); err != nil {
			return nil, fmt.Errorf("下载 xray (用于生成 keypair) 失败: %v", err)
		}
	}

	port := promptPort("请输入 AnyTLS+Reality 端口", 443)
	serverName := selectRealityServerName()

	password := utils.GeneratePassword(16)
	kp, err := GenerateXrayReality25519()
	if err != nil {
		return nil, fmt.Errorf("生成 Reality keypair: %w", err)
	}
	shortID := generateShortID()

	cfg := AnyTLSRealityConfig{
		ServerIP:       serverIP,
		IPVersion:      ipVersion,
		Port:           port,
		Password:       password,
		PrivateKey:     kp.PrivateKey,
		PublicKey:      kp.PublicKey,
		ShortID:        shortID,
		ServerName:     serverName,
		Padding:        "default",
		SingboxVersion: singboxVersion,
	}

	if err := os.MkdirAll(AnyTLSRealityConfigDir, 0755); err != nil {
		return nil, err
	}
	utils.CreateSystemUser("anytls-reality")
	if err := createAnyTLSRealityConfig(cfg); err != nil {
		return nil, fmt.Errorf("创建 sing-box config 失败: %v", err)
	}
	if err := createAnyTLSRealityService(); err != nil {
		return nil, fmt.Errorf("创建 service 失败: %v", err)
	}
	utils.ServiceEnable(AnyTLSRealityServiceName)
	utils.ServiceStart(AnyTLSRealityServiceName)
	if !utils.VerifyServiceStarted(AnyTLSRealityServiceName, 10) {
		return nil, fmt.Errorf("服务启动失败 (查 journalctl -u %s)", AnyTLSRealityServiceName)
	}
	saveAnyTLSRealityConfig(cfg)
	upsertNode(storeNodeFromAnyTLSReality(cfg))

	fmt.Println()
	utils.PrintSuccess("安装完成！")
	fmt.Printf("%s服务器:%s %s:%d\n", utils.ColorCyan, utils.ColorReset, serverIP, port)
	fmt.Printf("%s密码:%s %s\n", utils.ColorCyan, utils.ColorReset, password)
	fmt.Printf("%sSNI 目标:%s %s\n", utils.ColorCyan, utils.ColorReset, serverName)
	fmt.Printf("%sPublicKey:%s %s\n", utils.ColorCyan, utils.ColorReset, kp.PublicKey)
	fmt.Printf("%sShortID:%s %s\n", utils.ColorCyan, utils.ColorReset, shortID)
	PrintFirewallHint(port, FirewallTCP)

	return &InstallResult{
		Success:   true,
		ServerIP:  serverIP,
		IPVersion: ipVersion,
		Port:      port,
	}, nil
}

func createAnyTLSRealityConfig(cfg AnyTLSRealityConfig) error {
	config := map[string]any{
		"log": map[string]any{"level": "info", "timestamp": true},
		"inbounds": []map[string]any{
			{
				"type":        "anytls",
				"tag":         "anytls-reality-in",
				"listen":      "::",
				"listen_port": cfg.Port,
				"users": []map[string]any{
					{"name": "user1", "password": cfg.Password},
				},
				"tls": map[string]any{
					"enabled":     true,
					"server_name": cfg.ServerName,
					"reality": map[string]any{
						"enabled": true,
						"handshake": map[string]any{
							"server":      cfg.ServerName,
							"server_port": 443,
						},
						"private_key": cfg.PrivateKey,
						"short_id":    []string{cfg.ShortID},
					},
				},
			},
		},
		"outbounds": []map[string]any{{"type": "direct", "tag": "direct"}},
	}
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	return utils.WriteFile(AnyTLSRealityConfigPath, string(data), PermConfigFile)
}

func createAnyTLSRealityService() error {
	return CreateSystemdService(SystemdServiceConfig{
		Name:         AnyTLSRealityServiceName,
		Description:  "AnyTLS + Reality (sing-box) Service",
		User:         "anytls-reality",
		ExecStart:    fmt.Sprintf("%s run -c %s", SingboxBinaryPath, AnyTLSRealityConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

func saveAnyTLSRealityConfig(cfg AnyTLSRealityConfig) {
	kv := map[string]string{
		"TYPE":            "anytls-reality",
		"SERVER_IP":       cfg.ServerIP,
		"IP_VERSION":      cfg.IPVersion,
		"PORT":            strconv.Itoa(cfg.Port),
		"PASSWORD":        cfg.Password,
		"PRIVATE_KEY":     cfg.PrivateKey,
		"PUBLIC_KEY":      cfg.PublicKey,
		"SHORT_ID":        cfg.ShortID,
		"SERVER_NAME":     cfg.ServerName,
		"SINGBOX_VERSION": cfg.SingboxVersion,
	}
	SaveConfigFile(AnyTLSRealityProxyConfigPath, kv)
}

func storeNodeFromAnyTLSReality(cfg AnyTLSRealityConfig) store.Node {
	return store.Node{
		ID:     "anytls-reality",
		Name:   "AnyTLS-Reality",
		Type:   store.TypeAnyTLSReality,
		Server: cfg.ServerIP,
		Port:   cfg.Port,
		Params: map[string]any{
			"password":    cfg.Password,
			"public_key":  cfg.PublicKey,
			"short_id":    cfg.ShortID,
			"server_name": cfg.ServerName,
		},
	}
}

func UninstallAnyTLSReality() error {
	utils.PrintInfo("卸载 AnyTLS+Reality...")
	RemoveSystemdService(AnyTLSRealityServiceName)
	os.RemoveAll(AnyTLSRealityConfigDir)
	os.Remove(AnyTLSRealityProxyConfigPath)
	removeNodeByType(store.TypeAnyTLSReality)
	utils.DeleteSystemUser("anytls-reality")
	utils.PrintSuccess("已卸载")
	return nil
}

func IsAnyTLSRealityInstalled() bool {
	return utils.FileExists(AnyTLSRealityProxyConfigPath)
}
