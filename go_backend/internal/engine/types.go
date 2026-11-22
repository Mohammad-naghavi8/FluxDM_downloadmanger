package engine

type FileInfo struct {
	FileName             string `json:"fileName"`
	FileSize             *int64 `json:"fileSize"`
	FileType             string `json:"fileType"`
	SupportsResume       bool   `json:"supportsResume"`
	Protocol             string `json:"protocol"`
	IsDirectDownload     bool   `json:"isDirectDownload"`
	DirectDownloadReason string `json:"directDownloadReason"`
	ContentType          string `json:"contentType,omitempty"`
}

type ConnectionState struct {
	Number          int    `json:"number"`
	StartByte       int64  `json:"startByte"`
	EndByte         *int64 `json:"endByte,omitempty"`
	DownloadedBytes int64  `json:"downloadedBytes"`
	Info            string `json:"info"`
	IsActive        bool   `json:"isActive"`
	IsCompleted     bool   `json:"isCompleted"`
	HasError        bool   `json:"hasError"`
}

type ProgressEvent struct {
	Type        string            `json:"type"` // progress, reconnecting, rebuilding, completed, paused, stopped, error
	Received    int64             `json:"received"`
	Total       int64             `json:"total"`
	Attempt     int               `json:"attempt,omitempty"`
	Connections []ConnectionState `json:"connections,omitempty"`
	Error       string            `json:"error,omitempty"`
}

type DownloadRequest struct {
	ID                   string `json:"id"`
	URL                  string `json:"url"`
	SavePath             string `json:"savePath"`
	TotalBytes           int64  `json:"totalBytes"`
	ConnectionCount      int    `json:"connectionCount"`
	ResumeExisting       bool   `json:"resumeExisting"`
	InitialOffset        int64  `json:"initialOffset"`
	Segmented            bool   `json:"segmented"`
	SpeedLimitBytesPerSec int64 `json:"speedLimitBytesPerSec"`
	Username             string `json:"username,omitempty"`
	Password             string `json:"password,omitempty"`
	MaxReconnectAttempts int    `json:"maxReconnectAttempts,omitempty"`
}

type SegmentSpec struct {
	Index     int   `json:"index"`
	StartByte int64 `json:"startByte"`
	EndByte   int64 `json:"endByte"`
}

func (s SegmentSpec) Length() int64 {
	return s.EndByte - s.StartByte + 1
}

type SavedStateFile struct {
	URL        string        `json:"url"`
	TotalBytes int64         `json:"totalBytes"`
	Segments   []SegmentSpec `json:"segments"`
}
