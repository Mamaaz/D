package install

import (
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
