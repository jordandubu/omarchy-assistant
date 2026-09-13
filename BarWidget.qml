import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-assistant"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  // ------------------------------------------------------------- state
  property string state: "idle"
  property string activity: ""
  property string setup: "ok"
  property var agents: []
  property bool assistantEnabled: true

  function toggleEnabled() {
    toggleEnabledProcess.running = true
  }

  Process {
    id: toggleEnabledProcess
    running: false
    command: [
      "bash",
      Qt.resolvedUrl("scripts/settings.sh").toString().replace("file://", ""),
      "toggle-enabled"
    ]
    onExited: {
      statusProcess.running = true
    }
  }

  readonly property color faceColor: {
    if (!assistantEnabled || state === "disabled") return Qt.rgba(1, 1, 1, 0.28)
    if (setup !== "ok") return Color.urgent
    if (state === "thinking") return Color.accent
    if (state === "listening") return Color.urgent
    if (state === "speaking") return Color.accent
    return bar ? bar.barForeground : Color.foreground
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // State poller: fast while busy, slow while idle
  Timer {
    interval: root.state !== "idle" ? 600 : 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusProcess.running = true
  }

  Component.onCompleted: {
    statusProcess.command = [
      "bash",
      Qt.resolvedUrl("scripts/status.sh").toString().replace("file://", "")
    ]
  }

  Process {
    id: statusProcess
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var s = JSON.parse(text.trim())
          root.state = s.state || "idle"
          root.activity = s.activity || ""
          root.setup = s.setup || "ok"
          root.agents = s.agents || []
          root.assistantEnabled = s.enabled !== false
        } catch (e) {}
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: (!root.assistantEnabled || root.state === "disabled") ? "AI Assistant (Disabled / Muted — click to open, right-click to enable)"
      : root.setup !== "ok" ? "Assistant needs setup — click to configure"
      : root.activity !== "" ? root.activity : "AI Assistant"
    iconComponent: Component {
      AssistantMark {
        state: (!root.assistantEnabled || root.state === "disabled") ? "disabled" : root.state
        setup: root.setup
        color: root.faceColor
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
      } else if (buttonCode === Qt.RightButton) {
        root.toggleEnabled()
      }
    }
  }
}