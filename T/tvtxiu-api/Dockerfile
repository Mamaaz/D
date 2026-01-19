# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# 安装依赖
COPY go.mod go.sum ./
RUN go mod download

# 复制源码
COPY . .

# 构建
RUN CGO_ENABLED=0 GOOS=linux go build -o /tvtxiu-api .

# Run stage
FROM alpine:latest

WORKDIR /app

# 复制构建产物
COPY --from=builder /tvtxiu-api .

# 暴露端口
EXPOSE 8080

# 启动
CMD ["./tvtxiu-api"]
