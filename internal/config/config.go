package config

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Protocol 协议类型
type Protocol string

const (
	ProtocolSnell     Protocol = "snell"
	ProtocolSingbox   Protocol = "singbox"
	ProtocolReality   Protocol = "reality"
	ProtocolHysteria2 Protocol = "hysteria2"
	ProtocolAnyTLS    Protocol = "anytls"
)

// ServiceConfig 服务配置
type ServiceConfig struct {
	Enabled   bool     `json:"enabled"`
	Port      int      `json:"port"`
	TLSDomain string   `json:"tls_domain,omitempty"`
	Domain    string   `json:"domain,omitempty"`
	Password  string   `json:"password,omitempty"`
	Protocol  Protocol `json:"protocol"`
}

// Config 全局配置
type Config struct {
	Version  string                     `json:"version"`
	Services map[Protocol]ServiceConfig `json:"services"`
}

// ConfigPath 配置文件路径
const ConfigPath = "/etc/proxy-manager/config.json"

// DefaultConfig 默认配置
func DefaultConfig() *Config {
	return &Config{
		Version:  "4.0.0",
		Services: make(map[Protocol]ServiceConfig),
	}
}

// Load 加载配置
func Load() (*Config, error) {
	if _, err := os.Stat(ConfigPath); os.IsNotExist(err) {
		return DefaultConfig(), nil
	}

	data, err := os.ReadFile(ConfigPath)
	if err != nil {
		return nil, err
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}

	return &config, nil
}

// Save 保存配置
func (c *Config) Save() error {
	// 确保目录存在
	dir := filepath.Dir(ConfigPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(ConfigPath, data, 0600)
}

// GetService 获取服务配置
func (c *Config) GetService(protocol Protocol) (ServiceConfig, bool) {
	svc, ok := c.Services[protocol]
	return svc, ok
}

// SetService 设置服务配置
func (c *Config) SetService(protocol Protocol, svc ServiceConfig) {
	if c.Services == nil {
		c.Services = make(map[Protocol]ServiceConfig)
	}
	c.Services[protocol] = svc
}
