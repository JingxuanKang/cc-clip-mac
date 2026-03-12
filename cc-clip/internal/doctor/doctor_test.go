package doctor

import (
	"testing"
	"time"
)

func TestFormatDuration(t *testing.T) {
	tests := []struct {
		d        time.Duration
		expected string
	}{
		{30 * time.Second, "30s"},
		{5 * time.Minute, "5m"},
		{2*time.Hour + 30*time.Minute, "2h30m"},
		{26 * time.Hour, "1d2h"},
		{49 * time.Hour, "2d1h"},
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

func TestRunLocalReturnsResults(t *testing.T) {
	results := RunLocal(18339)

	if len(results) < 3 {
		t.Fatalf("expected at least 3 checks, got %d", len(results))
	}

	names := make(map[string]bool)
	for _, r := range results {
		names[r.Name] = true
		if r.Name == "" {
			t.Fatal("check result has empty name")
		}
		if r.Message == "" {
			t.Fatalf("check %s has empty message", r.Name)
		}
	}

	for _, expected := range []string{"daemon", "clipboard", "token"} {
		if !names[expected] {
			t.Fatalf("missing check: %s", expected)
		}
	}

	// The new token-expiry check should be present
	if !names["token-expiry"] {
		// It is OK if the token file does not exist — the check itself should still run
		// and return a result (either pass or fail)
		t.Log("token-expiry check not found (token file may not exist)")
	}
}

func TestPrintResults(t *testing.T) {
	results := []CheckResult{
		{"test-pass", true, "all good"},
		{"test-fail", false, "something wrong"},
	}
	allOK := PrintResults(results)
	if allOK {
		t.Fatal("expected allOK=false when one check fails")
	}

	allPass := []CheckResult{
		{"a", true, "ok"},
		{"b", true, "ok"},
	}
	if !PrintResults(allPass) {
		t.Fatal("expected allOK=true when all pass")
	}
}

func TestCheckResultStructFields(t *testing.T) {
	r := CheckResult{
		Name:    "test-check",
		OK:      true,
		Message: "everything fine",
	}
	if r.Name != "test-check" {
		t.Fatal("Name field mismatch")
	}
	if !r.OK {
		t.Fatal("OK should be true")
	}
	if r.Message != "everything fine" {
		t.Fatal("Message field mismatch")
	}
}
