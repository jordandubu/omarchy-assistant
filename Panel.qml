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
  property string ttsVoice: "george"
  property string liveActivity: "on"
  property var personaOptions: ["default"]
  property var voiceOptions: ["george"]


  readonly property bool micActive: state === "listening"

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

  Process {
    id: stopProcess
    running: false
    command: [Quickshell.env("HOME") + "/.local/bin/jarvis-stop"]
  }

  Process {
    id: micProcess
    running: false
  }

  function toggleMic() {
    var verb = root.micActive ? "stop" : "start"
    micProcess.command = ["voxtype", "record", verb, "--profile", "assistant"]
    micProcess.running = true
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

  // ------------------------------------------------------------- UI
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)


        // ---- Big mic button ----
        Item {
          width: parent.width
          height: micButtonSize

          readonly property real micButtonSize: Style.space(44)

          Rectangle {
            id: micCircle
            anchors.centerIn: parent
            width: parent.height
            height: parent.height
            radius: width / 2
            color: root.micActive ? Color.urgent : Style.normalFill
            border.color: root.micActive ? Color.urgent : Color.accent
            border.width: root.micActive ? 0 : 1

            SequentialAnimation on scale {
              running: root.micActive
              loops: Animation.Infinite
              NumberAnimation { to: 1.12; duration: 400; easing.type: Easing.OutQuad }
              NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InQuad }
            }

            Text {
              anchors.centerIn: parent
              // Nerd Font microphone glyphs (same as shell Microphone widget)
              text: root.micActive ? "󰍭" : "󰍬"
              color: root.micActive ? Color.background : Color.accent
              font.family: "monospace"
              font.pixelSize: Style.font.display
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleMic()
            }
          }
        }


        // ---- Live activity (gated by setting) ----
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.activity !== "" && root.liveActivity !== "off"

          PanelSectionHeader {
            text: "Working on it"
          }

          Text {
            width: parent.width
            text: root.activity
            color: Color.muted
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // ---- Answer ----
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.lastAnswer !== ""

          PanelSectionHeader {
            text: "Answer"
          }

          Text {
            width: parent.width
            text: root.lastAnswer
            color: root.barForeground
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        // ---- Recent ----
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.historyLines.length > 0

          PanelSectionHeader {
            text: "Recent"
          }

          Repeater {
            model: root.historyLines.length > 4 ? 4 : root.historyLines.length

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

        PanelSeparator { }

        // ---- Settings (always visible, compact 2-col grid) ----
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "Settings"
          }

          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            Dropdown {
              width: (parent.width - Style.space(8)) / 2
              label: "Brain"
              options: ["omp", "opencode", "claude", "codex", "gemini"]
              value: root.brain
              onChanged: function(v) { root.setSetting("brain", v) }
            }

            Dropdown {
              width: (parent.width - Style.space(8)) / 2
              label: "Personality"
              options: root.personaOptions
              value: root.personality
              onChanged: function(v) { root.setSetting("personality", v) }
            }

            Dropdown {
              width: (parent.width - Style.space(8)) / 2
              label: "Speech to text"
              options: ["parakeet", "whisper-tiny", "whisper-small", "whisper-medium", "whisper-large-v3-turbo"]
              value: root.sttEngine
              onChanged: function(v) { root.setSetting("stt_engine", v) }
            }

            Dropdown {
              width: (parent.width - Style.space(8)) / 2
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
              width: (parent.width - Style.space(8)) / 2
              label: "Live activity"
              options: ["on", "off"]
              value: root.liveActivity
              onChanged: function(v) { root.setSetting("live_activity", v); root.liveActivity = v }
            }
          }
        }

        // ---- Footer ----
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

  Process {
    id: terminalProcess
    running: false
    command: ["foot", "-e", "tmux", "attach", "-t", "jarvis"]
  }

