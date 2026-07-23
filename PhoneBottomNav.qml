import QtQuick 2.15

import QtQuick.Layouts 1.15



Rectangle {

    id: root

    property string currentTab: "main"

    signal tabSelected(string tab)

    // Compact tab row — gesture inset is painted by PhoneShell, not here.
    readonly property int barHeight: 44

    implicitHeight: barHeight
    Layout.preferredHeight: barHeight
    Layout.minimumHeight: barHeight
    Layout.maximumHeight: barHeight

    color: theme.banner

    RowLayout {

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.barHeight

        Repeater {

            model: [

                { id: "main", label: qsTr("MAIN") },

                { id: "map", label: qsTr("MAP") },

                { id: "setup", label: qsTr("SETUP") }

            ]

            Rectangle {

                Layout.fillWidth: true

                Layout.fillHeight: true

                color: ma.pressed ? theme.bannerHi

                     : (modelData.id === root.currentTab ? theme.panel : "transparent")

                Text {

                    anchors.centerIn: parent

                    text: modelData.label

                    color: modelData.id === root.currentTab ? theme.accent : theme.textDim

                    font.pixelSize: 14

                    font.bold: modelData.id === root.currentTab

                }

                MouseArea {

                    id: ma

                    anchors.fill: parent

                    onClicked: root.tabSelected(modelData.id)

                }

            }

        }

    }

}

