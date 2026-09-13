import QtQuick
import qs.Commons

Item {
  id: root

  property string state: "idle"       // idle | listening | thinking | speaking
  property string setup: "ok"         // ok | incomplete | running
  property color color: Color.foreground

  implicitWidth: Style.bar.iconCanvas
  implicitHeight: Style.bar.iconCanvas

  readonly property real barWidth: Math.max(2, Math.round(width * 0.14))
  readonly property real barRadius: barWidth / 2
  readonly property real gap: Math.max(1.5, (width - (4 * barWidth)) / 3)
  readonly property real rowWidth: (4 * barWidth) + (3 * gap)

  // Wave phase for continuous animation loops
  property real wavePhase: 0

  NumberAnimation on wavePhase {
    running: root.visible && root.state !== "idle"
    from: 0
    to: Math.PI * 2
    duration: root.state === "listening" ? 650 : root.state === "thinking" ? 950 : 750
    loops: Animation.Infinite
  }

  // Idle breath animation
  property real idleBreath: 0
  SequentialAnimation on idleBreath {
    running: root.visible && root.state === "idle"
    loops: Animation.Infinite
    NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
  }

  Item {
    id: container
    anchors.centerIn: parent
    width: root.rowWidth
    height: root.height

    Repeater {
      model: 4

      Rectangle {
        required property int index
        id: bar

        readonly property real baseH: {
          if (index === 0) return 0.35
          if (index === 1) return 0.75
          if (index === 2) return 1.00
          return 0.55
        }

        readonly property real targetHeight: {
          var h = container.height
          if (root.setup !== "ok") {
            return Math.max(bar.width, h * baseH * 0.65)
          }
          if (root.state === "idle") {
            var breath = 0.88 + 0.24 * root.idleBreath
            return Math.max(bar.width, h * baseH * breath)
          }
          if (root.state === "listening") {
            var s = Math.sin(root.wavePhase + index * 1.5)
            var norm = (s + 1) / 2
            return Math.max(bar.width, h * (0.25 + 0.75 * norm))
          }
          if (root.state === "thinking") {
            var offset = root.wavePhase - index * (Math.PI / 2)
            var w = Math.sin(offset)
            var norm = Math.max(0, w)
            return Math.max(bar.width, h * (0.25 + 0.70 * norm))
          }
          if (root.state === "speaking") {
            var s = Math.sin(root.wavePhase * 1.5 + index * 1.0)
            var norm = (s + 1) / 2
            return Math.max(bar.width, h * (0.30 + 0.65 * norm))
          }
          return Math.max(bar.width, h * baseH)
        }

        x: index * (root.barWidth + root.gap)
        width: root.barWidth
        height: targetHeight
        anchors.verticalCenter: parent.verticalCenter
        radius: root.barRadius
        color: root.color

        Behavior on color {
          ColorAnimation { duration: 180 }
        }
      }
    }
  }
}
