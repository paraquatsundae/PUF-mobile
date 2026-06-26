import QtQuick 2.15
import "Style.js" as Style

// A page-selector button for the top-left of the banner.
Rectangle {
    id: root
    property string label: ""
    property string glyph: ""
    property bool active: false
    signal clicked()

    implicitWidth: Math.max(64, content.width + 22)
    implicitHeight: 48
    radius: 8
    color: active ? Style.accent : (ma.pressed ? Style.bannerHi : "transparent")
    border.color: active ? Style.accent : Style.panelEdge
    border.width: 1

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 0
        MdiIcon {
            visible: root.glyph.length > 0
            icon: root.glyph
            anchors.horizontalCenter: parent.horizontalCenter
            color: active ? Style.banner : Style.white
            font.pixelSize: 20
        }
        Text {
            text: root.label
            anchors.horizontalCenter: parent.horizontalCenter
            color: active ? Style.banner : Style.white
            font.pixelSize: 14
            font.bold: active
        }
    }

    MouseArea { id: ma; anchors.fill: parent; onClicked: root.clicked() }
}
