#!/usr/bin/env bash
# Omarchy AI Assistant — one-shot installer for the voice pipeline.
# Safe to re-run. Copies pipeline scripts, merges voxtype profile,
# seeds settings + personas. TTS daemon (pocket-tts) optional: --with-tts.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_TTS=0
[[ "${1:-}" == "--with-tts" ]] && WITH_TTS=1

# 1) Pipeline scripts
install -m 755 "$REPO/scripts/jarvis-brain"  "$HOME/.local/bin/jarvis-brain"
install -m 755 "$REPO/scripts/jarvis-worker" "$HOME/.local/bin/jarvis-worker"
install -m 755 "$REPO/scripts/jarvis-stop"   "$HOME/.local/bin/jarvis-stop"
install -m 755 "$REPO/scripts/jarvis-router" "$HOME/.local/bin/jarvis-router"
# voice-router passthrough for dictation profile compatibility
install -m 755 "$REPO/scripts/voice-router"  "$HOME/.local/bin/voice-router"

# 2) voxtype assistant profile (merge if missing)
VT="$HOME/.config/voxtype/config.toml"
if [[ -f "$VT" ]] && ! grep -q "profiles.assistant" "$VT"; then
  cat >> "$VT" <<'PROF'

# AI Assistant profile: routes to jarvis-router
[profiles.assistant]
post_process_command = "$HOME/.local/bin/jarvis-router"
output_mode = "clipboard"
PROF
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
  "tts": { "backend": "kyutai", "voice": "george" }
}
JSON
[[ -f "$CFG/personas/default.md" ]] || install -m 644 "$REPO/config/personas/default.md" "$CFG/personas/default.md"

# 4) Optional: pocket-tts systemd unit
if [[ $WITH_TTS -eq 1 && -f "$REPO/config/omarchy-assistant-tts.service" ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  install -m 644 "$REPO/config/omarchy-assistant-tts.service" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now omarchy-assistant-tts.service
fi

echo "Assistant installed. Hold SUPER+A and speak (press SUPER+SHIFT+A is omarchy audio, avoid)."
echo "Keybinding to add (SUPER+A push-to-talk):"
cat <<'KEY'

o.bind("SUPER + A", "Start assistant (push-to-talk)", "voxtype record start --profile assistant")
o.bind("SUPER + A", "Stop assistant (push-to-talk)", "voxtype record stop", { release = true })

KEY
echo "Add those to ~/.config/hypr/bindings.lua if not present, then reload."
