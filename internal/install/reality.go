package install

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// =========================================
// VLESS Reality 安装 (xray-core 内核)
// =========================================
//
// 从 v4.0.7 起，Reality 协议从 sing-box 切到 xray-core：
//   - Reality 是 XTLS 团队的发明，新特性 (e.g. MLKEM-768) 先进 xray
//   - 其他协议 (Snell+ShadowTLS, SS2022+ShadowTLS, Hysteria2, AnyTLS) 继续 sing-box
//
// 旧 sing-box-reality.service 由 RebuildAllServices 中的迁移逻辑自动卸载。
// 配置目录从 /etc/sing-box-reality 迁到 /etc/xray-reality。
const (
	RealityConfigDir       = "/etc/xray-reality"
	RealityConfigPath      = "/etc/xray-reality/config.json"
	RealityProxyConfigPath = "/etc/reality-proxy-config.txt"

	// 旧路径，用于迁移检测
	LegacyRealityConfigDir   = "/etc/sing-box-reality"
	LegacyRealityServiceUnit = "/lib/systemd/system/sing-box-reality.service"

	RealityServiceName = "xray-reality"
	RealityServiceUser = "xray"
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

	// 拿 xray 最新版 + 下载 (Reality 切到 xray 内核)
	xrayVersion := utils.GetLatestVersion("XTLS/Xray-core", DefaultXrayVersion)
	utils.PrintInfo("Xray 版本: %s", xrayVersion)
	if err := downloadXray(xrayVersion, arch); err != nil {
		return nil, fmt.Errorf("下载 Xray 失败: %v", err)
	}

	// 获取配置参数
	port := promptPort("请输入 Reality 监听端口", 443)
	serverName := selectRealityServerName()

	// 生成密钥 — 用 xray x25519 (sing-box generate 路径已废弃)
	uuid := generateRandomUUIDv4()
	kp, err := GenerateXrayReality25519()
	if err != nil {
		return nil, fmt.Errorf("生成 Reality 密钥失败: %w", err)
	}
	privateKey, publicKey := kp.PrivateKey, kp.PublicKey
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
		SingboxVersion: xrayVersion, // 名字保留兼容旧 .txt schema (字段叫 SINGBOX_VERSION 但存的是当前内核版本)
	}

	// 旧 sing-box-reality 残留先清掉，避免端口冲突或服务名混淆
	migrateLegacyRealityIfPresent()

	if err := createRealityConfig(config); err != nil {
		return nil, fmt.Errorf("创建配置失败: %v", err)
	}

	utils.CreateSystemUser(RealityServiceUser)

	if err := createRealityService(); err != nil {
		return nil, fmt.Errorf("创建服务失败: %v", err)
	}

	utils.ServiceEnable(RealityServiceName)
	utils.ServiceStart(RealityServiceName)

	if !utils.VerifyServiceStarted(RealityServiceName, 10) {
		return nil, fmt.Errorf("Reality 服务启动失败")
	}

	// 保存配置
	saveRealityConfig(config)
	upsertNode(storeNodeFromReality(config))

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
	PrintFirewallHint(config.Port, FirewallTCP)

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

	choice := utils.PromptInt("请选择", 1, 0, len(serverNames))
	if choice == 0 {
		for {
			d := utils.PromptInput("请输入自定义目标服务器", "")
			if d != "" {
				return d
			}
			utils.PrintWarn("自定义不能为空")
		}
	}
	return serverNames[choice-1]
}

func generateUUID() string {
	cmd := exec.Command(SingboxBinaryPath, "generate", "uuid")
	output, err := cmd.Output()
	if err == nil {
		s := strings.TrimSpace(string(output))
		if isValidUUID(s) {
			return s
		}
	}
	return generateRandomUUIDv4()
}

// generateRandomUUIDv4 produces a RFC 4122 v4 UUID using crypto/rand. We
// avoid pulling google/uuid as a dep since this is the only consumer.
func generateRandomUUIDv4() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand failure on Linux is essentially unreachable; if it
		// somehow happens, fail loud rather than emit garbage that sing-box
		// will reject at startup.
		panic("crypto/rand unavailable: " + err.Error())
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant RFC 4122
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func isValidUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, c := range s {
		switch i {
		case 8, 13, 18, 23:
			if c != '-' {
				return false
			}
		default:
			if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
				return false
			}
		}
	}
	return true
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

// generateShortID 出 16-char (8-byte) 全 hex 串。Reality short_id 在 sing-box
// / xray 内核里都是按 hex 解析；QX 客户端的 reality-hex-shortid 字段更是
// 严格 hex 校验（出现 g-z 直接判语法错误,节点不可用)。
//
// 历史 bug (修于 v4.0.31): 这里以前 shell 出 sing-box `generate rand --hex 8`,
// 失败时 fallback 到 utils.GeneratePassword(8) — 后者用 base64 字母表
// (A-Z/a-z/0-9/+),非 hex。装 VLESS Reality 时机器上若没 sing-box (常见,因
// VLESS Reality 走 xray 内核),fallback 直接生效,store 里就被写进非 hex
// shortid。xray 服务端宽松能跑,但 QX 加节点直接 syntax error。
//
// 改成 crypto/rand + hex.EncodeToString,无外部依赖,无 fallback 路径。
func generateShortID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand 在 Linux 上 io.ReadFull(/dev/urandom) 实质不会失败;
		// 真失败时整个程序也没法继续,fail loud 比静默生成弱随机串好。
		panic("crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b[:])
}

// createRealityConfig 写 xray-core 风格的 Reality JSON。字段名跟 sing-box
// 不同：privateKey (camelCase)、shortIds (数组 + 复数)、dest 用 host:port、
// flow 直接写在 client 上、serverNames 是数组。
func createRealityConfig(cfg RealityConfig) error {
	if err := os.MkdirAll(RealityConfigDir, 0755); err != nil {
		return err
	}

	config := map[string]interface{}{
		"log": map[string]interface{}{
			"loglevel": "warning",
		},
		"inbounds": []map[string]interface{}{
			{
				"tag":      "vless-in",
				"listen":   "0.0.0.0",
				"port":     cfg.Port,
				"protocol": "vless",
				"settings": map[string]interface{}{
					"clients": []map[string]interface{}{
						{
							"id":   cfg.UUID,
							"flow": "xtls-rprx-vision",
						},
					},
					"decryption": "none",
				},
				"streamSettings": map[string]interface{}{
					"network":  "tcp",
					"security": "reality",
					"realitySettings": map[string]interface{}{
						"show":        false,
						"dest":        fmt.Sprintf("%s:443", cfg.ServerName),
						"xver":        0,
						"serverNames": []string{cfg.ServerName},
						"privateKey":  cfg.PrivateKey,
						"shortIds":    []string{cfg.ShortID},
					},
				},
				"sniffing": map[string]interface{}{
					"enabled":      true,
					"destOverride": []string{"http", "tls", "quic"},
					"routeOnly":    true,
				},
			},
		},
		"outbounds": []map[string]interface{}{
			{"protocol": "freedom", "tag": "direct"},
			{"protocol": "blackhole", "tag": "block"},
		},
		// 注：故意不写 routing.rules——xray 的 geoip:private 等规则要 geoip.dat
		// 数据库文件，xray binary 不自带。简单部署默认全放行；用户要 BT 阻断
		// /内网防泄漏，单独下 geoip.dat 到 /usr/local/bin/ 后手动加 rules。
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	return utils.WriteFile(RealityConfigPath, string(data), PermConfigFile)
}

// createRealityService 写 xray-reality.service unit。User=xray + CAP_NET_BIND_SERVICE
// 跟其他协议的 isolation 模型一致；非 root 也能 bind 443。
func createRealityService() error {
	return CreateSystemdService(SystemdServiceConfig{
		Name:         RealityServiceName,
		Description:  "Xray-core Reality Service",
		User:         RealityServiceUser,
		ExecStart:    fmt.Sprintf("%s run -c %s", XrayBinaryPath, RealityConfigPath),
		Capabilities: "CAP_NET_BIND_SERVICE",
	})
}

// migrateLegacyRealityIfPresent 检测旧 sing-box-reality 残留，停服 + 删 unit
// + 删旧配置目录。安全：只在 install / rebuild 这些显式触发处调用，不在
// 普通查询路径上自动跑。
func migrateLegacyRealityIfPresent() {
	if !utils.FileExists(LegacyRealityServiceUnit) {
		return
	}
	utils.PrintInfo("检测到旧 sing-box-reality 服务，正在迁移到 xray-reality...")
	_ = utils.ServiceStop("sing-box-reality")
	_ = utils.ServiceDisable("sing-box-reality")
	_ = os.Remove(LegacyRealityServiceUnit)
	_ = os.RemoveAll(LegacyRealityConfigDir)
	_ = utils.DaemonReload()
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
	PrintAdditionalFormatsForType(store.TypeVLESSReality)
}

// =========================================
// Reality 更新
// =========================================

// UpdateReality 更新 xray-core 内核 (Reality 协议从 v4.0.7 起跑在 xray)。
// 字段名 SINGBOX_VERSION 保留兼容旧 .txt schema，实际存的是 xray 版本号。
func UpdateReality() error {
	if !utils.FileExists(RealityProxyConfigPath) {
		return fmt.Errorf("VLESS Reality 未安装")
	}
	config, err := ParseConfigFile(RealityProxyConfigPath)
	if err != nil {
		return err
	}
	currentVersion := config["SINGBOX_VERSION"]
	latestVersion := utils.GetLatestVersion("XTLS/Xray-core", DefaultXrayVersion)

	fmt.Printf("%s当前 Xray 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, currentVersion)
	fmt.Printf("%s最新 Xray 版本:%s %s\n", utils.ColorCyan, utils.ColorReset, latestVersion)
	if currentVersion == latestVersion {
		utils.PrintSuccess("已是最新版本")
		return nil
	}
	if !utils.PromptConfirm("确认更新？") {
		return nil
	}

	utils.ServiceStop(RealityServiceName)

	// 备份现有 binary 防回滚
	os.Rename(XrayBinaryPath, XrayBinaryPath+".bak")
	arch, _ := utils.DetectArch()
	os.Remove(XrayBinaryPath)

	if err := downloadXray(latestVersion, arch); err != nil {
		os.Rename(XrayBinaryPath+".bak", XrayBinaryPath)
		utils.ServiceStart(RealityServiceName)
		return fmt.Errorf("更新失败: %v", err)
	}

	config["SINGBOX_VERSION"] = latestVersion // 字段名兼容
	SaveConfigFile(RealityProxyConfigPath, config)

	utils.ServiceStart(RealityServiceName)

	os.Remove(XrayBinaryPath + ".bak")
	utils.PrintSuccess("更新成功: %s -> %s", currentVersion, latestVersion)
	return nil
}

// =========================================
// Reality 卸载
// =========================================

// UninstallReality 卸载 Reality (xray 内核)。
// xray 二进制只服务 Reality，所以卸载时直接删 binary + 用户；不像 sing-box
// 那样要检查"其他协议是否在用"。
func UninstallReality() error {
	utils.PrintInfo("正在卸载 VLESS Reality...")

	RemoveSystemdService(RealityServiceName)
	// 旧的 sing-box-reality unit 也清掉，防止残留
	migrateLegacyRealityIfPresent()

	os.RemoveAll(RealityConfigDir)
	os.Remove(RealityProxyConfigPath)
	removeNodeByType(store.TypeVLESSReality)

	// xray 是 Reality 专属，没有其他协议共用，直接卸
	os.Remove(XrayBinaryPath)
	utils.DeleteSystemUser(RealityServiceUser)

	utils.PrintSuccess("VLESS Reality 已卸载")
	return nil
}

// IsRealityInstalled 检查是否已安装
func IsRealityInstalled() bool {
	return utils.FileExists(RealityProxyConfigPath)
}
