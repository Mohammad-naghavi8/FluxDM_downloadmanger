package engine

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

type RSSArticle struct {
	Title   string `json:"title"`
	Link    string `json:"link"`
	PubDate string `json:"pubDate"`
}

type RSSFeedResult struct {
	Title    string       `json:"title"`
	Articles []RSSArticle `json:"articles"`
}

type rssDocument struct {
	Channel struct {
		Title string `xml:"title"`
		Items []struct {
			Title     string `xml:"title"`
			Link      string `xml:"link"`
			PubDate   string `xml:"pubDate"`
			Enclosure struct {
				URL string `xml:"url,attr"`
			} `xml:"enclosure"`
		} `xml:"item"`
	} `xml:"channel"`
}

type atomDocument struct {
	Title   string `xml:"title"`
	Entries []struct {
		Title   string `xml:"title"`
		Updated string `xml:"updated"`
		Links   []struct {
			Href string `xml:"href,attr"`
			Rel  string `xml:"rel,attr"`
		} `xml:"link"`
	} `xml:"entry"`
}

func (e *Engine) FetchRSS(ctx context.Context, rawURL string) (*RSSFeedResult, error) {
	u, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, fmt.Errorf("invalid RSS feed URL")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "DownloadManager-Go/1.0")
	req.Header.Set("Accept", "application/rss+xml, application/atom+xml, application/xml, text/xml, */*")

	resp, err := e.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("server returned HTTP %d", resp.StatusCode)
	}

	// Cap RSS XML payload at 4 MiB to protect RAM.
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}

	return ParseRSSBytes(data, u.Host)
}

func ParseRSSBytes(data []byte, fallbackTitle string) (*RSSFeedResult, error) {
	var rss rssDocument
	if err := xml.Unmarshal(data, &rss); err == nil && (len(rss.Channel.Items) > 0 || strings.TrimSpace(rss.Channel.Title) != "") {
		title := strings.TrimSpace(rss.Channel.Title)
		if title == "" {
			title = fallbackTitle
		}
		articles := make([]RSSArticle, 0, len(rss.Channel.Items))
		for _, item := range rss.Channel.Items {
			link := strings.TrimSpace(item.Enclosure.URL)
			if link == "" {
				link = strings.TrimSpace(item.Link)
			}
			t := strings.TrimSpace(item.Title)
			if t == "" && link == "" {
				continue
			}
			if t == "" {
				t = link
			}
			articles = append(articles, RSSArticle{
				Title:   t,
				Link:    link,
				PubDate: strings.TrimSpace(item.PubDate),
			})
		}
		return &RSSFeedResult{Title: title, Articles: articles}, nil
	}

	var atom atomDocument
	if err := xml.Unmarshal(data, &atom); err == nil && (len(atom.Entries) > 0 || strings.TrimSpace(atom.Title) != "") {
		title := strings.TrimSpace(atom.Title)
		if title == "" {
			title = fallbackTitle
		}
		articles := make([]RSSArticle, 0, len(atom.Entries))
		for _, entry := range atom.Entries {
			link := ""
			for _, l := range entry.Links {
				if l.Href != "" {
					link = strings.TrimSpace(l.Href)
					if l.Rel == "enclosure" || l.Rel == "alternate" || l.Rel == "" {
						break
					}
				}
			}
			t := strings.TrimSpace(entry.Title)
			if t == "" && link == "" {
				continue
			}
			if t == "" {
				t = link
			}
			articles = append(articles, RSSArticle{
				Title:   t,
				Link:    link,
				PubDate: strings.TrimSpace(entry.Updated),
			})
		}
		return &RSSFeedResult{Title: title, Articles: articles}, nil
	}

	return nil, fmt.Errorf("unsupported or invalid RSS/Atom XML")
}
