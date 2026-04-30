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
			name:    "Snell + Shadow-TLS",
			check:   func() bool { return utils.FileExists(SnellProxyConfigPath) },
			rebuild: rebuildSnell,
			units:   []string{"snell", "shadow-tls"},
		},
		{
			name:    "SS2022 + Shadow-TLS",
			check:   func() bool { return utils.FileExists(SingboxProxyConfigPath) },
			rebuild: createSingboxService,
			units:   []string{"sing-box"},
		},
		{
			name:    "VLESS Reality",
			check:   func() bool { return utils.FileExists(RealityProxyConfigPath) },
			rebuild: createRealityService,
			units:   []string{"sing-box-reality"},
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

// rebuildSnell needs the original SnellConfig because shadow-tls.service's
// ExecStart embeds runtime parameters (port, sni, password). We reconstitute
// the cfg from the legacy .txt the service was originally installed with.
func rebuildSnell() error {
	kv, err := ParseConfigFile(SnellProxyConfigPath)
	if err != nil {
		return fmt.Errorf("parse snell config: %w", err)
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
	return createSnellServices(cfg)
}

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
