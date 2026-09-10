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
  property int reloadTick: 0

  function reload() {
    answerFile.reload()
    historyProcess.running = true
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function send() {
    var text = input.text.trim()
    if (text === "" || brainProcess.running) return
    brainProcess.command = [Quickshell.env("HOME") + "/.local/bin/jarvis-brain", text]
    brainProcess.running = true
    input.text = ""
    root.reload()
  }

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

  Component.onCompleted: {
    historyProcess.command = [
      "bash", "-c",
      "for f in $(ls -t ~/Work/jarvis-answers/*.log 2>/dev/null | head -20); do " +
      "  head -1 \"$f\" | cut -c1-100; " +
      "  tail -1 \"$f\" | cut -c1-100; " +
      "done"
    ]
  }

  Process {
    id: brainProcess
    running: false
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

        // Activity line while thinking
        Text {
          width: parent.width
          visible: root.activity !== ""
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

        Text {
          width: parent.width
          visible: root.lastAnswer === ""
          text: "Ask something — type below or hold F10 and speak."
          color: Color.muted
          font.pixelSize: Style.font.caption
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

        // Input row
        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: input
            width: parent.width - sendButton.width - Style.space(6)
            placeholderText: "Ask the assistant…"
            onAccepted: root.send()
          }

          Button {
            id: sendButton
            text: "Send"
            onClicked: root.send()
          }
        }

        // Footer actions
        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Stop"
            visible: root.state === "thinking"
            onClicked: root.close()
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
}