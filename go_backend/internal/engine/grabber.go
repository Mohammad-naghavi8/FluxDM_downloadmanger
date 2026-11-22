package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os/exec"
	"path"
	"regexp"
	"strings"
	"sync"
)

type GrabbedLink struct {
	URL       string `json:"url"`
	Name      string `json:"name"`
	SizeBytes int64  `json:"sizeBytes"`
	Status    string `json:"status"`
	IsWebPage bool   `json:"isWebPage"`
	IsDirect  bool   `json:"isDirect"`
}

type GrabLinksResult struct {
	Source string        `json:"source"`
	Links  []GrabbedLink `json:"links"`
}

type VideoStreamOption struct {
	Title     string `json:"title"`
	URL       string `json:"url"`
	Quality   string `json:"quality"`
	Format    string `json:"format"`
	SizeBytes int64  `json:"sizeBytes"`
}

type GrabVideoResult struct {
	PageTitle string              `json:"pageTitle"`
	Streams   []VideoStreamOption `json:"streams"`
	Subtitles []string            `json:"subtitles"`
	UsedYtDlp bool                `json:"usedYtDlp"`
}

var (
	hrefAttrRegex  = regexp.MustCompile(`(?i)(?:href|src)=["']([^"'#]+)["']`)
	rawURLRegex    = regexp.MustCompile(`(?i)\b(?:https?|ftp)://[^\s"'<>()]+`)
	htmlTitleRegex = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
	ogVideoRegex   = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:video(?::secure_url)?["'][^>]+content=["']([^"']+)["']`)
	videoFileRegex = regexp.MustCompile(`(?i)\.(?:mp4|mkv|webm|mov|m4v|m3u8|flv|avi)(?:\?|$)`)
	webPageExtSet  = map[string]bool{
		".html": true, ".htm": true, ".php": true, ".asp": true, ".aspx": true,
		".jsp": true, ".shtml": true, ".css": true, ".js": true,
	}
)

func (e *Engine) GrabLinks(ctx context.Context, input string, probeOnline bool, hideWebPages bool) (*GrabLinksResult, error) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return &GrabLinksResult{Source: "", Links: []GrabbedLink{}}, nil
	}

	rawURLs := make([]string, 0, 16)
	sourceLabel := "Clipboard / Text"

	// If input is a single HTTP/HTTPS URL to a webpage, fetch & extract links from it.
	if !strings.ContainsAny(trimmed, " \n\r\t") {
		if u, err := url.Parse(trimmed); err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != "" {
			sourceLabel = trimmed
			if isLikelyDirectFileURL(u) {
				rawURLs = append(rawURLs, trimmed)
			} else {
				extracted, err := e.fetchPageLinks(ctx, u)
				if err == nil && len(extracted) > 0 {
					rawURLs = append(rawURLs, extracted...)
				} else {
					rawURLs = append(rawURLs, trimmed)
				}
			}
		}
	}

	if len(rawURLs) == 0 {
		for _, m := range rawURLRegex.FindAllString(trimmed, 200) {
			rawURLs = append(rawURLs, strings.TrimRight(m, ".,;)]}"))
		}
	}

	// Deduplicate
	seen := make(map[string]struct{}, len(rawURLs))
	unique := make([]string, 0, len(rawURLs))
	for _, raw := range rawURLs {
		if _, ok := seen[raw]; ok {
			continue
		}
		seen[raw] = struct{}{}
		unique = append(unique, raw)
		if len(unique) >= 100 {
			break
		}
	}

	results := make([]GrabbedLink, len(unique))
	sem := make(chan struct{}, 8)
	var wg sync.WaitGroup

	for i, raw := range unique {
		idx := i
		linkURL := raw
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			u, err := url.Parse(linkURL)
			if err != nil {
				return
			}
			base := path.Base(u.Path)
			if base == "" || base == "/" || base == "." {
				base = u.Host
			}
			ext := strings.ToLower(path.Ext(base))
			isWeb := webPageExtSet[ext] || ext == ""
			isDirect := isLikelyDirectFileURL(u)

			item := GrabbedLink{
				URL:       linkURL,
				Name:      base,
				SizeBytes: 0,
				Status:    "Ready",
				IsWebPage: isWeb && !isDirect,
				IsDirect:  isDirect,
			}

			if probeOnline && ctx.Err() == nil {
				pCtx, cancel := context.WithTimeout(ctx, 5*1e9)
				info, pErr := e.Probe(pCtx, linkURL, "", "")
				cancel()
				if pErr == nil {
					if info.FileName != "" {
						item.Name = info.FileName
					}
					if info.FileSize != nil && *info.FileSize > 0 {
						item.SizeBytes = *info.FileSize
					}
					item.IsDirect = info.IsDirectDownload
					item.IsWebPage = !info.IsDirectDownload
					item.Status = "Online"
				} else {
					item.Status = "Offline"
				}
			}

			results[idx] = item
		}()
	}
	wg.Wait()

	filtered := make([]GrabbedLink, 0, len(results))
	for _, r := range results {
		if r.URL == "" {
			continue
		}
		if hideWebPages && r.IsWebPage {
			continue
		}
		filtered = append(filtered, r)
	}

	return &GrabLinksResult{
		Source: sourceLabel,
		Links:  filtered,
	}, nil
}

func (e *Engine) fetchPageLinks(ctx context.Context, pageURL *url.URL) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, pageURL.String(), nil)
	if err != nil {
		return nil, err
	}
	e.applyConfiguredHeaders(req, "", "")
	resp, err := e.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	ct := strings.ToLower(resp.Header.Get("Content-Type"))
	if !strings.Contains(ct, "text/html") && !strings.Contains(ct, "application/xhtml") {
		return []string{pageURL.String()}, nil
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return nil, err
	}
	html := string(body)

	var found []string
	for _, m := range hrefAttrRegex.FindAllStringSubmatch(html, 400) {
		if len(m) < 2 {
			continue
		}
		ref := strings.TrimSpace(m[1])
		if ref == "" || strings.HasPrefix(ref, "javascript:") || strings.HasPrefix(ref, "mailto:") || strings.HasPrefix(ref, "data:") {
			continue
		}
		if refURL, err := url.Parse(ref); err == nil {
			abs := pageURL.ResolveReference(refURL)
			if abs.Scheme == "http" || abs.Scheme == "https" || abs.Scheme == "ftp" {
				found = append(found, abs.String())
			}
		}
	}
	return found, nil
}

func isLikelyDirectFileURL(u *url.URL) bool {
	ext := strings.ToLower(strings.TrimPrefix(path.Ext(u.Path), "."))
	if ext == "" {
		return false
	}
	return directExtensions[ext] || partExtRegex.MatchString(ext)
}

func (e *Engine) GrabVideo(ctx context.Context, rawURL string) (*GrabVideoResult, error) {
	trimmed := strings.TrimSpace(rawURL)
	u, err := url.Parse(trimmed)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, fmt.Errorf("enter a valid HTTP/HTTPS page address")
	}

	// 1. Try yt-dlp if installed on PATH for sites like YouTube/Vimeo/etc.
	if ytdlpPath, lookErr := exec.LookPath("yt-dlp"); lookErr == nil && ytdlpPath != "" {
		if res, ok := runYtDlpInspect(ctx, ytdlpPath, trimmed); ok {
			return res, nil
		}
	}

	// 2. Native Go HTML video & direct stream extractor.
	if videoFileRegex.MatchString(u.Path) {
		name := path.Base(u.Path)
		return &GrabVideoResult{
			PageTitle: name,
			Streams: []VideoStreamOption{
				{
					Title:   name,
					URL:     trimmed,
					Quality: "Original",
					Format:  strings.ToUpper(strings.TrimPrefix(path.Ext(name), ".")),
				},
			},
			Subtitles: []string{"None"},
		}, nil
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, trimmed, nil)
	if err != nil {
		return nil, err
	}
	e.applyConfiguredHeaders(req, "", "")
	resp, err := e.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return nil, err
	}
	html := string(body)

	pageTitle := u.Host
	if tm := htmlTitleRegex.FindStringSubmatch(html); len(tm) > 1 {
		t := strings.TrimSpace(tm[1])
		if t != "" {
			pageTitle = t
		}
	}

	seen := map[string]struct{}{}
	streams := make([]VideoStreamOption, 0, 8)
	addStream := func(raw string, label string) {
		ref, pErr := url.Parse(strings.TrimSpace(raw))
		if pErr != nil {
			return
		}
		abs := u.ResolveReference(ref).String()
		if _, exists := seen[abs]; exists {
			return
		}
		seen[abs] = struct{}{}
		ext := strings.ToUpper(strings.TrimPrefix(path.Ext(ref.Path), "."))
		if ext == "" {
			ext = "VIDEO"
		}
		streams = append(streams, VideoStreamOption{
			Title:   pageTitle,
			URL:     abs,
			Quality: label,
			Format:  ext,
		})
	}

	for _, m := range ogVideoRegex.FindAllStringSubmatch(html, 10) {
		if len(m) > 1 {
			addStream(m[1], "Direct / OG Video")
		}
	}
	for _, m := range hrefAttrRegex.FindAllStringSubmatch(html, 300) {
		if len(m) > 1 && videoFileRegex.MatchString(m[1]) {
			addStream(m[1], "Embedded Stream")
		}
	}
	for _, m := range rawURLRegex.FindAllString(html, 300) {
		if videoFileRegex.MatchString(m) {
			addStream(strings.TrimRight(m, ".,;)]}\"'"), "Stream")
		}
	}

	return &GrabVideoResult{
		PageTitle: pageTitle,
		Streams:   streams,
		Subtitles: []string{"None"},
	}, nil
}

func runYtDlpInspect(ctx context.Context, binPath, pageURL string) (*GrabVideoResult, bool) {
	cmd := exec.CommandContext(ctx, binPath, "--dump-single-json", "--no-playlist", "--no-warnings", pageURL)
	out, err := cmd.Output()
	if err != nil || len(out) == 0 {
		return nil, false
	}
	var doc struct {
		Title   string `json:"title"`
		Formats []struct {
			URL        string `json:"url"`
			Ext        string `json:"ext"`
			FormatNote string `json:"format_note"`
			Height     int    `json:"height"`
			Filesize   int64  `json:"filesize"`
			Vcodec     string `json:"vcodec"`
		} `json:"formats"`
	}
	if err := json.Unmarshal(out, &doc); err != nil {
		return nil, false
	}
	streams := make([]VideoStreamOption, 0, 12)
	for _, f := range doc.Formats {
		if f.URL == "" || f.Vcodec == "none" {
			continue
		}
		q := f.FormatNote
		if q == "" && f.Height > 0 {
			q = fmt.Sprintf("%dp", f.Height)
		}
		if q == "" {
			q = "Video"
		}
		streams = append(streams, VideoStreamOption{
			Title:     doc.Title,
			URL:       f.URL,
			Quality:   q,
			Format:    strings.ToUpper(f.Ext),
			SizeBytes: f.Filesize,
		})
	}
	if len(streams) == 0 {
		return nil, false
	}
	return &GrabVideoResult{
		PageTitle: doc.Title,
		Streams:   streams,
		Subtitles: []string{"None"},
		UsedYtDlp: true,
	}, true
}
