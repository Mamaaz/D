package install

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

const (
	XrayBinaryPath = "/usr/local/bin/xray"
	// DefaultXrayVersion 是 install 时如果 GitHub API 拿不到 latest 用的兜底。
	// 升级走 utils.GetLatestVersion 拉真实最新。
	DefaultXrayVersion = "v26.3.27"
)

// downloadXray 拉取 XTLS/Xray-core release zip 解压到 /usr/local/bin/xray。
// 已存在则跳过 (升级路径走 update_service 单独处理)。
//
// 架构映射: Go arch (amd64/arm64) → Xray release name (64/arm64-v8a)。
func downloadXray(version, arch string) error {
	if utils.FileExists(XrayBinaryPath) {
		return nil
	}
	if err := ensureUnzip(); err != nil {
		return err
	}

	releaseArch, ok := xrayArchMap(arch)
	if !ok {
		return fmt.Errorf("xray 没有对应 %s 架构的 release", arch)
	}

	url := fmt.Sprintf(
		"https://github.com/XTLS/Xray-core/releases/download/%s/Xray-linux-%s.zip",
		version, releaseArch,
	)
	tempFile := "/tmp/xray-core.zip"
	if err := utils.DownloadFile(url, tempFile, 3); err != nil {
		return err
	}
	defer os.Remove(tempFile)

	tempDir := "/tmp/xray-extract"
	_ = os.RemoveAll(tempDir)
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return err
	}
	defer os.RemoveAll(tempDir)

	if err := exec.Command("unzip", "-o", tempFile, "-d", tempDir).Run(); err != nil {
		return fmt.Errorf("解压 xray 失败: %v", err)
	}
	srcPath := tempDir + "/xray"
	if !utils.FileExists(srcPath) {
		return fmt.Errorf("zip 中没找到 xray 二进制")
	}
	if err := os.Rename(srcPath, XrayBinaryPath); err != nil {
		// 跨设备 rename 不行就 copy
		cmd := exec.Command("cp", srcPath, XrayBinaryPath)
		if err := cmd.Run(); err != nil {
			return err
		}
	}
	if err := os.Chmod(XrayBinaryPath, 0755); err != nil {
		return err
	}
	utils.PrintSuccess("Xray 下载成功 (%s)", version)
	return nil
}

func xrayArchMap(arch string) (string, bool) {
	switch arch {
	case "amd64":
		return "64", true
	case "arm64":
		return "arm64-v8a", true
	}
	return "", false
}

func ensureUnzip() error {
	if _, err := exec.LookPath("unzip"); err == nil {
		return nil
	}
	utils.PrintInfo("正在安装 unzip...")
	if _, err := exec.LookPath("apt-get"); err == nil {
		return exec.Command("apt-get", "install", "-y", "-qq", "unzip").Run()
	}
	if _, err := exec.LookPath("yum"); err == nil {
		return exec.Command("yum", "install", "-y", "-q", "unzip").Run()
	}
	return fmt.Errorf("没有 unzip 且无法自动安装")
}

// XrayKeypair 调 `xray x25519` 生成 Reality 的 X25519 密钥对。
// 输出格式 (xray v26+):
//
//	PrivateKey: <base64>
//	Password (PublicKey): <base64>
//	Hash32: <base64>
type XrayKeypair struct {
	PrivateKey string
	PublicKey  string
}

func GenerateXrayReality25519() (XrayKeypair, error) {
	out, err := exec.Command(XrayBinaryPath, "x25519").Output()
	if err != nil {
		return XrayKeypair{}, fmt.Errorf("xray x25519 调用失败: %w", err)
	}
	var kp XrayKeypair
	for _, line := range strings.Split(string(out), "\n") {
		s := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(s, "PrivateKey:"):
			kp.PrivateKey = strings.TrimSpace(strings.TrimPrefix(s, "PrivateKey:"))
		case strings.HasPrefix(s, "Password (PublicKey):"):
			kp.PublicKey = strings.TrimSpace(strings.TrimPrefix(s, "Password (PublicKey):"))
		case strings.HasPrefix(s, "PublicKey:"): // 老版本 fallback
			kp.PublicKey = strings.TrimSpace(strings.TrimPrefix(s, "PublicKey:"))
		}
	}
	if kp.PrivateKey == "" || kp.PublicKey == "" {
		return kp, fmt.Errorf("xray x25519 输出解析失败: %s", string(out))
	}
	return kp, nil
}
