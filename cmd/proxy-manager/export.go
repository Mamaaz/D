package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/format"
	"github.com/Mamaaz/proxy-manager/internal/store"
)

// runExport implements `proxy-manager export --format=<surge|clash|singbox|xray|json>`.
//
// Output is written to stdout. The command runs LoadOrMigrate so the first
// invocation on an old install transparently builds nodes.json from existing
// .txt configs.
func runExport(args []string) {
	formatName := "json"
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--format" && i+1 < len(args):
			formatName = args[i+1]
			i++
		case strings.HasPrefix(a, "--format="):
			formatName = strings.TrimPrefix(a, "--format=")
		case a == "-h" || a == "--help":
			fmt.Println("Usage: proxy-manager export [--format=json|surge|clash|singbox|xray]")
			return
		default:
			fmt.Fprintf(os.Stderr, "未知参数: %s\n", a)
			os.Exit(2)
		}
	}

	s, err := store.LoadOrMigrate()
	if err != nil {
		fmt.Fprintf(os.Stderr, "读取节点失败: %v\n", err)
		os.Exit(1)
	}

	// Stable order helps deterministic output for diffing/audits.
	sort.SliceStable(s.Nodes, func(i, j int) bool {
		return s.Nodes[i].ID < s.Nodes[j].ID
	})

	if err := writeFormat(os.Stdout, formatName, s); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func writeFormat(w io.Writer, name string, s *store.Store) error {
	switch name {
	case "json":
		return writeJSON(w, s)
	case "surge":
		return writeSurge(w, s)
	case "clash":
		return writeClash(w, s)
	case "singbox", "sing-box":
		return writeSingbox(w, s)
	case "xray":
		return writeXray(w, s)
	}
	return fmt.Errorf("未知格式: %s (支持: json, surge, clash, singbox, xray)", name)
}

func writeJSON(w io.Writer, s *store.Store) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(s)
}

func writeSurge(w io.Writer, s *store.Store) error {
	for _, n := range s.Nodes {
		line, err := format.ToSurge(&n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  # skip %s: %v\n", n.ID, err)
			continue
		}
		fmt.Fprintln(w, line)
	}
	return nil
}

func writeClash(w io.Writer, s *store.Store) error {
	proxies := make([]map[string]any, 0, len(s.Nodes))
	for _, n := range s.Nodes {
		entry, err := format.ToClash(&n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  # skip %s: %v\n", n.ID, err)
			continue
		}
		proxies = append(proxies, entry)
	}
	out := map[string]any{"proxies": proxies}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}

func writeSingbox(w io.Writer, s *store.Store) error {
	outbounds := make([]map[string]any, 0, len(s.Nodes)*2)
	for _, n := range s.Nodes {
		entries, err := format.ToSingbox(&n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  # skip %s: %v\n", n.ID, err)
			continue
		}
		outbounds = append(outbounds, entries...)
	}
	out := map[string]any{"outbounds": outbounds}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}

func writeXray(w io.Writer, s *store.Store) error {
	outbounds := make([]map[string]any, 0, len(s.Nodes))
	for _, n := range s.Nodes {
		if !format.NeedsBridge(&n) {
			continue
		}
		entries, err := format.ToXray(&n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  # skip %s: %v\n", n.ID, err)
			continue
		}
		outbounds = append(outbounds, entries...)
	}
	out := map[string]any{"outbounds": outbounds}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}
