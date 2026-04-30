package main

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/subscribe"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runDoctor implements `proxy-manager doctor`.
//
// One-shot health check: walks installed nodes, asks systemd whether each
// protocol's service is running, peeks at certificate expiry where we know
// the path, and prints a colored summary. No mutations; safe to run any time.
func runDoctor(args []string) {
	_ = args

	s, err := store.LoadOrMigrate()
	if err != nil {
		fmt.Fprintf(os.Stderr, "读取节点失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Printf("%s=== proxy-manager doctor ===%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Println()

	// --- Protocols section -------------------------------------------------
	fmt.Printf("%s[Protocols]%s\n", utils.ColorCyan, utils.ColorReset)
	if len(s.Nodes) == 0 {
		fmt.Println("  (尚未安装任何协议)")
	} else {
		nodes := append([]store.Node{}, s.Nodes...)
		sort.SliceStable(nodes, func(i, j int) bool { return nodes[i].ID < nodes[j].ID })
		for _, n := range nodes {
			printProtocolRow(n)
		}
	}

	// --- Subscribe service -------------------------------------------------
	fmt.Println()
	fmt.Printf("%s[Subscribe service]%s\n", utils.ColorCyan, utils.ColorReset)
	subState := subscribe.Status()
	if subState == "" {
		subState = "inactive"
	}
	subActive := subState == "active"
	checkmark := badIcon
	if subActive {
		checkmark = goodIcon
	}
	fmt.Printf("  %s %s\n", checkmark, paint(subState, subActive))
	if s.Subscribe.Domain != "" {
		fmt.Printf("    Domain: %s\n", s.Subscribe.Domain)
		fmt.Printf("    Port:   %d\n", s.Subscribe.Port)
		printAutocertCert(s.Subscribe.Domain)
	} else {
		fmt.Println("    (未配置 — proxy-manager subscribe enable 启用)")
	}

	// --- General -----------------------------------------------------------
	fmt.Println()
	fmt.Printf("%s[General]%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("  Config:  %s (%d nodes)\n", store.FilePath(), len(s.Nodes))
	legacyCount := countLegacyFiles()
	if legacyCount > 0 {
		fmt.Printf("  Legacy:  %d 旧 .txt 文件存在 (兼容存留，可忽略)\n", legacyCount)
	}
	fmt.Println()
}

// --- protocol row helpers --------------------------------------------------

const (
	goodIcon = "✓"
	warnIcon = "⚠"
	badIcon  = "✗"
)

// protocolDescriptor maps a Node.Type to the systemd unit + cert paths we
// can probe. Centralised here so adding a new protocol means one map entry.
type protocolDescriptor struct {
	displayName string
	serviceName string
	certPath    string // optional, empty if no cert to inspect
}

var protocolMap = map[store.NodeType]protocolDescriptor{
	store.TypeSnellShadowTLS:  {"Snell + Shadow-TLS", "snell", ""},
	store.TypeSS2022ShadowTLS: {"SS2022 + Shadow-TLS", "sing-box", ""},
	store.TypeVLESSReality:    {"VLESS + Reality", "sing-box-reality", ""},
	store.TypeHysteria2:       {"Hysteria2", "hysteria2", "/etc/hysteria2/server.crt"},
	store.TypeAnyTLS:          {"AnyTLS", "anytls", "/etc/anytls/server.crt"},
}

func printProtocolRow(n store.Node) {
	desc, ok := protocolMap[n.Type]
	if !ok {
		fmt.Printf("  ? %-40s 未知协议类型 (%s)\n", n.Name, n.Type)
		return
	}
	state := systemctlIsActive(desc.serviceName)
	icon := badIcon
	colored := false
	switch state {
	case "active":
		icon, colored = goodIcon, true
	case "activating", "reloading":
		icon = warnIcon
	}
	fmt.Printf("  %s %-22s %-24s %-12s :%d\n",
		icon, n.Name, desc.serviceName, paint(state, colored), n.Port)
	if desc.certPath != "" {
		printCertExpiry(desc.certPath, "    ")
	}
}

// systemctlIsActive shells out to systemctl. Uses Output (not Run) so we
// capture the literal state string regardless of exit code.
func systemctlIsActive(unit string) string {
	out, _ := exec.Command("systemctl", "is-active", unit).Output()
	state := strings.TrimSpace(string(out))
	if state == "" {
		return "unknown"
	}
	return state
}

// --- cert helpers ---------------------------------------------------------

func printCertExpiry(path, indent string) {
	cert, err := readCert(path)
	if err != nil {
		fmt.Printf("%s证书: %s%s%s (%v)\n", indent, utils.ColorYellow, path, utils.ColorReset, err)
		return
	}
	left := time.Until(cert.NotAfter)
	days := int(left.Hours() / 24)
	if days < 0 {
		fmt.Printf("%s证书: %s 已过期 %d 天前%s\n", indent, utils.ColorRed, -days, utils.ColorReset)
	} else if days < 14 {
		fmt.Printf("%s证书: %s%d 天后过期%s — 即将续约\n", indent, utils.ColorYellow, days, utils.ColorReset)
	} else {
		fmt.Printf("%s证书: %s%d 天后过期%s\n", indent, utils.ColorGreen, days, utils.ColorReset)
	}
}

func readCert(path string) (*x509.Certificate, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	for {
		block, rest := pem.Decode(data)
		if block == nil {
			break
		}
		if block.Type == "CERTIFICATE" {
			return x509.ParseCertificate(block.Bytes)
		}
		data = rest
	}
	return nil, fmt.Errorf("未找到 CERTIFICATE PEM block")
}

// printAutocertCert finds the most recent cert in the autocert cache for
// the given domain and reports expiry. autocert's cache uses the bare domain
// name as the filename, no extension.
func printAutocertCert(domain string) {
	candidates := []string{
		filepath.Join(subscribe.CertCacheDir, domain),
		filepath.Join(subscribe.CertCacheDir, domain+"+rsa"),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			printCertExpiry(p, "    ")
			return
		}
	}
	fmt.Printf("    证书: 尚未签发 (autocert 在首次请求时自动签)\n")
}

// --- misc -----------------------------------------------------------------

func countLegacyFiles() int {
	var n int
	for _, p := range store.LegacyPaths {
		if _, err := os.Stat(p); err == nil {
			n++
		}
	}
	return n
}

// paint colors a status string green-on-good or red-on-bad.
func paint(s string, good bool) string {
	if good {
		return utils.ColorGreen + s + utils.ColorReset
	}
	return utils.ColorRed + s + utils.ColorReset
}
