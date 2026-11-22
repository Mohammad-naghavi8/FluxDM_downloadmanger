package engine

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"
)

const unhealthyIPTTL = 5 * time.Minute

type SmartDialer struct {
	mu           sync.Mutex
	unhealthyIPs map[string]time.Time
	hostCursor   map[string]int
	baseDialer   *net.Dialer
	dnsServer    string
	resolver     *net.Resolver
}

func NewSmartDialer() *SmartDialer {
	return &SmartDialer{
		unhealthyIPs: make(map[string]time.Time),
		hostCursor:   make(map[string]int),
		baseDialer: &net.Dialer{
			Timeout:   15 * time.Second,
			KeepAlive: 30 * time.Second,
		},
		resolver: net.DefaultResolver,
	}
}

func (d *SmartDialer) SetDNSServer(addr string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if addr == d.dnsServer {
		return
	}
	d.dnsServer = addr
	if addr == "" {
		d.resolver = net.DefaultResolver
		return
	}
	target := addr
	d.resolver = &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return d.baseDialer.DialContext(ctx, "udp", target)
		},
	}
}

func (d *SmartDialer) markUnhealthy(ip string) {
	d.mu.Lock()
	d.unhealthyIPs[ip] = time.Now().Add(unhealthyIPTTL)
	d.mu.Unlock()
}

func (d *SmartDialer) lookupCandidates(ctx context.Context, host string) ([]string, error) {
	if ip := net.ParseIP(host); ip != nil {
		return []string{ip.String()}, nil
	}

	d.mu.Lock()
	res := d.resolver
	d.mu.Unlock()
	if res == nil {
		res = net.DefaultResolver
	}

	resolved, err := res.LookupIPAddr(ctx, host)
	if err != nil || len(resolved) == 0 {
		return nil, err
	}

	now := time.Now()
	d.mu.Lock()
	for ip, until := range d.unhealthyIPs {
		if now.After(until) {
			delete(d.unhealthyIPs, ip)
		}
	}

	healthy := make([]string, 0, len(resolved))
	all := make([]string, 0, len(resolved))
	for _, addr := range resolved {
		ipStr := addr.IP.String()
		all = append(all, ipStr)
		if _, bad := d.unhealthyIPs[ipStr]; !bad {
			healthy = append(healthy, ipStr)
		}
	}

	candidates := healthy
	if len(candidates) == 0 {
		candidates = all
	}

	cursor := d.hostCursor[host]
	d.hostCursor[host] = cursor + 1
	d.mu.Unlock()

	// Rotate candidates starting at cursor so load spreads across healthy edge nodes
	if len(candidates) > 1 {
		offset := cursor % len(candidates)
		rotated := make([]string, len(candidates))
		copy(rotated, candidates[offset:])
		copy(rotated[len(candidates)-offset:], candidates[:offset])
		return rotated, nil
	}
	return candidates, nil
}

func (d *SmartDialer) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return d.baseDialer.DialContext(ctx, network, addr)
	}

	candidates, err := d.lookupCandidates(ctx, host)
	if err != nil || len(candidates) == 0 {
		return d.baseDialer.DialContext(ctx, network, addr)
	}

	var lastErr error
	maxTries := len(candidates)
	if maxTries > 6 {
		maxTries = 6
	}

	for i := 0; i < maxTries; i++ {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		ip := candidates[i]
		conn, dialErr := d.baseDialer.DialContext(ctx, network, net.JoinHostPort(ip, port))
		if dialErr == nil {
			return conn, nil
		}
		lastErr = dialErr
		d.markUnhealthy(ip)
	}
	return nil, fmt.Errorf("all edge IPs failed for %s: %w", host, lastErr)
}

func (d *SmartDialer) DialTLSContext(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}

	candidates, err := d.lookupCandidates(ctx, host)
	if err != nil || len(candidates) == 0 {
		raw, dialErr := d.baseDialer.DialContext(ctx, network, addr)
		if dialErr != nil {
			return nil, dialErr
		}
		tlsConn := tls.Client(raw, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
		if hsErr := tlsConn.HandshakeContext(ctx); hsErr != nil {
			_ = raw.Close()
			return nil, hsErr
		}
		return tlsConn, nil
	}

	var lastErr error
	maxTries := len(candidates)
	if maxTries > 6 {
		maxTries = 6
	}

	for i := 0; i < maxTries; i++ {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		ip := candidates[i]
		raw, dialErr := d.baseDialer.DialContext(ctx, network, net.JoinHostPort(ip, port))
		if dialErr != nil {
			lastErr = dialErr
			d.markUnhealthy(ip)
			continue
		}

		// Strict TLS verification with proper SNI for the target hostname
		tlsConn := tls.Client(raw, &tls.Config{
			ServerName: host,
			MinVersion: tls.VersionTLS12,
		})
		if hsErr := tlsConn.HandshakeContext(ctx); hsErr != nil {
			_ = raw.Close()
			lastErr = hsErr
			d.markUnhealthy(ip)
			continue
		}
		return tlsConn, nil
	}

	return nil, fmt.Errorf("TLS handshake failed across edge IPs for %s: %w", host, lastErr)
}

func NewSmartHTTPClient(dialer *SmartDialer) *http.Client {
	transport := &http.Transport{
		DialContext:           dialer.DialContext,
		DialTLSContext:        dialer.DialTLSContext,
		MaxIdleConns:          48,
		MaxIdleConnsPerHost:   16,
		IdleConnTimeout:       30 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ResponseHeaderTimeout: 25 * time.Second,
		ExpectContinueTimeout: 2 * time.Second,
		DisableCompression:    true,
		ReadBufferSize:        64 * 1024,
		WriteBufferSize:       32 * 1024,
		ForceAttemptHTTP2:     false,
	}

	return &http.Client{
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 10 {
				return fmt.Errorf("stopped after 10 redirects")
			}
			// Preserve User-Agent and Range/Auth headers across redirects
			if len(via) > 0 {
				prev := via[len(via)-1]
				if ua := prev.Header.Get("User-Agent"); ua != "" {
					req.Header.Set("User-Agent", ua)
				}
				if rng := prev.Header.Get("Range"); rng != "" && req.Header.Get("Range") == "" {
					req.Header.Set("Range", rng)
				}
			}
			return nil
		},
	}
}
