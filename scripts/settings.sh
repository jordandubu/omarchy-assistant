#!/usr/bin/env bash
# Read or write ~/.config/omarchy-assistant/settings.json
# usage: settings.sh get <key>            -> value
#        settings.sh set <key> <value>    -> writes (flat or dot-path)
#        settings.sh personas             -> persona names, one per line
#        settings.sh voices               -> tts voices, one per line
set -u
CFG="$HOME/.config/omarchy-assistant/settings.json"
mkdir -p "$(dirname "$CFG")"
CFG_DATA='{"brain":"omp","stt_engine":"parakeet","language":"en","tts":{"backend":"kyutai","voice":"george","fallback":"piper"},"personality":"default","live_activity":"on","wake_word":{"enabled":true}}'
[ -f "$CFG" ] || echo "$CFG_DATA" > "$CFG"

case "${1:-}" in
  get)
    python3 -c "
import json,sys
d=json.load(open('$CFG'))
cur=d
for part in '$2'.split('.'):
    cur = cur.get(part) if isinstance(cur,dict) else None
    if cur is None: break
print(cur if cur is not None else '')"
    ;;
  set)
    python3 - "$2" "$3" "$CFG" <<'PY'
import json, sys
path, val = sys.argv[1], sys.argv[2]
f = sys.argv[3]
d = json.load(open(f))
cur = d
parts = path.split(".")
for p in parts[:-1]:
    cur = cur.setdefault(p, {})
# coerce "true"/numbers
if val in ("true", "false"):
    cur[parts[-1]] = val == "true"
elif val.lstrip("-").isdigit():
    cur[parts[-1]] = int(val)
else:
    cur[parts[-1]] = val
json.dump(d, open(f, "w"), indent=2)
PY
    # side effects: STT switch rewrites voxtype engine+model, then restart
    if [ "$2" = "stt_engine" ]; then
      (
        case "$3" in
          parakeet)
            voxtype config set engine parakeet >/dev/null 2>&1
            voxtype config set parakeet.model parakeet-tdt-0.6b-v3-int8 >/dev/null 2>&1 ;;
          whisper-*)
            voxtype config set engine whisper >/dev/null 2>&1
            voxtype config set whisper.model "${3#whisper-}" >/dev/null 2>&1 ;;
        esac
        systemctl --user restart voxtype >/dev/null 2>&1
      ) &
    fi
    # side effects: language switch restarts the TTS daemon with the new --language
    if [ "$2" = "language" ]; then
      systemctl --user restart omarchy-assistant-tts >/dev/null 2>&1 &
    fi
    # side effects: wake_word switch stops or starts the wake word listener
    if [ "$2" = "wake_word.enabled" ]; then
      if [ "$3" = "false" ]; then
        systemctl --user stop omarchy-assistant-wake >/dev/null 2>&1 || true
      else
        IS_EN=$("$0" is-enabled)
        if [ "$IS_EN" = "true" ]; then
          systemctl --user start omarchy-assistant-wake >/dev/null 2>&1 || true
        fi
      fi
    fi
    # side effects: direct enabled switch
    if [ "$2" = "enabled" ]; then
      "$0" set-enabled "$3"
    fi
    ;;
  is-enabled)
    python3 -c "
import json
try:
    d = json.load(open('$CFG'))
    print('true' if d.get('enabled', True) else 'false')
except Exception:
    print('true')
"
    ;;
  set-enabled)
    VAL="${2:-true}"
    python3 - "$VAL" "$CFG" <<'PY'
import json, sys
raw = sys.argv[1].lower()
val = raw in ("true", "1", "on", "yes")
f = sys.argv[2]
try:
    d = json.load(open(f))
except Exception:
    d = {}
d["enabled"] = val
json.dump(d, open(f, "w"), indent=2)
PY
    RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    WAKE_DIR="$RT/jarvis-wake"
    mkdir -p "$WAKE_DIR"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ "$VAL" = "false" ] || [ "$VAL" = "off" ] || [ "$VAL" = "0" ]; then
      touch "$WAKE_DIR/disabled"
      systemctl --user stop omarchy-assistant-wake.service >/dev/null 2>&1 || true
      bash "$SCRIPT_DIR/jarvis-stop" --silent >/dev/null 2>&1 || true
      omarchy-notification-send -r 424242 -t 2500 "Assistant: Disabled (Muted)" >/dev/null 2>&1 || true
    else
      rm -f "$WAKE_DIR/disabled"
      WW_ON=$(python3 -c "import json;print('true' if json.load(open('$CFG')).get('wake_word',{}).get('enabled',True) else 'false')" 2>/dev/null || echo true)
      if [ "$WW_ON" = "true" ]; then
        systemctl --user start omarchy-assistant-wake.service >/dev/null 2>&1 || true
      fi
      omarchy-notification-send -r 424242 -t 2500 "Assistant: Enabled" >/dev/null 2>&1 || true
    fi
    ;;
  toggle-enabled)
    CUR=$("$0" is-enabled)
    if [ "$CUR" = "true" ]; then
      "$0" set-enabled false
    else
      "$0" set-enabled true
    fi
    ;;
  personas)
    ls "$HOME/.config/omarchy-assistant/personas/" 2>/dev/null | sed 's/\.md$//'
    ;;
  voices)
    # kyutai voices grouped by the TTS language + piper fallback
    LANG_CODE=$(python3 -c "import json;print(json.load(open('$CFG')).get('language','en'))" 2>/dev/null || echo en)
    case "$LANG_CODE" in
      fr) echo "estelle"; echo "eponine" ;;
      de) echo "juergen" ;;
      it) echo "giovanni" ;;
      es) echo "lola" ;;
      pt) echo "rafael" ;;
      *)  echo "george"; echo "alba"; echo "anna"; echo "charles" ;;
    esac
    echo "piper (alan)"
    ;;
esac

