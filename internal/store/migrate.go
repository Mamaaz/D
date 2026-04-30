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
	"/etc/snell-proxy-config.txt",
	"/etc/singbox-proxy-config.txt",
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
	switch kv["TYPE"] {
	case "snell":
		return Node{
			ID:     "snell-shadowtls",
			Name:   "Snell-ShadowTLS",
			Type:   TypeSnellShadowTLS,
			Server: kv["SERVER_IP"],
			Port:   atoi(kv["SHADOW_TLS_PORT"]),
			Params: map[string]any{
				"snell_port":          atoi(kv["SNELL_PORT"]),
				"snell_psk":           kv["SNELL_PSK"],
				"snell_version":       kv["SNELL_VERSION"],
				"shadow_tls_password": kv["SHADOW_TLS_PASSWORD"],
				"shadow_tls_sni":      kv["TLS_DOMAIN"],
				"shadow_tls_version":  atoiOr(kv["SHADOW_TLS_VERSION"], 3),
			},
		}, true
	case "singbox":
		return Node{
			ID:     "ss2022-shadowtls",
			Name:   "SS2022-ShadowTLS",
			Type:   TypeSS2022ShadowTLS,
			Server: kv["SERVER_IP"],
			Port:   atoi(kv["SHADOW_TLS_PORT"]),
			Params: map[string]any{
				"ss_port":             atoi(kv["SS_PORT"]),
				"method":              kv["SS_METHOD"],
				"password":            kv["SS_PASSWORD"],
				"shadow_tls_password": kv["SHADOW_TLS_PASSWORD"],
				"shadow_tls_sni":      kv["TLS_DOMAIN"],
				"shadow_tls_version":  3,
			},
		}, true
	case "reality":
		return Node{
			ID:     "vless-reality",
			Name:   "VLESS-Reality",
			Type:   TypeVLESSReality,
			Server: kv["SERVER_IP"],
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
			ID:     "hysteria2",
			Name:   "Hysteria2",
			Type:   TypeHysteria2,
			Server: kv["SERVER_IP"],
			Port:   atoi(kv["HYSTERIA2_PORT"]),
			Params: params,
		}, true
	case "anytls":
		return Node{
			ID:     "anytls",
			Name:   "AnyTLS",
			Type:   TypeAnyTLS,
			Server: kv["SERVER_IP"],
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

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func atoiOr(s string, fallback int) int {
	if s == "" {
		return fallback
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return fallback
	}
	return n
}
