package main

import (
	"bufio"
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/subscribe"
	"github.com/mdp/qrterminal/v3"
)

// runSubscribe dispatches `proxy-manager subscribe <command>`.
//
//	enable [--domain X] [--port N] [--email Y]
//	disable
//	status
//	rotate-token
//	url
//	serve [--domain X --port N --email Y]   (used by the systemd unit; not for direct human use)
func runSubscribe(args []string) {
	if len(args) == 0 {
		fmt.Println(subscribeHelp())
		os.Exit(2)
	}
	switch args[0] {
	case "enable":
		runSubscribeEnable(args[1:])
	case "disable":
		runSubscribeDisable()
	case "status":
		runSubscribeStatus()
	case "rotate-token":
		runSubscribeRotate()
	case "url":
		runSubscribeURL()
	case "serve":
		runSubscribeServe(args[1:])
	case "-h", "--help", "help":
		fmt.Println(subscribeHelp())
	default:
		fmt.Fprintf(os.Stderr, "未知子命令: %s\n\n%s\n", args[0], subscribeHelp())
		os.Exit(2)
	}
}

func subscribeHelp() string {
	return `用法: proxy-manager subscribe <command>

  enable [--domain D] [--port N] [--email E]
                 启用订阅服务 (申请 LE 证书 + 注册 systemd 服务)
                 缺省参数会交互式询问. port 默认随机 10000-65000.
  disable        停止并删除订阅服务 (保留 token, 配置可恢复)
  status         查看订阅服务状态
  url            打印当前订阅 URL (5 种格式)
  rotate-token   生成新 token, 旧 URL 立即失效
  serve ...      作为前台进程运行订阅服务 (供 systemd 调用, 一般不需要手动跑)`
}

func runSubscribeEnable(args []string) {
	domain := flagValue(args, "--domain")
	portStr := flagValue(args, "--port")
	email := flagValue(args, "--email")

	if domain == "" {
		domain = prompt("订阅域名 (例如 sub.your-domain.com): ", "")
		if domain == "" {
			fmt.Fprintln(os.Stderr, "domain 必填")
			os.Exit(1)
		}
	}
	if email == "" {
		email = prompt("ACME 注册邮箱 (用于证书过期通知, 可空): ", "")
	}
	port := 0
	if portStr != "" {
		var err error
		port, err = strconv.Atoi(portStr)
		if err != nil {
			fmt.Fprintf(os.Stderr, "port 解析失败: %v\n", err)
			os.Exit(1)
		}
	} else {
		port = randomPort()
		ans := prompt(fmt.Sprintf("订阅监听端口 [回车使用 %d]: ", port), "")
		if ans != "" {
			n, err := strconv.Atoi(ans)
			if err != nil || n <= 0 || n > 65535 {
				fmt.Fprintln(os.Stderr, "无效端口")
				os.Exit(1)
			}
			port = n
		}
	}

	urls, err := subscribe.Install(domain, port, email)
	if err != nil {
		fmt.Fprintf(os.Stderr, "启用失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Println()
	fmt.Println("订阅服务已启用，URL:")
	printURLs(urls)
	fmt.Println()
	fmt.Println("提示: 域名必须解析到本机 IP，且 80 端口需对公网可达 (ACME 验证)")
	fmt.Println("Cloudflare 用户务必关闭橙云代理 (改为灰云 DNS only)")
}

func runSubscribeDisable() {
	if err := subscribe.Uninstall(); err != nil {
		fmt.Fprintf(os.Stderr, "停用失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("订阅服务已停用 (token 保留，再次 enable 时恢复)")
}

func runSubscribeStatus() {
	state := subscribe.Status()
	fmt.Printf("systemd: %s\n", state)
	s, err := store.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "读取配置失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("domain:  %s\n", emptyDash(s.Subscribe.Domain))
	fmt.Printf("port:    %s\n", emptyDash(strconv.Itoa(s.Subscribe.Port)))
	if s.Subscribe.Token == "" {
		fmt.Println("token:   (未生成)")
	} else {
		// 截短显示，避免日志泄露完整 token
		fmt.Printf("token:   %s...%s\n", s.Subscribe.Token[:4], s.Subscribe.Token[len(s.Subscribe.Token)-4:])
	}
}

func runSubscribeURL() {
	s, err := store.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "读取配置失败: %v\n", err)
		os.Exit(1)
	}
	urls := subscribe.Urls(s)
	if urls == nil {
		fmt.Println("订阅服务未启用. 先运行: proxy-manager subscribe enable")
		os.Exit(1)
	}
	printURLs(urls)
}

func runSubscribeRotate() {
	token, err := store.RotateToken()
	if err != nil {
		fmt.Fprintf(os.Stderr, "rotate 失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("新 token: %s...%s\n", token[:4], token[len(token)-4:])
	graceDays := int(store.PreviousTokenGracePeriod.Hours()) / 24
	fmt.Printf("旧 URL 仍可用 %d 天 (grace period),之后才彻底失效 — 期间请把客户端订阅改成新 URL\n", graceDays)
	s, _ := store.Load()
	if urls := subscribe.Urls(s); urls != nil {
		fmt.Println()
		fmt.Println("新 URL:")
		printURLs(urls)
	}
}

func runSubscribeServe(args []string) {
	domain := flagValue(args, "--domain")
	portStr := flagValue(args, "--port")
	email := flagValue(args, "--email")
	if domain == "" || portStr == "" {
		// fallback to store config (for ad-hoc runs without flags)
		s, err := store.Load()
		if err != nil {
			fmt.Fprintf(os.Stderr, "无法读取 store, 必须显式提供 --domain 和 --port: %v\n", err)
			os.Exit(1)
		}
		if domain == "" {
			domain = s.Subscribe.Domain
		}
		if portStr == "" {
			portStr = strconv.Itoa(s.Subscribe.Port)
		}
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "port 解析失败: %v\n", err)
		os.Exit(1)
	}
	staging := flagPresent(args, "--staging")
	if err := subscribe.Serve(subscribe.ServeOptions{
		Domain:  domain,
		Port:    port,
		Email:   email,
		Staging: staging,
	}); err != nil {
		fmt.Fprintf(os.Stderr, "serve 退出: %v\n", err)
		os.Exit(1)
	}
}

// --- small CLI helpers ----------------------------------------------------

func flagValue(args []string, key string) string {
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == key && i+1 < len(args):
			return args[i+1]
		case strings.HasPrefix(a, key+"="):
			return strings.TrimPrefix(a, key+"=")
		}
	}
	return ""
}

func flagPresent(args []string, key string) bool {
	for _, a := range args {
		if a == key {
			return true
		}
	}
	return false
}

func prompt(msg, fallback string) string {
	fmt.Print(msg)
	rd := bufio.NewReader(os.Stdin)
	line, err := rd.ReadString('\n')
	if err != nil && line == "" {
		return fallback
	}
	s := strings.TrimSpace(line)
	if s == "" {
		return fallback
	}
	return s
}

func emptyDash(s string) string {
	if s == "" || s == "0" {
		return "-"
	}
	return s
}

func printURLs(urls map[string]string) {
	for _, k := range []string{"surge", "clash", "mihomo", "singbox", "xray", "qx", "json"} {
		if v, ok := urls[k]; ok {
			fmt.Printf("  %-8s %s\n", k+":", v)
		}
	}
	// QR for the JSON URL — that's the one Mac client and most subscription
	// readers consume. Surge can subscribe by pasting the surge URL by hand.
	if json, ok := urls["json"]; ok {
		fmt.Println()
		fmt.Println("  扫码导入 (json):")
		printQR(json)
	}
}

// printQR renders an ASCII QR for the URL using qrterminal. Compact output
// (HALFBLOCK) keeps the QR fitting in a typical 80-col terminal.
func printQR(text string) {
	cfg := qrterminal.Config{
		Level:     qrterminal.M,
		Writer:    os.Stdout,
		HalfBlocks: true,
		BlackChar: qrterminal.BLACK_BLACK,
		WhiteChar: qrterminal.WHITE_WHITE,
		BlackWhiteChar: qrterminal.BLACK_WHITE,
		WhiteBlackChar: qrterminal.WHITE_BLACK,
		QuietZone: 1,
	}
	qrterminal.GenerateWithConfig(text, cfg)
}

// randomPort returns an int in [10000, 65000] suitable as a default
// subscription port. Avoids well-known ports and the 443 conflict zone.
func randomPort() int {
	var b [2]byte
	if _, err := rand.Read(b[:]); err != nil {
		return 12580 // deterministic fallback
	}
	n := int(binary.BigEndian.Uint16(b[:]))
	return 10000 + (n % 55001)
}
