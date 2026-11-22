package engine

import (
	"context"
	"sync"
	"sync/atomic"
	"time"
)

type SpeedLimiter struct {
	limitBps atomic.Int64

	mu            sync.Mutex
	windowStart   time.Time
	bytesInWindow int64
}

func NewSpeedLimiter(bytesPerSecond int64) *SpeedLimiter {
	l := &SpeedLimiter{
		windowStart: time.Now(),
	}
	l.limitBps.Store(bytesPerSecond)
	return l
}

func (l *SpeedLimiter) SetLimit(bytesPerSecond int64) {
	if bytesPerSecond < 0 {
		bytesPerSecond = 0
	}
	l.limitBps.Store(bytesPerSecond)
}

func (l *SpeedLimiter) Limit() int64 {
	return l.limitBps.Load()
}

func (l *SpeedLimiter) Throttle(ctx context.Context, n int64) error {
	maxBps := l.limitBps.Load()
	if maxBps <= 0 || n <= 0 {
		return nil
	}

	l.mu.Lock()
	now := time.Now()
	if now.Sub(l.windowStart) >= time.Second {
		l.windowStart = now
		l.bytesInWindow = 0
	}
	l.bytesInWindow += n
	expected := time.Duration(l.bytesInWindow*int64(time.Second)) / time.Duration(maxBps)
	elapsed := now.Sub(l.windowStart)
	wait := expected - elapsed
	l.mu.Unlock()

	if wait <= 10*time.Millisecond {
		return nil
	}
	if wait > time.Second {
		wait = time.Second
	}

	timer := time.NewTimer(wait)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func CancellableSleep(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return nil
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
