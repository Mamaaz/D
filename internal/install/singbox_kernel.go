package install

// 此文件保留 Snell+ShadowTLS / SS-2022+ShadowTLS 协议被删除 (v4.0.26) 后仍然
// 共享的 sing-box 内核管理工具：二进制路径、下载，以及给 reality / hysteria2 /
// anytls / anytls+reality 安装流程使用的小工具 (promptPort / newCommand)。

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

const (
	SingboxBinaryPath = "/usr/local/bin/sing-box"
)

// downloadSingbox 下载 sing-box 二进制到 SingboxBinaryPath。如已存在则跳过。
func downloadSingbox(version, arch string) error {
	if utils.FileExists(SingboxBinaryPath) {
		return nil
	}

	versionNum := version
	if len(version) > 0 && version[0] == 'v' {
		versionNum = version[1:]
	}

	url := fmt.Sprintf(
		"https://github.com/SagerNet/sing-box/releases/download/%s/sing-box-%s-linux-%s.tar.gz",
		version, versionNum, arch,
	)

	tempFile := "/tmp/sing-box.tar.gz"
	if err := utils.DownloadFile(url, tempFile, 3); err != nil {
		return err
	}
	defer os.Remove(tempFile)

	if err := utils.ExtractTarGz(tempFile, "/tmp"); err != nil {
		return fmt.Errorf("解压失败: %v", err)
	}

	extractDir := fmt.Sprintf("/tmp/sing-box-%s-linux-%s", versionNum, arch)
	srcPath := extractDir + "/sing-box"

	if !utils.FileExists(srcPath) {
		return fmt.Errorf("找不到 sing-box 二进制文件")
	}
	if err := os.Rename(srcPath, SingboxBinaryPath); err != nil {
		// 跨设备 rename 会失败 (e.g. /tmp 是 tmpfs)，回退到 cp
		if cpErr := newCommand("cp", srcPath, SingboxBinaryPath).Run(); cpErr != nil {
			return cpErr
		}
	}

	os.Chmod(SingboxBinaryPath, 0755)
	os.RemoveAll(extractDir)

	utils.PrintSuccess("Sing-box 下载成功")
	return nil
}

// promptPort 交互式让用户输入端口号，含校验 + 占用检查。
func promptPort(prompt string, defaultPort int) int {
	for {
		input := utils.PromptInput(prompt, strconv.Itoa(defaultPort))
		port, err := strconv.Atoi(input)
		if err != nil {
			utils.PrintError("请输入有效的端口号")
			continue
		}
		if err := utils.ValidatePort(port); err != nil {
			utils.PrintError("%v", err)
			continue
		}
		if utils.IsPortInUse(port) {
			utils.PrintWarn("端口 %d 已被占用", port)
			if !utils.PromptConfirm("是否仍然使用此端口？") {
				continue
			}
		}
		return port
	}
}

func newCommand(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}
