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

  // Mascot animation
  property int frame: 0

  // Kaomoji mascot faces per state (robot style, animated)
  readonly property string mascotFace: {
    if (state === "thinking") {
      var spin = ["(◕‿◕)◔", "(◕‿◕)◐", "(◕‿◕)◑", "(◕‿◕)◒"]
      return spin[frame % 4]
    }
    if (state === "listening") return (frame % 2 === 0) ? "✧(◉‿◉)" : "(◉‿◉)"
    if (state === "speaking") return (frame % 2 === 0) ? "(◕o◕)" : "(◕‿◕)"
    // idle: blink every ~8 frames
    return (frame % 8 < 7) ? "(◕‿◕)" : "(◕_◕)"
  }

  readonly property color mascotColor: {
    if (state === "thinking") return Color.accent
    if (state === "listening") return Color.urgent
    if (state === "speaking") return Color.accent
    return Color.foreground
  }

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

        // ---- Hero: mascot with eyes that track the mouse ----
        Item {
          id: mascot
          width: parent.width
          height: mascotEyeFace.height + statusText.height + Style.space(4)

          // Eyes dart randomly around; cuter idle behavior
          property point look: Qt.point(0, 0)
          readonly property real eyeSize: Style.space(14)
          readonly property real pupilSize: Style.space(6)
          readonly property real lookRange: eyeSize / 4.0

          // Wink cycle in idle: left-eye wink at frame 4, right-eye wink at frame 11
          readonly property int winkPhase: frame % 14
          readonly property bool winkingLeft: state === "idle" && winkPhase === 4
          readonly property bool winkingRight: state === "idle" && winkPhase === 11
          readonly property bool blinking: state === "idle" && winkPhase === 9

          // Dart timer: eyes jump to a random spot, hold, jump again (idle/listening)
          Timer {
            running: root.state === "idle" || root.state === "listening"
            repeat: true
            interval: 1800 + Math.random() * 1600
            onTriggered: {
              var a = Math.random() * Math.PI * 2
              var r = Math.random() * mascot.lookRange
              mascot.look = Qt.point(Math.cos(a) * r, Math.sin(a) * r * 0.6)
            }
          }

          // Micro-jitter while busy (thinking/speaking)
          Timer {
            running: root.state === "thinking" || root.state === "speaking"
            repeat: true
            interval: 320
            onTriggered: {
              mascot.look = Qt.point((Math.random() - 0.5) * mascot.lookRange,
                                     (Math.random() - 0.5) * mascot.lookRange * 0.6)
            }
          }

          // Ease look back to center when timers stop (reset on state change)
          onStateChanged: mascot.look = Qt.point(0, 0)

          // Mascot head
          Item {
            id: mascotEyeFace
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: eyeL.width + Style.space(6) + eyeR.width + Style.space(12)
            height: Math.max(eyeL.height, mouthText.height)

            // Left eye (squints on wink/blink, pupil hides)
            Rectangle {
              id: eyeL
              x: 0
              anchors.verticalCenter: parent.verticalCenter
              width: mascot.eyeSize
              height: (mascot.winkingLeft || mascot.blinking) ? mascot.pupilSize : mascot.eyeSize * 1.35
              radius: width / 2
              color: root.mascotColor

              Behavior on height { NumberAnimation { duration: 90 } }

              Rectangle {
                anchors.centerIn: parent
                width: mascot.pupilSize
                height: mascot.pupilSize
                radius: width / 2
                color: Color.background
                visible: !mascot.winkingLeft && !mascot.blinking
                x: parent.width / 2 - width / 2 + mascot.look.x
                y: parent.height / 2 - height / 2 + mascot.look.y
              }
            }

            // Mouth
            Text {
              id: mouthText
              anchors.verticalCenter: parent.verticalCenter
              x: eyeL.width + Style.space(4)
              text: {
                if (root.state === "speaking") return (root.frame % 2 === 0) ? "o" : "‿"
                if (root.state === "listening") return "◡"
                if (root.state === "thinking") return "…"
                if (root.winkingLeft || root.winkingRight) return "ᴗ"   // cheeky grin while winking
                return "‿"
              }
              color: root.mascotColor
              font.family: "monospace"
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            // Right eye (squints on wink/blink, pupil hides)
            Rectangle {
              id: eyeR
              x: eyeL.width + Style.space(6) + mouthText.width + Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              width: mascot.eyeSize
              height: (mascot.winkingRight || mascot.blinking) ? mascot.pupilSize : mascot.eyeSize * 1.35
              radius: width / 2
              color: root.mascotColor

              Behavior on height { NumberAnimation { duration: 90 } }

              Rectangle {
                anchors.centerIn: parent
                width: mascot.pupilSize
                height: mascot.pupilSize
                radius: width / 2
                color: Color.background
                visible: !mascot.winkingRight && !mascot.blinking
                x: parent.width / 2 - width / 2 + mascot.look.x
                y: parent.height / 2 - height / 2 + mascot.look.y
              }
            }

            // Breathe/pulse while busy
            SequentialAnimation on opacity {
              running: root.state !== "idle"
              loops: Animation.Infinite
              NumberAnimation { to: 0.55; duration: 500 }
              NumberAnimation { to: 1.0; duration: 500 }
            }
          }

          Text {
            id: statusText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: {
              if (root.state === "thinking") return "thinking…"
              if (root.state === "listening") return "listening — tap mic to send"
              if (root.state === "speaking") return "speaking"
              return "ready"
            }
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }

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

          // caption under circle
          Text {
            anchors.top: micCircle.bottom
            anchors.topMargin: -Style.space(2)
            anchors.horizontalCenter: parent.horizontalCenter
            visible: false
            text: ""
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
  }

  Process {
    id: terminalProcess
    running: false
    command: ["foot", "-e", "tmux", "attach", "-t", "jarvis"]
  }

  // Mascot animation timer
  Timer {
    interval: root.state === "thinking" ? 250 : 500
    running: true
    repeat: true
    onTriggered: root.frame++
  }
}