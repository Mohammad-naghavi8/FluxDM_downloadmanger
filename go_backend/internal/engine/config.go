package engine

import (
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

type ConnectionExceptionRule struct {
	Server      string `json:"server"`
	Connections int    `json:"connections"`
}

type SiteLoginRule struct {
	SitePath string `json:"sitePath"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type EngineConfig struct {
	UserAgent            string                    `json:"userAgent"`
	ProxyMode            string                    `json:"proxyMode"` // none, system, manual
	ProxyServer          string                    `json:"proxyServer"`
	ProxyPort            string                    `json:"proxyPort"`
	ProxyUsername        string                    `json:"proxyUsername"`
	ProxyPassword        string                    `json:"proxyPassword"`
	ProxyHTTP            bool                      `json:"proxyHttp"`
	ProxyHTTPS           bool                      `json:"proxyHttps"`
	DNSMode              string                    `json:"dnsMode"`
	UseFtpPasv           bool                      `json:"useFtpPasv"`
	ConnectionExceptions []ConnectionExceptionRule `json:"connectionExceptions"`
	SiteLogins           []SiteLoginRule           `json:"siteLogins"`
}

func (e *Engine) ApplyConfig(cfg EngineConfig) {
	dnsAddr := ""
	lowDNS := strings.ToLower(cfg.DNSMode)
	switch {
	case strings.Contains(lowDNS, "1.1.1.1") || strings.Contains(lowDNS, "cloudflare"):
		dnsAddr = "1.1.1.1:53"
	case strings.Contains(lowDNS, "8.8.8.8") || strings.Contains(lowDNS, "google"):
		dnsAddr = "8.8.8.8:53"
	}
	e.dialer.SetDNSServer(dnsAddr)

	var proxyFn func(*http.Request) (*url.URL, error)
	switch strings.ToLower(strings.TrimSpace(cfg.ProxyMode)) {
	case "system":
		proxyFn = http.ProxyFromEnvironment
	case "manual":
		host := strings.TrimSpace(cfg.ProxyServer)
		port := strings.TrimSpace(cfg.ProxyPort)
		if host != "" {
			rawProxy := host
			if !strings.Contains(rawProxy, "://") {
				rawProxy = "http://" + rawProxy
			}
			if port != "" && !strings.Contains(strings.TrimPrefix(strings.TrimPrefix(rawProxy, "http://"), "https://"), ":") {
				rawProxy = rawProxy + ":" + port
			}
			if parsed, err := url.Parse(rawProxy); err == nil {
				if cfg.ProxyUsername != "" {
					parsed.User = url.UserPassword(cfg.ProxyUsername, cfg.ProxyPassword)
				}
				proxyURL := parsed
				allowHTTP := cfg.ProxyHTTP || (!cfg.ProxyHTTP && !cfg.ProxyHTTPS)
				allowHTTPS := cfg.ProxyHTTPS || (!cfg.ProxyHTTP && !cfg.ProxyHTTPS)
				proxyFn = func(req *http.Request) (*url.URL, error) {
					scheme := strings.ToLower(req.URL.Scheme)
					if (scheme == "http" && allowHTTP) || (scheme == "https" && allowHTTPS) {
						return proxyURL, nil
					}
					return nil, nil
				}
			}
		}
	default:
		proxyFn = nil
	}

	if tr, ok := e.client.Transport.(*http.Transport); ok {
		tr.Proxy = proxyFn
		tr.CloseIdleConnections()
	}

	e.cfgMu.Lock()
	e.cfg = cfg
	e.cfgMu.Unlock()
}

func (e *Engine) effectiveUserAgent() string {
	e.cfgMu.RLock()
	ua := strings.TrimSpace(e.cfg.UserAgent)
	e.cfgMu.RUnlock()
	if ua != "" {
		return ua
	}
	return defaultUserAgent
}

func (e *Engine) effectiveCredentials(rawURL, username, password string) (string, string) {
	if username != "" {
		return username, password
	}
	e.cfgMu.RLock()
	logins := e.cfg.SiteLogins
	e.cfgMu.RUnlock()

	if len(logins) == 0 {
		return username, password
	}
	lowerURL := strings.ToLower(rawURL)
	parsed, _ := url.Parse(rawURL)
	host := ""
	if parsed != nil {
		host = strings.ToLower(parsed.Hostname())
	}

	for _, rule := range logins {
		site := strings.ToLower(strings.TrimSpace(rule.SitePath))
		if site == "" || rule.Username == "" {
			continue
		}
		if strings.HasPrefix(lowerURL, site) || (host != "" && (host == site || strings.HasSuffix(host, "."+site))) {
			return rule.Username, rule.Password
		}
	}
	return username, password
}

func (e *Engine) effectiveConnectionCount(rawURL string, requested int) int {
	if requested < 1 {
		requested = 1
	}
	e.cfgMu.RLock()
	exceptions := e.cfg.ConnectionExceptions
	e.cfgMu.RUnlock()

	if len(exceptions) == 0 {
		return requested
	}
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Hostname() == "" {
		return requested
	}
	host := strings.ToLower(parsed.Hostname())
	for _, ex := range exceptions {
		pattern := strings.ToLower(strings.TrimSpace(ex.Server))
		if pattern == "" || ex.Connections < 1 {
			continue
		}
		if host == pattern || strings.HasSuffix(host, "."+pattern) {
			return ex.Connections
		}
	}
	return requested
}

func (e *Engine) applyConfiguredHeaders(req *http.Request, username, password string) {
	u, p := e.effectiveCredentials(req.URL.String(), username, password)
	applyCommonHeaders(req, u, p)
	req.Header.Set("User-Agent", e.effectiveUserAgent())
	if u != "" && req.Header.Get("Authorization") == "" {
		req.SetBasicAuth(u, p)
	}
	_ = fmt.Sprintf("")
}
