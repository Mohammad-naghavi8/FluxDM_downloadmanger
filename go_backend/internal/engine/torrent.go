package engine

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type TorrentFileEntry struct {
	Name         string `json:"name"`
	RelativePath string `json:"relativePath"`
	SizeBytes    int64  `json:"sizeBytes"`
}

type TorrentInfo struct {
	Source   string             `json:"source"`
	Name     string             `json:"name"`
	InfoHash string             `json:"infoHash,omitempty"`
	Trackers []string           `json:"trackers"`
	Files    []TorrentFileEntry `json:"files"`
	IsMagnet bool               `json:"isMagnet"`
}

func ParseTorrentSource(input string) (*TorrentInfo, error) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return nil, fmt.Errorf("empty torrent source")
	}
	if strings.HasPrefix(strings.ToLower(trimmed), "magnet:?") {
		return ParseMagnetURI(trimmed)
	}
	// Cap .torrent file at 16 MiB for RAM safety.
	stat, err := os.Stat(trimmed)
	if err != nil {
		return nil, fmt.Errorf("torrent file not found: %w", err)
	}
	if stat.Size() > 16<<20 {
		return nil, fmt.Errorf("torrent file too large")
	}
	data, err := os.ReadFile(trimmed)
	if err != nil {
		return nil, err
	}
	return ParseTorrentBytes(data, trimmed)
}

func ParseMagnetURI(raw string) (*TorrentInfo, error) {
	u, err := url.Parse(raw)
	if err != nil || strings.ToLower(u.Scheme) != "magnet" {
		return nil, fmt.Errorf("invalid magnet link")
	}
	q := u.Query()
	var infoHash string
	for _, xt := range q["xt"] {
		low := strings.ToLower(xt)
		if strings.HasPrefix(low, "urn:btih:") {
			infoHash = xt[len("urn:btih:"):]
			break
		}
		if strings.HasPrefix(low, "urn:btmh:") {
			infoHash = xt[len("urn:btmh:"):]
			break
		}
	}
	if infoHash == "" {
		return nil, fmt.Errorf("magnet link missing xt=urn:btih info hash")
	}

	name := strings.TrimSpace(q.Get("dn"))
	if name == "" {
		name = "Torrent_" + infoHash
	}
	var sizeBytes int64
	if xl := strings.TrimSpace(q.Get("xl")); xl != "" {
		if parsed, err := strconv.ParseInt(xl, 10, 64); err == nil && parsed > 0 {
			sizeBytes = parsed
		}
	}
	trackers := q["tr"]
	if trackers == nil {
		trackers = []string{}
	}

	return &TorrentInfo{
		Source:   raw,
		Name:     name,
		InfoHash: infoHash,
		Trackers: trackers,
		IsMagnet: true,
		Files: []TorrentFileEntry{
			{
				Name:         name,
				RelativePath: name,
				SizeBytes:    sizeBytes,
			},
		},
	}, nil
}

func ParseTorrentBytes(data []byte, sourcePath string) (*TorrentInfo, error) {
	dec := &bencodeDecoder{data: data}
	val, err := dec.decode()
	if err != nil {
		return nil, err
	}
	root, ok := val.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("invalid torrent root dictionary")
	}
	info, ok := root["info"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("missing info dictionary in torrent")
	}

	torrentName := asString(info["name"])
	if torrentName == "" {
		torrentName = filepath.Base(sourcePath)
	}

	trackers := make([]string, 0, 4)
	seen := map[string]struct{}{}
	addTracker := func(t string) {
		t = strings.TrimSpace(t)
		if t == "" {
			return
		}
		if _, exists := seen[t]; !exists {
			seen[t] = struct{}{}
			trackers = append(trackers, t)
		}
	}
	addTracker(asString(root["announce"]))
	if list, ok := root["announce-list"].([]any); ok {
		for _, tier := range list {
			if tierList, ok := tier.([]any); ok {
				for _, item := range tierList {
					addTracker(asString(item))
				}
			}
		}
	}

	files := make([]TorrentFileEntry, 0, 8)
	if rawFiles, ok := info["files"].([]any); ok && len(rawFiles) > 0 {
		for _, rf := range rawFiles {
			fm, ok := rf.(map[string]any)
			if !ok {
				continue
			}
			length := asInt64(fm["length"])
			var parts []string
			if rawPath, ok := fm["path"].([]any); ok {
				for _, seg := range rawPath {
					if s := asString(seg); s != "" {
						parts = append(parts, s)
					}
				}
			}
			rel := torrentName
			name := torrentName
			if len(parts) > 0 {
				rel = strings.Join(parts, "/")
				name = parts[len(parts)-1]
			}
			files = append(files, TorrentFileEntry{
				Name:         name,
				RelativePath: rel,
				SizeBytes:    length,
			})
		}
	} else {
		files = append(files, TorrentFileEntry{
			Name:         torrentName,
			RelativePath: torrentName,
			SizeBytes:    asInt64(info["length"]),
		})
	}

	return &TorrentInfo{
		Source:   sourcePath,
		Name:     torrentName,
		Trackers: trackers,
		Files:    files,
		IsMagnet: false,
	}, nil
}

func asString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []byte:
		return string(t)
	default:
		return ""
	}
}

func asInt64(v any) int64 {
	if i, ok := v.(int64); ok {
		return i
	}
	return 0
}

type bencodeDecoder struct {
	data []byte
	pos  int
}

func (d *bencodeDecoder) decode() (any, error) {
	if d.pos >= len(d.data) {
		return nil, fmt.Errorf("unexpected EOF in bencode")
	}
	switch d.data[d.pos] {
	case 'i':
		return d.decodeInt()
	case 'l':
		return d.decodeList()
	case 'd':
		return d.decodeDict()
	default:
		if d.data[d.pos] >= '0' && d.data[d.pos] <= '9' {
			return d.decodeBytes()
		}
		return nil, fmt.Errorf("invalid bencode token at %d", d.pos)
	}
}

func (d *bencodeDecoder) decodeInt() (int64, error) {
	d.pos++
	start := d.pos
	for d.pos < len(d.data) && d.data[d.pos] != 'e' {
		d.pos++
	}
	if d.pos >= len(d.data) {
		return 0, fmt.Errorf("unterminated bencode int")
	}
	val, err := strconv.ParseInt(string(d.data[start:d.pos]), 10, 64)
	if err != nil {
		return 0, err
	}
	d.pos++
	return val, nil
}

func (d *bencodeDecoder) decodeBytes() ([]byte, error) {
	start := d.pos
	for d.pos < len(d.data) && d.data[d.pos] != ':' {
		d.pos++
	}
	if d.pos >= len(d.data) {
		return nil, fmt.Errorf("unterminated bencode string length")
	}
	length, err := strconv.Atoi(string(d.data[start:d.pos]))
	if err != nil || length < 0 {
		return nil, fmt.Errorf("invalid bencode string length")
	}
	d.pos++
	if d.pos+length > len(d.data) {
		return nil, fmt.Errorf("bencode string out of bounds")
	}
	out := d.data[d.pos : d.pos+length]
	d.pos += length
	return out, nil
}

func (d *bencodeDecoder) decodeList() ([]any, error) {
	d.pos++
	var out []any
	for d.pos < len(d.data) && d.data[d.pos] != 'e' {
		v, err := d.decode()
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	if d.pos >= len(d.data) {
		return nil, fmt.Errorf("unterminated bencode list")
	}
	d.pos++
	return out, nil
}

func (d *bencodeDecoder) decodeDict() (map[string]any, error) {
	d.pos++
	out := make(map[string]any)
	for d.pos < len(d.data) && d.data[d.pos] != 'e' {
		keyBytes, err := d.decodeBytes()
		if err != nil {
			return nil, err
		}
		val, err := d.decode()
		if err != nil {
			return nil, err
		}
		out[string(keyBytes)] = val
	}
	if d.pos >= len(d.data) {
		return nil, fmt.Errorf("unterminated bencode dict")
	}
	d.pos++
	return out, nil
}
