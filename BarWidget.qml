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

  // Plain cube; color carries the state
  readonly property string face: "◼"

  readonly property color faceColor: {
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
        } catch (e) {}
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.face
    fontFamily: "monospace"
    tooltipText: root.setup !== "ok" ? "Assistant needs setup — click to configure"
      : root.activity !== "" ? root.activity : "AI Assistant"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}