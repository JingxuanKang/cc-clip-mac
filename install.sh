#!/bin/bash
# cc-clip-mac installer
# Usage: ./install.sh <ssh-host>
#
# Must be run from the cloned repo directory (needs bin/ and osascript-shim.sh).

set -e

HOST="$1"
if [ -z "$HOST" ]; then
    echo "Usage: $0 <ssh-host>"
    echo "  ssh-host: the Host name from your ~/.ssh/config (e.g. mini)"
    exit 1
fi

PORT="${CC_CLIP_PORT:-18339}"
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}[$1/$TOTAL_STEPS]${NC} $2"; }

TOTAL_STEPS=6

# ─── Detect platform ───

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) error "Unsupported architecture: $arch" ;;
    esac
}

# ─── Verify repo structure ───

[ -f "$SCRIPT_DIR/osascript-shim.sh" ] || error "osascript-shim.sh not found. Run this script from the cloned repo directory."
[ -d "$SCRIPT_DIR/bin" ] || error "bin/ directory not found. Run this script from the cloned repo directory."

# ─── Step 1: Install cc-clip (local clipboard daemon) ───

step 1 "Installing local clipboard daemon..."

if command -v cc-clip >/dev/null 2>&1; then
    info "cc-clip already installed: $(which cc-clip)"
else
    ARCH=$(detect_arch)
    BINARY="$SCRIPT_DIR/bin/cc-clip-darwin-${ARCH}"
    [ -f "$BINARY" ] || error "Binary not found: $BINARY"

    mkdir -p "$INSTALL_DIR"
    cp "$BINARY" "$INSTALL_DIR/cc-clip"
    chmod +x "$INSTALL_DIR/cc-clip"

    # macOS: remove quarantine and sign
    xattr -d com.apple.quarantine "$INSTALL_DIR/cc-clip" 2>/dev/null || true
    codesign -s - "$INSTALL_DIR/cc-clip" 2>/dev/null || true

    info "cc-clip installed to $INSTALL_DIR/cc-clip"
fi

# Ensure PATH includes ~/.local/bin
export PATH="$INSTALL_DIR:$PATH"

# Install pngpaste if missing
if ! command -v pngpaste >/dev/null 2>&1; then
    echo "  Installing pngpaste via Homebrew..."
    brew install pngpaste || error "Failed to install pngpaste. Install Homebrew first: https://brew.sh"
    info "pngpaste installed"
else
    info "pngpaste available"
fi

# ─── Step 2: Start local daemon ───

step 2 "Starting local clipboard daemon..."

if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    info "Daemon already running on :${PORT}"
else
    cc-clip service install 2>/dev/null || cc-clip serve --port "$PORT" &
    sleep 1
    if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        info "Daemon started on :${PORT}"
    else
        error "Failed to start daemon"
    fi
fi

# Verify token
TOKEN_FILE="$HOME/.cache/cc-clip/session.token"
if [ ! -f "$TOKEN_FILE" ]; then
    error "No session token found. Daemon may not have started properly."
fi
TOKEN=$(head -1 "$TOKEN_FILE")
info "Session token ready"

# ─── Step 3: Configure SSH ───

step 3 "Configuring SSH tunnel for '$HOST'..."

SSH_CONFIG="$HOME/.ssh/config"
if grep -A10 "Host $HOST" "$SSH_CONFIG" 2>/dev/null | grep -q "RemoteForward.*${PORT}"; then
    info "RemoteForward already configured"
else
    if grep -q "^Host ${HOST}$" "$SSH_CONFIG" 2>/dev/null; then
        sed -i '' "/^Host ${HOST}$/a\\
\\  RemoteForward ${PORT} 127.0.0.1:${PORT}" "$SSH_CONFIG"
        info "Added RemoteForward to existing Host $HOST"
    else
        echo "" >> "$SSH_CONFIG"
        echo "Host $HOST" >> "$SSH_CONFIG"
        echo "  RemoteForward ${PORT} 127.0.0.1:${PORT}" >> "$SSH_CONFIG"
        info "Created Host $HOST with RemoteForward"
    fi
fi

# ─── Step 4: Test SSH ───

step 4 "Testing SSH connection to '$HOST'..."

if ! ssh -o ConnectTimeout=10 "$HOST" "echo ok" >/dev/null 2>&1; then
    error "Cannot SSH to $HOST. Make sure Host '$HOST' is configured in ~/.ssh/config"
fi
info "SSH connection OK"

# Verify remote is macOS
REMOTE_OS=$(ssh "$HOST" "uname -s" 2>/dev/null)
if [ "$REMOTE_OS" != "Darwin" ]; then
    error "Remote host is $REMOTE_OS, not macOS. For Linux remote, use: cc-clip setup $HOST"
fi
info "Remote is macOS"

# ─── Step 5: Deploy to remote ───

step 5 "Deploying osascript shim to remote..."

ssh "$HOST" "mkdir -p ~/.local/bin ~/.cache/cc-clip"

# Sync token
scp -q "$TOKEN_FILE" "$HOST:~/.cache/cc-clip/session.token"
info "Token synced"

# Deploy shim
scp -q "$SCRIPT_DIR/osascript-shim.sh" "$HOST:~/.local/bin/osascript"
ssh "$HOST" "chmod +x ~/.local/bin/osascript"
info "osascript shim deployed"

# Ensure remote PATH
REMOTE_PATH=$(ssh "$HOST" 'echo $PATH')
if echo "$REMOTE_PATH" | grep -q '.local/bin'; then
    info "~/.local/bin in remote PATH"
else
    ssh "$HOST" 'cat >> ~/.zshrc << '\''EOF'\''

# cc-clip-mac: osascript shim for remote clipboard
export PATH="$HOME/.local/bin:$PATH"
EOF'
    info "Added ~/.local/bin to remote ~/.zshrc"
    warn "Restart SSH session for PATH to take effect"
fi

# ─── Step 6: Verify ───

step 6 "Verifying..."

TUNNEL_TEST=$(ssh -R ${PORT}:127.0.0.1:${PORT} "$HOST" \
    "curl -sf -m 3 -H 'Authorization: Bearer ${TOKEN}' -H 'User-Agent: cc-clip-shim' http://127.0.0.1:${PORT}/health" 2>/dev/null || true)
if [ -n "$TUNNEL_TEST" ]; then
    info "Clipboard tunnel working!"
else
    warn "Tunnel test inconclusive (may work after reconnecting SSH)"
fi

REMOTE_WHICH=$(ssh "$HOST" 'source ~/.zshrc 2>/dev/null; which osascript' 2>/dev/null)
if echo "$REMOTE_WHICH" | grep -q '.local/bin'; then
    info "osascript shim active: $REMOTE_WHICH"
else
    warn "Shim at ~/.local/bin/osascript — reconnect SSH for it to take priority"
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Usage:"
echo "  ssh $HOST"
echo "  claude"
echo "  # Copy an image on your local Mac, Ctrl+V in Claude Code"
echo ""
echo "Uninstall:"
echo "  ssh $HOST 'rm ~/.local/bin/osascript'"
echo "  # Remove RemoteForward line from ~/.ssh/config"
