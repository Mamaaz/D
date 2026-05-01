// QuantumultX server_local 配置行生成。
//
// QX 在 iOS 上是 Reality 唯一好用的 client（Surge iOS 至今不支持 Reality）。
// 每协议字段名跟 Surge / Clash 都不一样，下面一一映射。
//
// 字段表 (VLESS Reality)：见 reference_qx_vless_reality memory，关键易漏：
//   - vless-flow=xtls-rprx-vision (不是 flow=)
//   - reality-base64-pubkey / reality-hex-shortid 字段名
//   - fast-open=false (Reality 用 iOS 26 Safari 指纹，Client Hello > 1500B，
//     TFO 必失败)
//   - obfs=over-tls (tcp transport)
package format

import (
	"fmt"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func vlessRealityToQX(n *store.Node) string {
	p := n.Params
	parts := []string{
		fmt.Sprintf("vless=%s:%d", n.Server, n.Port),
		"method=none",
		"password=" + str(p, "uuid"),
		"obfs=over-tls",
		"obfs-host=" + str(p, "server_name"),
		"reality-base64-pubkey=" + str(p, "public_key"),
		"reality-hex-shortid=" + str(p, "short_id"),
	}
	if flow := str(p, "flow"); flow != "" {
		parts = append(parts, "vless-flow="+flow)
	}
	parts = append(parts,
		"fast-open=false", // Reality + 大 ClientHello，TFO 必败
		"udp-relay=true",
		"tag="+n.Name,
	)
	return strings.Join(parts, ", ")
}

// QX Snell + ShadowTLS：n.Port 是公网 ShadowTLS 端口；snell_version 在 store
// 里是字符串。param key 名跟 Surge format 严格对齐 (避免拼写漂移)。
func snellToQX(n *store.Node) string {
	p := n.Params
	v := defaultInt(parseStrInt(str(p, "snell_version")), 4)
	stlsVer := defaultInt(num(p, "shadow_tls_version"), 3)
	sni := str(p, "shadow_tls_sni")
	parts := []string{
		fmt.Sprintf("snell=%s:%d", n.Server, n.Port),
		"psk=" + str(p, "snell_psk"),
		fmt.Sprintf("version=%d", v),
	}
	if stp := str(p, "shadow_tls_password"); stp != "" {
		parts = append(parts,
			"obfs=shadow-tls",
			"obfs-host="+sni,
			"obfs-uri=/",
			"shadow-tls-password="+stp,
			fmt.Sprintf("shadow-tls-version=%d", stlsVer),
			"shadow-tls-sni="+sni,
		)
	}
	parts = append(parts, "fast-open=false", "udp-relay=true", "tag="+n.Name)
	return strings.Join(parts, ", ")
}

// QX SS-2022 + ShadowTLS：n.Port 是公网 ShadowTLS 端口；param key 是
// `method` + `password` (没 ss_ 前缀)。
func ss2022ToQX(n *store.Node) string {
	p := n.Params
	stlsVer := defaultInt(num(p, "shadow_tls_version"), 3)
	sni := str(p, "shadow_tls_sni")
	parts := []string{
		fmt.Sprintf("shadowsocks=%s:%d", n.Server, n.Port),
		"method=" + str(p, "method"),
		"password=" + str(p, "password"),
	}
	if stp := str(p, "shadow_tls_password"); stp != "" {
		parts = append(parts,
			"obfs=shadow-tls",
			"obfs-host="+sni,
			"obfs-uri=/",
			"shadow-tls-password="+stp,
			fmt.Sprintf("shadow-tls-version=%d", stlsVer),
			"shadow-tls-sni="+sni,
		)
	}
	parts = append(parts, "fast-open=false", "udp-relay=true", "tag="+n.Name)
	return strings.Join(parts, ", ")
}

// QX Hysteria2: hysteria2= 块。连接 host 用域名 (LE 证书绑域名)，
// 用 IP 连会触发证书校验失败。obfs (salamander) 是可选 server-side feature。
func hysteria2ToQX(n *store.Node) string {
	p := n.Params
	host := str(p, "domain")
	if host == "" {
		host = n.Server
	}
	parts := []string{
		fmt.Sprintf("hysteria2=%s:%d", host, n.Port),
		"password=" + str(p, "password"),
		"sni=" + host,
	}
	if obfsPw := str(p, "obfs_password"); obfsPw != "" {
		parts = append(parts,
			"obfs=salamander",
			"obfs-password="+obfsPw,
		)
	}
	parts = append(parts, "fast-open=true", "udp-relay=true", "tag="+n.Name)
	return strings.Join(parts, ", ")
}

// QX AnyTLS: 2024 年 QX 加的协议。连接 host 用域名 (LE 证书)。
func anytlsToQX(n *store.Node) string {
	p := n.Params
	host := str(p, "domain")
	if host == "" {
		host = n.Server
	}
	parts := []string{
		fmt.Sprintf("anytls=%s:%d", host, n.Port),
		"password=" + str(p, "password"),
		"sni=" + host,
		"fast-open=true",
		"udp-relay=true",
		"tag=" + n.Name,
	}
	return strings.Join(parts, ", ")
}
