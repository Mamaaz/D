// Package store implements the unified nodes.json storage layer.
//
// Each installed proxy node is a single entry in a flat list. Per-protocol
// .txt config files (legacy) are kept for backward compatibility but the
// JSON store is the canonical source of truth going forward.
package store

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const (
	StorePath    = "/etc/proxy-manager/nodes.json"
	StoreDir     = "/etc/proxy-manager"
	StoreVersion = 1
)

// NodeType enumerates the supported protocol kinds. Strings, not iota, so
// the JSON representation is stable across binary upgrades.
type NodeType string

const (
	TypeSnellShadowTLS    NodeType = "snell-shadowtls"
	TypeSS2022ShadowTLS   NodeType = "ss2022-shadowtls"
	TypeVLESSReality      NodeType = "vless-reality"
	TypeHysteria2         NodeType = "hysteria2"
	TypeAnyTLS            NodeType = "anytls"
)

// Node is a single installed proxy. Params holds protocol-specific fields;
// keys vary by Type. Generators consume Type+Params to render client configs.
type Node struct {
	ID        string         `json:"id"`
	Name      string         `json:"name"`
	Type      NodeType       `json:"type"`
	Server    string         `json:"server"`
	Port      int            `json:"port"`
	Params    map[string]any `json:"params"`
	CreatedAt time.Time      `json:"created_at"`
}

// SubscribeConfig is reserved for PR2 (subscription server). The token field
// is generated on first install but only consumed once the HTTP service ships.
type SubscribeConfig struct {
	Token  string `json:"token,omitempty"`
	Domain string `json:"domain,omitempty"`
	Port   int    `json:"port,omitempty"`
}

// Store is the on-disk root document.
type Store struct {
	Version   int             `json:"version"`
	Subscribe SubscribeConfig `json:"subscribe"`
	Nodes     []Node          `json:"nodes"`
}

var mu sync.Mutex

// Load reads the store file. If it doesn't exist, returns an empty store.
// Migration from legacy .txt configs is performed by callers of LoadOrMigrate.
func Load() (*Store, error) {
	mu.Lock()
	defer mu.Unlock()
	return loadLocked()
}

func loadLocked() (*Store, error) {
	data, err := os.ReadFile(StorePath)
	if os.IsNotExist(err) {
		return &Store{Version: StoreVersion}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read store: %w", err)
	}
	var s Store
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("parse store: %w", err)
	}
	if s.Version == 0 {
		s.Version = StoreVersion
	}
	return &s, nil
}

// Save writes the store atomically (temp file + rename).
func Save(s *Store) error {
	mu.Lock()
	defer mu.Unlock()
	return saveLocked(s)
}

func saveLocked(s *Store) error {
	if s.Version == 0 {
		s.Version = StoreVersion
	}
	if err := os.MkdirAll(StoreDir, 0755); err != nil {
		return fmt.Errorf("mkdir store dir: %w", err)
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal store: %w", err)
	}
	tmp := StorePath + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return fmt.Errorf("write store tmp: %w", err)
	}
	if err := os.Rename(tmp, StorePath); err != nil {
		return fmt.Errorf("rename store: %w", err)
	}
	return nil
}

// Upsert inserts a node, replacing any existing node with the same ID.
func Upsert(node Node) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadLocked()
	if err != nil {
		return err
	}
	if node.CreatedAt.IsZero() {
		node.CreatedAt = time.Now().UTC()
	}
	replaced := false
	for i, n := range s.Nodes {
		if n.ID == node.ID {
			s.Nodes[i] = node
			replaced = true
			break
		}
	}
	if !replaced {
		s.Nodes = append(s.Nodes, node)
	}
	return saveLocked(s)
}

// RemoveByID removes a node. Missing IDs are not an error.
func RemoveByID(id string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadLocked()
	if err != nil {
		return err
	}
	out := s.Nodes[:0]
	for _, n := range s.Nodes {
		if n.ID != id {
			out = append(out, n)
		}
	}
	s.Nodes = out
	return saveLocked(s)
}

// RemoveByType removes all nodes whose Type matches. Used by uninstall flows
// where the legacy .txt format only supports one node per protocol.
func RemoveByType(t NodeType) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadLocked()
	if err != nil {
		return err
	}
	out := s.Nodes[:0]
	for _, n := range s.Nodes {
		if n.Type != t {
			out = append(out, n)
		}
	}
	s.Nodes = out
	return saveLocked(s)
}

// EnsureSubscribeToken returns the subscribe token, generating one if absent.
// PR2 will consume this; PR1 just persists it on first call.
func EnsureSubscribeToken() (string, error) {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadLocked()
	if err != nil {
		return "", err
	}
	if s.Subscribe.Token != "" {
		return s.Subscribe.Token, nil
	}
	token, err := generateToken(16)
	if err != nil {
		return "", err
	}
	s.Subscribe.Token = token
	if err := saveLocked(s); err != nil {
		return "", err
	}
	return token, nil
}

// RotateToken regenerates the subscribe token, invalidating all existing URLs.
func RotateToken() (string, error) {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadLocked()
	if err != nil {
		return "", err
	}
	token, err := generateToken(16)
	if err != nil {
		return "", err
	}
	s.Subscribe.Token = token
	if err := saveLocked(s); err != nil {
		return "", err
	}
	return token, nil
}

func generateToken(nBytes int) (string, error) {
	b := make([]byte, nBytes)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("rand: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// FilePath returns the canonical store file path. Useful for tests/diagnostics.
func FilePath() string {
	return filepath.Clean(StorePath)
}
