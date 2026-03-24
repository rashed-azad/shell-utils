#!/bin/bash

tor_browser() {
  # Start Tor
  echo "Starting Tor..."
  tor &
  TOR_PID=$!

  # Wait until Tor SOCKS port is actually ready
  echo "Waiting for Tor to be ready..."
  until nc -z 127.0.0.1 9050 2>/dev/null; do
    sleep 0.5
  done
  echo "Tor is ready."

  # Launch Chromium
  echo "Launching Chromium..."
  /Applications/Chromium.app/Contents/MacOS/Chromium \
    --user-data-dir="$HOME/.config/chromium-tor-profile" \
    --proxy-server="socks5://127.0.0.1:9050" \
    --incognito \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-plugins \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-hang-monitor \
    --disable-prompt-on-repost \
    --disable-translate \
    --metrics-recording-only \
    --safebrowsing-disable-auto-update \
    --force-dark-mode \
    --enable-smooth-scrolling \
    --disable-infobars \
    --ash-no-nudges \
    --disable-search-engine-choice-screen \
    --start-maximized \
    --disk-cache-size=524288000 \
    --media-cache-size=524288000 \
    --enable-quic \
    --enable-tcp-fast-open \
    --prerender \
    --dns-prefetch-disable=false \
    --prefetch-search-results \
    --enable-accelerated-video-decode \
    --enable-accelerated-video-encode \
    --enable-gpu-rasterization \
    --enable-zero-copy \
    --ignore-gpu-blocklist \
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization \
    --disable-features=UseChromeOSDirectVideoDecoder \
    --high-dpi-support=1 \
    --num-raster-threads=4 \
    --enable-native-gpu-memory-buffers \
    --use-gl=angle \
    --use-angle=metal \
    "https://check.torproject.org/api/ip" &
  CHROMIUM_PID=$!

  # Ctrl+C handler
  trap "echo 'Shutting down...'; kill $CHROMIUM_PID 2>/dev/null; killall tor 2>/dev/null; echo 'Done.'; trap - INT; return" INT

  # Wait — closes Tor if Chromium window is closed manually too
  wait $CHROMIUM_PID
  killall tor 2>/dev/null
  echo "Done."
}