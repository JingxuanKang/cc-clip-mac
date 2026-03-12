#!/bin/bash
# cc-clip-mac: Setup script for macOS remote clipboard support
# Usage: ./setup-remote-mac.sh <ssh-host>
#
# This adapts cc-clip to work with macOS remote hosts (not just Linux).
# It sets up SSH RemoteForward and deploys an osascript shim.

set -e

HOST="${1:-mini}"
PORT="${CC_CLIP_PORT:-18339}"
TOKEN_FILE="$HOME/.cache/cc-clip/session.token"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Step 1: Verify local daemon is running
echo "=== cc-clip macOS Remote Setup for '$HOST' ==="
echo ""

if ! curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    error "Local cc-clip daemon not running. Run: cc-clip serve &"
fi
info "Local daemon running on :${PORT}"

# Step 2: Check token
if [ ! -f "$TOKEN_FILE" ]; then
    error "No session token found at $TOKEN_FILE"
fi
TOKEN=$(head -1 "$TOKEN_FILE")
info "Session token found"

# Step 3: Configure SSH RemoteForward (if not already set)
SSH_CONFIG="$HOME/.ssh/config"
if grep -A10 "Host $HOST" "$SSH_CONFIG" 2>/dev/null | grep -q "RemoteForward.*${PORT}"; then
    info "SSH RemoteForward already configured for $HOST"
else
    warn "Adding RemoteForward to SSH config for $HOST"
    # Use sed to add RemoteForward after the Host line
    if grep -q "Host $HOST" "$SSH_CONFIG" 2>/dev/null; then
        # macOS sed syntax
        sed -i '' "/^Host ${HOST}$/a\\
\\  RemoteForward ${PORT} 127.0.0.1:${PORT}" "$SSH_CONFIG"
        info "Added RemoteForward ${PORT} to existing Host $HOST entry"
    else
        echo "" >> "$SSH_CONFIG"
        echo "Host $HOST" >> "$SSH_CONFIG"
        echo "  RemoteForward ${PORT} 127.0.0.1:${PORT}" >> "$SSH_CONFIG"
        info "Created new Host $HOST entry with RemoteForward"
    fi
fi

# Step 4: Test SSH connection
echo ""
echo "Testing SSH connection to $HOST..."
if ! ssh -o ConnectTimeout=5 "$HOST" "echo 'SSH OK'" 2>/dev/null; then
    error "Cannot SSH to $HOST"
fi
info "SSH connection OK"

# Step 5: Deploy to remote
echo ""
echo "Deploying to remote Mac..."

# Create remote directories
ssh "$HOST" "mkdir -p ~/.local/bin ~/.cache/cc-clip"
info "Created remote directories"

# Sync token
scp -q "$TOKEN_FILE" "$HOST:~/.cache/cc-clip/session.token"
info "Synced session token"

# Deploy osascript shim
scp -q "$SCRIPT_DIR/osascript-shim.sh" "$HOST:~/.local/bin/osascript"
ssh "$HOST" "chmod +x ~/.local/bin/osascript"
info "Deployed osascript shim"

# Step 6: Ensure ~/.local/bin is in PATH on remote
echo ""
echo "Checking remote PATH..."
REMOTE_PATH=$(ssh "$HOST" 'echo $PATH')
if echo "$REMOTE_PATH" | grep -q '.local/bin'; then
    info "~/.local/bin already in remote PATH"
else
    warn "Adding ~/.local/bin to remote PATH"
    ssh "$HOST" 'cat >> ~/.zshrc << '\''EOF'\''

# cc-clip: osascript shim for remote clipboard
export PATH="$HOME/.local/bin:$PATH"
EOF'
    info "Added ~/.local/bin to remote ~/.zshrc"
    warn "You may need to restart your SSH session for PATH changes to take effect"
fi

# Step 7: Verify
echo ""
echo "Verifying setup..."
REMOTE_OSASCRIPT=$(ssh "$HOST" 'which osascript')
if echo "$REMOTE_OSASCRIPT" | grep -q '.local/bin'; then
    info "Remote osascript shim is active: $REMOTE_OSASCRIPT"
else
    warn "Remote osascript resolves to: $REMOTE_OSASCRIPT"
    warn "The shim may not be in PATH yet. Reconnect SSH and verify with 'which osascript'"
fi

# Step 8: Test tunnel
echo ""
echo "Testing clipboard tunnel (connect via SSH with tunnel)..."
TUNNEL_TEST=$(ssh -R ${PORT}:127.0.0.1:${PORT} "$HOST" \
    "curl -sf -m 2 -H 'Authorization: Bearer ${TOKEN}' -H 'User-Agent: cc-clip-shim' http://127.0.0.1:${PORT}/health" 2>/dev/null || true)
if [ -n "$TUNNEL_TEST" ]; then
    info "Clipboard tunnel working!"
else
    warn "Tunnel test failed. This may work once you SSH with the RemoteForward config."
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  1. SSH to your Mac: ssh $HOST"
echo "  2. Start Claude Code: claude"
echo "  3. Copy an image on your local Mac, then Ctrl+V in Claude Code"
echo ""
echo "To uninstall:"
echo "  ssh $HOST 'rm ~/.local/bin/osascript'"
echo "  Remove the RemoteForward line from ~/.ssh/config"
