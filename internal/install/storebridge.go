package install

import (
	"fmt"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// This file bridges the per-protocol install structs into the unified
// store.Node format. Install/uninstall functions call these helpers in
// addition to the legacy .txt save/delete; the .txt files remain the
// runtime source of truth for now and are removed in a later PR.

func upsertNode(n store.Node) {
	if err := store.Upsert(n); err != nil {
		utils.PrintWarn("写入 nodes.json 失败 (不影响安装): %v", err)
	}
}

func removeNodeByType(t store.NodeType) {
	if err := store.RemoveByType(t); err != nil {
		utils.PrintWarn("从 nodes.json 移除失败 (不影响卸载): %v", err)
	}
}

func storeNodeFromSnell(cfg SnellConfig) store.Node {
	stlsVer := 3
	if cfg.ShadowTLSVersion != "" {
		stlsVer = parseIntOr(cfg.ShadowTLSVersion, 3)
	}
	snellVer := cfg.SnellVersion
	if snellVer == "" {
		snellVer = "4"
	}
	return store.Node{
		ID:     "snell-shadowtls",
		Name:   "Snell-ShadowTLS",
		Type:   store.TypeSnellShadowTLS,
		Server: cfg.ServerIP,
		Port:   cfg.ShadowTLSPort,
		Params: map[string]any{
			"snell_port":          cfg.SnellPort,
			"snell_psk":           cfg.SnellPSK,
			"snell_version":       snellVer,
			"shadow_tls_password": cfg.ShadowTLSPassword,
			"shadow_tls_sni":      cfg.TLSDomain,
			"shadow_tls_version":  stlsVer,
		},
	}
}

func parseIntOr(s string, fallback int) int {
	var n int
	if _, err := fmt.Sscanf(s, "%d", &n); err != nil || n == 0 {
		return fallback
	}
	return n
}

func storeNodeFromSingbox(cfg SingboxConfig) store.Node {
	return store.Node{
		ID:     "ss2022-shadowtls",
		Name:   "SS2022-ShadowTLS",
		Type:   store.TypeSS2022ShadowTLS,
		Server: cfg.ServerIP,
		Port:   cfg.ShadowTLSPort,
		Params: map[string]any{
			"ss_port":             cfg.SSPort,
			"method":              cfg.SSMethod,
			"password":            cfg.SSPassword,
			"shadow_tls_password": cfg.ShadowTLSPassword,
			"shadow_tls_sni":      cfg.TLSDomain,
			"shadow_tls_version":  3,
		},
	}
}

func storeNodeFromReality(cfg RealityConfig) store.Node {
	return store.Node{
		ID:     "vless-reality",
		Name:   "VLESS-Reality",
		Type:   store.TypeVLESSReality,
		Server: cfg.ServerIP,
		Port:   cfg.Port,
		Params: map[string]any{
			"uuid":        cfg.UUID,
			"private_key": cfg.PrivateKey,
			"public_key":  cfg.PublicKey,
			"short_id":    cfg.ShortID,
			"server_name": cfg.ServerName,
			"flow":        "xtls-rprx-vision",
		},
	}
}

func storeNodeFromHysteria2(cfg Hysteria2Config) store.Node {
	params := map[string]any{
		"password":    cfg.Password,
		"domain":      cfg.Domain,
		"enable_obfs": cfg.EnableObfs,
	}
	if cfg.EnableObfs {
		params["obfs_password"] = cfg.ObfsPassword
	}
	return store.Node{
		ID:     "hysteria2",
		Name:   "Hysteria2",
		Type:   store.TypeHysteria2,
		Server: cfg.ServerIP,
		Port:   cfg.Port,
		Params: params,
	}
}

func storeNodeFromAnyTLS(cfg AnyTLSConfig) store.Node {
	return store.Node{
		ID:     "anytls",
		Name:   "AnyTLS",
		Type:   store.TypeAnyTLS,
		Server: cfg.ServerIP,
		Port:   cfg.Port,
		Params: map[string]any{
			"password":     cfg.Password,
			"domain":       cfg.Domain,
			"padding_name": cfg.PaddingName,
		},
	}
}
