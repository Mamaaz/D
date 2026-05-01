package main

import (
	"crypto/tls"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/sni"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runSNITest 是 `proxy-manager sni-test <hostname>` 子命令的入口。
func runSNITest(args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "用法: proxy-manager sni-test <hostname>")
		fmt.Fprintln(os.Stderr, "  example: proxy-manager sni-test www.apple.com")
		os.Exit(2)
	}
	host := strings.TrimSpace(args[0])
	if host == "" {
		fmt.Fprintln(os.Stderr, "hostname 不能为空")
		os.Exit(2)
	}

	fmt.Println()
	fmt.Printf("%s=== SNI Test: %s ===%s\n", utils.ColorCyan, host, utils.ColorReset)
	fmt.Println()

	r := sni.Probe(host, 5*time.Second)
	renderProbe(r)

	if !r.Suitable() {
		os.Exit(1)
	}
}

func renderProbe(r *sni.ProbeResult) {
	if r.DNSError != nil {
		fmt.Printf("  %sDNS 解析失败:%s %v\n", utils.ColorRed, utils.ColorReset, r.DNSError)
		return
	}
	fmt.Printf("  解析:        %s\n", strings.Join(r.ResolvedIPs, ", "))

	if r.HandshakeErr != nil {
		fmt.Printf("  %sTLS 1.3 + X25519 握手失败:%s %v\n", utils.ColorRed, utils.ColorReset, r.HandshakeErr)
		return
	}
	fmt.Printf("  TLS 版本:    %s ✓\n", paintGreen(versionString(r.TLSVersion)))
	fmt.Printf("  Cipher:      %s\n", tls.CipherSuiteName(r.Cipher))
	fmt.Printf("  X25519:      %s (forced 强制 X25519，握手成功)\n", paintGreen("✓"))
	switch r.ALPN {
	case "h2":
		fmt.Printf("  ALPN:        %s\n", paintGreen("h2 ✓"))
	case "":
		fmt.Printf("  ALPN:        %s(无协商)%s\n", utils.ColorYellow, utils.ColorReset)
	default:
		fmt.Printf("  ALPN:        %s%s%s (h2 不支持，h1 可用但不优)\n", utils.ColorYellow, r.ALPN, utils.ColorReset)
	}
	if r.CertVerified {
		fmt.Printf("  证书链:      %s ✓\n", paintGreen("verified"))
	} else {
		fmt.Printf("  证书链:      %sunverified%s\n", utils.ColorRed, utils.ColorReset)
	}
	if r.CertCN != "" {
		fmt.Printf("  证书 CN:     %s\n", r.CertCN)
		fmt.Printf("  证书 SAN:    %s\n", strings.Join(r.CertSANs, ", "))
		fmt.Printf("  证书剩余:    %d 天\n", r.CertExpiresInDays)
	}
	if r.HTTPErr != nil {
		fmt.Printf("  HTTP HEAD:   %s%v%s\n", utils.ColorYellow, r.HTTPErr, utils.ColorReset)
	} else {
		fmt.Printf("  HTTP HEAD:   %d (Server: %s, %d ms)\n", r.HTTPStatus, r.Server, r.HTTPRTTMs)
	}
	fmt.Println()
	fmt.Printf("  TLS 握手耗时: %d ms\n", r.HandshakeMs)
	fmt.Println()
	if r.Suitable() {
		fmt.Printf("%s判定:%s %s 适合作 Reality SNI %s\n",
			utils.ColorCyan, utils.ColorReset, paintGreen("✅"), paintGreen(r.Host))
	} else {
		fmt.Printf("%s判定:%s %s 不建议作 Reality SNI（缺 TLS1.3/证书可信）\n",
			utils.ColorCyan, utils.ColorReset, paintRed("❌"))
	}
	fmt.Println()
}

func versionString(v uint16) string {
	switch v {
	case tls.VersionTLS13:
		return "TLS 1.3"
	case tls.VersionTLS12:
		return "TLS 1.2"
	case tls.VersionTLS11:
		return "TLS 1.1"
	case tls.VersionTLS10:
		return "TLS 1.0"
	default:
		return fmt.Sprintf("0x%04x", v)
	}
}

func paintGreen(s string) string { return utils.ColorGreen + s + utils.ColorReset }
func paintRed(s string) string   { return utils.ColorRed + s + utils.ColorReset }
