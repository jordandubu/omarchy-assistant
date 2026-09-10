import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy-assistant"
  manageIpc: true
  ipcTarget: "omarchy-assistant"

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
  readonly property color mascotTextColor: {
    if (state === "listening") return Color.urgent
    if (state !== "idle") return Color.accent
    return Color.muted
  }

  // Settings table: one row per setting (label + dropdown + apply)
  readonly property var settingRows: [
    {
      label: "Brain",
      options: ["omp", "opencode", "claude", "codex", "gemini"],
      value: brain,
      apply: function(v) { setSetting("brain", v) }
    },
    {
      label: "Personality",
      options: personaOptions,
      value: personality,
      apply: function(v) { setSetting("personality", v) }
    },
    {
      label: "Speech to text",
      options: ["parakeet", "whisper-tiny", "whisper-small", "whisper-medium", "whisper-large-v3-turbo"],
      value: sttEngine,
      apply: function(v) { setSetting("stt_engine", v) }
    },
    {
      label: "Voice",
      options: voiceOptions,
      value: ttsVoice,
      apply: function(v) {
        if (v === "piper (alan)") {
          setSetting("tts.backend", "piper")
        } else {
          setSetting("tts.backend", "kyutai")
          setSetting("tts.voice", v)
        }
      }
    },
    {
      label: "Live activity",
      options: ["on", "off"],
      value: liveActivity,
      apply: function(v) { setSetting("live_activity", v); liveActivity = v }
    }
  ]

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
        spacing: Style.space(6)

        // ---- Mic hero: big button + state label ----
        Column {
          width: parent.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: Style.space(64)

            Rectangle {
              id: micCircle
              anchors.centerIn: parent
              width: Style.space(64)
              height: Style.space(64)
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
                text: root.micActive ? "󰍭" : "󰍬"   // md mic-off / mic
                color: root.micActive ? Color.background : Color.accent
                font.family: "monospace"
                font.pixelSize: Style.font.displayLarge
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMic()
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              if (root.state === "listening") return "listening — tap again to send"
              if (root.state === "thinking") return "thinking…"
              if (root.state === "speaking") return "speaking…"
              return "tap to talk"
            }
            color: root.state === "idle" ? Color.muted : root.mascotTextColor
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { }

        // ---- Live activity ----
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
          spacing: Style.space(3)
          visible: root.historyLines.length > 0

          PanelSectionHeader {
            text: "Recent"
          }

          Repeater {
            model: root.historyLines.length > 3 ? 3 : root.historyLines.length

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

        // ---- Settings: label left, control right ----
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Settings"
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.settingRows

              delegate: Row {
                required property int index
                width: parent.width
                spacing: Style.space(6)

                Text {
                  width: parent.width * 0.38
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.settingRows[index].label
                  color: Color.muted
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Dropdown {
                  width: parent.width * 0.62
                  options: root.settingRows[index].options
                  value: root.settingRows[index].value
                  onChanged: function(v) { root.settingRows[index].apply(v) }
                }
              }
            }
          }
        }

        // ---- Stop (only while working) ----
        Button {
          width: parent.width
          text: "Stop assistant"
          visible: root.state === "thinking"
          onClicked: root.stop()
        }
      }
    }
  }
}
