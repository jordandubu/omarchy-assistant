#!/usr/bin/env bash
# Setup completeness probe for the assistant panel.
# Emits single-line JSON: {"setup":"ok|incomplete","items":[{"id","label","ok"}]}
set -u
items_json=""

add_item() { # id label rc (rc 0 = check passed)
  local ok="false"; [ "$3" = "0" ] && ok="true"
  local label="${2//\"/\\\"}"
  items_json+="{\"id\":\"$1\",\"label\":\"$label\",\"ok\":$ok},"
}

# 1) voxtype daemon installed + running
systemctl --user is-active --quiet voxtype 2>/dev/null
add_item "voxtype" "voxtype daemon (speech to text)" "$?"

# 2) pipeline scripts installed
[ -x "$HOME/.local/bin/jarvis-router" ] && [ -x "$HOME/.local/bin/jarvis-brain" ] && [ -x "$HOME/.local/bin/jarvis-worker" ]
add_item "pipeline" "Assistant pipeline scripts" "$?"

# 3) a brain CLI available (any of the supported agents)
[ -n "$(command -v omp || command -v opencode || command -v claude || command -v codex || command -v gemini || command -v cursor-agent || command -v crush 2>/dev/null)" ]
add_item "brain" "Agent CLI (omp, claude, codex, …)" "$?"

# 4) notification helper
[ -n "$(command -v omarchy-notification-send 2>/dev/null)" ]
add_item "notify" "omarchy-notification-send" "$?"

# 5) tmux (brain sessions)
[ -n "$(command -v tmux 2>/dev/null)" ]
add_item "tmux" "tmux" "$?"

# 6) push-to-talk keybinding present
grep -qs "voxtype record start" "$HOME/.config/hypr/bindings.lua"
add_item "keybind" "Push-to-talk keybinding (SUPER+A)" "$?"

# 7) wake-word model + python-vosk
[ -d "$HOME/.local/share/omarchy-assistant/vosk-model" ] && python3 -c "import vosk" 2>/dev/null
add_item "wakeword" 'Wake-word model (say "omarchy")' "$?"

# 8) TTS optional: only counts if user opted in (service unit exists)
if [ -f "$HOME/.config/systemd/user/omarchy-assistant-tts.service" ]; then
  systemctl --user is-active --quiet omarchy-assistant-tts 2>/dev/null
  add_item "tts" "Spoken replies (Kyutai TTS)" "$?"
fi

# settings seeded?
[ -f "$HOME/.config/omarchy-assistant/settings.json" ]
add_item "settings" "Settings file" "$?"

items_json="${items_json%,}"
setup="ok"
echo "$items_json" | grep -q '"ok":false' && setup="incomplete"
printf '{"setup":"%s","items":[%s]}\n' "$setup" "$items_json"