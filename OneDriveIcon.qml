import QtQuick
import QtQuick.Shapes
import qs.Commons

// Filled dual-cloud OneDrive mark (Mac tray / Icons8 iOS glyph):
// a smaller back cloud with an arch, and a larger front cloud, with a
// crescent gap between them. Theme-colored fill, no stroke.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  readonly property real markWidth: 106
  readonly property real markHeight: 66

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

      // Back cloud (left puffs + arch)
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        strokeWidth: 0
        fillRule: ShapePath.WindingFill
        PathSvg {
          path: "M1 46 A14 14 0 0 1 12 33.5 A18.5 18.5 0 0 1 29.5 12.5 A21.5 21.5 0 0 1 61.5 2.2 A21.5 21.5 0 0 1 78.8 20 L76.2 22.6 A24.5 24.5 0 0 0 58 16 A26 26 0 0 0 36 32.5 A18 18 0 0 0 22.5 42.5 A16 16 0 0 0 21.2 60.8 L11.5 60.8 A14 14 0 0 1 1 46 Z"
        }
      }

      // Front cloud
      ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        strokeWidth: 0
        fillRule: ShapePath.WindingFill
        PathSvg {
          path: "M27 51 A14.5 14.5 0 0 1 41.5 38 A19.2 19.2 0 0 1 60.2 23 A18.5 18.5 0 0 1 74.5 30.2 A13 13 0 0 1 90 30 A18.5 18.5 0 0 1 105 53 A13.5 13.5 0 0 1 96.2 66 L38.2 66 A14.5 14.5 0 0 1 27 51 Z"
        }
      }
    }
  }
}
