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
  property string language: "en"
  property var setupItems: []
  property string setupState: "ok"   // ok | incomplete | running
  property var personaOptions: ["default"]
  property var voiceOptions: ["george"]

  readonly property bool needsSetup: (hostWidget ? hostWidget.setup : "ok") !== "ok"
    || setupState === "incomplete"


  readonly property bool micActive: state === "listening"
  // Theme-derived contrast (same pattern as first-party panels: dim from foreground)
  readonly property color foreground: bar ? bar.barForeground : Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent


  // Settings table: one row per setting (label + dropdown + apply)
  readonly property var settingRows: [
    {
      label: "Brain",
      options: ["omp", "opencode", "claude", "codex", "gemini", "cursor-agent", "crush"],
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
      label: "Language",
      options: ["en", "fr", "de", "it", "es", "pt"],
      value: language,
      apply: function(v) {
        language = v
        setSetting("language", v)
        // voice must match language; reset to that language's first voice
        var map = {"en":"george","fr":"estelle","de":"juergen","it":"giovanni","es":"lola","pt":"rafael"}
        ttsVoice = map[v] || "george"
        setSetting("tts.voice", ttsVoice)
        setSetting("tts.backend", "kyutai")
        voicesProcess.running = true
      }
    },
    {
      label: "Wake word",
      options: ["on", "off"],
      value: wakeWordOn,
      apply: function(v) {
        wakeWordOn = v
        setSetting("wake_word.enabled", v === "on" ? "true" : "false")
      }
    },
    {
      label: "Live activity",
      options: ["on", "off"],
      value: liveActivity,
      apply: function(v) { setSetting("live_activity", v); liveActivity = v }
    }
  ]

  property string wakeWordOn: "on"

  function reload() {
    answerFile.reload()
    historyProcess.running = true
    settingsGetProcess.running = true
    personasProcess.running = true
    voicesProcess.running = true
    setupCheckProcess.running = true
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
        // one line: brain|personality|stt|voice|live|lang|wake
        var p = String(text || "").trim().split("|")
        if (p.length >= 4) {
          root.brain = p[0]
          root.personality = p[1]
          root.sttEngine = p[2]
          root.ttsVoice = p[3]
          if (p.length >= 5) root.liveActivity = p[4]
          if (p.length >= 6) root.language = p[5]
          if (p.length >= 7) root.wakeWordOn = p[6]
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

  readonly property string scriptDir: {
    var u = Qt.resolvedUrl("scripts/")
    return u.toString().replace("file://", "")
  }

  function setSetting(key, value) {
    settingsSetProcess.command = [
      scriptDir + "settings.sh",
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

  // Setup check/run
  Process {
    id: setupCheckProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text.trim())
          root.setupItems = s.items || []
          root.setupState = s.setup || "ok"
        } catch (e) { root.setupState = "ok"; root.setupItems = [] }
      }
    }
  }

  Process {
    id: setupRunProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text.trim())
          root.setupItems = s.items || []
          root.setupState = s.setup || "ok"
        } catch (e) { root.setupState = "ok" }
      }
    }
  }

  function runSetup() {
    if (setupState === "running") return
    setupState = "running"
    setupRunProcess.running = true
  }

  Component.onCompleted: {
    var sh = root.scriptDir
    historyProcess.command = [
      "bash", "-c",
      "for f in $(ls -t ~/Work/jarvis-answers/*.log 2>/dev/null | head -20); do " +
      "  head -1 \"$f\" | cut -c1-100; " +
      "  tail -1 \"$f\" | cut -c1-100; " +
      "done"
    ]
    settingsGetProcess.command = ["bash", "-c",
      "sh=" + sh + "/settings.sh; " +
      "echo \"$(\"$sh\" get brain)|$(\"$sh\" get personality)|$(\"$sh\" get stt_engine)|$(\"$sh\" get tts.voice)|$(\"$sh\" get live_activity)|$(\"$sh\" get language)|$(\"$sh\" get wake_word.enabled)\""]
    personasProcess.command = ["bash", "-c", sh + "/settings.sh personas"]
    voicesProcess.command = ["bash", "-c", sh + "/settings.sh voices"]
    setupCheckProcess.command = ["bash", "-c",
      "sh=" + sh + "; rm -f \"$XDG_RUNTIME_DIR/omarchy-assistant-setup-cache\"; " +
      "\"$sh/setup-status.sh\" 2>/dev/null || echo '{\"setup\":\"ok\",\"items\":[]}'"]
    setupRunProcess.command = ["bash", "-c",
      "sh=" + sh + "; \"$sh/install.sh\" >/tmp/omarchy-assistant-setup.log 2>&1; " +
      "rm -f \"$XDG_RUNTIME_DIR/omarchy-assistant-setup-cache\"; \"$sh/setup-status.sh\" 2>/dev/null"]
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
        spacing: Style.space(10)

        // ---------- Hero: assistant name + state ----------
        PanelHero {
          width: parent.width
          title: root.needsSetup ? "Assistant — Setup" : "Assistant"
          meta: {
            if (root.needsSetup && root.setupState === "running") return "setting up…"
            if (root.needsSetup) return "setup required"
            if (root.state === "thinking") return "working…"
            if (root.state === "listening") return "listening"
            if (root.state === "speaking") return "speaking"
            return "ready"
          }
          foreground: (root.needsSetup || root.state === "listening") ? root.urgent : Color.popups.text
          fontFamily: root.fontFamily
          iconComponent: Component {
            Item {
              width: Style.font.display
              height: Style.font.display

              Text {
                text: "◼"
                font.family: "monospace"
                font.pixelSize: Style.font.display
              }
            }
          }
        }
        // ---------- Setup card (shown until setup complete) ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.needsSetup

          PanelSectionHeader {
            text: "Setup"
          }

          Repeater {
            model: root.setupItems

            Row {
              required property int index
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.ok ? "✓" : "✗"
                color: modelData.ok ? Color.accent : root.urgent
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width - Style.space(20)
                text: modelData.label
                color: modelData.ok ? root.dim : Color.popups.text
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Button {
            width: parent.width
            text: root.setupState === "running" ? "Setting up…" : "Run setup"
            enabled: root.setupState !== "running"
            onClicked: root.runSetup()
          }

          Text {
            width: parent.width
            visible: root.setupState === "running"
            text: "Installing pipeline, wake-word model and keybindings…"
            color: root.dim
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Mic: hero control on tinted card ----------
        Row {
          visible: !root.needsSetup
          width: parent.width
          spacing: Style.space(10)

          Button {
            id: micButton
            width: Style.space(44)
            height: Style.space(44)
            text: root.micActive ? "◼" : "◻"
            fontSize: Style.font.heading
            tooltipText: root.micActive ? "Stop & send" : "Start voice request"
            active: root.micActive
            onClicked: root.toggleMic()
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: {
                if (root.state === "listening") return "listening — tap again to send"
                if (root.state === "thinking") return "working on it…"
                if (root.state === "speaking") return "speaking…"
                return "tap to talk"
              }
              color: root.state === "listening" ? root.urgent : Color.popups.text
              font.pixelSize: Style.font.body
            }

            Text {
              // Show what was heard while working: strip "[HH:MM:SS] prompt: " prefix
              property string heard: {
                var a = root.activity || ""
                var i = a.indexOf("prompt: ")
                return i >= 0 ? a.substring(i + 8) : a
              }
              text: root.state === "thinking" ? ("heard: " + (root.heard || ""))
                    : root.state === "idle" ? "or hold SUPER+A and speak"
                    : ""
              visible: text !== "" && !(root.state === "thinking" && root.heard === "")
              color: root.state === "thinking" ? root.foreground : root.foreground
              opacity: root.state === "thinking" ? 1.0 : 0.75
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }
        }

        // ---------- Activity banner ----------
        Text {
          visible: !root.needsSetup && root.activity !== "" && root.liveActivity !== "off"
          text: root.activity
          color: root.dim
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        // ---------- Answer ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: !root.needsSetup && root.lastAnswer !== ""

          PanelSectionHeader {
            text: "Answer"
          }

          Text {
            width: parent.width
            text: root.lastAnswer
            color: Color.popups.text
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Recent ----------
        Column {
          width: parent.width
          spacing: Style.space(3)
          visible: !root.needsSetup && root.historyLines.length > 0

          PanelSectionHeader {
            text: "Recent"
          }

          Repeater {
            model: root.historyLines.length > 3 ? 3 : root.historyLines.length

            Text {
              required property int index
              width: parent.width
              text: "· " + (root.historyLines[index] || "")
              color: root.dim
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }
        }

        // ---------- Settings: rows on a tinted card ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "Settings"
          }

          Repeater {
            model: root.settingRows

            delegate: Row {
              required property int index
              width: parent.width
              height: Style.space(30)
              spacing: Style.space(8)

              Text {
                  width: parent.width * 0.40
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.settingRows[index].label
                  color: root.dim
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
              }

              Dropdown {
                  width: parent.width * 0.60 - Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  options: root.settingRows[index].options
                  value: root.settingRows[index].value
                  onChanged: function(v) { root.settingRows[index].apply(v) }
              }
            }
          }
        }

        // ---------- Stop banner (while working) ----------
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
