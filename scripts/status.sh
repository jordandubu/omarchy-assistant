#!/usr/bin/env bash
# One-shot state for the assistant bar widget.
# Emits single-line JSON: {"state":"idle|listening|thinking|speaking","activity":"..."}
set -u
STATE="idle"
ACTIVITY=""

# Recording (F10 held) -> listening
vox_state="$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voxtype/state" 2>/dev/null || echo idle)"
if [ "$vox_state" = "recording" ] || [ "$vox_state" = "transcribing" ]; then
  STATE="listening"
fi

ANS_DIR="$HOME/Work/jarvis-answers"

# Agent working: live.log modified in the last 20 s -> thinking
# (worker session lingers 24 h after finishing, so session existence alone is not "working")
if [ -f "$ANS_DIR/live.log" ]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$ANS_DIR/live.log" 2>/dev/null || echo 0)
  age=$((now - mtime))
  if [ "$age" -lt 20 ]; then
    STATE="thinking"
    ACTIVITY="$(tail -n 1 "$ANS_DIR/live.log" 2>/dev/null | cut -c1-120)"
  fi
fi

# TTS playback -> speaking
if pgrep -f "pw-play /tmp/jarvis" >/dev/null 2>&1; then
  STATE="speaking"
fi

printf '{"state":"%s","activity":%s}\n' "$STATE" "$(printf '%s' "$ACTIVITY" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"