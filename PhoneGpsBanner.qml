import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Compact GPS strip: sat colour, correction tier, optional 4G/5G for phone GNSS.
Rectangle {
    id: root
    property bool showTitle: false
    // Map tab header: single-row strip sized by parent (no 40 px inner layout).
    property bool compact: false
    property bool phoneGpsSource: app.lastSource === "tablet"
    readonly property color satColor: Style.fixColor(gps.fixQuality, gps.stale)
    readonly property int _rowH: root.compact ? height : 40

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

    implicitHeight: root.compact ? 36 : (40 + root._topInset)
    color: theme.banner
    clip: root.compact
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.compact ? 0 : root._topInset
        anchors.bottom: root.compact ? parent.bottom : undefined
        anchors.leftMargin: root.compact ? 6 : 10
        anchors.rightMargin: root.compact ? 0 : 10
        height: root._rowH
        spacing: root.compact ? 4 : 10
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
            font.pixelSize: root.compact ? 15 : 22
        }
        Text {
            text: tierText()
            color: theme.text
            font.pixelSize: root.compact ? 11 : 16
            font.bold: true
            elide: Text.ElideRight
            Layout.maximumWidth: root.compact ? 56 : 10000
        }
        Text {
            visible: root.phoneGpsSource && platform.cellularGeneration.length > 0
            text: platform.cellularGeneration
            color: theme.textDim
            font.pixelSize: root.compact ? 10 : 14
            font.bold: true
        }
        Item { visible: !root.compact; Layout.fillWidth: true }
    }
}
