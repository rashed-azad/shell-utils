#!/bin/bash

tor_browser() {
  # ── Tor config ────────────────────────────────────────────────────────────────
  TOR_CONFIG="$HOME/.config/tor-stream/torrc"
  mkdir -p "$(dirname "$TOR_CONFIG")"
  cat > "$TOR_CONFIG" << 'EOF'
# Circuit performance
NumEntryGuards 4
NumDirectoryGuards 3
GuardLifetime 2 months
MaxCircuitDirtiness 600
NewCircuitPeriod 120
CircuitBuildTimeout 10
LearnCircuitBuildTimeout 1

# Bandwidth (0 = unlimited)
RelayBandwidthRate 0
RelayBandwidthBurst 0
PerConnBWRate 0
PerConnBWBurst 0

# Scheduler tuning
KISTSchedRunInterval 10

# Isolated SOCKS port
SocksPort 9050 IsolateDestAddr IsolateDestPort

# Optional: pin to faster exit countries (uncomment to enable)
StrictNodes 1
ExitNodes {de},{nl},{se},{ch}
EOF

  # ── Graceful shutdown ─────────────────────────────────────────────────────────
  cleanup() {
    echo "Shutting down..."

    pkill -TERM -f "chromium-tor-profile" 2>/dev/null
    for i in $(seq 1 10); do
      pgrep -f "chromium-tor-profile" > /dev/null 2>&1 || break
      sleep 0.5
    done
    pgrep -f "chromium-tor-profile" > /dev/null 2>&1 && \
      pkill -KILL -f "chromium-tor-profile" 2>/dev/null

    if kill -0 "$TOR_PID" 2>/dev/null; then
      kill -TERM "$TOR_PID" 2>/dev/null
      wait "$TOR_PID" 2>/dev/null
    fi

    echo "Done."
    trap - INT TERM
  }

  trap cleanup INT TERM

  # ── Start Tor ────────────────────────────────────────────────────────────────
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

  # ── Launch Ungoogled Chromium ─────────────────────────────────────────────────
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