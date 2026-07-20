import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// GPS health symbol: signal bars, fix tier, satellite count — tablet centre banner
// or compact pill on the phone MAP tab header.
Rectangle {
    id: root
    property bool compact: false
    property bool phoneGpsSource: app.lastSource === "tablet"
    readonly property color hue: Style.fixColor(gps.fixQuality, gps.stale)
    readonly property int barCount: gps.hdopValid ? Style.bars(gps.hdop, gps.hasFix) : 0

    function tierText() {
        if (gps.stale || !gps.hasFix) return qsTr("NO FIX")
        switch (gps.fixQuality) {
        case 4: return "RTK"
        case 5: return "RTK"
        case 2: return "DGPS"
        case 1: return root.phoneGpsSource ? "GNSS" : "GPS"
        default: return gps.fixText.toUpperCase()
        }
    }
    readonly property string fixLabel: gps.stale ? qsTr("STALE") : root.tierText()

    implicitWidth: root.compact ? compactRow.implicitWidth + 14 : row.width + 28
    implicitHeight: root.compact ? 28 : 44
    radius: root.compact ? 5 : 8
    color: Qt.rgba(hue.r, hue.g, hue.b, root.compact ? 0.22 : 0.18)
    border.color: hue
    border.width: 1
    clip: root.compact

    RowLayout {
        id: compactRow
        visible: root.compact
        anchors.centerIn: parent
        spacing: 4
        MdiIcon {
            icon: Icons.satellite
            color: root.hue
            font.pixelSize: 14
        }
        Text {
            text: root.fixLabel
            color: Style.white
            font.pixelSize: 10
            font.bold: true
        }
        Text {
            visible: gps.satellitesValid
            text: gps.satellites
            color: Style.white
            font.pixelSize: 10
            font.bold: true
        }
        Text {
            visible: root.phoneGpsSource && platform.cellularGeneration.length > 0
            text: platform.cellularGeneration
            color: Style.textDim
            font.pixelSize: 9
            font.bold: true
        }
    }

    Row {
        id: row
        visible: !root.compact
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
