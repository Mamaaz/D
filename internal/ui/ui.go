package ui

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/services"
	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
	"github.com/Mamaaz/proxy-manager/internal/version"
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Styles
var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("39")).
			MarginLeft(2)

	statusStyle = lipgloss.NewStyle().
			MarginLeft(2).
			MarginBottom(1)

	helpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241")).
			MarginLeft(2)
)

// MenuItem 菜单项
type MenuItem struct {
	title       string
	description string
	action      string
}

func (m MenuItem) Title() string       { return m.title }
func (m MenuItem) Description() string { return m.description }
func (m MenuItem) FilterValue() string { return m.title }

// Model TUI 模型
type Model struct {
	list     list.Model
	status   map[string]services.ServiceStatus
	quitting bool
	width    int
	height   int
}

// 菜单项列表
var menuItems = []list.Item{
	MenuItem{title: "1. 安装 VLESS Reality", description: "抗检测，xray 内核", action: "install_reality"},
	MenuItem{title: "2. 安装 Hysteria2", description: "高速 QUIC 协议", action: "install_hysteria2"},
	MenuItem{title: "3. 安装 AnyTLS", description: "Surge 原生支持", action: "install_anytls"},
	MenuItem{title: "4. 安装 AnyTLS + Reality", description: "无证书，sing-box / mihomo / QX 客户端", action: "install_anytls_reality"},
	MenuItem{title: "6. 查看服务配置", description: "显示已安装服务配置", action: "view_config"},
	MenuItem{title: "7. 查看服务日志", description: "显示服务运行日志", action: "view_logs"},
	MenuItem{title: "8. 更新服务", description: "更新已安装服务", action: "update_service"},
	MenuItem{title: "9. 卸载服务", description: "卸载指定服务", action: "uninstall_service"},
	MenuItem{title: "10. 续签证书", description: "续签 Let's Encrypt 证书", action: "renew_cert"},
	MenuItem{title: "11. 查看证书状态", description: "显示证书信息", action: "view_cert"},
	MenuItem{title: "12. 更新 Proxy Manager", description: "更新管理工具", action: "update_pm"},
	MenuItem{title: "13. 完全卸载", description: "卸载 Proxy Manager", action: "uninstall_pm"},
	MenuItem{title: "0. 退出", description: "退出程序", action: "quit"},
}

// InitialModel 初始化模型
func InitialModel() Model {
	delegate := list.NewDefaultDelegate()
	delegate.ShowDescription = true

	l := list.New(menuItems, delegate, 60, 20)
	l.Title = "Proxy Manager v" + version.Version
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)

	return Model{
		list:   l,
		status: services.GetAllStatus(),
	}
}

// Init 初始化
func (m Model) Init() tea.Cmd {
	return nil
}

// Update 更新
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.list.SetSize(msg.Width-4, msg.Height-10)
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		case "enter":
			if item, ok := m.list.SelectedItem().(MenuItem); ok {
				switch item.action {
				case "quit":
					m.quitting = true
					return m, tea.Quit
				default:
					// 在 TUI 模式下，退出 TUI 并执行操作
					action := item.action
					return m, tea.Sequence(
						tea.ExitAltScreen,
						func() tea.Msg {
							ExecuteAction(action)
							return nil
						},
						tea.Quit,
					)
				}
			}
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// execAction 执行菜单操作 (已废弃，保留兼容)
func execAction(action string) *exec.Cmd {
	// 创建一个子命令来执行操作
	return exec.Command(os.Args[0], "--action", action)
}

// View 渲染视图
func (m Model) View() string {
	if m.quitting {
		return "正在退出...\n"
	}

	var b strings.Builder

	// 标题
	b.WriteString(titleStyle.Render("╔════════════════════════════════════════════════════════════╗"))
	b.WriteString("\n")
	b.WriteString(titleStyle.Render("║       Proxy Manager v" + version.Version + " - 多协议代理管理"))
	b.WriteString("\n")
	b.WriteString(titleStyle.Render("╚════════════════════════════════════════════════════════════╝"))
	b.WriteString("\n\n")

	// 服务状态
	statusLines := m.renderStatus()
	b.WriteString(statusStyle.Render(statusLines))
	b.WriteString("\n")

	// 菜单列表
	b.WriteString(m.list.View())
	b.WriteString("\n")

	// 帮助信息
	b.WriteString(helpStyle.Render("↑/↓: 选择  Enter: 确认  q: 退出"))

	return b.String()
}

// renderStatus 渲染服务状态
func (m Model) renderStatus() string {
	var b strings.Builder

	b.WriteString("┌─────────────────────────────────────────────────────────────┐\n")
	b.WriteString("│  服务状态                                                   │\n")
	b.WriteString("├─────────────────────────────────────────────────────────────┤\n")

	for _, svc := range services.Services {
		status := m.status[svc.Name]
		statusStr := services.StatusString(status)
		b.WriteString(fmt.Sprintf("│  %-20s: %-10s                         │\n", svc.DisplayName, statusStr))
	}

	b.WriteString("└─────────────────────────────────────────────────────────────┘")

	return b.String()
}

// Run 运行 TUI
func Run() error {
	p := tea.NewProgram(InitialModel(), tea.WithAltScreen())
	_, err := p.Run()
	return err
}

// =========================================
// 直接执行模式 (非 TUI)
// =========================================

// ExecuteAction 执行指定操作
func ExecuteAction(action string) {
	switch action {
	case "install_reality":
		doInstallReality()
	case "install_hysteria2":
		doInstallHysteria2()
	case "install_anytls":
		doInstallAnyTLS()
	case "install_anytls_reality":
		doInstallAnyTLSReality()
	case "view_config":
		doViewConfig()
	case "view_logs":
		doViewLogs()
	case "update_service":
		doUpdateService()
	case "uninstall_service":
		doUninstallService()
	case "renew_cert":
		doRenewCert()
	case "view_cert":
		doViewCert()
	case "update_pm":
		doUpdatePM()
	case "uninstall_pm":
		doUninstallPM()
	case "rank_sni":
		doRankSNI()
	default:
		utils.PrintError("未知操作: %s", action)
	}
}

// =========================================
// 安装操作
// =========================================

func doInstallReality() {
	_, err := install.InstallReality()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	} else {
		printNodeShareURL(store.TypeVLESSReality)
		printSubscribeURLs()
	}
	waitForEnter()
}

func doInstallHysteria2() {
	_, err := install.InstallHysteria2()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	} else {
		printSubscribeURLs()
	}
	waitForEnter()
}

func doInstallAnyTLS() {
	_, err := install.InstallAnyTLS()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	} else {
		printSubscribeURLs()
	}
	waitForEnter()
}

func doInstallAnyTLSReality() {
	_, err := install.InstallAnyTLSReality()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	} else {
		printSubscribeURLs()
	}
	waitForEnter()
}


// =========================================
// 查看配置
// =========================================

func doViewConfig() {
	options := []string{
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"AnyTLS + Reality",
		"返回",
	}

	choice := utils.PromptSelect("选择要查看的配置:", options)
	switch choice {
	case 1:
		install.ViewRealityConfig()
	case 2:
		install.ViewHysteria2Config()
	case 3:
		install.ViewAnyTLSConfig()
	case 4:
		install.ViewAnyTLSRealityConfig()
	}
	waitForEnter()
}

// =========================================
// 查看日志
// =========================================

func doViewLogs() {
	options := []string{
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"AnyTLS + Reality",
		"返回",
	}

	choice := utils.PromptSelect("选择要查看的日志:", options)
	var service string
	switch choice {
	case 1:
		service = "xray-reality"
	case 2:
		service = "hysteria2"
	case 3:
		service = "anytls"
	case 4:
		service = "anytls-reality"
	default:
		return
	}

	cmd := exec.Command("journalctl", "-u", service, "-n", "50", "--no-pager")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
	waitForEnter()
}

// =========================================
// 更新服务
// =========================================

func doUpdateService() {
	options := []string{
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"AnyTLS + Reality",
		"返回",
	}

	choice := utils.PromptSelect("选择要更新的服务:", options)
	var err error
	switch choice {
	case 1:
		err = install.UpdateReality()
	case 2:
		err = install.UpdateHysteria2()
	case 3:
		err = install.UpdateAnyTLS()
	case 4:
		// AnyTLS+Reality 用 sing-box，复用 UpdateAnyTLS 路径升级 sing-box binary。
		// 实际 reality 配置不需重签证，service-rebuild 即可让新 binary 生效。
		err = install.UpdateAnyTLS()
	}
	if err != nil {
		utils.PrintError("更新失败: %v", err)
	}
	waitForEnter()
}

// =========================================
// 卸载服务
// =========================================

func doUninstallService() {
	options := []string{
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"AnyTLS + Reality",
		"返回",
	}

	choice := utils.PromptSelect("选择要卸载的服务:", options)

	// 确认卸载
	if choice >= 1 && choice <= 4 {
		if !utils.PromptConfirm("确认卸载？") {
			return
		}
	}

	switch choice {
	case 1:
		install.UninstallReality()
	case 2:
		install.UninstallHysteria2()
	case 3:
		install.UninstallAnyTLS()
	case 4:
		install.UninstallAnyTLSReality()
	}
	waitForEnter()
}

// =========================================
// 证书管理
// =========================================

func doRenewCert() {
	options := []string{
		"Hysteria2 证书",
		"AnyTLS 证书",
		"返回",
	}

	choice := utils.PromptSelect("选择要续签的证书:", options)
	switch choice {
	case 1:
		utils.PrintInfo("重启 Hysteria2 将自动续签证书...")
		utils.ServiceRestart("hysteria2")
		utils.PrintSuccess("证书续签请求已发送")
	case 2:
		utils.PrintInfo("重启 AnyTLS 将自动续签证书...")
		utils.ServiceRestart("anytls")
		utils.PrintSuccess("证书续签请求已发送")
	}
	waitForEnter()
}

func doViewCert() {
	fmt.Println()
	fmt.Printf("%s=========================================%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s   证书状态%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s=========================================%s\n", utils.ColorCyan, utils.ColorReset)

	// Hysteria2 证书
	if install.IsHysteria2Installed() {
		fmt.Printf("\n%sHysteria2:%s 使用 ACME 自动管理证书\n", utils.ColorCyan, utils.ColorReset)
	}

	// AnyTLS 证书
	if install.IsAnyTLSInstalled() {
		fmt.Printf("\n%sAnyTLS:%s 使用 ACME 自动管理证书\n", utils.ColorCyan, utils.ColorReset)
	}

	if !install.IsHysteria2Installed() && !install.IsAnyTLSInstalled() {
		utils.PrintWarn("没有使用证书的服务")
	}

	waitForEnter()
}

// =========================================
// Proxy Manager 管理
// =========================================

func doUpdatePM() {
	utils.PrintInfo("正在更新 Proxy Manager...")

	// 委托给本进程的 `proxy-manager update` 子命令（cmd/proxy-manager/main.go
	// doUpdate）。两条路径以前各写一份 `curl ... | bash -s update`，导致
	// v4.0.28 PR #41 只修了 CLI 那条，菜单这条还卡 stdin EOF。更早还混了
	// 错的 monorepo 旧 URL (P/proxy_manager_go/scripts/install.sh) 直接 404，
	// 把 GitHub 的 "404: Not Found" 响应体喂给 bash → "bash: line 1: 404::
	// command not found"。统一用 os.Executable() 自调，规避两个坑。
	self, err := os.Executable()
	if err != nil {
		utils.PrintError("定位自身二进制失败: %v", err)
		return
	}
	cmd := exec.Command(self, "update")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		utils.PrintError("更新失败: %v", err)
		return
	}

	// 升级成功:disk 上 binary 已是新版,但本进程 (TUI menu loop) 还是更新前
	// fork 出来的旧进程,version.Version 已编进二进制 / generateShortID 等
	// 函数指针都指向旧实现。如果用户接着在同一个菜单 session 里重装协议
	// (v4.0.31 修 generateShortID 后用户碰到的真实场景),走的还是旧逻辑,
	// 又会复现刚才修掉的 bug,但用户感知不到 — 标题甚至都还显示旧版本。
	//
	// syscall.Exec 把当前 PID 替换成 disk 上的新 binary,菜单立刻按新代码
	// 重启:版本号、bug 修复、新协议入口都生效。binPath 用 install.sh 的
	// 固定 INSTALL_DIR 路径,install.sh 跑 service-rebuild 已经验证过新
	// binary 可执行。
	binPath := "/usr/local/bin/proxy-manager"
	utils.PrintInfo("加载新版本 ...")
	if err := syscall.Exec(binPath, []string{binPath}, os.Environ()); err != nil {
		utils.PrintWarn("自动重启失败: %v;请手动 exit 后重新运行 proxy-manager", err)
		os.Exit(0)
	}
}

func doUninstallPM() {
	fmt.Println()
	fmt.Printf("%s═══════════════════════════════════════%s\n", utils.ColorRed, utils.ColorReset)
	fmt.Printf("%s   警告: 完全卸载 Proxy Manager%s\n", utils.ColorRed, utils.ColorReset)
	fmt.Printf("%s═══════════════════════════════════════%s\n", utils.ColorRed, utils.ColorReset)
	fmt.Println()
	fmt.Printf("%s这将删除:%s\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println("  - Proxy Manager 管理工具")
	fmt.Printf("%s以下不会被删除:%s\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println("  - 已安装的代理服务")
	fmt.Println()

	if !utils.PromptConfirm("确认卸载？输入 y 继续") {
		utils.PrintSuccess("已取消")
		return
	}

	// 删除文件
	os.Remove("/usr/local/bin/proxy-manager")
	os.RemoveAll("/etc/proxy-manager")

	// 删除健康检查
	utils.ServiceStop("proxy-health.timer")
	utils.ServiceDisable("proxy-health.timer")
	os.Remove("/etc/systemd/system/proxy-health.service")
	os.Remove("/etc/systemd/system/proxy-health.timer")
	utils.DaemonReload()

	utils.PrintSuccess("Proxy Manager 已卸载")
	fmt.Println()
	fmt.Printf("%s重新安装:%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%sbash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)%s\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println()

	os.Exit(0)
}

// =========================================
// 辅助函数
// =========================================

func waitForEnter() {
	fmt.Print("\n按回车键继续...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}

// =========================================
// 简易菜单模式 (不使用 Bubbletea)
// =========================================

// RunSimpleMenu 运行简易菜单模式
func RunSimpleMenu() {
	for {
		showHeader()
		showStatus()
		showMenu()

		choice := utils.PromptInt("请选择", 0, 0, 15)

		switch choice {
		case 1:
			doInstallReality()
		case 2:
			doInstallHysteria2()
		case 3:
			doInstallAnyTLS()
		case 4:
			doInstallAnyTLSReality()
		case 5:
			doViewConfig()
		case 6:
			doViewLogs()
		case 7:
			doUpdateService()
		case 8:
			doUninstallService()
		case 9:
			doRenewCert()
		case 10:
			doViewCert()
		case 11:
			doUpdatePM()
		case 12:
			doUninstallPM()
		case 13:
			doRankSNI()
		case 14:
			doSubscribeMenu()
		case 15:
			doKernelUpgradeAll()
		case 0:
			fmt.Println("再见！")
			return
		default:
			utils.PrintError("无效选择")
		}
	}
}

func showHeader() {
	// 清屏
	fmt.Print("\033[2J\033[H")

	fmt.Printf("%s╔════════════════════════════════════════════════════════════╗%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s║%s       %sProxy Manager v%s%s - %s多协议代理管理%s\n",
		utils.ColorCyan, utils.ColorReset,
		utils.ColorGreen, version.Version, utils.ColorReset,
		utils.ColorYellow, utils.ColorReset)
	fmt.Printf("%s╚════════════════════════════════════════════════════════════╝%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Println()
}

func showStatus() {
	status := services.GetAllStatus()

	fmt.Printf("%s┌─────────────────────────────────────────────────────────────┐%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s│%s  %s服务状态%s                                                 %s│%s\n",
		utils.ColorCyan, utils.ColorReset,
		utils.ColorYellow, utils.ColorReset,
		utils.ColorCyan, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorCyan, utils.ColorReset)

	for _, svc := range services.Services {
		s := status[svc.Name]
		var statusColor, statusText string
		switch s {
		case services.StatusActive:
			statusColor = utils.ColorGreen
			statusText = "运行中"
		case services.StatusInactive, services.StatusFailed:
			statusColor = utils.ColorRed
			statusText = "已停止"
		case services.StatusNotFound:
			statusColor = utils.ColorYellow
			statusText = "未安装"
		default:
			statusColor = utils.ColorYellow
			statusText = "未知"
		}
		fmt.Printf("%s│%s  %-20s: %s%-10s%s                       %s│%s\n",
			utils.ColorCyan, utils.ColorReset,
			svc.DisplayName,
			statusColor, statusText, utils.ColorReset,
			utils.ColorCyan, utils.ColorReset)
	}

	fmt.Printf("%s└─────────────────────────────────────────────────────────────┘%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Println()
}

func showMenu() {
	fmt.Printf("%s┌─────────────────────────────────────────────────────────────┐%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s安装服务%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s1.%s 安装 VLESS Reality (xray)                            %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s2.%s 安装 Hysteria2 (LE 证书)                             %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s3.%s 安装 AnyTLS (LE 证书 — Surge 原生)                   %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s4.%s 安装 AnyTLS + Reality (无需证书)                     %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s管理服务%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s5.%s 查看服务配置                                         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s6.%s 查看服务日志                                         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s7.%s 更新服务                                             %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s8.%s 卸载服务                                             %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s证书管理%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s9.%s 续签证书 (Hysteria2/AnyTLS)                          %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s10.%s 查看证书状态                                        %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %sReality SNI 工具%s                                         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s13.%s Reality SNI 候选评估 (粘扫描结果一键挑最佳)         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s订阅 / 内核管理%s                                          %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s14.%s 订阅服务管理 (启用/停用/URL/轮换 token)              %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s15.%s 一键升级所有内核 (xray + sing-box)                  %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s系统管理%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s11.%s 更新 Proxy Manager                                  %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s12.%s 完全卸载 Proxy Manager                              %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s0.%s 退出                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s└─────────────────────────────────────────────────────────────┘%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
}
