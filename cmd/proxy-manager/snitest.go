package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runSNITest 是 `proxy-manager sni-test <hostname>` 子命令的入口。
//
// 从 VPS 视角对一个候选 SNI 做 TLS 1.3 + X25519 握手 + ALPN h2 协商 + 证书
// 链验证 + HTTP HEAD 探测，输出结构化判定。
//
// 这是 Reality SNI 选择流程里 VPS 视角的一票——本地 RealiTLScanner 扫出
// 候选清单后，从 VPS 跑这个命令确认那条出口路径上 TLS 表现 OK + 延迟可接受。
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

	// 1) DNS
	addrs, err := net.LookupHost(host)
	if err != nil {
		fmt.Printf("  %sDNS 解析失败:%s %v\n", utils.ColorRed, utils.ColorReset, err)
		os.Exit(1)
	}
	fmt.Printf("  解析:        %s\n", strings.Join(addrs, ", "))

	// 2) TLS 1.3 + X25519 握手
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	cfg := &tls.Config{
		ServerName:       host,
		MinVersion:       tls.VersionTLS13,
		MaxVersion:       tls.VersionTLS13,
		CurvePreferences: []tls.CurveID{tls.X25519}, // 只发 X25519，握手成功即对端支持
		NextProtos:       []string{"h2", "http/1.1"},
	}
	started := time.Now()
	conn, err := tls.DialWithDialer(dialer, "tcp", host+":443", cfg)
	if err != nil {
		fmt.Printf("  %sTLS 1.3 + X25519 握手失败:%s %v\n", utils.ColorRed, utils.ColorReset, err)
		os.Exit(1)
	}
	defer conn.Close()
	tlsRTT := time.Since(started)
	state := conn.ConnectionState()

	fmt.Printf("  TLS 版本:    %s ✓\n", paintGreen(versionString(state.Version)))
	fmt.Printf("  Cipher:      %s\n", tls.CipherSuiteName(state.CipherSuite))
	fmt.Printf("  X25519:      %s (forced 强制 X25519，握手成功)\n", paintGreen("✓"))
	if state.NegotiatedProtocol == "h2" {
		fmt.Printf("  ALPN:        %s\n", paintGreen("h2 ✓"))
	} else if state.NegotiatedProtocol != "" {
		fmt.Printf("  ALPN:        %s%s%s (h2 不支持，h1 可用但不优)\n", utils.ColorYellow, state.NegotiatedProtocol, utils.ColorReset)
	} else {
		fmt.Printf("  ALPN:        %s(无协商)%s\n", utils.ColorYellow, utils.ColorReset)
	}

	// 3) 证书
	certVerified := verifyChain(state.PeerCertificates, host)
	if certVerified {
		fmt.Printf("  证书链:      %s ✓\n", paintGreen("verified"))
	} else {
		fmt.Printf("  证书链:      %sunverified%s (Reality 仍可用，但需谨慎)\n", utils.ColorRed, utils.ColorReset)
	}
	if len(state.PeerCertificates) > 0 {
		c := state.PeerCertificates[0]
		fmt.Printf("  证书 CN:     %s\n", c.Subject.CommonName)
		fmt.Printf("  证书 SAN:    %s\n", strings.Join(c.DNSNames, ", "))
		left := time.Until(c.NotAfter)
		fmt.Printf("  证书剩余:    %d 天\n", int(left.Hours()/24))
	}

	// 4) HTTP HEAD
	httpStarted := time.Now()
	hresp, herr := httpHead("https://" + host + "/")
	httpRTT := time.Since(httpStarted)
	if herr != nil {
		fmt.Printf("  HTTP HEAD:   %s%v%s\n", utils.ColorYellow, herr, utils.ColorReset)
	} else {
		serverHdr := hresp.Header.Get("Server")
		fmt.Printf("  HTTP HEAD:   %d %s (Server: %s, %d ms)\n", hresp.StatusCode, hresp.Status, serverHdr, httpRTT.Milliseconds())
		hresp.Body.Close()
	}

	fmt.Println()
	fmt.Printf("  TLS 握手耗时: %d ms\n", tlsRTT.Milliseconds())

	// 5) 总判
	tls13 := state.Version == tls.VersionTLS13
	suitable := tls13 && certVerified
	fmt.Println()
	if suitable {
		fmt.Printf("%s判定:%s %s 适合作 Reality SNI %s\n", utils.ColorCyan, utils.ColorReset, paintGreen("✅"), paintGreen(host))
	} else {
		fmt.Printf("%s判定:%s %s 不建议作 Reality SNI（缺 TLS1.3/证书可信）\n", utils.ColorCyan, utils.ColorReset, paintRed("❌"))
		os.Exit(1)
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

// verifyChain 用系统根证书池校验对端证书链。crypto/tls 默认在 Dial 时已经
// verify 了（除非 InsecureSkipVerify=true）—— 这里 Dial 不带 skip，所以
// 能 Dial 成功本身就意味着 verified。但显式跑一次 chain build 让我们能区分
// "Dial 成功 + 证书 OK" 和 "Dial 失败"。
func verifyChain(chain []*x509.Certificate, hostname string) bool {
	if len(chain) == 0 {
		return false
	}
	roots, _ := x509.SystemCertPool()
	intermediates := x509.NewCertPool()
	for _, c := range chain[1:] {
		intermediates.AddCert(c)
	}
	_, err := chain[0].Verify(x509.VerifyOptions{
		Roots:         roots,
		Intermediates: intermediates,
		DNSName:       hostname,
	})
	return err == nil
}

func httpHead(url string) (*http.Response, error) {
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodHead, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "proxy-manager sni-test")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	// 即使 HEAD 也 drain 掉 body 避免 keep-alive 漏 fd
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp, nil
}

func paintGreen(s string) string { return utils.ColorGreen + s + utils.ColorReset }
func paintRed(s string) string   { return utils.ColorRed + s + utils.ColorReset }
