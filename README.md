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

    omarchy plugin add ~/Documents/repo/omarchy-assistant --enable

Or for development, symlink/copy into `~/.config/omarchy/plugins/` and run
`omarchy-shell shell rescanPlugins`.

## License

MIT
