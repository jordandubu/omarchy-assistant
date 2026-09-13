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

# Agent working: detect active agents via tmux & live.log
INFO=$(python3 - <<'PY'
import json, os, re, subprocess, time

agents = []
live_log = os.path.expanduser("~/Work/jarvis-answers/live.log")

# Check if jarvis-worker process is actively running
pg = subprocess.run(["pgrep", "-f", "jarvis-worker"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
worker_alive = (pg.returncode == 0 and bool(pg.stdout.strip()))

stopped = False
if os.path.exists(live_log):
    try:
        with open(live_log, "r", errors="ignore") as f:
            lines = f.readlines()
            if lines:
                last_few = "".join(lines[-6:])
                if "[stopped by user]" in last_few or "[stopped or brain error]" in last_few:
                    stopped = True
    except Exception:
        pass

if worker_alive and not stopped:
    prompt = ""
    brain = "omp"
    step = ""
    if os.path.exists(live_log):
        try:
            with open(live_log, "r", errors="ignore") as f:
                for l in f:
                    if "prompt: " in l and not prompt:
                        prompt = l.split("prompt: ", 1)[1].strip()
                    elif "brain: " in l:
                        m = re.search(r"brain:\s*([^\s·]+)", l)
                        if m: brain = m.group(1)
                    if l.startswith("[") and " #" in l:
                        step = l.split("]", 1)[1].strip()
                    elif l.strip().startswith("→"):
                        step = l.strip()
        except Exception:
            pass
    agents.append({
        "id": "jarvis",
        "name": f"{brain.upper()} Agent",
        "brain": brain,
        "prompt": prompt or "Processing request...",
        "step": step or "Thinking...",
        "status": "working"
    })

activity = agents[0]["step"] if agents else ""
print(json.dumps({"agents": agents, "activity": activity}))
PY
)

AGENTS=$(echo "$INFO" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin).get("agents",[])))' 2>/dev/null || echo '[]')
AGENT_ACT=$(echo "$INFO" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("activity",""))' 2>/dev/null || echo '')

if [ "$STATE" = "idle" ] && [ "$AGENTS" != "[]" ]; then
  STATE="thinking"
  ACTIVITY="$AGENT_ACT"
fi

# TTS playback -> speaking
if pgrep -f "pw-play /tmp/jarvis" >/dev/null 2>&1; then
  STATE="speaking"
fi

# Assistant disabled?
CFG="$HOME/.config/omarchy-assistant/settings.json"
DISABLED_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/jarvis-wake/disabled"
ENABLED="true"
if [ -f "$DISABLED_FILE" ]; then
  ENABLED="false"
elif [ -f "$CFG" ]; then
  ENABLED="$(python3 -c "import json;print('true' if json.load(open('$CFG')).get('enabled',True) else 'false')" 2>/dev/null || echo true)"
fi

if [ "$ENABLED" = "false" ]; then
  STATE="disabled"
fi

# Setup incomplete? (cached 10 s to keep the poll cheap)
SETUP="ok"
CACHE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omarchy-assistant-setup-cache"
now=$(date +%s)
cage=$((now - $(stat -c %Y "$CACHE" 2>/dev/null || echo now)))
if [ -f "$CACHE" ] && [ "$cage" -lt 10 ]; then
  SETUP="$(cat "$CACHE" 2>/dev/null || echo ok)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  OUT="$(bash "$SCRIPT_DIR/setup-status.sh" 2>/dev/null || echo '{"setup":"ok"}')"
  SETUP="$(printf '%s' "$OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("setup","ok"))' 2>/dev/null || echo ok)"
  echo "$SETUP" > "$CACHE"
fi

printf '{"state":"%s","enabled":%s,"setup":"%s","activity":%s,"agents":%s}\n' "$STATE" "$ENABLED" "$SETUP" "$(printf '%s' "$ACTIVITY" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" "$AGENTS"