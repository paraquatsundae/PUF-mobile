import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Compact GPS strip: sat colour, correction tier, optional 4G/5G for phone GNSS.
Rectangle {
    id: root
    property bool showTitle: false
    property bool phoneGpsSource: app.lastSource === "tablet"
    readonly property color satColor: Style.fixColor(gps.fixQuality, gps.stale)

    function tierText() {
        if (gps.stale || !gps.hasFix) return qsTr("NO FIX")
        switch (gps.fixQuality) {
        case 4: return "RTK"
        case 5: return "RTK"
        case 2: return "DGPS"
        case 1: return phoneGpsSource ? "GNSS" : "GPS"
        default: return gps.fixText.toUpperCase()
        }
    }

    // Main tab: banner owns the status-bar band. Map tab: parent Rectangle already
    // pads below the inset — do not apply it again (was double-counting on Mali).
    readonly property int _topInset: root.showTitle ? Math.max(28, platform.statusBarInset) : 0

    implicitHeight: 40 + root._topInset
    color: theme.banner
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root._topInset
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        height: 40
        spacing: 10
        Text {
            visible: root.showTitle
            text: "PUF"
            color: theme.accent
            font.pixelSize: 20
            font.bold: true
        }
        MdiIcon {
            icon: Icons.satellite
            color: root.satColor
            font.pixelSize: 22
        }
        Text {
            text: tierText()
            color: theme.text
            font.pixelSize: 16
            font.bold: true
        }
        Text {
            visible: root.phoneGpsSource && platform.cellularGeneration.length > 0
            text: platform.cellularGeneration
            color: theme.textDim
            font.pixelSize: 14
            font.bold: true
        }
        Item { Layout.fillWidth: true }
    }
}
