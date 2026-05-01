package install

import (
	"fmt"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// RebuildAllServices regenerates the systemd unit file for every installed
// protocol so an upgrade picks up changes to the unit (e.g., User= /
// Capabilities= / ExecStart= shifts that ship in a new binary version).
//
// Idempotent. Only acts on protocols that have an existing config file
// (i.e. were previously installed).  daemon-reload and service restart are
// invoked per-protocol so a partial failure on one doesn't block the others.
func RebuildAllServices() ([]string, error) {
	var rebuilt []string
	var firstErr error

	type svc struct {
		name    string
		check   func() bool
		rebuild func() error
		// service unit name(s) that need a restart afterwards
		units []string
	}

	tasks := []svc{
		{
			name:    "VLESS Reality",
			check:   func() bool { return utils.FileExists(RealityProxyConfigPath) },
			rebuild: rebuildReality,
			units:   []string{RealityServiceName},
		},
		{
			name:    "Hysteria2",
			check:   func() bool { return utils.FileExists(Hysteria2ProxyConfigPath) },
			rebuild: createHysteria2Service,
			units:   []string{"hysteria2"},
		},
		{
			name:    "AnyTLS",
			check:   func() bool { return utils.FileExists(AnyTLSProxyConfigPath) },
			rebuild: createAnyTLSService,
			units:   []string{"anytls"},
		},
		{
			name:    "AnyTLS + Reality",
			check:   func() bool { return utils.FileExists(AnyTLSRealityProxyConfigPath) },
			rebuild: createAnyTLSRealityService,
			units:   []string{AnyTLSRealityServiceName},
		},
	}

	for _, t := range tasks {
		if !t.check() {
			continue
		}
		if err := t.rebuild(); err != nil {
			utils.PrintWarn("[%s] 重建失败: %v", t.name, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		// Restart so the new unit's User=/Capabilities= take effect.
		for _, u := range t.units {
			if err := utils.ServiceRestart(u); err != nil {
				utils.PrintWarn("[%s] 重启 %s 失败: %v", t.name, u, err)
			}
		}
		rebuilt = append(rebuilt, t.name)
	}

	return rebuilt, firstErr
}

// rebuildReality 处理两种情况：
//  1. 全新 / 已是 xray 内核：重写 xray-reality.service unit
//  2. 旧 sing-box 内核 → 迁移到 xray (v4.0.7+)：
//     - 卸 sing-box-reality.service + 删旧 config dir
//     - 下载 xray binary (如未装)
//     - 用现有 keypair / UUID / SNI / shortID 重生成 xray config
//     - 起 xray-reality.service
//
// 关键：UUID / privateKey / publicKey / shortId 全保留——客户端订阅里这些
// 字段不变，重连后立即可用，无需重发新订阅。
func rebuildReality() error {
	migrateLegacyRealityIfPresent()
	utils.CreateSystemUser(RealityServiceUser)

	// 确保 xray binary 在；旧部署可能压根没有
	if !utils.FileExists(XrayBinaryPath) {
		arch, err := utils.DetectArch()
		if err != nil {
			return fmt.Errorf("detect arch: %w", err)
		}
		v := utils.GetLatestVersion("XTLS/Xray-core", DefaultXrayVersion)
		if err := downloadXray(v, arch); err != nil {
			return fmt.Errorf("download xray: %w", err)
		}
	}

	// 从 .txt 读现有配置 (sing-box 时代写的 PRIVATE_KEY/UUID 都能复用)
	kv, err := ParseConfigFile(RealityProxyConfigPath)
	if err != nil {
		return fmt.Errorf("parse reality config: %w", err)
	}
	cfg := RealityConfig{
		ServerIP:       kv["SERVER_IP"],
		IPVersion:      kv["IP_VERSION"],
		Port:           atoi(kv["PORT"]),
		UUID:           kv["UUID"],
		PrivateKey:     kv["PRIVATE_KEY"],
		PublicKey:      kv["PUBLIC_KEY"],
		ShortID:        kv["SHORT_ID"],
		ServerName:     kv["SERVER_NAME"],
		SingboxVersion: kv["SINGBOX_VERSION"], // 字段名兼容；存的可能是旧 sing-box 版本
	}
	if err := createRealityConfig(cfg); err != nil {
		return fmt.Errorf("create xray reality config: %w", err)
	}
	return createRealityService()
}

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
