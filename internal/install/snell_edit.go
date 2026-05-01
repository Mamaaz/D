package install

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// CurrentSnellFields 列出 Snell + ShadowTLS 可编辑的字段。
// 这些字段都不涉及证书签发——纯 config + restart 就完事。
func CurrentSnellFields() ([]EditableRealityField, error) {
	if !utils.FileExists(SnellProxyConfigPath) {
		return nil, fmt.Errorf("Snell + Shadow-TLS 未安装")
	}
	cfg, err := ParseConfigFile(SnellProxyConfigPath)
	if err != nil {
		return nil, err
	}
	return []EditableRealityField{
		{Name: "snell-port", DisplayName: "Snell 内部端口", CurrentValue: cfg["SNELL_PORT"],
			Description: "Snell 监听端口，仅 ShadowTLS forward 用，不对公网开放"},
		{Name: "snell-psk", DisplayName: "Snell PSK", CurrentValue: cfg["SNELL_PSK"],
			Description: "Snell 协议预共享密钥；改后所有客户端立即失效"},
		{Name: "shadowtls-port", DisplayName: "ShadowTLS 公网端口", CurrentValue: cfg["SHADOW_TLS_PORT"],
			Description: "对外暴露的端口；防火墙要放行新端口"},
		{Name: "shadowtls-password", DisplayName: "ShadowTLS 密码", CurrentValue: cfg["SHADOW_TLS_PASSWORD"],
			Description: "ShadowTLS 验证密码；改后所有客户端立即失效"},
		{Name: "tls-domain", DisplayName: "ShadowTLS SNI", CurrentValue: cfg["TLS_DOMAIN"],
			Description: "TLS 握手仿冒的目标域名（如 itunes.apple.com）"},
	}, nil
}

// EditSnell 改 Snell + ShadowTLS 的一个字段并重启两个服务。
func EditSnell(field, newValue string) error {
	if !utils.FileExists(SnellProxyConfigPath) {
		return fmt.Errorf("Snell + Shadow-TLS 未安装")
	}
	kv, err := ParseConfigFile(SnellProxyConfigPath)
	if err != nil {
		return fmt.Errorf("解析现有配置失败: %w", err)
	}
	newValue = strings.TrimSpace(newValue)
	switch field {
	case "snell-port":
		if !validPort(newValue) {
			return fmt.Errorf("port 必须是 1-65535 的整数")
		}
		kv["SNELL_PORT"] = newValue
	case "snell-psk":
		if newValue == "" {
			return fmt.Errorf("PSK 不能为空")
		}
		kv["SNELL_PSK"] = newValue
	case "shadowtls-port":
		if !validPort(newValue) {
			return fmt.Errorf("port 必须是 1-65535 的整数")
		}
		kv["SHADOW_TLS_PORT"] = newValue
	case "shadowtls-password":
		if newValue == "" {
			return fmt.Errorf("密码不能为空")
		}
		kv["SHADOW_TLS_PASSWORD"] = newValue
	case "tls-domain":
		if !validBareHost(newValue) {
			return fmt.Errorf("SNI 必须是裸域名 (如 itunes.apple.com)")
		}
		kv["TLS_DOMAIN"] = newValue
	default:
		return fmt.Errorf("未知字段: %s (支持: snell-port / snell-psk / shadowtls-port / shadowtls-password / tls-domain)", field)
	}
	cfg := SnellConfig{
		ServerIP:          kv["SERVER_IP"],
		IPVersion:         kv["IP_VERSION"],
		SnellPort:         atoi(kv["SNELL_PORT"]),
		SnellPSK:          kv["SNELL_PSK"],
		ShadowTLSPort:     atoi(kv["SHADOW_TLS_PORT"]),
		ShadowTLSPassword: kv["SHADOW_TLS_PASSWORD"],
		TLSDomain:         kv["TLS_DOMAIN"],
		SnellVersion:      kv["SNELL_VERSION"],
		ShadowTLSVersion:  kv["SHADOW_TLS_VERSION"],
	}
	if err := createSnellConfig(cfg); err != nil {
		return fmt.Errorf("写 snell config 失败: %w", err)
	}
	if err := createSnellServices(cfg); err != nil {
		return fmt.Errorf("重写 service 失败: %w", err)
	}
	saveSnellConfig(cfg)
	upsertNode(storeNodeFromSnell(cfg))
	if err := utils.ServiceRestart("snell"); err != nil {
		return fmt.Errorf("配置已更新但重启 snell 失败: %w", err)
	}
	if err := utils.ServiceRestart("shadow-tls"); err != nil {
		return fmt.Errorf("配置已更新但重启 shadow-tls 失败: %w", err)
	}
	return nil
}

// CurrentSingboxFields / EditSingbox 是 SS-2022 + ShadowTLS 的等价版本。
// SS_METHOD 不让改——不同方法对密码长度有硬约束 (16/32 byte)，改方法
// = 重新生成密钥，等同于 reinstall 流程更清楚。
func CurrentSingboxFields() ([]EditableRealityField, error) {
	if !utils.FileExists(SingboxProxyConfigPath) {
		return nil, fmt.Errorf("SS-2022 + Shadow-TLS 未安装")
	}
	cfg, err := ParseConfigFile(SingboxProxyConfigPath)
	if err != nil {
		return nil, err
	}
	return []EditableRealityField{
		{Name: "ss-port", DisplayName: "SS 内部端口", CurrentValue: cfg["SS_PORT"],
			Description: "SS 监听端口，仅 ShadowTLS forward 用，不对公网开放"},
		{Name: "ss-password", DisplayName: "SS 密码", CurrentValue: cfg["SS_PASSWORD"],
			Description: "SS-2022 密码 (base64, " + cfg["SS_METHOD"] + " 方法)，改后客户端失效"},
		{Name: "shadowtls-port", DisplayName: "ShadowTLS 公网端口", CurrentValue: cfg["SHADOW_TLS_PORT"],
			Description: "对外暴露的端口；防火墙要放行新端口"},
		{Name: "shadowtls-password", DisplayName: "ShadowTLS 密码", CurrentValue: cfg["SHADOW_TLS_PASSWORD"],
			Description: "ShadowTLS 验证密码；改后所有客户端立即失效"},
		{Name: "tls-domain", DisplayName: "ShadowTLS SNI", CurrentValue: cfg["TLS_DOMAIN"],
			Description: "TLS 握手仿冒的目标域名（如 shonga.cc）"},
	}, nil
}

func EditSingbox(field, newValue string) error {
	if !utils.FileExists(SingboxProxyConfigPath) {
		return fmt.Errorf("SS-2022 + Shadow-TLS 未安装")
	}
	kv, err := ParseConfigFile(SingboxProxyConfigPath)
	if err != nil {
		return fmt.Errorf("解析现有配置失败: %w", err)
	}
	newValue = strings.TrimSpace(newValue)
	switch field {
	case "ss-port":
		if !validPort(newValue) {
			return fmt.Errorf("port 必须是 1-65535 的整数")
		}
		kv["SS_PORT"] = newValue
	case "ss-password":
		if newValue == "" {
			return fmt.Errorf("密码不能为空")
		}
		kv["SS_PASSWORD"] = newValue
	case "shadowtls-port":
		if !validPort(newValue) {
			return fmt.Errorf("port 必须是 1-65535 的整数")
		}
		kv["SHADOW_TLS_PORT"] = newValue
	case "shadowtls-password":
		if newValue == "" {
			return fmt.Errorf("密码不能为空")
		}
		kv["SHADOW_TLS_PASSWORD"] = newValue
	case "tls-domain":
		if !validBareHost(newValue) {
			return fmt.Errorf("SNI 必须是裸域名")
		}
		kv["TLS_DOMAIN"] = newValue
	default:
		return fmt.Errorf("未知字段: %s (支持: ss-port / ss-password / shadowtls-port / shadowtls-password / tls-domain)", field)
	}
	cfg := SingboxConfig{
		ServerIP:          kv["SERVER_IP"],
		IPVersion:         kv["IP_VERSION"],
		SSPort:            atoi(kv["SS_PORT"]),
		SSMethod:          kv["SS_METHOD"],
		SSPassword:        kv["SS_PASSWORD"],
		ShadowTLSPort:     atoi(kv["SHADOW_TLS_PORT"]),
		ShadowTLSPassword: kv["SHADOW_TLS_PASSWORD"],
		TLSDomain:         kv["TLS_DOMAIN"],
		SingboxVersion:    kv["SINGBOX_VERSION"],
	}
	if err := createSingboxConfig(cfg); err != nil {
		return fmt.Errorf("写 sing-box config 失败: %w", err)
	}
	saveSingboxConfig(cfg)
	upsertNode(storeNodeFromSingbox(cfg))
	if err := utils.ServiceRestart("sing-box"); err != nil {
		return fmt.Errorf("配置已更新但重启 sing-box 失败: %w", err)
	}
	return nil
}

func validPort(s string) bool {
	p, err := strconv.Atoi(s)
	return err == nil && p > 0 && p <= 65535
}
func validBareHost(s string) bool {
	return s != "" && !strings.ContainsAny(s, " \t/")
}
