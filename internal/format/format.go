// Package format renders Node entries from the store into client-facing
// configuration in different formats: Surge, Clash Meta, sing-box, and xray.
//
// Surge / Clash / sing-box cover all five protocols this tool installs.
// xray is implemented for VLESS-Reality only (the one protocol that needs a
// client-side bridge for Surge users).
package format

import (
	"errors"
	"fmt"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

// ErrUnsupportedFormat is returned when a protocol cannot be rendered in the
// requested format (e.g. xray output for Snell).
var ErrUnsupportedFormat = errors.New("format not supported for this protocol")

// ErrUnknownNodeType signals a Node.Type that no generator is registered for.
var ErrUnknownNodeType = errors.New("unknown node type")

// ToSurge returns one [Proxy] line (no trailing newline).
func ToSurge(n *store.Node) (string, error) {
	switch n.Type {
	case store.TypeSnellShadowTLS:
		return snellToSurge(n), nil
	case store.TypeSS2022ShadowTLS:
		return ss2022ToSurge(n), nil
	case store.TypeVLESSReality:
		return vlessRealityToSurge(n), nil
	case store.TypeHysteria2:
		return hysteria2ToSurge(n), nil
	case store.TypeAnyTLS:
		return anytlsToSurge(n), nil
	}
	return "", fmt.Errorf("%w: %q", ErrUnknownNodeType, n.Type)
}

// ToClash returns a Clash Meta proxy entry as map[string]any.
func ToClash(n *store.Node) (map[string]any, error) {
	switch n.Type {
	case store.TypeSnellShadowTLS:
		return snellToClash(n), nil
	case store.TypeSS2022ShadowTLS:
		return ss2022ToClash(n), nil
	case store.TypeVLESSReality:
		return vlessRealityToClash(n), nil
	case store.TypeHysteria2:
		return hysteria2ToClash(n), nil
	case store.TypeAnyTLS:
		return anytlsToClash(n), nil
	}
	return nil, fmt.Errorf("%w: %q", ErrUnknownNodeType, n.Type)
}

// ToSingbox returns one or more sing-box outbound entries for the node.
// ShadowTLS-fronted protocols emit two outbounds (outer ShadowTLS + inner SS).
func ToSingbox(n *store.Node) ([]map[string]any, error) {
	switch n.Type {
	case store.TypeSnellShadowTLS:
		return nil, fmt.Errorf("%w: snell has no sing-box outbound", ErrUnsupportedFormat)
	case store.TypeSS2022ShadowTLS:
		return ss2022ToSingbox(n), nil
	case store.TypeVLESSReality:
		return []map[string]any{vlessRealityToSingbox(n)}, nil
	case store.TypeHysteria2:
		return []map[string]any{hysteria2ToSingbox(n)}, nil
	case store.TypeAnyTLS:
		return []map[string]any{anytlsToSingbox(n)}, nil
	}
	return nil, fmt.Errorf("%w: %q", ErrUnknownNodeType, n.Type)
}

// ToXray returns xray outbound entries. Only VLESS-Reality is supported,
// since xray is the canonical Reality client and the bridge is only needed
// for that one protocol.
func ToXray(n *store.Node) ([]map[string]any, error) {
	if n.Type == store.TypeVLESSReality {
		return []map[string]any{vlessRealityToXray(n)}, nil
	}
	return nil, fmt.Errorf("%w: xray only renders vless-reality (use surge/sing-box for %q)", ErrUnsupportedFormat, n.Type)
}

// NeedsBridge reports whether a node must be reached via a local proxy bridge
// (xray) to be usable by Surge. Currently only VLESS-Reality.
func NeedsBridge(n *store.Node) bool {
	return n.Type == store.TypeVLESSReality
}

// --- typed param accessors -------------------------------------------------
// JSON numbers always decode to float64. These helpers normalize back to the
// expected Go types so callers don't sprinkle type assertions everywhere.

func str(p map[string]any, key string) string {
	if v, ok := p[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func num(p map[string]any, key string) int {
	if v, ok := p[key]; ok {
		switch x := v.(type) {
		case int:
			return x
		case int64:
			return int(x)
		case float64:
			return int(x)
		}
	}
	return 0
}

func boolean(p map[string]any, key string) bool {
	if v, ok := p[key]; ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return false
}
