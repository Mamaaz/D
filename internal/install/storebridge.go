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
//
// v4.0.33: ID 和 Name 都按 ServerIP 后缀唯一化。之前所有 VPS 的 Reality
// 节点都用静态 "vless-reality" / "VLESS-Reality",XSurge 合并多个订阅时
// node.id 撞 key,nodeOverrides 共享一个槽,改名串台。store/migrate.go
// rewriteStaticIDs 给老 nodes.json 在 load 时做 in-memory 迁移。

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
		ID:     fmt.Sprintf("vless-reality-%s", cfg.ServerIP),
		Name:   fmt.Sprintf("VLESS-Reality@%s", cfg.ServerIP),
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
		ID:     fmt.Sprintf("hysteria2-%s", cfg.ServerIP),
		Name:   fmt.Sprintf("Hysteria2@%s", cfg.ServerIP),
		Type:   store.TypeHysteria2,
		Server: cfg.ServerIP,
		Port:   cfg.Port,
		Params: params,
	}
}

func storeNodeFromAnyTLS(cfg AnyTLSConfig) store.Node {
	return store.Node{
		ID:     fmt.Sprintf("anytls-%s", cfg.ServerIP),
		Name:   fmt.Sprintf("AnyTLS@%s", cfg.ServerIP),
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
