# Omarchy AI Assistant

Animated ASCII assistant for the Omarchy bar: voice + text commands, live agent
activity, spoken replies. Wraps the local voice pipeline (voxtype push-to-talk,
whitelist router, headless agent, Kyutai Pocket TTS) — it adds a UI, it does not
replace the pipeline.

## What you get

- A monospace ASCII face in the bar that blinks when idle, perks up while
  listening, spins while the agent works, and opens its mouth while speaking.
- Click it: a panel with live activity, the last answer, recent history, a text
  input (sends to the same agent brain), Stop, and a terminal attach button.
- Voice flow unchanged: hold F10 and speak; release to dispatch.

## Requirements

- Omarchy Quattro (omarchy-shell / quickshell)
- The voice stack: voxtype daemon, `/usr/local/bin/jarvis-router`,
  `~/.local/bin/jarvis-brain`, `~/.local/bin/jarvis-stop`, tmux
- Kyutai Pocket TTS on localhost:8765 (optional; spoken replies)

## Install

    git clone https://github.com/<you>/omarchy-assistant
    cd omarchy-assistant
    ./scripts/install.sh          # pipeline scripts + voxtype profile + settings
    omarchy plugin add "$PWD" --enable

Optional spoken replies (Kyutai Pocket TTS, ~1 GB local model):

    ./scripts/install.sh --with-tts

Then add the push-to-talk keys to `~/.config/hypr/bindings.lua`:

    o.bind("SUPER + A", "Start assistant (push-to-talk)", "voxtype record start --profile assistant")
    o.bind("SUPER + A", "Stop assistant (push-to-talk)", "voxtype record stop", { release = true })

and reload the shell. Requires: voxtype (STT), tmux, an agent CLI for the brain
(omp by default), `omarchy-notification-send` (omarchy built-in).

## License

MIT
