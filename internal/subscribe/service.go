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

// ServiceUser 是 subscribe 守护进程运行的非 root 系统用户。从 v4.0.6 起所有
// 协议服务都跑在专属用户下，subscribe 也跟上。CAP_NET_BIND_SERVICE 让它能
// bind :80 / :443 而不需要 root。
const ServiceUser = "proxy-manager"

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
	if err := prepareRuntimeDirs(); err != nil {
		return nil, err
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
User=%s
ExecStart=%s %s
Restart=always
RestartSec=10s
LimitNOFILE=65535

# 非 root 用户绑定 :80 (ACME http-01) 靠 CAP_NET_BIND_SERVICE。
# autocert 写入 /var/lib/proxy-manager/autocert，nodes.json 在
# /etc/proxy-manager。两个目录的 owner 在 prepareRuntimeDirs 里 chown 过。
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/proxy-manager /etc/proxy-manager

[Install]
WantedBy=multi-user.target
`, ServiceUser, binary, strings.Join(args, " "))

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

// prepareRuntimeDirs 确保 ServiceUser 存在 + autocert 缓存目录 + store 目录
// 都建好且 owner 正确。失败抛错让上层 alert，不要静默继续——非 root 服务
// 启动时若目录无写权限会立刻挂。
//
// 幂等：CreateSystemUser 跳过已存在用户；MkdirAll 不报已有；chown 总是覆盖。
func prepareRuntimeDirs() error {
	if err := utils.CreateSystemUser(ServiceUser); err != nil {
		return fmt.Errorf("创建系统用户 %s 失败: %w", ServiceUser, err)
	}
	for _, p := range []string{"/var/lib/proxy-manager", CertCacheDir, "/etc/proxy-manager"} {
		if err := os.MkdirAll(p, 0750); err != nil {
			return fmt.Errorf("创建目录 %s 失败: %w", p, err)
		}
	}
	// chown -R 让 ServiceUser 能读写 nodes.json + autocert 缓存。
	for _, p := range []string{"/var/lib/proxy-manager", "/etc/proxy-manager"} {
		if out, err := exec.Command("chown", "-R", ServiceUser+":"+ServiceUser, p).CombinedOutput(); err != nil {
			return fmt.Errorf("chown %s 失败: %v (%s)", p, err, strings.TrimSpace(string(out)))
		}
	}
	// CertCacheDir 由 autocert 自动建子目录但首次写需要权限。它已经在上面
	// chown 链里 (它是 /var/lib/proxy-manager 的子目录)。
	return nil
}

// Rebuild 重写 unit + chown 目录 + 重启服务，但不动 store 里的 domain/port。
// 给 service-rebuild 子命令用：升级二进制后让旧部署也拿到新 unit 模板
// (e.g. v4.0.6 把 User=root 降到 User=proxy-manager)。
//
// 区别于 Install：不验证 port 可用 (我们自己正在用)、不询问 email
// (沿用 store 里没有 email 的事实——initial install 时给过的不存于此)。
func Rebuild() error {
	s, err := store.LoadOrMigrate()
	if err != nil {
		return err
	}
	if s.Subscribe.Domain == "" || s.Subscribe.Port == 0 {
		return nil // 未启用，无需重建
	}

	binary, err := os.Executable()
	if err != nil {
		return fmt.Errorf("找不到当前可执行文件路径: %w", err)
	}

	if err := prepareRuntimeDirs(); err != nil {
		return err
	}

	args := []string{"subscribe", "serve", "--domain", s.Subscribe.Domain, "--port", strconv.Itoa(s.Subscribe.Port)}

	unit := fmt.Sprintf(`[Unit]
Description=Proxy Manager subscription endpoint
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=%s
ExecStart=%s %s
Restart=always
RestartSec=10s
LimitNOFILE=65535

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/proxy-manager /etc/proxy-manager

[Install]
WantedBy=multi-user.target
`, ServiceUser, binary, strings.Join(args, " "))

	if err := os.WriteFile(SystemdUnitPath, []byte(unit), 0644); err != nil {
		return fmt.Errorf("写入 systemd 单元失败: %w", err)
	}
	if err := utils.DaemonReload(); err != nil {
		return err
	}
	// Restart 而不是 reload — User= 改动只在重启时生效
	if err := utils.ServiceRestart(ServiceName); err != nil {
		return fmt.Errorf("重启服务失败: %w", err)
	}
	return nil
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
