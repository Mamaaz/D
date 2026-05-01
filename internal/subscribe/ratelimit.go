package subscribe

// 自用单实例,所有限流状态都在内存里。
//
// - 速率: 每 IP 60 req/min,token bucket,burst 10。XSurge 默认每小时同步一次,
//   远低于此;curl 调试也够用。
// - 401/404 计数: 服务端用 404 隐藏 token 存在性 (server.go:62),所以这里
//   用统一计数。同 IP 连续 5 次未授权 → ban 1h。合法客户端不会触发。
// - 清理: 每次访问顺手 GC,超过 1h 没动过的 entry 删掉,避免攻击者造大量
//   假源 IP 撑爆 map。

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	rlRatePerMin       = 60
	rlBurst            = 10
	rlUnauthThreshold  = 5
	rlBanDuration      = time.Hour
	rlIdleEvict        = time.Hour
	rlMaxEntries       = 10000 // 内存上限,防 source-IP flood
)

type ipState struct {
	tokens         float64
	lastRefill     time.Time
	consecutive401 int
	bannedUntil    time.Time
	lastSeen       time.Time
}

type limiter struct {
	mu  sync.Mutex
	ips map[string]*ipState
}

func newLimiter() *limiter {
	return &limiter{ips: make(map[string]*ipState)}
}

// allow 返回 (是否放行, banned-until 时间戳)。banned-until 仅在被拒绝时
// 有意义,用来在响应头里告知客户端何时可重试。
func (l *limiter) allow(ip string, now time.Time) (bool, time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()

	st, ok := l.ips[ip]
	if !ok {
		// 已经达到 entry 上限的话,先 GC 一波;还满则直接丢请求 (避免无界增长)。
		if len(l.ips) >= rlMaxEntries {
			l.evictLocked(now)
			if len(l.ips) >= rlMaxEntries {
				return false, now.Add(time.Minute)
			}
		}
		st = &ipState{tokens: rlBurst, lastRefill: now, lastSeen: now}
		l.ips[ip] = st
	}

	st.lastSeen = now
	if now.Before(st.bannedUntil) {
		return false, st.bannedUntil
	}

	// Token bucket refill.
	elapsed := now.Sub(st.lastRefill).Seconds()
	st.tokens += elapsed * (rlRatePerMin / 60.0)
	if st.tokens > rlBurst {
		st.tokens = rlBurst
	}
	st.lastRefill = now

	if st.tokens < 1 {
		// 超速被拒不计入 401 计数 (合法客户端 burst 也可能撞这里),只短拒。
		return false, now.Add(time.Second)
	}
	st.tokens -= 1
	return true, time.Time{}
}

// recordUnauth 401/404 计数 +1,达阈值 → ban。在 token 校验失败时调用。
func (l *limiter) recordUnauth(ip string, now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	st, ok := l.ips[ip]
	if !ok {
		st = &ipState{tokens: rlBurst, lastRefill: now, lastSeen: now}
		l.ips[ip] = st
	}
	st.consecutive401++
	st.lastSeen = now
	if st.consecutive401 >= rlUnauthThreshold {
		st.bannedUntil = now.Add(rlBanDuration)
	}
}

// recordAuth 校验通过 → 重置 401 计数。在 token 正确时调用。
func (l *limiter) recordAuth(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if st, ok := l.ips[ip]; ok {
		st.consecutive401 = 0
	}
}

func (l *limiter) evictLocked(now time.Time) {
	for ip, st := range l.ips {
		if now.Sub(st.lastSeen) > rlIdleEvict && now.After(st.bannedUntil) {
			delete(l.ips, ip)
		}
	}
}

// clientIP 提取 r.RemoteAddr 的 IP 部分。订阅服务直接监听公网,不在反向
// 代理后面,所以不读 X-Forwarded-For (避免被伪造)。
func clientIP(r *http.Request) string {
	addr := r.RemoteAddr
	if i := strings.LastIndexByte(addr, ':'); i >= 0 {
		// IPv6 形如 [::1]:1234,strip 端口后还要去掉中括号
		addr = addr[:i]
	}
	addr = strings.TrimPrefix(strings.TrimSuffix(addr, "]"), "[")
	if ip := net.ParseIP(addr); ip != nil {
		return ip.String()
	}
	return addr
}

// rateLimitMiddleware 包裹 mux,在 token 校验之前先做 IP rate limit。
// token 校验失败的 401/404 计数由 server.go:serveSubscribe 通过 recordUnauth
// 调用,本中间件不知道 token 是否对。
func rateLimitMiddleware(l *limiter, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// healthz 不限流 (要给监控系统用)。
		if r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}
		ip := clientIP(r)
		ok, retryAfter := l.allow(ip, time.Now())
		if !ok {
			retrySec := int(time.Until(retryAfter).Seconds())
			if retrySec < 1 {
				retrySec = 1
			}
			w.Header().Set("Retry-After", itoa(retrySec))
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func itoa(n int) string {
	// strconv.Itoa 会触发 strconv import 链,这里就一行手写
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
