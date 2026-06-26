import QtQuick 2.15
import "Style.js" as Style

// A bottom-banner soft key. Width/contents are data-driven by the layout model.
Rectangle {
    id: root
    property string label: ""
    property string glyph: ""
    property bool enabledKey: true
    property bool active: false
    signal activated()

    radius: 8
    color: ma.pressed ? Style.accent : (active ? "#c0392b" : Style.panel)
    border.color: active ? "#e74c3c" : Style.panelEdge
    border.width: active ? 2 : 1
    opacity: enabledKey ? 1.0 : 0.4

    Column {
        anchors.centerIn: parent
        spacing: 2
        MdiIcon {
            visible: root.glyph.length > 0
            icon: root.glyph
            anchors.horizontalCenter: parent.horizontalCenter
            color: ma.pressed ? Style.banner : Style.accent
            font.pixelSize: 26
        }
        Text {
            text: root.label
            anchors.horizontalCenter: parent.horizontalCenter
            color: ma.pressed ? Style.banner : Style.white
            font.pixelSize: 13
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.enabledKey
        onClicked: root.activated()
    }
}
