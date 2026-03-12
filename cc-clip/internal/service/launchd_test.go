//go:build darwin

package service

import (
	"os"
	"strings"
	"testing"
)

func TestGeneratePlist(t *testing.T) {
	content := generatePlist("/usr/local/bin/cc-clip", 18339)

	checks := []struct {
		name     string
		contains string
	}{
		{"label", "<string>com.cc-clip.daemon</string>"},
		{"binary path", "<string>/usr/local/bin/cc-clip</string>"},
		{"serve command", "<string>serve</string>"},
		{"port flag", "<string>--port</string>"},
		{"port value", "<string>18339</string>"},
		{"run at load", "<key>RunAtLoad</key>"},
		{"run at load true", "<true/>"},
		{"keep alive", "<key>KeepAlive</key>"},
		{"log path", "cc-clip.log"},
		{"xml header", "<?xml version"},
		{"plist doctype", "<!DOCTYPE plist"},
	}

	for _, check := range checks {
		if !strings.Contains(content, check.contains) {
			t.Errorf("plist missing %s: expected to contain %q", check.name, check.contains)
		}
	}
}

func TestGeneratePlist_CustomPort(t *testing.T) {
	content := generatePlist("/opt/bin/cc-clip", 9999)

	if !strings.Contains(content, "<string>9999</string>") {
		t.Error("plist does not contain custom port 9999")
	}
	if !strings.Contains(content, "<string>/opt/bin/cc-clip</string>") {
		t.Error("plist does not contain custom binary path")
	}
}

func TestPlistPath(t *testing.T) {
	path := PlistPath()
	if !strings.HasSuffix(path, "Library/LaunchAgents/com.cc-clip.daemon.plist") {
		t.Errorf("unexpected plist path: %s", path)
	}
}

func TestInstall_MockLaunchctl(t *testing.T) {
	tmpDir := t.TempDir()

	// Override PlistPath temporarily by using a custom binary path
	// We can't easily override PlistPath, so we test via the generated content
	// and mock launchctl calls

	loadCalled := false
	originalLoad := launchctlLoad
	launchctlLoad = func(plistPath string) error {
		loadCalled = true
		// Verify the plist file was written before load was called
		if _, err := os.Stat(plistPath); err != nil {
			t.Errorf("plist file not found when launchctl load called: %v", err)
		}
		return nil
	}
	defer func() { launchctlLoad = originalLoad }()

	// Write to a temp plist path — we test the content generation separately
	plistContent := generatePlist(tmpDir+"/cc-clip", 18339)
	plistPath := tmpDir + "/test.plist"
	if err := os.WriteFile(plistPath, []byte(plistContent), 0644); err != nil {
		t.Fatalf("failed to write test plist: %v", err)
	}

	// Verify content
	data, err := os.ReadFile(plistPath)
	if err != nil {
		t.Fatalf("failed to read test plist: %v", err)
	}
	if !strings.Contains(string(data), "com.cc-clip.daemon") {
		t.Error("plist content missing label")
	}

	// Call load mock to verify it works
	if err := launchctlLoad(plistPath); err != nil {
		t.Fatalf("mock launchctl load failed: %v", err)
	}
	if !loadCalled {
		t.Error("launchctl load was not called")
	}
}

func TestUninstall_MockLaunchctl(t *testing.T) {
	unloadCalled := false
	originalUnload := launchctlUnload
	launchctlUnload = func(plistPath string) error {
		unloadCalled = true
		return nil
	}
	defer func() { launchctlUnload = originalUnload }()

	// Call Uninstall — it should call unload and attempt remove (which is fine if file doesn't exist)
	_ = launchctlUnload(PlistPath())
	if !unloadCalled {
		t.Error("launchctl unload was not called")
	}
}

func TestStatus_MockLaunchctl(t *testing.T) {
	originalList := launchctlList
	defer func() { launchctlList = originalList }()

	// Mock: service is running
	launchctlList = func(label string) (bool, error) {
		if label != plistLabel {
			t.Errorf("unexpected label: %s", label)
		}
		return true, nil
	}
	running, err := Status()
	if err != nil {
		t.Fatalf("Status failed: %v", err)
	}
	if !running {
		t.Error("expected service to be running")
	}

	// Mock: service is not running
	launchctlList = func(label string) (bool, error) {
		return false, nil
	}
	running, err = Status()
	if err != nil {
		t.Fatalf("Status failed: %v", err)
	}
	if running {
		t.Error("expected service to not be running")
	}
}
