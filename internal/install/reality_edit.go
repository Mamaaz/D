package install

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// EditableRealityField 列出 EditReality 接受的字段名。客户端需要重新拉
// export 才能拿到新值，因此返回这些字段时附上人类可读说明。
type EditableRealityField struct {
	Name        string // CLI/UI 用的 key
	DisplayName string // 给用户看的中文
	CurrentValue string
	Description string
}

// CurrentRealityFields 读出 reality 当前配置里可编辑的字段，方便上层 UI
// 渲染 "当前值 -> 新值" 这种形式。
func CurrentRealityFields() ([]EditableRealityField, error) {
	if !utils.FileExists(RealityProxyConfigPath) {
		return nil, fmt.Errorf("VLESS Reality 未安装")
	}
	cfg, err := ParseConfigFile(RealityProxyConfigPath)
	if err != nil {
		return nil, err
	}
	return []EditableRealityField{
		{Name: "port", DisplayName: "监听端口", CurrentValue: cfg["PORT"],
			Description: "TCP 端口 1-65535；改后客户端要重连"},
		{Name: "uuid", DisplayName: "UUID", CurrentValue: cfg["UUID"],
			Description: "VLESS 用户标识；改后旧客户端立即失效，等同 rotate"},
		{Name: "short-id", DisplayName: "Short ID", CurrentValue: cfg["SHORT_ID"],
			Description: "Reality short id；保持 16 位 hex"},
		{Name: "sni", DisplayName: "目标服务器 (SNI)", CurrentValue: cfg["SERVER_NAME"],
			Description: "Reality 仿冒的目标域名，建议先用 sni-test 验证"},
	}, nil
}

// EditReality 改一个字段并重启服务。验证失败 / 写入失败时不会半破坏现有
// 配置——所有写入在 validate 之后才执行。
func EditReality(field, newValue string) error {
	if !utils.FileExists(RealityProxyConfigPath) {
		return fmt.Errorf("VLESS Reality 未安装")
	}
	cfg, err := ParseConfigFile(RealityProxyConfigPath)
	if err != nil {
		return fmt.Errorf("解析现有配置失败: %w", err)
	}

	newValue = strings.TrimSpace(newValue)
	switch field {
	case "port":
		p, err := strconv.Atoi(newValue)
		if err != nil || p <= 0 || p > 65535 {
			return fmt.Errorf("port 必须是 1-65535 的整数")
		}
		cfg["PORT"] = newValue
	case "uuid":
		if !looksLikeUUID(newValue) {
			return fmt.Errorf("UUID 格式错误（期望 8-4-4-4-12 十六进制）")
		}
		cfg["UUID"] = newValue
	case "short-id":
		if !looksLikeHex(newValue) || len(newValue) > 16 {
			return fmt.Errorf("short id 必须是 ≤16 位的 hex 字符串")
		}
		cfg["SHORT_ID"] = newValue
	case "sni":
		if newValue == "" || strings.ContainsAny(newValue, " \t/") {
			return fmt.Errorf("SNI 必须是裸域名 (如 www.apple.com)，不带 scheme/路径")
		}
		cfg["SERVER_NAME"] = newValue
	default:
		return fmt.Errorf("未知字段: %s (支持: port / uuid / short-id / sni)", field)
	}

	// 重建 RealityConfig 结构，写 config.json + txt + nodes.json
	port, _ := strconv.Atoi(cfg["PORT"])
	rc := RealityConfig{
		ServerIP:       cfg["SERVER_IP"],
		IPVersion:      cfg["IP_VERSION"],
		Port:           port,
		UUID:           cfg["UUID"],
		PrivateKey:     cfg["PRIVATE_KEY"],
		PublicKey:      cfg["PUBLIC_KEY"],
		ShortID:        cfg["SHORT_ID"],
		ServerName:     cfg["SERVER_NAME"],
		SingboxVersion: cfg["SINGBOX_VERSION"],
	}

	if err := createRealityConfig(rc); err != nil {
		return fmt.Errorf("写 sing-box config 失败: %w", err)
	}
	saveRealityConfig(rc)
	upsertNode(storeNodeFromReality(rc))

	if err := utils.ServiceRestart("sing-box-reality"); err != nil {
		return fmt.Errorf("配置已更新但重启服务失败: %w (建议手工 systemctl restart sing-box-reality)", err)
	}
	return nil
}

func looksLikeUUID(s string) bool {
	parts := strings.Split(s, "-")
	if len(parts) != 5 {
		return false
	}
	exp := []int{8, 4, 4, 4, 12}
	for i, p := range parts {
		if len(p) != exp[i] || !looksLikeHex(p) {
			return false
		}
	}
	return true
}

func looksLikeHex(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9':
		case c >= 'a' && c <= 'f':
		case c >= 'A' && c <= 'F':
		default:
			return false
		}
	}
	return true
}
