import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

// A labelled value card used on the data page.
Rectangle {
    property string label: ""
    property string value: "--"
    Layout.fillWidth: true
    implicitHeight: 82
    radius: 8
    color: Style.panel
    border.color: Style.panelEdge
    border.width: 1

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 2
        Text { text: label; color: Style.textDim; font.pixelSize: 13 }
        Text {
            text: value; color: Style.white; font.pixelSize: 28; font.bold: true
            elide: Text.ElideRight; width: parent.width
        }
    }
}
