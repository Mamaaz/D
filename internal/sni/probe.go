// Package sni 提供 Reality SNI 候选探测 + 批量打分排序。CLI (sni-test /
// sni-rank) 和 TUI 菜单都从这里调，避免逻辑重复。
package sni

import (
	"crypto/tls"
	"crypto/x509"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// ProbeResult 是单个 host 的探测结果。结构化输出，单点 sni-test 直接渲染，
// 批量 sni-rank 用来排序+打分。
type ProbeResult struct {
	Host        string
	ResolvedIPs []string
	DNSError    error

	TLSVersion   uint16 // tls.VersionTLS13 等
	Cipher       uint16
	X25519       bool
	ALPN         string
	HandshakeMs  int
	HandshakeErr error

	CertVerified      bool
	CertCN            string
	CertSANs          []string
	CertExpiresInDays int

	HTTPStatus int
	HTTPRTTMs  int
	Server     string
	HTTPErr    error
}

// Suitable 等同于现有 sni-test 的判定：TLS 1.3 + cert verified。h2 加分但不强求。
func (r *ProbeResult) Suitable() bool {
	return r.HandshakeErr == nil && r.TLSVersion == tls.VersionTLS13 && r.CertVerified
}

// IsCDN 用 Server header 启发式判断常见 CDN。Reality 协议建议避开 CDN。
func (r *ProbeResult) IsCDN() bool {
	if r.Server == "" {
		return false
	}
	s := strings.ToLower(r.Server)
	for _, k := range []string{"cloudflare", "akamai", "fastly", "cloudfront", "netlify"} {
		if strings.Contains(s, k) {
			return true
		}
	}
	return false
}

// Probe 跑一次完整探测：DNS → TLS 1.3 + X25519 握手 → ALPN → 证书 → HTTP HEAD。
// 失败/部分失败也返回 result，由调用方决定如何渲染。
func Probe(host string, hardTimeout time.Duration) *ProbeResult {
	r := &ProbeResult{Host: host}

	addrs, err := net.LookupHost(host)
	if err != nil {
		r.DNSError = err
		return r
	}
	r.ResolvedIPs = addrs

	dialer := &net.Dialer{Timeout: hardTimeout}
	cfg := &tls.Config{
		ServerName:       host,
		MinVersion:       tls.VersionTLS13,
		MaxVersion:       tls.VersionTLS13,
		CurvePreferences: []tls.CurveID{tls.X25519},
		NextProtos:       []string{"h2", "http/1.1"},
	}
	tlsStart := time.Now()
	conn, err := tls.DialWithDialer(dialer, "tcp", host+":443", cfg)
	r.HandshakeMs = int(time.Since(tlsStart).Milliseconds())
	if err != nil {
		r.HandshakeErr = err
		return r
	}
	defer conn.Close()
	state := conn.ConnectionState()
	r.TLSVersion = state.Version
	r.Cipher = state.CipherSuite
	r.X25519 = (state.Version == tls.VersionTLS13)
	r.ALPN = state.NegotiatedProtocol

	if len(state.PeerCertificates) > 0 {
		r.CertVerified = verifyChain(state.PeerCertificates, host)
		c := state.PeerCertificates[0]
		r.CertCN = c.Subject.CommonName
		r.CertSANs = c.DNSNames
		r.CertExpiresInDays = int(time.Until(c.NotAfter).Hours() / 24)
	}

	httpStart := time.Now()
	resp, herr := httpHEAD("https://" + host + "/")
	r.HTTPRTTMs = int(time.Since(httpStart).Milliseconds())
	if herr != nil {
		r.HTTPErr = herr
	} else {
		r.HTTPStatus = resp.StatusCode
		r.Server = resp.Header.Get("Server")
		resp.Body.Close()
	}
	return r
}

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

func httpHEAD(url string) (*http.Response, error) {
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodHead, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "proxy-manager sni-probe")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp, nil
}
