package install

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// Kernel 描述一个二进制内核：用什么协议、装在哪、版本怎么拿、怎么升级。
// "kernel" 这层是新增的，原来的 protocol-level Update* 函数继续用——
// kernel.Upgrade 不重写它们，只编排顺序 + 共享 binary 的协议复用。
type Kernel struct {
	Name        string   // 显示名: "xray-core", "sing-box"
	BinaryPath  string
	Repo        string   // GitHub "owner/repo"，Releases API 拉 latest
	DefaultVer  string   // 拉不到 latest 时的 fallback
	UsedBy      []string // 该内核被哪些协议使用 (展示用)
	Services    []string // 用此 binary 的 systemd unit 名 (升级时统一 stop/start)
	VersionCmd  []string // 用什么命令问 binary 自己的版本 (空 = 不能问)
	VersionGrep string   // version 输出里抓哪行的"第二列"作为 ver 字符串

	// download 函数指针，避免在外面再写一遍升级流程
	download func(version, arch string) error
}

// ListKernels 扫描已安装协议，返回当前部署的内核清单。空数组 = 啥协议都没装。
func ListKernels() []Kernel {
	s, _ := store.LoadOrMigrate()
	if s == nil {
		s = &store.Store{}
	}

	hasReality, hasH2, hasAnyTLS, hasAnyTLSReality := false, false, false, false
	for _, n := range s.Nodes {
		switch n.Type {
		case store.TypeVLESSReality:
			hasReality = true
		case store.TypeHysteria2:
			hasH2 = true
		case store.TypeAnyTLS:
			hasAnyTLS = true
		case store.TypeAnyTLSReality:
			hasAnyTLSReality = true
		}
	}

	var out []Kernel
	if hasReality {
		out = append(out, Kernel{
			Name: "xray-core", BinaryPath: XrayBinaryPath,
			Repo: "XTLS/Xray-core", DefaultVer: DefaultXrayVersion,
			UsedBy:      []string{"VLESS Reality"},
			Services:    []string{RealityServiceName},
			VersionCmd:  []string{"version"},
			VersionGrep: "Xray ",
			download:    downloadXray,
		})
	}
	// sing-box 是多协议共享内核，UsedBy / Services 累加
	if hasH2 || hasAnyTLS || hasAnyTLSReality {
		k := Kernel{
			Name: "sing-box", BinaryPath: SingboxBinaryPath,
			Repo: "SagerNet/sing-box", DefaultVer: utils.DefaultSingboxVersion,
			VersionCmd:  []string{"version"},
			VersionGrep: "sing-box version ",
			download:    downloadSingbox,
		}
		if hasH2 {
			k.UsedBy = append(k.UsedBy, "Hysteria2")
			k.Services = append(k.Services, "hysteria2")
		}
		if hasAnyTLS {
			k.UsedBy = append(k.UsedBy, "AnyTLS")
			k.Services = append(k.Services, "anytls")
		}
		if hasAnyTLSReality {
			k.UsedBy = append(k.UsedBy, "AnyTLS + Reality")
			k.Services = append(k.Services, "anytls-reality")
		}
		out = append(out, k)
	}
	return out
}

// CurrentVersion 问 binary 自己的版本；问不出来 fallback 到从 .txt 读。
// 返回空串表示不知道。
func (k Kernel) CurrentVersion() string {
	if !utils.FileExists(k.BinaryPath) {
		return ""
	}
	if len(k.VersionCmd) > 0 {
		out, err := exec.Command(k.BinaryPath, k.VersionCmd...).Output()
		if err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				if k.VersionGrep == "" || strings.Contains(line, k.VersionGrep) {
					// 行里包含 "Xray 1.2.3 ..." 这种，抽数字+点的子串
					return extractVersionToken(line)
				}
			}
		}
	}
	// fallback：从协议 txt config 读版本号
	switch k.Name {
	case "xray-core":
		if kv, err := ParseConfigFile(RealityProxyConfigPath); err == nil {
			return kv["SINGBOX_VERSION"] // 字段名兼容旧 schema
		}
	case "sing-box":
		for _, p := range []string{Hysteria2ProxyConfigPath, AnyTLSProxyConfigPath, AnyTLSRealityProxyConfigPath} {
			if kv, err := ParseConfigFile(p); err == nil && kv["SINGBOX_VERSION"] != "" {
				return kv["SINGBOX_VERSION"]
			}
		}
	}
	return ""
}

// LatestVersion 问 GitHub Releases。失败回退 DefaultVer。
func (k Kernel) LatestVersion() string {
	if k.Repo == "" {
		return k.DefaultVer
	}
	return utils.GetLatestVersion(k.Repo, k.DefaultVer)
}

// Upgrade 升级一个内核：stop services → backup binary → download new →
// start services。失败时 rollback binary。
func (k Kernel) Upgrade() error {
	if k.download == nil {
		return fmt.Errorf("%s 内核暂不支持自动升级，请走 install 重装相关协议", k.Name)
	}
	arch, err := utils.DetectArch()
	if err != nil {
		return err
	}
	latest := k.LatestVersion()

	utils.PrintInfo("正在升级 %s → %s ...", k.Name, latest)

	// 1) 停所有用此 binary 的 services
	for _, svc := range k.Services {
		_ = utils.ServiceStop(svc)
	}

	// 2) backup 现有 binary
	bak := k.BinaryPath + ".bak"
	if utils.FileExists(k.BinaryPath) {
		_ = os.Rename(k.BinaryPath, bak)
	}
	_ = os.Remove(k.BinaryPath)

	// 3) 下载新
	if err := k.download(latest, arch); err != nil {
		// 回滚
		_ = os.Rename(bak, k.BinaryPath)
		for _, svc := range k.Services {
			_ = utils.ServiceStart(svc)
		}
		return fmt.Errorf("下载 %s 失败: %w (已回滚)", k.Name, err)
	}

	// 4) 重启 services
	for _, svc := range k.Services {
		if err := utils.ServiceStart(svc); err != nil {
			return fmt.Errorf("启动 %s 失败: %w", svc, err)
		}
	}

	// 5) 升级版本号到协议 txt config
	updateVersionInTxt(k.Name, latest)

	// 6) backup 删
	_ = os.Remove(bak)
	return nil
}

func updateVersionInTxt(kernelName, latest string) {
	switch kernelName {
	case "xray-core":
		if kv, err := ParseConfigFile(RealityProxyConfigPath); err == nil {
			kv["SINGBOX_VERSION"] = latest
			_ = SaveConfigFile(RealityProxyConfigPath, kv)
		}
	case "sing-box":
		for _, p := range []string{Hysteria2ProxyConfigPath, AnyTLSProxyConfigPath, AnyTLSRealityProxyConfigPath} {
			if kv, err := ParseConfigFile(p); err == nil && kv["SINGBOX_VERSION"] != "" {
				kv["SINGBOX_VERSION"] = latest
				_ = SaveConfigFile(p, kv)
			}
		}
	}
}

// extractVersionToken 从一行像 "Xray 1.2.3 (Xray-core, mit) ..." 里
// 找第一个 "数字.数字.数字" 形状的 token。简单 + 容错好。
func extractVersionToken(line string) string {
	for _, tok := range strings.Fields(line) {
		dots := 0
		ok := true
		for _, c := range tok {
			if c == '.' {
				dots++
			} else if !(c >= '0' && c <= '9') {
				ok = false
				break
			}
		}
		if ok && dots >= 2 {
			return tok
		}
	}
	return ""
}
