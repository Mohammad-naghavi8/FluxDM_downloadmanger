package engine

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type ExtractResult struct {
	ExtractedTo string `json:"extractedTo"`
	FileCount   int    `json:"fileCount"`
}

// ExtractArchive extracts .zip, .tar, .tar.gz, and .tgz archives safely in Go.
func ExtractArchive(archivePath string, targetMode string) (*ExtractResult, error) {
	lower := strings.ToLower(strings.TrimSpace(archivePath))
	if lower == "" {
		return nil, fmt.Errorf("archive path is empty")
	}
	if _, err := os.Stat(archivePath); err != nil {
		return nil, err
	}

	parentDir := filepath.Dir(archivePath)
	baseName := filepath.Base(archivePath)
	folderName := stripArchiveExtension(baseName)
	namedFolder := filepath.Join(parentDir, folderName)

	alwaysFolder := strings.Contains(strings.ToLower(targetMode), "always")
	directNext := strings.Contains(strings.ToLower(targetMode), "directly")

	switch {
	case strings.HasSuffix(lower, ".zip"):
		return extractZip(archivePath, parentDir, namedFolder, alwaysFolder, directNext)
	case strings.HasSuffix(lower, ".tar.gz") || strings.HasSuffix(lower, ".tgz"):
		return extractTarGz(archivePath, parentDir, namedFolder, alwaysFolder, directNext)
	case strings.HasSuffix(lower, ".tar"):
		return extractTarFile(archivePath, parentDir, namedFolder, alwaysFolder, directNext)
	default:
		return nil, fmt.Errorf("unsupported archive format: %s", filepath.Ext(archivePath))
	}
}

func stripArchiveExtension(name string) string {
	low := strings.ToLower(name)
	for _, ext := range []string{".tar.gz", ".tgz", ".zip", ".tar"} {
		if strings.HasSuffix(low, ext) {
			return name[:len(name)-len(ext)]
		}
	}
	return name
}

func safeJoin(destDir, entryName string) (string, error) {
	cleanDest := filepath.Clean(destDir)
	target := filepath.Clean(filepath.Join(cleanDest, entryName))
	prefix := cleanDest + string(os.PathSeparator)
	if target != cleanDest && !strings.HasPrefix(target, prefix) {
		return "", fmt.Errorf("illegal archive entry path: %s", entryName)
	}
	return target, nil
}

func extractZip(archivePath, parentDir, namedFolder string, alwaysFolder, directNext bool) (*ExtractResult, error) {
	r, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, err
	}
	defer r.Close()

	destDir := parentDir
	if alwaysFolder || (!directNext && len(r.File) > 1) {
		destDir = namedFolder
	}
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return nil, err
	}

	count := 0
	bufPtr := ioBufPool.Get().(*[]byte)
	defer ioBufPool.Put(bufPtr)
	buf := *bufPtr

	for _, f := range r.File {
		target, err := safeJoin(destDir, f.Name)
		if err != nil {
			return nil, err
		}
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return nil, err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return nil, err
		}
		rc, err := f.Open()
		if err != nil {
			return nil, err
		}
		out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
		if err != nil {
			_ = rc.Close()
			return nil, err
		}
		_, copyErr := io.CopyBuffer(out, rc, buf)
		_ = out.Close()
		_ = rc.Close()
		if copyErr != nil {
			return nil, copyErr
		}
		count++
	}
	return &ExtractResult{ExtractedTo: destDir, FileCount: count}, nil
}

func extractTarGz(archivePath, parentDir, namedFolder string, alwaysFolder, directNext bool) (*ExtractResult, error) {
	f, err := os.Open(archivePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	destDir := namedFolder
	if directNext {
		destDir = parentDir
	}
	return extractTarStream(tar.NewReader(gz), destDir)
}

func extractTarFile(archivePath, parentDir, namedFolder string, alwaysFolder, directNext bool) (*ExtractResult, error) {
	f, err := os.Open(archivePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	destDir := namedFolder
	if directNext {
		destDir = parentDir
	}
	return extractTarStream(tar.NewReader(f), destDir)
}

func extractTarStream(tr *tar.Reader, destDir string) (*ExtractResult, error) {
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return nil, err
	}
	count := 0
	bufPtr := ioBufPool.Get().(*[]byte)
	defer ioBufPool.Put(bufPtr)
	buf := *bufPtr

	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		target, err := safeJoin(destDir, hdr.Name)
		if err != nil {
			return nil, err
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return nil, err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return nil, err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
			if err != nil {
				return nil, err
			}
			_, copyErr := io.CopyBuffer(out, tr, buf)
			_ = out.Close()
			if copyErr != nil {
				return nil, copyErr
			}
			count++
		}
	}
	return &ExtractResult{ExtractedTo: destDir, FileCount: count}, nil
}
