package store

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// LegacyPaths is the set of pre-store .txt config files this package can
// migrate. Kept exported so install/uninstall code can detect/remove them.
var LegacyPaths = []string{
	"/etc/reality-proxy-config.txt",
	"/etc/hysteria2-proxy-config.txt",
	"/etc/anytls-proxy-config.txt",
}

// LoadOrMigrate reads the store, importing from legacy .txt files on the first
// call (when nodes.json doesn't yet exist). Idempotent and safe to call from
// any code path before reading nodes.
func LoadOrMigrate() (*Store, error) {
	if _, err := os.Stat(StorePath); err == nil {
		return Load()
	} else if !os.IsNotExist(err) {
		return nil, err
	}

	s := &Store{Version: StoreVersion}
	for _, p := range LegacyPaths {
		if _, err := os.Stat(p); err != nil {
			continue
		}
		kv, err := readLegacyTxt(p)
		if err != nil {
			return nil, fmt.Errorf("read legacy %s: %w", p, err)
		}
		node, ok := legacyToNode(kv)
		if !ok {
			continue
		}
		s.Nodes = append(s.Nodes, node)
	}
	// Best-effort persist: callers may be non-root (e.g. local diagnostics),
	// in which case we still return the in-memory store rather than fail.
	_ = Save(s)
	return s, nil
}

func readLegacyTxt(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	out := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		i := strings.IndexByte(line, '=')
		if i <= 0 {
			continue
		}
		out[line[:i]] = line[i+1:]
	}
	return out, sc.Err()
}

func legacyToNode(kv map[string]string) (Node, bool) {
	ip := kv["SERVER_IP"]
	switch kv["TYPE"] {
	case "reality":
		return Node{
			ID:     fmt.Sprintf("vless-reality-%s", ip),
			Name:   fmt.Sprintf("VLESS-Reality@%s", ip),
			Type:   TypeVLESSReality,
			Server: ip,
			Port:   atoi(kv["PORT"]),
			Params: map[string]any{
				"uuid":        kv["UUID"],
				"private_key": kv["PRIVATE_KEY"],
				"public_key":  kv["PUBLIC_KEY"],
				"short_id":    kv["SHORT_ID"],
				"server_name": kv["SERVER_NAME"],
				"flow":        "xtls-rprx-vision",
			},
		}, true
	case "hysteria2":
		params := map[string]any{
			"password":    kv["HYSTERIA2_PASSWORD"],
			"domain":      kv["HYSTERIA2_DOMAIN"],
			"enable_obfs": kv["ENABLE_OBFS"] == "true",
		}
		if v, ok := kv["OBFS_PASSWORD"]; ok && v != "" {
			params["obfs_password"] = v
		}
		return Node{
			ID:     fmt.Sprintf("hysteria2-%s", ip),
			Name:   fmt.Sprintf("Hysteria2@%s", ip),
			Type:   TypeHysteria2,
			Server: ip,
			Port:   atoi(kv["HYSTERIA2_PORT"]),
			Params: params,
		}, true
	case "anytls":
		return Node{
			ID:     fmt.Sprintf("anytls-%s", ip),
			Name:   fmt.Sprintf("AnyTLS@%s", ip),
			Type:   TypeAnyTLS,
			Server: ip,
			Port:   atoi(kv["ANYTLS_PORT"]),
			Params: map[string]any{
				"password":     kv["ANYTLS_PASSWORD"],
				"domain":       kv["ANYTLS_DOMAIN"],
				"padding_name": kv["PADDING_NAME"],
			},
		}, true
	}
	return Node{}, false
}

// rewriteStaticIDs 把 v4.0.32 之前用的"全 VPS 共享"的静态 ID/Name 改写成
// 按 ServerIP 唯一化的形式。XSurge 合并多个订阅的节点时按 node.id 索引
// nodeOverrides;静态 ID 撞 key 导致重命名串台 (一个订阅改名,所有订阅
// 跟着变),v4.0.33 起服务端写出来的 ID 就是唯一的,这里 in-memory 给老
// nodes.json 也做同样处理,subscribe 服务返给客户端的 JSON 立刻拿到
// 唯一 ID,不必等用户重装协议。
//
// 幂等:已经唯一化的 ID 不再处理 (前缀匹配 + "-" 后还有内容才算静态)。
// 不写盘:loadLocked 是只读路径,subscribe 用非 root 用户跑没写权;下次
// install/edit 走 saveLocked 时自然落盘。
func rewriteStaticIDs(s *Store) {
	for i := range s.Nodes {
		n := &s.Nodes[i]
		if n.Server == "" {
			continue
		}
		switch n.ID {
		case "vless-reality":
			n.ID = fmt.Sprintf("vless-reality-%s", n.Server)
			if n.Name == "VLESS-Reality" || n.Name == "Reality" {
				n.Name = fmt.Sprintf("VLESS-Reality@%s", n.Server)
			}
		case "hysteria2":
			n.ID = fmt.Sprintf("hysteria2-%s", n.Server)
			if n.Name == "Hysteria2" {
				n.Name = fmt.Sprintf("Hysteria2@%s", n.Server)
			}
		case "anytls":
			n.ID = fmt.Sprintf("anytls-%s", n.Server)
			if n.Name == "AnyTLS" {
				n.Name = fmt.Sprintf("AnyTLS@%s", n.Server)
			}
		case "anytls-reality":
			n.ID = fmt.Sprintf("anytls-reality-%s", n.Server)
			if n.Name == "AnyTLS-Reality" {
				n.Name = fmt.Sprintf("AnyTLS-Reality@%s", n.Server)
			}
		}
	}
}

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
