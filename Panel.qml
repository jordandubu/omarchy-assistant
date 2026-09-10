import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy-assistant"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null

  // State mirrored from the bar widget (injected hostWidget)
  readonly property string state: hostWidget ? hostWidget.state : "idle"
  readonly property string activity: hostWidget ? hostWidget.activity : ""

  property string lastAnswer: ""
  property var historyLines: []

  // Settings (loaded via scripts/settings.sh)
  property string brain: "omp"
  property string personality: "default"
  property string sttEngine: "parakeet"
  property string liveActivity: "on"
  property string ttsVoice: "george"
  property var personaOptions: ["default"]
  property var voiceOptions: ["george"]

  function reload() {
    answerFile.reload()
    historyProcess.running = true
    settingsGetProcess.running = true
    personasProcess.running = true
    voicesProcess.running = true
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function stop() {
    stopProcess.running = true
  }

  // ------------------------------------------------------------- data
  FileView {
    id: answerFile
    path: Quickshell.env("HOME") + "/Work/jarvis-answers/answer.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: root.lastAnswer = text()
    onLoaded: root.lastAnswer = text()
  }

  Process {
    id: historyProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = []
        var parts = String(text || "").split("\n")
        for (var i = 0; i < parts.length; i++) {
          var line = parts[i].trim()
          if (line !== "") lines.push(line)
        }
        root.historyLines = lines
      }
    }
  }



  // Settings IO
  Process {
    id: settingsGetProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // one line: brain|personality|stt|voice|live
        var p = String(text || "").trim().split("|")
        if (p.length >= 4) {
          root.brain = p[0]
          root.personality = p[1]
          root.sttEngine = p[2]
          root.ttsVoice = p[3]
          if (p.length >= 5) root.liveActivity = p[4]
        }
      }
    }
  }

  Process {
    id: personasProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var opts = []
        var parts = String(text || "").split("\n")
        for (var i = 0; i < parts.length; i++)
          if (parts[i].trim() !== "") opts.push(parts[i].trim())
        root.personaOptions = opts.length > 0 ? opts : ["default"]
      }
    }
  }

  Process {
    id: voicesProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var opts = []
        var parts = String(text || "").split("\n")
        for (var i = 0; i < parts.length; i++)
          if (parts[i].trim() !== "") opts.push(parts[i].trim())
        root.voiceOptions = opts.length > 0 ? opts : ["george"]
      }
    }
  }

  Process {
    id: settingsSetProcess
    running: false
  }

  function setSetting(key, value) {
    settingsSetProcess.command = [
      Quickshell.env("HOME") + "/Documents/repo/omarchy-assistant/scripts/settings.sh",
      "set", key, value
    ]
    settingsSetProcess.running = true
  }

  Component.onCompleted: {
    var sh = Quickshell.env("HOME") + "/Documents/repo/omarchy-assistant/scripts"
    historyProcess.command = [
      "bash", "-c",
      "for f in $(ls -t ~/Work/jarvis-answers/*.log 2>/dev/null | head -20); do " +
      "  head -1 \"$f\" | cut -c1-100; " +
      "  tail -1 \"$f\" | cut -c1-100; " +
      "done"
    ]
    settingsGetProcess.command = ["bash", "-c",
      "sh=" + sh + "/settings.sh; " +
      "echo \"$(\"$sh\" get brain)|$(\"$sh\" get personality)|$(\"$sh\" get stt_engine)|$(\"$sh\" get tts.voice)|$(\"$sh\" get live_activity)\""]
    personasProcess.command = ["bash", "-c", sh + "/settings.sh personas"]
    voicesProcess.command = ["bash", "-c", sh + "/settings.sh voices"]
  }
  Process {
    id: brainProcess
    running: false
  }

  Process {
    id: micProcess
    running: false
    command: ["voxtype", "record", "start", "--profile", "assistant"]
  }

  Process {
    id: stopProcess
    running: false
    command: [Quickshell.env("HOME") + "/.local/bin/jarvis-stop"]
  }

  // ------------------------------------------------------------- UI
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // Header: big mascot + state label
        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: root.state === "thinking" ? "[-.-]" : (root.state === "listening" ? "[=.o]" : "[^.]")
            color: root.barForeground
            font.family: "monospace"
            font.pixelSize: Style.font.display
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: "AI Assistant"
              color: root.barForeground
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              text: root.state === "idle" ? "ready" : root.state
              color: Color.muted
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Activity line while thinking (controlled by Live activity setting)
        Text {
          width: parent.width
          visible: root.activity !== "" && root.liveActivity !== "off"
          text: root.activity
          color: Color.muted
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        PanelSeparator { }

        // Last answer
        Text {
          width: parent.width
          visible: root.lastAnswer !== ""
          text: root.lastAnswer
          color: root.barForeground
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        // History (recent tasks)
        Column {
          width: parent.width
          visible: root.historyLines.length > 0
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "Recent"
          }

          Repeater {
            model: root.historyLines.length > 8 ? 8 : root.historyLines.length

            Text {
              required property int index
              width: parent.width
              text: "· " + (root.historyLines[index] || "")
              color: Color.muted
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }
        }

        // Mic row (Google-Assistant style: push to talk, assistant does the rest)
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            property bool recording: root.state === "listening"
            text: recording ? "● Recording — tap to send" : "● Mic: tap to talk"
            onClicked: {
              micProcess.command = ["voxtype", "record", recording ? "stop" : "start", "--profile", "assistant"]
              micProcess.running = true
            }
          }
        }

        // Footer actions

        // Settings (always visible)
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "Settings"
          }

          Dropdown {
            width: parent.width
            label: "Brain"
            options: ["omp", "opencode", "claude", "codex", "gemini"]
            value: root.brain
            onChanged: function(v) { root.setSetting("brain", v) }
          }

          Dropdown {
            width: parent.width
            label: "Personality"
            options: root.personaOptions
            value: root.personality
            onChanged: function(v) { root.setSetting("personality", v) }
          }

          Dropdown {
            width: parent.width
            label: "Speech to text"
            options: ["parakeet", "whisper-tiny", "whisper-small", "whisper-medium", "whisper-large-v3-turbo"]
            value: root.sttEngine
            onChanged: function(v) { root.setSetting("stt_engine", v) }
          }

          Dropdown {
            width: parent.width
            label: "Voice"
            options: root.voiceOptions
            value: root.ttsVoice
            onChanged: function(v) {
              if (v === "piper (alan)") {
                root.setSetting("tts.backend", "piper")
              } else {
                root.setSetting("tts.backend", "kyutai")
                root.setSetting("tts.voice", v)
              }
            }
          }

          Dropdown {
            width: parent.width
            label: "Show live activity"
            options: ["on", "off"]
            value: root.liveActivity
            onChanged: function(v) { root.setSetting("live_activity", v); root.liveActivity = v }
          }
        }

        PanelSeparator { }
        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Stop"
            visible: root.state === "thinking"
            onClicked: root.stop()
          }

          Button {
            text: "Terminal"
            onClicked: {
              terminalProcess.running = true
              root.close()
            }
          }
        }
      }
    }
  }

  Process {
    id: terminalProcess
    running: false
    command: ["foot", "-e", "tmux", "attach", "-t", "jarvis"]
  }
}// touch 1789052569
