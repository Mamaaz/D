// Package version 给所有需要 proxy-manager 版本号的代码 (cmd/main, ui 包) 一个
// 共同的真相源。CI 通过 -ldflags 注入：
//
//	go build -ldflags "-X github.com/Mamaaz/proxy-manager/internal/version.Version=v4.0.16"
package version

// Version 由 -ldflags -X 注入；本地 go build 不带 ldflag 时显示 "dev"。
var Version = "dev"
