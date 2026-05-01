package subscribe

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// ServiceName is the systemd unit name for the subscription daemon. Kept
// distinct from the protocol services so subscribe can be restarted without
// touching live proxy traffic.
const ServiceName = "proxy-manager-subscribe"

// SystemdUnitPath is where we drop the unit file. /lib/systemd/system aligns
// with the rest of this project's services (see install/common.go).
const SystemdUnitPath = "/lib/systemd/system/proxy-manager-subscribe.service"

// Install writes the subscribe block to nodes.json and creates+starts the
// systemd service. Returns the public subscription URLs for the caller to
// print.
func Install(domain string, port int, email string) (urls map[string]string, err error) {
	if domain == "" {
		return nil, fmt.Errorf("domain 不能为空")
	}
	if port <= 0 || port > 65535 {
		return nil, fmt.Errorf("port 必须在 1-65535")
	}

	if err := CheckPortAvailable(port); err != nil {
		return nil, fmt.Errorf("端口 %d 不可用: %w", port, err)
	}
	if err := CheckPortAvailable(80); err != nil {
		return nil, fmt.Errorf("端口 80 不可用 (ACME http-01 需要): %w", err)
	}

	s, err := store.LoadOrMigrate()
	if err != nil {
		return nil, err
	}
	if s.Subscribe.Token == "" {
		token, err := store.EnsureSubscribeToken()
		if err != nil {
			return nil, err
		}
		s.Subscribe.Token = token
	}
	s.Subscribe.Domain = domain
	s.Subscribe.Port = port
	if err := store.Save(s); err != nil {
		return nil, err
	}

	binary, err := os.Executable()
	if err != nil {
		return nil, fmt.Errorf("找不到当前可执行文件路径: %w", err)
	}

	// systemd 的 ReadWritePaths 要求路径在服务启动前已存在，否则
	// namespace 挂载阶段就会 fail (status=226/NAMESPACE)。autocert
	// 自己会按需建子目录，但这里得先把根路径创出来。
	if err := os.MkdirAll(CertCacheDir, 0700); err != nil {
		return nil, fmt.Errorf("创建 autocert 缓存目录失败: %w", err)
	}
	args := []string{"subscribe", "serve", "--domain", domain, "--port", strconv.Itoa(port)}
	if email != "" {
		args = append(args, "--email", email)
	}

	unit := fmt.Sprintf(`[Unit]
Description=Proxy Manager subscription endpoint
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=%s %s
Restart=always
RestartSec=10s
LimitNOFILE=65535

# Bind low ports without full root in the future; for now run as root because
# autocert wants to bind :80 and write to /var/lib/proxy-manager/autocert.
NoNewPrivileges=false
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/proxy-manager /etc/proxy-manager

[Install]
WantedBy=multi-user.target
`, binary, strings.Join(args, " "))

	if err := os.WriteFile(SystemdUnitPath, []byte(unit), 0644); err != nil {
		return nil, fmt.Errorf("写入 systemd 单元失败: %w", err)
	}
	if err := utils.DaemonReload(); err != nil {
		return nil, err
	}
	if err := utils.ServiceEnable(ServiceName); err != nil {
		return nil, fmt.Errorf("enable 服务失败: %w", err)
	}
	if err := utils.ServiceStart(ServiceName); err != nil {
		return nil, fmt.Errorf("启动服务失败: %w", err)
	}
	if !utils.VerifyServiceStarted(ServiceName, 15) {
		return nil, fmt.Errorf("服务启动验证失败 (检查 journalctl -u %s)", ServiceName)
	}

	return Urls(s), nil
}

// Uninstall stops + disables the service and removes the unit file. The
// subscribe block in nodes.json is preserved so re-enabling reuses the same
// token; rotate explicitly if you want a fresh one.
func Uninstall() error {
	_ = utils.ServiceStop(ServiceName)
	_ = utils.ServiceDisable(ServiceName)
	if err := os.Remove(SystemdUnitPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	return utils.DaemonReload()
}

// Status reports whether the unit is active. Returns the systemctl is-active
// output verbatim so users can see "active" / "inactive" / "failed".
func Status() string {
	out, _ := exec.Command("systemctl", "is-active", ServiceName).Output()
	return strings.TrimSpace(string(out))
}

// Urls renders the four subscription URLs from the current subscribe config.
// Empty map if subscribe is not configured.
func Urls(s *store.Store) map[string]string {
	if s.Subscribe.Token == "" || s.Subscribe.Domain == "" {
		return nil
	}
	base := fmt.Sprintf("https://%s", s.Subscribe.Domain)
	if s.Subscribe.Port != 0 && s.Subscribe.Port != 443 {
		base = fmt.Sprintf("https://%s:%d", s.Subscribe.Domain, s.Subscribe.Port)
	}
	out := map[string]string{}
	for _, f := range []string{"surge", "clash", "singbox", "xray", "json"} {
		out[f] = fmt.Sprintf("%s/s/%s/%s", base, f, s.Subscribe.Token)
	}
	return out
}
