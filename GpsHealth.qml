import QtQuick 2.15
import "Style.js" as Style
import "Icons.js" as Icons

// GPS health symbol for the centre of the top banner: signal bars (from HDOP),
// fix-type text and satellite count, coloured by fix quality.
Rectangle {
    id: root
    readonly property color hue: Style.fixColor(gps.fixQuality, gps.stale)
    readonly property int barCount: gps.hdopValid ? Style.bars(gps.hdop, gps.hasFix) : 0

    implicitWidth: row.width + 28
    implicitHeight: 44
    radius: 8
    color: Qt.rgba(hue.r, hue.g, hue.b, 0.18)
    border.color: hue
    border.width: 1

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12

        // signal bars
        Row {
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: 5
                Rectangle {
                    width: 6
                    height: 8 + index * 5
                    radius: 1
                    anchors.bottom: parent.bottom
                    color: index < root.barCount ? root.hue : "#33ffffff"
                }
            }
        }

        // satellite glyph + count
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            MdiIcon { icon: Icons.satellite; color: root.hue; font.pixelSize: 20
                   anchors.verticalCenter: parent.verticalCenter }
            Text { text: gps.satellitesValid ? gps.satellites : "\u2014"; color: Style.white
                   font.pixelSize: 20; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        }

        // fix text
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2
            Text { text: gps.stale ? "STALE" : gps.fixText; color: Style.white
                   font.pixelSize: 16; font.bold: true }
            Text { text: gps.hdopValid ? "HDOP " + gps.hdop.toFixed(1) : "HDOP \u2014"
                   color: Style.textDim; font.pixelSize: 11 }
        }
    }
}
