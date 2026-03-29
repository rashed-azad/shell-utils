#!/bin/bash

tor_browser() {
    TOR_CONFIG="$HOME/.config/tor-stream/torrc"
    mkdir -p "$(dirname "$TOR_CONFIG")"
    cat >"$TOR_CONFIG" <<'EOF'
# Circuit performance
NumEntryGuards 4
NumDirectoryGuards 3
GuardLifetime 2 months
MaxCircuitDirtiness 300
NewCircuitPeriod 60
CircuitBuildTimeout 10
LearnCircuitBuildTimeout 1

# Stability — rotate away from slow circuits quickly
MaxClientCircuitsPending 32
CircuitStreamTimeout 15
SocksTimeout 15
ConnectionPadding 1

# Bandwidth (0 = unlimited)
RelayBandwidthRate 0
RelayBandwidthBurst 0
PerConnBWRate 0
PerConnBWBurst 0

# Scheduler tuning
KISTSchedRunInterval 10

# Isolated SOCKS port
SocksPort 9050 IsolateDestAddr IsolateDestPort

# Pin to stable high-bandwidth exits
StrictNodes 0
ExitNodes {de},{nl},{se},{ch},{fi},{no}
ExcludeNodes {ru},{cn},{ir},{kp}
ExcludeExitNodes {ru},{cn},{ir},{kp}
EOF

    # ── Graceful shutdown ──────────────────────────────────────────────────────
    cleanup() {
        echo "Shutting down..."

        pkill -TERM -f "chromium-tor-profile" 2>/dev/null
        for i in $(seq 1 10); do
            pgrep -f "chromium-tor-profile" >/dev/null 2>&1 || break
            sleep 0.5
        done
        pgrep -f "chromium-tor-profile" >/dev/null 2>&1 &&
            pkill -KILL -f "chromium-tor-profile" 2>/dev/null

        if kill -0 "$TOR_PID" 2>/dev/null; then
            kill -TERM "$TOR_PID" 2>/dev/null
            wait "$TOR_PID" 2>/dev/null
        fi

        echo "Wiping session data..."

        # Visited sites and search queries
        rm -rf \
            "$HOME/.config/chromium-tor-profile/Default/History" \
            "$HOME/.config/chromium-tor-profile/Default/History-journal" \
            "$HOME/.config/chromium-tor-profile/Default/Visited Links" \
            "$HOME/.config/chromium-tor-profile/Default/Favicons" \
            "$HOME/.config/chromium-tor-profile/Default/Favicons-journal"

        # Network-level state
        rm -rf \
            "$HOME/.config/chromium-tor-profile/Default/Network Action Predictor" \
            "$HOME/.config/chromium-tor-profile/Default/Network Persistent State" \
            "$HOME/.config/chromium-tor-profile/Default/TransportSecurity"

        # Site permissions and download history
        rm -rf \
            "$HOME/.config/chromium-tor-profile/Default/Site Characteristics Database" \
            "$HOME/.config/chromium-tor-profile/Default/Download Service"

        # WebRTC and fingerprinting
        rm -rf \
            "$HOME/.config/chromium-tor-profile/Default/WebRTC Logs" \
            "$HOME/.config/chromium-tor-profile/Default/Feature Engagement Tracker" \
            "$HOME/.config/chromium-tor-profile/Default/Segmentation Platform" \
            "$HOME/.config/chromium-tor-profile/Default/Shared Dictionary"

        # Cache and GPU
        rm -rf \
            "$HOME/.config/chromium-tor-profile/Default/Cache" \
            "$HOME/.config/chromium-tor-profile/Default/Code Cache" \
            "$HOME/.config/chromium-tor-profile/Default/GPUCache" \
            "$HOME/.config/chromium-tor-profile/Default/IndexedDB" \
            "$HOME/.config/chromium-tor-profile/Default/Local Storage" \
            "$HOME/.config/chromium-tor-profile/Default/Session Storage" \
            "$HOME/.config/chromium-tor-profile/Default/Sessions" \
            "$HOME/.config/chromium-tor-profile/Default/Service Worker/CacheStorage" \
            "$HOME/.config/chromium-tor-profile/Default/blob_storage" \
            "$HOME/.config/chromium-tor-profile/Default/VideoDecodeStats" \
            "$HOME/.config/chromium-tor-profile/Default/WebrtcVideoStats" \
            "$HOME/.config/chromium-tor-profile/GrShaderCache" \
            "$HOME/.config/chromium-tor-profile/ShaderCache" \
            "$HOME/.config/chromium-tor-profile/GraphiteDawnCache"

        echo "Done."
        trap - INT TERM
    }

    trap cleanup INT TERM

    # ── Start Tor ──────────────────────────────────────────────────────────────
    echo "Starting Tor..."
    tor -f "$TOR_CONFIG" &
    TOR_PID=$!

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

    # ── Launch Ungoogled Chromium ──────────────────────────────────────────────
    echo "Launching Chromium..."
    /Applications/Chromium.app/Contents/MacOS/Chromium \
        \
        `# ── Proxy / network ──────────────────────────────────` \
        --proxy-server="socks5://127.0.0.1:9050" \
        --proxy-bypass-list="<-loopback>" \
        --disable-quic \
        --dns-prefetch-disable \
        --no-pings \
        \
        `# ── Profile / session ────────────────────────────────` \
        --user-data-dir="$HOME/.config/chromium-tor-profile" \
        --incognito \
        --no-first-run \
        --no-default-browser-check \
        --disable-sync \
        \
        `# ── Privacy & telemetry ───────────────────────────────` \
        --disable-client-side-phishing-detection \
        --metrics-recording-only \
        --safebrowsing-disable-auto-update \
        \
        `# ── Background activity ───────────────────────────────` \
        --disable-background-networking \
        --disable-default-apps \
        --disable-hang-monitor \
        --disable-prompt-on-repost \
        \
        `# ── UI / appearance ──────────────────────────────────` \
        --disable-translate \
        --disable-infobars \
        --force-dark-mode \
        --enable-smooth-scrolling \
        --window-size=1280,800 \
        \
        `# ── GPU / hardware decode for HD–4K ──────────────────` \
        --enable-accelerated-video-decode \
        --enable-accelerated-video-encode \
        --enable-gpu-rasterization \
        --enable-zero-copy \
        --ignore-gpu-blocklist \
        --enable-native-gpu-memory-buffers \
        --use-gl=angle \
        --use-angle=metal \
        --num-raster-threads=4 \
        --high-dpi-support=1 \
        \
        `# ── Feature flags ────────────────────────────────────` \
        --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,BlockInsecurePrivateNetworkRequests \
        --disable-features=NetworkPrediction,Prerender2,PreloadMediaEngagementData,UseChromeOSDirectVideoDecoder \
        \
        "https://check.torproject.org/" &

    echo "Chromium launched. Press Ctrl+C to quit."

    # Wait here until Ctrl+C triggers cleanup
    wait
}

# ── dl ────────────────────────────────────────────────────────────────────────
# Downloads a file using yt-dlp routed through the Tor SOCKS5 proxy on
# 127.0.0.1:9050. Supports any URL that yt-dlp handles (video sites, direct
# MP4/MKV links, etc). Uses 16 concurrent fragments for faster downloads and
# resumes interrupted downloads automatically.
#
# Note: Tor must already be running (e.g. via tor_browser or `tor` standalone)
# before calling dl, otherwise the proxy connection will fail.
#
# Usage:
#   dl "output filename" "url"
#
# Example:
#   dl "video.mp4" "https://example.com/video.mp4"
#
# Dependencies:
#   tor    — brew install tor    / sudo port install tor    (must be running on port 9050)
#   yt-dlp — brew install yt-dlp / sudo port install yt-dlp
#   curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
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