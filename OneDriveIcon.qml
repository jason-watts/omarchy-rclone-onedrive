import QtQuick
import QtQuick.Shapes
import qs.Commons

// Official 2025 OneDrive mark: cloud split by an S-wave (hook + top lobe +
// bottom lobe). Theme-colored fill so the wave stays a transparent gap.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  readonly property real markWidth: 104
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
      preferredRendererType: Shape.CurveRenderer
      layer.enabled: true
      layer.samples: 8
      layer.smooth: true

      // Left hook (start of the S-wave)
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        strokeWidth: 0
        PathSvg {
          path: "M0.5 35.5 C1 26 11 13 21.5 10.5 C15 17 9 27 6.5 36.5 C3.5 38 1 37.5 0.5 35.5 Z"
        }
      }

      // Top / left body
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        strokeWidth: 0
        PathSvg {
          path: "M1.2 45 C2 36 16 12 42 1.5 C56 -0.5 70 4 82.5 13.8 C72 16.5 60 24 46 44 C38 56 33 61 29 63.2 C20 64.5 8 59 2.5 50 C1.5 48 1.2 46.5 1.2 45 Z"
        }
      }

      // Bottom / right body
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        strokeWidth: 0
        PathSvg {
          path: "M39 64 C52 44 64 26 78 19.8 C90 16.5 102 26 104 42 C104.5 52 100 60 90 63.2 C82 64.5 70 64 39 64 Z"
        }
      }
    }
  }
}
