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

// QX Snell + ShadowTLS：QX 的 snell 块支持 obfs=shadow-tls 嵌入。
func snellToQX(n *store.Node) string {
	p := n.Params
	parts := []string{
		fmt.Sprintf("snell=%s:%d", n.Server, num(p, "shadowtls_port")),
		"psk=" + str(p, "snell_psk"),
		fmt.Sprintf("version=%d", num(p, "snell_version")),
	}
	if num(p, "snell_version") == 0 {
		parts[2] = "version=5" // 缺省 v5
	}
	if stp := str(p, "shadowtls_password"); stp != "" {
		parts = append(parts,
			"obfs=shadow-tls",
			"obfs-host="+str(p, "tls_domain"),
			"obfs-uri=/",
			"shadow-tls-password="+stp,
			"shadow-tls-version=3",
			"shadow-tls-sni="+str(p, "tls_domain"),
		)
	}
	parts = append(parts, "fast-open=false", "udp-relay=true", "tag="+n.Name)
	return strings.Join(parts, ", ")
}

// QX SS-2022 + ShadowTLS：method 用 shadowsocks 标准 method 字段；ShadowTLS
// 套在外层用 obfs=shadow-tls。
func ss2022ToQX(n *store.Node) string {
	p := n.Params
	parts := []string{
		fmt.Sprintf("shadowsocks=%s:%d", n.Server, num(p, "shadowtls_port")),
		"method=" + str(p, "ss_method"),
		"password=" + str(p, "ss_password"),
	}
	if stp := str(p, "shadowtls_password"); stp != "" {
		parts = append(parts,
			"obfs=shadow-tls",
			"obfs-host="+str(p, "tls_domain"),
			"obfs-uri=/",
			"shadow-tls-password="+stp,
			"shadow-tls-version=3",
			"shadow-tls-sni="+str(p, "tls_domain"),
		)
	}
	parts = append(parts, "fast-open=false", "udp-relay=true", "tag="+n.Name)
	return strings.Join(parts, ", ")
}

// QX Hysteria2: hysteria2= 块。obfs (salamander) 是可选的 server-side feature。
func hysteria2ToQX(n *store.Node) string {
	p := n.Params
	parts := []string{
		fmt.Sprintf("hysteria2=%s:%d", n.Server, n.Port),
		"password=" + str(p, "password"),
		"sni=" + str(p, "domain"),
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

// QX AnyTLS: 2024 年 QX 加的协议。anytls= 块。
func anytlsToQX(n *store.Node) string {
	p := n.Params
	parts := []string{
		fmt.Sprintf("anytls=%s:%d", n.Server, n.Port),
		"password=" + str(p, "password"),
		"sni=" + str(p, "domain"),
		"fast-open=true",
		"udp-relay=true",
		"tag=" + n.Name,
	}
	return strings.Join(parts, ", ")
}
