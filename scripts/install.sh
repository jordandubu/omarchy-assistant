#!/usr/bin/env bash
# Omarchy AI Assistant — one-shot installer for the voice pipeline.
# Safe to re-run. Copies pipeline scripts, merges voxtype profile,
# seeds settings + personas, installs the wake-word listener.
# TTS daemon (pocket-tts) optional: --with-tts.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_TTS=0
[[ "${1:-}" == "--with-tts" ]] && WITH_TTS=1

# 1) Pipeline scripts + wake-word listener
install -m 755 "$REPO/scripts/jarvis-brain"  "$HOME/.local/bin/jarvis-brain"
install -m 755 "$REPO/scripts/jarvis-worker" "$HOME/.local/bin/jarvis-worker"
install -m 755 "$REPO/scripts/jarvis-stop"   "$HOME/.local/bin/jarvis-stop"
install -m 755 "$REPO/scripts/jarvis-router" "$HOME/.local/bin/jarvis-router"
install -m 755 "$REPO/scripts/jarvis-wake"   "$HOME/.local/bin/jarvis-wake"
install -m 755 "$REPO/scripts/jarvis-monitor" "$HOME/.local/bin/jarvis-monitor"
ln -sf "$HOME/.local/bin/jarvis-monitor" "$HOME/.local/bin/omarchy-assistant-monitor"
# voice-router passthrough for dictation profile compatibility
install -m 755 "$REPO/scripts/voice-router"  "$HOME/.local/bin/voice-router"

# 2) voxtype assistant profile (merge if missing)
VT="$HOME/.config/voxtype/config.toml"
if [[ -f "$VT" ]] && ! grep -q "profiles.assistant" "$VT"; then
  cat >> "$VT" <<EOF

# AI Assistant profile: routes to jarvis-router
[profiles.assistant]
post_process_command = "$HOME/.local/bin/jarvis-router"
output_mode = "clipboard"
fallback_on_empty = false
EOF
fi

# 3) Settings + personas defaults (never overwrite existing)
CFG="$HOME/.config/omarchy-assistant"
mkdir -p "$CFG/personas"
[[ -f "$CFG/settings.json" ]] || cat > "$CFG/settings.json" <<'JSON'
{
  "brain": "omp",
  "personality": "default",
  "live_activity": "on",
  "stt_engine": "parakeet",
  "language": "en",
  "wake_word": { "enabled": true },
  "tts": { "backend": "kyutai", "voice": "george" }
}
JSON
# merge language + wake_word into existing settings (keep user choices)
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.config/omarchy-assistant/settings.json")
try:
    d = json.load(open(p))
except Exception:
    d = {}
d.setdefault("language", "en")
d.setdefault("wake_word", {"enabled": True})
json.dump(d, open(p, "w"), indent=2)
PY
[[ -f "$CFG/personas/default.md" ]] || install -m 644 "$REPO/config/personas/default.md" "$CFG/personas/default.md"

# 3b) Wake-word vosk model (keyword spotting for "omarchy")
MODEL_DIR="$HOME/.local/share/omarchy-assistant/vosk-model"
if [[ ! -d "$MODEL_DIR" ]]; then
  echo "Downloading vosk wake-word model (~40 MB)…"
  mkdir -p "$HOME/.local/share/omarchy-assistant"
  TMP="$(mktemp -d)"
  if curl -sL -o "$TMP/m.zip" "https://huggingface.co/ambind/vosk-model-small-en-us-0.15/resolve/main/vosk-model-small-en-us-0.15_c_.zip"; then
    unzip -q "$TMP/m.zip" -d "$TMP" && mv "$TMP/vosk-model-small-en-us-0.15" "$MODEL_DIR"
  else
    echo "Warning: wake-word model download failed; the Setup panel can retry."
  fi
  rm -rf "$TMP"
fi

# 3c) Wake-word listener systemd service (starts on login)
if command -v python3 >/dev/null && python3 -c "import vosk" 2>/dev/null; then
  install -m 644 "$REPO/config/omarchy-assistant-wake.service" "$HOME/.config/systemd/user/" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable --now omarchy-assistant-wake.service 2>/dev/null || true
fi

# 4) Optional: pocket-tts systemd unit
if [[ $WITH_TTS -eq 1 && -f "$REPO/config/omarchy-assistant-tts.service" ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  install -m 644 "$REPO/config/omarchy-assistant-tts.service" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now omarchy-assistant-tts.service
fi

# Reload voxtype daemon so it picks up the assistant profile
if systemctl --user is-active voxtype.service >/dev/null 2>&1; then
  systemctl --user restart voxtype.service
fi

# 5) Hyprland keybindings (merge if missing)
HB="$HOME/.config/hypr/bindings.lua"
if [[ -f "$HB" ]]; then
  if ! grep -q "SUPER + A.*assistant" "$HB"; then
    cat >> "$HB" <<'KEY'

-- AI Assistant push-to-talk (hold SUPER + A, speak, release)
o.bind("SUPER + A", "Start assistant (push-to-talk)", "voxtype record start --profile assistant")
o.bind("SUPER + A", "Stop assistant (push-to-talk)", "voxtype record stop", { release = true })
KEY
  fi
  if ! grep -q "SUPER + I.*jarvis-monitor" "$HB"; then
    cat >> "$HB" <<'KEY'

-- AI Assistant agent monitor (watch live agent or interrupt with Ctrl+C)
o.bind("SUPER + I", "Watch assistant agent", "jarvis-monitor")
KEY
  fi
fi

echo "Assistant installed. Hold SUPER+A and speak. Press SUPER+I to watch running agents."
