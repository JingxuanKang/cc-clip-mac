package doctor

import (
	"testing"
	"time"

	"github.com/shunmei/cc-clip/internal/token"
)

func TestCheckTokenExpiryReturnsResult(t *testing.T) {
	// checkTokenExpiry should always return a result (pass or fail)
	results := checkTokenExpiry()
	if len(results) != 1 {
		t.Fatalf("expected exactly 1 result, got %d", len(results))
	}
	if results[0].Name != "token-expiry" {
		t.Fatalf("expected name 'token-expiry', got %q", results[0].Name)
	}
	if results[0].Message == "" {
		t.Fatal("expected non-empty message")
	}
}

func TestCheckTokenExpiryUsesStoredExpiry(t *testing.T) {
	tmpDir := t.TempDir()
	token.TokenDirOverride = tmpDir
	defer func() { token.TokenDirOverride = "" }()

	// Write a token that expires in 6 hours
	_, err := token.WriteTokenFile("test-token", time.Now().Add(6*time.Hour))
	if err != nil {
		t.Fatalf("WriteTokenFile: %v", err)
	}

	results := checkTokenExpiry()
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if !results[0].OK {
		t.Fatalf("expected OK for valid token, got FAIL: %s", results[0].Message)
	}
}

func TestCheckTokenExpiryDetectsExpired(t *testing.T) {
	tmpDir := t.TempDir()
	token.TokenDirOverride = tmpDir
	defer func() { token.TokenDirOverride = "" }()

	// Write a token that expired 1 hour ago
	_, err := token.WriteTokenFile("test-token", time.Now().Add(-1*time.Hour))
	if err != nil {
		t.Fatalf("WriteTokenFile: %v", err)
	}

	results := checkTokenExpiry()
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].OK {
		t.Fatalf("expected FAIL for expired token, got OK: %s", results[0].Message)
	}
}

func TestFormatDurationLocal(t *testing.T) {
	tests := []struct {
		d        time.Duration
		expected string
	}{
		{10 * time.Second, "10s"},
		{90 * time.Second, "1m"},
		{65 * time.Minute, "1h5m"},
		{25 * time.Hour, "1d1h"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			result := formatDuration(tt.d)
			if result != tt.expected {
				t.Fatalf("formatDuration(%v) = %q, want %q", tt.d, result, tt.expected)
			}
		})
	}
}
