import QtQuick
import QtQuick.Shapes
import qs.Commons

// Outlined dual-cloud OneDrive mark (two overlapping cloud strokes),
// matching the macOS / Microsoft tray glyph. Theme-colored, no fill.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  readonly property real markWidth: 96
  readonly property real markHeight: 64

  width: iconSize * (markWidth / markHeight)
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  Item {
    width: root.markWidth
    height: root.markHeight
    transform: Scale {
      xScale: root.width / root.markWidth
      yScale: root.height / root.markHeight
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      layer.smooth: true

      // Outer cloud
      ShapePath {
        fillColor: Qt.rgba(0, 0, 0, 0)
        strokeColor: root.color
        strokeWidth: 5.5
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M14 40 C12 30 20 22 30 23 C32 13 46 10 56 16 C64 9 80 12 84 24 C93 26 96 36 90 44 C94 54 82 58 70 57 L28 57 C16 58 12 50 14 40 Z"
        }
      }

      // Overlapping inner cloud
      ShapePath {
        fillColor: Qt.rgba(0, 0, 0, 0)
        strokeColor: root.color
        strokeWidth: 5.5
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M38 38 C36 28 46 22 56 24 C58 16 70 14 78 22 C86 18 94 26 92 36 C98 38 98 48 90 50 C92 56 82 58 72 56 L52 56 C42 57 36 48 38 38 Z"
        }
      }
    }
  }
}
