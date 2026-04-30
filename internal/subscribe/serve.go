package subscribe

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/crypto/acme"
	"golang.org/x/crypto/acme/autocert"
)

// CertCacheDir is where autocert persists Let's Encrypt certificates.
// Survives daemon restarts so we don't re-issue every boot.
const CertCacheDir = "/var/lib/proxy-manager/autocert"

// ServeOptions configures the daemon entry point. Domain and Port are
// required; the rest have sensible defaults.
type ServeOptions struct {
	Domain     string
	Port       int
	Email      string // optional ACME registration email
	Staging    bool   // use Let's Encrypt staging directory (avoids rate limits during dev)
	HTTPListen string // override :80 for testing; empty means standard ":80"
}

// Serve runs the subscription HTTPS daemon: ACME-signed cert via HTTP-01
// challenge on :80, subscription handler on :Port. Blocks until SIGINT/SIGTERM
// or a listener fails.
func Serve(opts ServeOptions) error {
	if opts.Domain == "" {
		return errors.New("domain is required")
	}
	if opts.Port <= 0 || opts.Port > 65535 {
		return fmt.Errorf("invalid port: %d", opts.Port)
	}
	if err := os.MkdirAll(filepath.Clean(CertCacheDir), 0700); err != nil {
		return fmt.Errorf("create cert cache: %w", err)
	}

	mgr := &autocert.Manager{
		Cache:      autocert.DirCache(CertCacheDir),
		Prompt:     autocert.AcceptTOS,
		HostPolicy: autocert.HostWhitelist(opts.Domain),
		Email:      opts.Email,
	}
	if opts.Staging {
		mgr.Client = &acme.Client{DirectoryURL: "https://acme-staging-v02.api.letsencrypt.org/directory"}
	}

	httpAddr := opts.HTTPListen
	if httpAddr == "" {
		httpAddr = ":80"
	}
	httpsAddr := fmt.Sprintf(":%d", opts.Port)

	// Port 80: the ACME http-01 challenge handler. autocert.HTTPHandler with
	// nil fallback returns 404 for non-challenge paths so we don't leak that
	// the host runs anything else there.
	httpServer := &http.Server{
		Addr:              httpAddr,
		Handler:           mgr.HTTPHandler(nil),
		ReadHeaderTimeout: 10 * time.Second,
	}
	httpsServer := &http.Server{
		Addr:    httpsAddr,
		Handler: Handler(),
		TLSConfig: &tls.Config{
			GetCertificate: mgr.GetCertificate,
			MinVersion:     tls.VersionTLS12,
			NextProtos:     []string{"h2", "http/1.1", acme.ALPNProto},
		},
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 2)
	go func() {
		log.Printf("subscribe: ACME http-01 listening on %s", httpAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("http listener: %w", err)
		}
	}()
	go func() {
		log.Printf("subscribe: HTTPS listening on %s for %s", httpsAddr, opts.Domain)
		// Empty cert/key paths because GetCertificate is set on TLSConfig.
		if err := httpsServer.ListenAndServeTLS("", ""); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("https listener: %w", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		shutdown(httpServer, httpsServer)
		return err
	case sig := <-stop:
		log.Printf("subscribe: received %s, shutting down", sig)
		shutdown(httpServer, httpsServer)
		return nil
	}
}

func shutdown(servers ...*http.Server) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for _, s := range servers {
		_ = s.Shutdown(ctx)
	}
}

// CheckPortAvailable returns nil if the port is free or held by us. Used
// by `subscribe enable` to fail loudly before installing a systemd unit.
func CheckPortAvailable(port int) error {
	l, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return err
	}
	_ = l.Close()
	return nil
}
