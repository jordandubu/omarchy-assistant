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
  readonly property var agents: hostWidget ? (hostWidget.agents || []) : []
  property bool assistantEnabled: hostWidget ? hostWidget.assistantEnabled : true

  function toggleEnabled() {
    assistantEnabled = !assistantEnabled
    if (hostWidget && typeof hostWidget.toggleEnabled === "function") {
      hostWidget.toggleEnabled()
    } else {
      toggleEnabledProcess.running = true
    }
  }

  Process {
    id: toggleEnabledProcess
    running: false
    command: [
      root.scriptDir + "settings.sh",
      "toggle-enabled"
    ]
    onExited: {
      root.reload()
    }
  }

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

  // Theme-derived contrast (same pattern as first-party panels: dim from foreground)
  readonly property color foreground: bar ? bar.barForeground : Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent


  // Settings table: one row per setting (label + dropdown + apply)
  readonly property var settingRows: [
    {
      label: "Assistant power",
      options: ["enabled", "disabled"],
      value: (root.assistantEnabled && root.state !== "disabled") ? "enabled" : "disabled",
      apply: function(v) {
        if (v === "disabled" && root.assistantEnabled) root.toggleEnabled()
        else if (v === "enabled" && !root.assistantEnabled) root.toggleEnabled()
      }
    },
    {
      label: "Brain",
      options: ["omp", "agy", "opencode", "claude", "codex", "gemini", "cursor-agent", "crush"],
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

  // Settings IO
  Process {
    id: settingsGetProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // one line: brain|personality|stt|voice|live|lang|wake|enabled
        var p = String(text || "").trim().split("|")
        if (p.length >= 4) {
          root.brain = p[0]
          root.personality = p[1]
          root.sttEngine = p[2]
          root.ttsVoice = p[3]
          if (p.length >= 5) root.liveActivity = p[4]
          if (p.length >= 6) root.language = p[5]
          if (p.length >= 7) root.wakeWordOn = p[6]
          if (p.length >= 8) root.assistantEnabled = (p[7].trim() === "true")
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
  }

  function stopAgent() {
    stopProcess.command = [root.scriptDir + "jarvis-stop"]
    stopProcess.running = true
  }

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
    settingsGetProcess.command = ["bash", "-c",
      "sh=" + sh + "/settings.sh; " +
      "echo \"$(\"$sh\" get brain)|$(\"$sh\" get personality)|$(\"$sh\" get stt_engine)|$(\"$sh\" get tts.voice)|$(\"$sh\" get live_activity)|$(\"$sh\" get language)|$(\"$sh\" get wake_word.enabled)|$(\"$sh\" is-enabled)\""]
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

        // ---------- Hero: assistant name + state + power switch ----------
        PanelHero {
          id: hero
          width: parent.width
          title: root.needsSetup ? "Assistant — Setup" : "Assistant"
          meta: {
            if (!root.assistantEnabled || root.state === "disabled") return "disabled"
            if (root.needsSetup && root.setupState === "running") return "setting up…"
            if (root.needsSetup) return "setup required"
            if (root.state === "thinking") return "working…"
            if (root.state === "listening") return "listening"
            if (root.state === "speaking") return "speaking"
            return "ready"
          }
          foreground: (!root.assistantEnabled || root.state === "disabled") ? root.dim : (root.needsSetup || root.state === "listening") ? root.urgent : Color.popups.text
          iconComponent: Component {
            AssistantMark {
              width: Style.font.display
              height: Style.font.display
              state: (!root.assistantEnabled || root.state === "disabled") ? "disabled" : root.state
              setup: root.setupState
              color: (!root.assistantEnabled || root.state === "disabled") ? root.dim : (root.needsSetup || root.state === "listening") ? root.urgent : (root.state === "thinking" || root.state === "speaking") ? Color.accent : Color.popups.text
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              checked: root.assistantEnabled && root.state !== "disabled"
              foreground: hero.foreground
              onToggled: root.toggleEnabled()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: (root.assistantEnabled && root.state !== "disabled") ? "Click to disable assistant completely" : "Click to enable assistant"
              }
            }
          }
        }

        // ---------- Disabled state banner (shown when assistant is off) ----------
        Rectangle {
          visible: !root.assistantEnabled || root.state === "disabled"
          width: parent.width
          implicitHeight: disabledCol.implicitHeight + Style.space(16)
          color: Qt.rgba(1, 0.2, 0.2, 0.08)
          radius: Style.cornerRadius
          border.width: 1
          border.color: root.urgent

          Column {
            id: disabledCol
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "●"
                color: root.urgent
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: "Assistant Completely Disabled"
                color: root.urgent
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              width: parent.width
              text: "Wake-word ('Omarchy'), microphone listening, and background agent brains are completely shut off."
              color: Color.popups.text
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: "Enable Assistant"
              onClicked: root.toggleEnabled()
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

        // ---------- Active Agents (shown when agents are running) ----------
        Column {
          visible: !root.needsSetup && (root.agents.length > 0 || root.state === "thinking")
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Agents Working (" + (root.agents.length > 0 ? root.agents.length : 1) + ")"
          }

          Repeater {
            model: root.agents.length > 0 ? root.agents : [{
              name: "Assistant Brain",
              prompt: "Working on task…",
              step: root.activity || "Thinking…"
            }]

            delegate: Rectangle {
              required property int index
              required property var modelData
              width: parent.width
              implicitHeight: agentCol.implicitHeight + Style.space(16)
              color: Qt.rgba(1, 1, 1, 0.05)
              radius: Style.cornerRadius
              border.width: 1
              border.color: Color.accent

              Column {
                id: agentCol
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: "●"
                    color: Color.accent
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: modelData.name || "Agent"
                    color: Color.accent
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Item {
                    width: parent.width - (parent.spacing * 3) - Style.space(110)
                    height: 1
                  }

                  Button {
                    text: "Stop"
                    width: Style.space(56)
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.stopAgent()
                  }
                }

                Text {
                  width: parent.width
                  visible: (modelData.prompt || "").length > 0
                  text: modelData.prompt || ""
                  color: Color.popups.text
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: modelData.step || "Working…"
                  color: root.dim
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        // ---------- Settings: rows on a tinted card ----------
        Column {
          visible: !root.needsSetup
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
      }
    }
  }
}
