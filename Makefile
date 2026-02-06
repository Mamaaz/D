.PHONY: build clean install linux-amd64 linux-arm64 all test fmt lint release

VERSION := 4.0.0
BINARY := proxy-manager
BUILD_DIR := dist
LDFLAGS := -ldflags "-s -w -X main.version=$(VERSION)"

# 默认构建
build:
	go build $(LDFLAGS) -o $(BINARY) ./cmd/proxy-manager/

# 清理
clean:
	rm -f $(BINARY)
	rm -rf $(BUILD_DIR)

# 本地安装
install: build
	sudo cp $(BINARY) /usr/local/bin/

# 跨平台编译
linux-amd64:
	mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-amd64 ./cmd/proxy-manager/

linux-arm64:
	mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-arm64 ./cmd/proxy-manager/

# 构建所有平台
all: clean linux-amd64 linux-arm64
	@echo "构建完成:"
	@ls -la $(BUILD_DIR)/

# 创建发布包
release: all
	@echo "创建发布包..."
	cd $(BUILD_DIR) && sha256sum * > checksums.txt
	@echo ""
	@echo "发布文件:"
	@ls -la $(BUILD_DIR)/
	@echo ""
	@echo "校验和:"
	@cat $(BUILD_DIR)/checksums.txt

# 测试
test:
	go test -v ./...

# 格式化
fmt:
	go fmt ./...

# 检查
lint:
	golangci-lint run

# 显示帮助
help:
	@echo "Proxy Manager 构建系统"
	@echo ""
	@echo "目标:"
	@echo "  make build        本地构建"
	@echo "  make install      构建并安装到系统"
	@echo "  make linux-amd64  构建 Linux amd64"
	@echo "  make linux-arm64  构建 Linux arm64"
	@echo "  make all          构建所有平台"
	@echo "  make release      构建并创建发布包"
	@echo "  make clean        清理构建文件"
	@echo "  make test         运行测试"
	@echo "  make fmt          格式化代码"
	@echo "  make lint         代码检查"
