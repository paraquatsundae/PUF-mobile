import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Elements.js" as Elements
import "Icons.js" as Icons

Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Display titles for run-page ids (set from main.qml).
    property var runTitles: ({})
    function titleFor(id) { return runTitles[id] !== undefined ? runTitles[id] : id; }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 14

        Label { text: qsTr("Layout Manager"); color: Style.accent; font.pixelSize: 20; font.bold: true }

        // ---- Active pages (which pages the top pager cycles, and order) ----
        Label { text: qsTr("Active pages (pager cycle)"); color: Style.textDim; font.pixelSize: 14 }
        Repeater {
            model: layout.runCatalog
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                property bool isActive: (layout.activePages, layout.pageActive(modelData))
                property int pos: (layout.activePages, layout.activePages.indexOf(modelData))
                Switch {
                    checked: parent.isActive
                    onToggled: layout.setPageActive(modelData, checked)
                }
                Label { text: page.titleFor(modelData); color: Style.white; font.pixelSize: 15
                        Layout.fillWidth: true }
                Label { text: parent.isActive ? ("#" + (parent.pos + 1)) : qsTr("off")
                        color: Style.textDim; font.pixelSize: 13; Layout.preferredWidth: 40 }
                Button { text: Icons.chevronUp; font.family: Icons.family; implicitWidth: 44
                         enabled: parent.isActive && parent.pos > 0
                         onClicked: layout.movePage(modelData, -1) }
                Button { text: Icons.chevronDown; font.family: Icons.family; implicitWidth: 44
                         enabled: parent.isActive && parent.pos >= 0 && parent.pos < layout.activePages.length - 1
                         onClicked: layout.movePage(modelData, 1) }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

        // Per-page column visibility
        Label { text: qsTr("Columns per page"); color: Style.textDim; font.pixelSize: 14 }
        Repeater {
            model: layout.runCatalog
            RowLayout {
                Layout.fillWidth: true
                spacing: 20
                Label { text: page.titleFor(modelData); color: Style.white; font.pixelSize: 15
                        Layout.preferredWidth: 90 }
                RowLayout {
                    spacing: 8
                    Switch {
                        checked: layout.leftVisibleFor(modelData)
                        onToggled: layout.setLeftVisibleFor(modelData, checked)
                    }
                    Label { text: qsTr("Left"); color: Style.textDim; font.pixelSize: 14 }
                }
                RowLayout {
                    spacing: 8
                    Switch {
                        checked: layout.rightVisibleFor(modelData)
                        onToggled: layout.setRightVisibleFor(modelData, checked)
                    }
                    Label { text: qsTr("Right"); color: Style.textDim; font.pixelSize: 14 }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

        Label { text: qsTr("Elements"); color: Style.textDim; font.pixelSize: 14 }

        // header row
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Element"); color: Style.textDim; font.pixelSize: 12; Layout.fillWidth: true }
            Label { text: qsTr("Left");  color: Style.textDim; font.pixelSize: 12; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter }
            Label { text: qsTr("Right"); color: Style.textDim; font.pixelSize: 12; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter }
        }

        // one row per available element
        Repeater {
            model: Elements.order
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 6
                    color: Style.panel
                    border.color: Style.panelEdge; border.width: 1
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: Elements.label(modelData); color: Style.white; font.pixelSize: 15
                    }
                }
                Button {
                    Layout.preferredWidth: 70
                    implicitHeight: 48
                    checkable: false
                    checked: (layout.leftElements, layout.contains("left", modelData))
                    text: checked ? Icons.check : Icons.plus
                    font.family: Icons.family
                    onClicked: layout.toggle("left", modelData)
                }
                Button {
                    Layout.preferredWidth: 70
                    implicitHeight: 48
                    checkable: false
                    checked: (layout.rightElements, layout.contains("right", modelData))
                    text: checked ? Icons.check : Icons.plus
                    font.family: Icons.family
                    onClicked: layout.toggle("right", modelData)
                }
            }
        }

        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            color: Style.textDim; font.pixelSize: 13
            text: qsTr("Toggle elements into the left/right columns. The centre view "
                       + "scales to fill whatever space remains.")
        }
    }
}
