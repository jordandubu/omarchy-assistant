# AGENTS.md — Omarchy AI Assistant

This document is the operating manual and architecture reference for any AI agent working on the **Omarchy AI Assistant** (`omarchy-assistant`).

---

## 1. Identity & System Overview

**Omarchy AI Assistant** is a multimodal, real-time voice and desktop assistant deeply integrated into the Omarchy Linux desktop shell (Arch Linux + Hyprland + Quickshell). It provides:
- Push-to-talk & wake-word voice interaction.
- Instant fast-path commands (weather, math evaluation, 5-minute rolling memory recall, app launching, playback control) without cloud LLM latency or API costs.
- Headless multi-agent brain execution (`agy`, `omp`, `claude`, `codex`, `opencode`, etc.) inside an isolated tmux session.
- Real-time conversational Text-to-Speech via **Kyutai Pocket TTS** HTTP server on `:8765`.
- Live status, active agent monitor, and settings control rendered via a custom Quickshell UI bar widget and popup panel.

---

## 2. Critical Operational Rules (MANDATORY)

> [!CAUTION]
> **NEVER RUN `pkill -f foot`**
> `foot` is the user's terminal emulator hosting your AI agent session. Killing `foot` abruptly terminates this session and disconnects you from the user.

> [!IMPORTANT]
> **Quickshell Plugin Symlink**
> Quickshell loads the assistant plugin strictly from `~/.config/omarchy/plugins/omarchy-assistant/`.
> This directory **MUST** be a direct symlink to this repository (`/home/jordandubu/Projects/repo/omarchy-assistant`).
> **Never** create a detached directory or separate git clone there, or edits in this repo will desync and will not show up on the UI.

> [!WARNING]
> **AI Credits / Quota State & Brain Selection**
> The default brain is **`omp`** (`oh-my-pi`).
> If Google Cloud Code Assist returns HTTP 429 RESOURCE_EXHAUSTED for `omp`, the assistant speaks an audible notice and sends a notification.
> **`agy`** (Antigravity CLI at `~/.local/bin/agy`) is integrated and available as an optional brain in the settings dropdown (`Panel.qml`). When selected, `agy` runs non-interactively with `-p <prompt> --output-format stream-json --dangerously-skip-permissions`, streaming responses and bash tool executions cleanly.
> The host machine is equipped with an **NVIDIA GeForce RTX 3080 12GB**, capable of running local models via Ollama if desired.

> [!NOTE]
> **Quickshell QML Styling Invariants**
> - Corner radius: Use `Style.cornerRadius` (a numeric property). **Do NOT** call `Style.radius(...)` as it is not a function and throws a fatal QML `TypeError`.
> - Spacing: Use `Style.space(px)`.
> - Colors: Use `Color.accent`, `Color.urgent`, `Color.popups.text`, `Color.popups.background`.
> - To reload the desktop UI shell after modifying QML files:
>   `systemctl --user restart quickshell-session.service`

---

## 3. End-to-End Architecture

```
[Voice Input]
   │
   ├── Say "Omarchy" ──────► omarchy-assistant-wake.service (OpenWakeWord)
   └── Hold SUPER + A ────► voxtype record start --profile assistant
                                 │
                                 ▼
                         [Voxtype (STT)] (Parakeet / Whisper)
                                 │
                                 ▼ pipes transcribed text via STT post_process
                     [~/.local/bin/jarvis-router]
                                 │
      ┌──────────────────────────┴──────────────────────────┐
      ▼                                                     ▼
[Fast-Path Commands]                                  [Complex Task]
(No LLM, zero latency)                                      │
- Weather (wttr.in)                                         ▼
- Math (arithmetic, percentages, powers, sqrt)    [~/.local/bin/jarvis-brain]
- System status (CPU, RAM, GPU utilization)                 │
- Memory recall ("what did I just ask")                     │
- App launcher ("open firefox")                             │
- Stop command ("omarchy stop")                             ▼
- Casual talk ("how are you")                     [tmux session: jarvis]
      │                                                     │
      │                                                     ▼
      │                                           [~/.local/bin/jarvis-worker]
      │                                           - Context: 5-min rolling memory
      │                                           - Brain: agy / omp / claude / etc.
      │                                           - Logs steps to live.log
      │                                           - Saves answer to answer.txt
      │                                                     │
      └──────────────────────────┬──────────────────────────┘
                                 │
                                 ▼
                    [Output & Delivery Layer]
                    ├── Speech: Kyutai Pocket TTS (:8765) ──► pw-play
                    ├── Notification: omarchy-notification-send
                    ├── Clipboard: wl-copy
                    └── UI: Quickshell BarWidget & Panel (status.sh)
```

---

## 4. Key Components & File Locations

### Pipeline Scripts (`scripts/` -> installed to `~/.local/bin/`)

| Script | Installed Path | Role |
|---|---|---|
| `scripts/jarvis-router` | `~/.local/bin/jarvis-router` | Fast-path router. Receives STT text from Voxtype via `sys.stdin` or CLI args. Executes instant commands, handles multi-actions & terminal combos, or dispatches to `jarvis-brain`. Updates rolling memory and triggers conversational follow-up. |
| `scripts/jarvis-wake` | `~/.local/bin/jarvis-wake` | Wake-word daemon (Vosk homophones for "Omarchy") and conversational follow-up listener. Listens for speech, stops on silence (VAD), or cancels cleanly on 8s timeout. |
| `scripts/jarvis-brain` | `~/.local/bin/jarvis-brain` | Reads active brain from `settings.json`, launches detached tmux session `jarvis` running `jarvis-worker`. |
| `scripts/jarvis-worker` | `~/.local/bin/jarvis-worker` | Headless brain driver inside tmux. Injects 5-min rolling memory context, parses tool events and response deltas, writes `live.log` and `answer.txt`, plays Pocket TTS audio, and triggers follow-up. |
| `scripts/jarvis-stop` | `~/.local/bin/jarvis-stop` | Emergency stop. Kills `pw-play`, halts `jarvis-worker`, terminates tmux session `jarvis`, cancels active recording, clears follow-up flags, and speaks confirmation *"Stopped."*. |
| `scripts/jarvis-monitor` | `~/.local/bin/jarvis-monitor` | Live agent monitor (`SUPER+I`). Toggles floating terminal attached to active agent in tmux `jarvis` session where user can see live tools/thoughts and press `Ctrl+C` to stop. Shows recent activity if idle. |
| `scripts/status.sh` | Called by Quickshell | Emits JSON `{state, setup, activity, agents}` for the bar widget and panel. Inspects tmux panes, `pgrep jarvis-worker`, and `live.log`. |
| `scripts/settings.sh` | Called by Panel / CLI | Reads/writes configuration in `~/.config/omarchy-assistant/settings.json`. Handles side effects (voxtype restart on engine change, TTS restart on language change). |

### UI Plugin Files (`~/.config/omarchy/plugins/omarchy-assistant/`)

- `BarWidget.qml`: Soundwave icon on the Omarchy bar. Uses `AssistantMark.qml` to animate idle breathing, listening waves, thinking ripples, and speaking motions. Polls `scripts/status.sh`.
- `AssistantMark.qml`: Pure QML procedural 4-bar soundwave canvas with sinusoidal physics animations.
- `Panel.qml`: Dropdown settings (Brain, Personality, STT engine, Voice, Language, Wake word), Setup card, and the **"Agents Working"** section displaying active background agents with live step progression and a direct **Stop** button.
- `manifest.json`: Omarchy plugin descriptor declaring `omarchy-assistant` as a `bar-widget`.

### Systemd Services

- `omarchy-assistant-tts.service`: Runs the Kyutai Pocket TTS HTTP daemon on `http://localhost:8765/tts` (`python -m assistant_tts.server --language english`). Uses the venv at `/home/jordandubu/Projects/repo/lagauchiasse/.venv`.
- `omarchy-assistant-wake.service`: Runs the OpenWakeWord background daemon listening for the hotword "omarchy".
- `voxtype.service`: Runs the Voxtype STT daemon. Profile `[profiles.assistant]` in `~/.config/voxtype/config.toml` configures:
  ```toml
  [profiles.assistant]
  post_process_command = "/home/jordandubu/.local/bin/jarvis-router"
  output_mode = "clipboard"
  fallback_on_empty = false
  ```
- `quickshell-session.service`: Runs the main desktop Quickshell instance.

### Runtime State & Memory Files

- `~/.local/share/omarchy-assistant/rolling-memory.json`: 5-minute rolling memory containing recent exchanges (`[{"t": timestamp, "user": "...", "assistant": "..."}]`). Pruned automatically.
- `~/Work/jarvis-answers/live.log`: Live stream of agent thoughts, steps, and tool execution.
- `~/Work/jarvis-answers/answer.txt`: Final response text from the current/most recent task.
- `~/.config/omarchy-assistant/settings.json`: User preferences:
  ```json
  {
    "brain": "omp",
    "stt_engine": "parakeet",
    "language": "en",
    "tts": {
      "backend": "kyutai",
      "voice": "george",
      "fallback": "piper"
    },
    "personality": "default",
    "live_activity": "on",
    "wake_word": {
      "enabled": true
    }
  }
  ```

---

## 5. Development & Verification Runbook

When implementing features, fixing bugs, or updating scripts in this repository:

### 1. Synchronizing Installed Binaries
Whenever you edit scripts in `scripts/`, you **must** update the installed executables:
```bash
cp scripts/jarvis-router ~/.local/bin/jarvis-router && chmod +x ~/.local/bin/jarvis-router
cp scripts/jarvis-worker ~/.local/bin/jarvis-worker && chmod +x ~/.local/bin/jarvis-worker
cp scripts/jarvis-stop ~/.local/bin/jarvis-stop && chmod +x ~/.local/bin/jarvis-stop
cp scripts/jarvis-monitor ~/.local/bin/jarvis-monitor && chmod +x ~/.local/bin/jarvis-monitor
```

### 2. Testing Fast-Path Routing & Memory
```bash
# Test weather fast path
~/.local/bin/jarvis-router "what's the weather"

# Test math fast path
~/.local/bin/jarvis-router "what is 2 + 2"
~/.local/bin/jarvis-router "what is 15 percent of 80"
~/.local/bin/jarvis-router "square root of 144"

# Test system status fast path
~/.local/bin/jarvis-router "how much ram cpu we taking"
~/.local/bin/jarvis-router "how much ram are we using"
~/.local/bin/jarvis-router "what is the cpu usage"

# Test rolling memory recall
~/.local/bin/jarvis-router "what did I just ask you"

# Verify rolling memory storage
cat ~/.local/share/omarchy-assistant/rolling-memory.json
```

### 3. Testing Complex Agent Tasks (Brain)
```bash
# Trigger a brain task (omp, agy, or whichever is configured)
~/.local/bin/jarvis-router "give me a 3-bullet summary of git status"

# Check UI poller during run (should show status: working, brain: omp/agy)
./scripts/status.sh

# Verify output
cat ~/Work/jarvis-answers/answer.txt
```

### 4. Testing the Emergency Stop Command
```bash
# Start a long-running prompt
~/.local/bin/jarvis-router "count from 1 to 100 with 1 second delay between each"

# In another call, stop it immediately
~/.local/bin/jarvis-stop
# Or: ~/.local/bin/jarvis-router "omarchy stop"
```

### 5. Testing & Reloading the UI Panel
```bash
# Check status JSON
./scripts/status.sh

# Restart Quickshell session
systemctl --user restart quickshell-session.service

# Toggle the assistant panel open via IPC
/usr/share/omarchy/bin/omarchy-shell omarchy-assistant toggle

# Check Quickshell journal for QML warnings or errors
journalctl --user -u quickshell-session.service -n 30 --no-pager
```

### 6. Testing Kyutai Pocket TTS
```bash
curl -s -X POST http://localhost:8765/tts \
  -F "text=Hello Jordan, your system is operational." \
  -F "voice_url=george" \
  -o /tmp/test-tts.wav && pw-play /tmp/test-tts.wav
```

---

## 6. Guidelines for Future AI Agents

1. **Keep Responses Spoken-Friendly**: Any text written to `~/Work/jarvis-answers/answer.txt` will be read aloud by Kyutai Pocket TTS. Avoid markdown headers, large ascii tables, or dense code snippets unless specifically asked.
2. **Handle Failures Audibly & Visually**: If a model fails, times out, or hits a rate limit, never fail silently. Log to `live.log`, send a desktop notification (`omarchy-notification-send`), and speak a concise error message so the user knows what happened.
3. **Preserve Symlinks**: Never replace `~/.config/omarchy/plugins/omarchy-assistant` with a physical directory. Always verify `readlink -f ~/.config/omarchy/plugins/omarchy-assistant` points to this repo.
4. **Never Kill the Terminal**: Avoid `pkill -f foot` or any broad process killing commands that could terminate the interactive session.
