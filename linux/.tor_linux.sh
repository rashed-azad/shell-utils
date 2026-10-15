#!/bin/bash
#
# Usage:
#   tor_browser            # fast profile — GPU/WebGL/hw-decode ON
#   tor_browser harden     # anonymity-hardened — GPU/WebGL/hw-decode OFF

eval "CHROMIUM_BIN=$(alias gBrowser 2>/dev/null | cut -d"'" -f2)"

tor_browser() {
    local MODE="${1:-fast}"
    TOR_CONFIG="$HOME/.config/tor-stream/torrc"
    mkdir -p "$(dirname "$TOR_CONFIG")"

    # Only these paths round-trip between the ephemeral profile and this
    # persistent directory — bookmarks and installed extensions. History,
    # cookies, cache, and site storage are never written here, so they
    # never survive past a single session regardless of this list.
    BASE_PROFILE_DIR="$HOME/.config/tor-stream/base-profile"
    PERSIST_PATHS=(
        Bookmarks
        Bookmarks.bak
        Extensions
        "Local Extension Settings"
        Preferences        # extension install/enabled state lives here — without
        "Secure Preferences" # it Chromium won't recognize the Extensions/ folder
    )
    # Note: Preferences also holds small unrelated bits (window size, per-site
    # permission grants). Persisting it is what makes extensions register
    # reliably; if you want to avoid carrying per-site permissions forward too,
    # that would need surgical JSON merging instead of a plain file copy — say
    # so and I'll build that instead.
    cat >"$TOR_CONFIG" <<EOF
# Circuit performance
LearnCircuitBuildTimeout 1

# Padding against traffic analysis
ConnectionPadding 1

# Isolated SOCKS port
SocksPort 9050 IsolateDestAddr
ControlPort 9051
CookieAuthentication 1
CookieAuthFile $HOME/.config/tor-stream/control_auth_cookie

StrictNodes 0
# NOTE: a small ExitNodes allow-list shrinks your anonymity set to "people
# exiting via these countries" instead of "all Tor users." Only exclude
# jurisdictions you actively distrust — that costs you nothing, since Tor's
# global exit pool is large. If you specifically need EU-only exits for
# latency, add them back knowingly:
#   ExitNodes {de},{nl},{se},{ch},{fi},{no}
ExcludeNodes {ru},{cn},{ir},{kp}
# (excludes these countries from every hop — guard, middle, and exit —
# so a separate ExcludeExitNodes line would only repeat the same list)
EOF

    # ── Graceful shutdown ──────────────────────────────────────────────────────
    cleanup() {
        echo "Shutting down..."

        pkill -TERM -f "$PROFILE_DIR" 2>/dev/null
        for i in $(seq 1 10); do
            pgrep -f "$PROFILE_DIR" >/dev/null 2>&1 || break
            sleep 0.5
        done
        pgrep -f "$PROFILE_DIR" >/dev/null 2>&1 &&
            pkill -KILL -f "$PROFILE_DIR" 2>/dev/null

        if kill -0 "$TOR_PID" 2>/dev/null; then
            kill -TERM "$TOR_PID" 2>/dev/null
            wait "$TOR_PID" 2>/dev/null
        fi

        if [[ -n "${PROFILE_DIR:-}" && -d "$PROFILE_DIR/Default" ]]; then
            echo "Saving bookmarks and extensions..."
            mkdir -p "$BASE_PROFILE_DIR/Default"
            for item in "${PERSIST_PATHS[@]}"; do
                if [[ -e "$PROFILE_DIR/Default/$item" ]]; then
                    rm -rf "$BASE_PROFILE_DIR/Default/$item"
                    cp -a "$PROFILE_DIR/Default/$item" "$BASE_PROFILE_DIR/Default/$item"
                fi
            done
        fi

        echo "Wiping session profile..."
        # Everything else (history, cookies, cache, site storage) was never
        # copied into BASE_PROFILE_DIR above, so it dies here for good.
        rm -rf "$PROFILE_DIR"

        echo "Done."
        trap - INT TERM
    }

    trap cleanup INT TERM

    # ── Start Tor ──────────────────────────────────────────────────────────────
    echo "Starting Tor..."
    tor -f "$TOR_CONFIG" &
    TOR_PID=$!
    echo "$TOR_PID" > "$HOME/.config/tor-stream/tor.pid"

    echo "Waiting for Tor to be ready..."
    until nc -z 127.0.0.1 9050 2>/dev/null; do
        if ! kill -0 "$TOR_PID" 2>/dev/null; then
            echo "Tor failed to start. Exiting."
            trap - INT TERM
            return 1
        fi
        sleep 0.5
    done
    echo "Tor is ready."

    # Fresh, disposable profile every launch — zero session state (history,
    # cookies, cache) carries between launches or across a tor_newid.
    # tmpfs (/dev/shm) keeps cache/cookies/IndexedDB in RAM instead of on
    # disk — faster, and nothing to wipe from disk because nothing was
    # written there. Falls back to normal disk temp storage if /dev/shm
    # is missing or not writable (e.g. some containers).
    PROFILE_DIR=$(mktemp -d -p /dev/shm 2>/dev/null) || PROFILE_DIR=$(mktemp -d)
    mkdir -p "$PROFILE_DIR/Default"

    if [[ -d "$BASE_PROFILE_DIR/Default" ]]; then
        for item in "${PERSIST_PATHS[@]}"; do
            [[ -e "$BASE_PROFILE_DIR/Default/$item" ]] &&
                cp -a "$BASE_PROFILE_DIR/Default/$item" "$PROFILE_DIR/Default/$item"
        done
    fi

    # ── Mode-dependent rendering flags ──────────────────────────────────────────
    # This is the one real trade-off: GPU rasterization, ANGLE, and hardware
    # video decode/encode expose your exact GPU model via WEBGL_debug_renderer_info
    # and shift your canvas/WebGL output signature — a stable, device-unique
    # fingerprint that survives Tor circuit rotation entirely. "fast" keeps them
    # for speed; "harden" drops them because this is the actual anti-tracking lever.
    local RENDER_FLAGS
    if [[ "$MODE" == "harden" ]]; then
        echo "Mode: harden (GPU accel / WebGL / hw video decode disabled)"
        RENDER_FLAGS=(
            --disable-webgl
            --disable-webgl2
            --disable-accelerated-video-decode
            --disable-accelerated-video-encode
            --disable-gpu-rasterization
        )
    else
        echo "Mode: fast (GPU accel on — more performant, more fingerprintable)"
        RENDER_FLAGS=(
            --enable-accelerated-video-decode
            --enable-accelerated-video-encode
            --enable-gpu-rasterization
            --enable-zero-copy
            --ignore-gpu-blocklist
            --enable-native-gpu-memory-buffers
            --use-gl=angle
            --use-angle=gl
            --num-raster-threads=4
        )
    fi

    # ── Flag groups ──────────────────────────────────────────────────────────
    # One flag per line, no trailing backslash: adding, removing, or editing a
    # single flag now changes exactly one line, so `git diff` shows just that
    # line instead of a hunk of backslash-continuation context around it.
    # Values and order are unchanged from before — this is formatting only.

    local PROXY_FLAGS=(
        --proxy-server="socks5://127.0.0.1:9050"
        --proxy-bypass-list="<-loopback>"
        --disable-quic
        --dns-prefetch-disable
        --no-pings
        --webrtc-ip-handling-policy=disable_non_proxied_udp
    )

    local FINGERPRINT_FLAGS=(
        --lang=en-US
        --accept-lang=en-US,en
        --http-accept-header="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    )

    local PROFILE_FLAGS=(
        --user-data-dir="$PROFILE_DIR"
        --incognito
        --no-first-run
        --no-default-browser-check
        --disable-sync
    )

    local PRIVACY_FLAGS=(
        --disable-client-side-phishing-detection
        --metrics-recording-only
        --safebrowsing-disable-auto-update
    )

    local BACKGROUND_FLAGS=(
        --disable-background-networking
        --disable-default-apps
        --disable-hang-monitor
        --disable-prompt-on-repost
    )

    local UI_FLAGS=(
        --disable-translate
        --disable-infobars
        --window-size=1280,800
    )

    local FEATURE_FLAGS=(
        --enable-features=BlockInsecurePrivateNetworkRequests
        --disable-features=NetworkPrediction,Prerender2,PreloadMediaEngagementData
    )

    # ── Launch Ungoogled Chromium ──────────────────────────────────────────────
    echo "Launching Chromium..."

    TZ=UTC "$CHROMIUM_BIN" \
        "${PROXY_FLAGS[@]}" \
        "${FINGERPRINT_FLAGS[@]}" \
        "${PROFILE_FLAGS[@]}" \
        "${PRIVACY_FLAGS[@]}" \
        "${BACKGROUND_FLAGS[@]}" \
        "${UI_FLAGS[@]}" \
        "${RENDER_FLAGS[@]}" \
        "${FEATURE_FLAGS[@]}" \
        "https://check.torproject.org/" &

    echo "Chromium launched (profile: $PROFILE_DIR). Press Ctrl+C to quit."

    # Wait here until Ctrl+C triggers cleanup
    wait
}

# ── dl ────────────────────────────────────────────────────────────────────────
# Unchanged from the original — downloads via yt-dlp routed through Tor's
# SOCKS5 proxy on 127.0.0.1:9050.
#
# Usage:
#   dl "output filename" "url"
# ─────────────────────────────────────────────────────────────────────────────
dl() {
    if [[ -z "$1" || -z "$2" ]]; then
        echo "Usage: dl \"output filename\" \"url\""
        return 1
    fi

    yt-dlp \
        --socket-timeout 120 \
        --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36" \
        --add-headers "Accept-Language:en-US,en;q=0.9" \
        --add-headers "Accept:*/*" \
        --proxy socks5://127.0.0.1:9050 \
        --concurrent-fragments 16 \
        --progress \
        --newline \
        --continue \
        --verbose \
        -o "$1" "$2"
}

# tor_newid
# Rotates your Tor *circuit* (new exit IP) via NEWNYM.
#
# IMPORTANT: this does not touch open tabs, cookies, or localStorage. If a
# site already fingerprinted you or set a cookie before you call this, a new
# IP changes nothing — it can still correlate old-session-you with
# new-IP-you through the browser state that's still sitting open. For an
# actual new identity, close the browser and re-run tor_browser (fresh
# profile + fresh circuit) rather than rotating mid-session.
#
# Usage: tor_newid
tor_newid() {
    local cookie_path="$HOME/.config/tor-stream/control_auth_cookie"

    if [[ -f "$cookie_path" ]]; then
        local hex_cookie
        hex_cookie=$(xxd -p "$cookie_path" | tr -d '\n')
        printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$hex_cookie" \
            | nc 127.0.0.1 9051
    else
        printf 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT\r\n' \
            | nc 127.0.0.1 9051
    fi

    echo "New Tor circuit requested. For a real new identity, restart tor_browser instead of just reloading."
}

# tor_rotate
# Recovery tool — reloads Tor config, opens the control port, and verifies
# identity rotation worked by comparing IPs before and after.
#
# Usage: tor_rotate
tor_rotate() {
    local pid_file="$HOME/.config/tor-stream/tor.pid"

    if [[ ! -f "$pid_file" ]]; then
        echo "Tor PID file not found. Is tor_browser running?"
        return 1
    fi

    local tor_pid
    tor_pid=$(cat "$pid_file")

    echo "Reloading Tor config (PID $tor_pid)..."
    kill -HUP "$tor_pid"

    sleep 1

    if ! nc -z 127.0.0.1 9051 2>/dev/null; then
        echo "Control port still closed. Check your torrc has ControlPort 9051."
        return 1
    fi
    echo "Control port open."

    printf "Current IP: "
    curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip && echo

    echo "Rotating identity..."
    tor_newid

    sleep 1

    printf "New IP:     "
    curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip && echo
}