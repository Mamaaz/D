package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var JWTSecret []byte

// Claims JWT 声明
type Claims struct {
	UserID   uuid.UUID `json:"userId"`
	Username string    `json:"username"`
	Role     string    `json:"role"`
	jwt.RegisteredClaims
}

// AuthMiddleware JWT 认证中间件
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未提供认证信息"})
			c.Abort()
			return
		}

		// Bearer token
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "认证格式错误"})
			c.Abort()
			return
		}

		tokenString := parts[1]
		claims := &Claims{}

		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return JWTSecret, nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "无效的认证令牌"})
			c.Abort()
			return
		}

		// 将用户信息存入上下文
		c.Set("userId", claims.UserID)
		c.Set("username", claims.Username)
		c.Set("role", claims.Role)

		c.Next()
	}
}

// AdminMiddleware 管理员权限中间件
func AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未认证"})
			c.Abort()
			return
		}

		if role != "admin" && role != "sub_admin" {
			c.JSON(http.StatusForbidden, gin.H{"error": "权限不足"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// GetCurrentUserID 从上下文获取当前用户 ID
func GetCurrentUserID(c *gin.Context) (uuid.UUID, bool) {
	userID, exists := c.Get("userId")
	if !exists {
		return uuid.Nil, false
	}
	return userID.(uuid.UUID), true
}

// IsAdmin 检查当前用户是否是管理员
func IsAdmin(c *gin.Context) bool {
	role, exists := c.Get("role")
	if !exists {
		return false
	}
	return role == "admin" || role == "sub_admin"
}

// GetCurrentUser 从上下文获取当前用户对象 (需要导入 models 和 database)
// 返回一个简化的用户信息结构
type CurrentUserInfo struct {
	ID       uuid.UUID
	Username string
	Role     string
}

func (u *CurrentUserInfo) HasAdminPrivilege() bool {
	return u.Role == "admin" || u.Role == "sub_admin"
}

func GetCurrentUser(c *gin.Context) (*CurrentUserInfo, bool) {
	userID, exists := c.Get("userId")
	if !exists {
		return nil, false
	}
	username, _ := c.Get("username")
	role, _ := c.Get("role")

	return &CurrentUserInfo{
		ID:       userID.(uuid.UUID),
		Username: username.(string),
		Role:     role.(string),
	}, true
}
