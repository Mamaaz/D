package ui

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/services"
	"github.com/Mamaaz/proxy-manager/internal/utils"
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
	MenuItem{title: "1. 安装 Snell + Shadow-TLS", description: "Surge 专用协议", action: "install_snell"},
	MenuItem{title: "2. 安装 SS-2022 + Shadow-TLS", description: "通用 Shadowsocks", action: "install_singbox"},
	MenuItem{title: "3. 安装 VLESS Reality", description: "抗检测协议", action: "install_reality"},
	MenuItem{title: "4. 安装 Hysteria2", description: "高速 QUIC 协议", action: "install_hysteria2"},
	MenuItem{title: "5. 安装 AnyTLS", description: "抗 TLS 指纹检测", action: "install_anytls"},
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
	l.Title = "Proxy Manager v4.0"
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
	b.WriteString(titleStyle.Render("║       Proxy Manager v4.0 - 多协议代理管理                  ║"))
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
	case "install_snell":
		doInstallSnell()
	case "install_singbox":
		doInstallSingbox()
	case "install_reality":
		doInstallReality()
	case "install_hysteria2":
		doInstallHysteria2()
	case "install_anytls":
		doInstallAnyTLS()
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
	default:
		utils.PrintError("未知操作: %s", action)
	}
}

// =========================================
// 安装操作
// =========================================

func doInstallSnell() {
	_, err := install.InstallSnell()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	}
	waitForEnter()
}

func doInstallSingbox() {
	_, err := install.InstallSingbox()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	}
	waitForEnter()
}

func doInstallReality() {
	_, err := install.InstallReality()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	}
	waitForEnter()
}

func doInstallHysteria2() {
	_, err := install.InstallHysteria2()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	}
	waitForEnter()
}

func doInstallAnyTLS() {
	_, err := install.InstallAnyTLS()
	if err != nil {
		utils.PrintError("安装失败: %v", err)
	}
	waitForEnter()
}

// =========================================
// 查看配置
// =========================================

func doViewConfig() {
	options := []string{
		"Snell + Shadow-TLS",
		"Sing-box (SS-2022)",
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"返回",
	}

	choice := utils.PromptSelect("选择要查看的配置:", options)
	switch choice {
	case 1:
		install.ViewSnellConfig()
	case 2:
		install.ViewSingboxConfig()
	case 3:
		install.ViewRealityConfig()
	case 4:
		install.ViewHysteria2Config()
	case 5:
		install.ViewAnyTLSConfig()
	}
	waitForEnter()
}

// =========================================
// 查看日志
// =========================================

func doViewLogs() {
	options := []string{
		"Snell",
		"Shadow-TLS",
		"Sing-box",
		"Reality",
		"Hysteria2",
		"AnyTLS",
		"返回",
	}

	choice := utils.PromptSelect("选择要查看的日志:", options)
	var service string
	switch choice {
	case 1:
		service = "snell"
	case 2:
		service = "shadow-tls"
	case 3:
		service = "sing-box"
	case 4:
		service = "sing-box-reality"
	case 5:
		service = "hysteria2"
	case 6:
		service = "anytls"
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
		"Snell + Shadow-TLS",
		"Sing-box (SS-2022)",
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"返回",
	}

	choice := utils.PromptSelect("选择要更新的服务:", options)
	var err error
	switch choice {
	case 1:
		err = install.UpdateSnell()
	case 2:
		err = install.UpdateSingbox()
	case 3:
		err = install.UpdateReality()
	case 4:
		err = install.UpdateHysteria2()
	case 5:
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
		"Snell + Shadow-TLS",
		"Sing-box (SS-2022)",
		"VLESS Reality",
		"Hysteria2",
		"AnyTLS",
		"返回",
	}

	choice := utils.PromptSelect("选择要卸载的服务:", options)

	// 确认卸载
	if choice >= 1 && choice <= 5 {
		if !utils.PromptConfirm("确认卸载？") {
			return
		}
	}

	switch choice {
	case 1:
		install.UninstallSnell()
	case 2:
		install.UninstallSingbox()
	case 3:
		install.UninstallReality()
	case 4:
		install.UninstallHysteria2()
	case 5:
		install.UninstallAnyTLS()
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

	installURL := "https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh"
	cmd := exec.Command("bash", "-c", fmt.Sprintf("curl -sL '%s' | bash -s update", installURL))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	cmd.Run()
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
	fmt.Printf("%sbash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh)%s\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println()

	os.Exit(0)
}

// =========================================
// 辅助函数
// =========================================

func waitForEnter() {
	fmt.Print("\n按回车键继续...")
	fmt.Scanln()
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

		var choice int
		fmt.Print("请选择 [0-13]: ")
		fmt.Scanln(&choice)

		switch choice {
		case 1:
			doInstallSnell()
		case 2:
			doInstallSingbox()
		case 3:
			doInstallReality()
		case 4:
			doInstallHysteria2()
		case 5:
			doInstallAnyTLS()
		case 6:
			doViewConfig()
		case 7:
			doViewLogs()
		case 8:
			doUpdateService()
		case 9:
			doUninstallService()
		case 10:
			doRenewCert()
		case 11:
			doViewCert()
		case 12:
			doUpdatePM()
		case 13:
			doUninstallPM()
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
	fmt.Printf("%s║%s       %sProxy Manager v4.0%s - %s多协议代理管理%s          %s║%s\n",
		utils.ColorCyan, utils.ColorReset,
		utils.ColorGreen, utils.ColorReset,
		utils.ColorYellow, utils.ColorReset,
		utils.ColorCyan, utils.ColorReset)
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
	fmt.Printf("%s│%s    %s1.%s 安装 Snell + Shadow-TLS                              %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s2.%s 安装 Sing-box (SS-2022 + Shadow-TLS)                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s3.%s 安装 VLESS Reality                                   %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s4.%s 安装 Hysteria2 (Let's Encrypt)                       %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s5.%s 安装 AnyTLS (Let's Encrypt)                          %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s管理服务%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s6.%s 查看服务配置                                         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s7.%s 查看服务日志                                         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s8.%s 更新服务                                             %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s9.%s 卸载服务                                             %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s证书管理%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s10.%s 续签证书 (Hysteria2/AnyTLS)                         %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s11.%s 查看证书状态                                        %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s  %s系统管理%s                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorYellow, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s12.%s 更新 Proxy Manager                                  %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s13.%s 完全卸载 Proxy Manager                              %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s├─────────────────────────────────────────────────────────────┤%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s│%s    %s0.%s 退出                                                 %s│%s\n",
		utils.ColorGreen, utils.ColorReset, utils.ColorCyan, utils.ColorReset, utils.ColorGreen, utils.ColorReset)
	fmt.Printf("%s└─────────────────────────────────────────────────────────────┘%s\n", utils.ColorGreen, utils.ColorReset)
	fmt.Println()
}
