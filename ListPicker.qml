import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Reusable dark-themed list selector with an optional inline "add new" row.
// Host sets title + model (list of strings) and handles onSelected / onAddRequested.
Popup {
    id: root
    modal: true
    dim: true
    padding: 16
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    parent: Overlay.overlay
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    width: 420
    height: 560

    property string title: ""
    property var model: []
    property bool allowAdd: true
    property string addPlaceholder: qsTr("New name")
    signal selected(string value)
    signal addRequested(string text)

    background: Rectangle {
        color: Style.panel
        border.color: Style.accent
        border.width: 1
        radius: 12
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: root.title; color: Style.accent; font.pixelSize: 18; font.bold: true
            }
            Button {
                text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                implicitWidth: 44; implicitHeight: 44
                onClicked: root.close()
            }
        }

        ListView {
            id: lv
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.model
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Rectangle {
                width: lv.width
                implicitHeight: 52
                radius: 8
                color: rma.pressed ? Style.accent : Style.bannerHi
                border.color: Style.panelEdge
                border.width: 1
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: rma.pressed ? Style.banner : Style.white
                    font.pixelSize: 17
                }
                MouseArea {
                    id: rma
                    anchors.fill: parent
                    onClicked: { root.selected(modelData); root.close(); }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !root.model || root.model.length === 0
            text: qsTr("Nothing here yet \u2014 add one below.")
            color: Style.textDim; font.pixelSize: 14; wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.allowAdd
            spacing: 8
            TextField {
                id: addField
                Layout.fillWidth: true
                placeholderText: root.addPlaceholder
                color: Style.white
                placeholderTextColor: Style.textDim
                selectByMouse: true
                background: Rectangle {
                    color: Style.bannerHi
                    border.color: addField.activeFocus ? Style.accent : Style.panelEdge
                    border.width: 1
                    radius: 6
                }
            }
            Button {
                text: qsTr("Add")
                enabled: addField.text.trim().length > 0
                onClicked: {
                    root.addRequested(addField.text.trim());
                    addField.text = "";
                }
            }
        }
    }
}
