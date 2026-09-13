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
