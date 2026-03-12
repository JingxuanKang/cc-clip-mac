#!/bin/bash
# osascript shim for cc-clip macOS remote support
# Intercepts clipboard image reads, fetches from SSH tunnel, sets remote clipboard,
# then delegates to real osascript.

REAL_OSASCRIPT=/usr/bin/osascript
CC_CLIP_PORT="${CC_CLIP_PORT:-18339}"
TOKEN_FILE="$HOME/.cache/cc-clip/session.token"
TMP_IMG="/tmp/cc-clip-paste.png"

# Join all arguments into a single string for pattern matching
ALL_ARGS="$*"

# Only intercept clipboard image reads (PNGf class = PNG image from clipboard)
if echo "$ALL_ARGS" | grep -q 'PNGf\|class png\|clipboard.*image\|clipboard as.*class'; then
    TOKEN=$(head -1 "$TOKEN_FILE" 2>/dev/null)
    if [ -n "$TOKEN" ]; then
        # Check if tunnel has an image
        CURL_HEADERS=(-H "Authorization: Bearer $TOKEN" -H "User-Agent: cc-clip-shim")
        TYPE=$(curl -sf -m 2 "${CURL_HEADERS[@]}" "http://127.0.0.1:${CC_CLIP_PORT}/clipboard/type" 2>/dev/null)
        if echo "$TYPE" | grep -qi "image"; then
            # Fetch image from local Mac's clipboard via tunnel
            curl -sf -m 5 "${CURL_HEADERS[@]}" \
                "http://127.0.0.1:${CC_CLIP_PORT}/clipboard/image" \
                -o "$TMP_IMG" 2>/dev/null
            if [ -f "$TMP_IMG" ] && [ -s "$TMP_IMG" ]; then
                # Set the remote Mac's clipboard to the fetched image
                $REAL_OSASCRIPT -e "set the clipboard to (read POSIX file \"$TMP_IMG\" as «class PNGf»)" 2>/dev/null
            fi
        fi
    fi
fi

# Always delegate to real osascript with original arguments
exec $REAL_OSASCRIPT "$@"
