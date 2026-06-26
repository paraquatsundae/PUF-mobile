import QtQuick 2.15
import "Style.js" as Style

// A configurable side column of info elements.
Rectangle {
    id: root
    property var elements: []

    color: Style.banner

    Flickable {
        anchors.fill: parent
        anchors.margins: 8
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: 8
            Repeater {
                model: root.elements
                InfoElement { elementId: modelData }
            }
        }
    }
}
