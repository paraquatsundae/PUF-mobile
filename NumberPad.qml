import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

// Reusable dark-themed numeric keypad with a unit picker, for touch entry of a
// rate/value. Host opens it with openWith(initialValue, initialUnit) and handles
// onAccepted(value, unit).
Popup {
    id: root
    modal: true
    dim: true
    padding: 16
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    parent: Overlay.overlay
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    width: 340
    height: 540

    property string title: qsTr("Enter value")
    property var units: ["g", "kg", "t", "ml", "L"]
    property string unit: units.length ? units[0] : ""
    property string value: ""
    signal accepted(real value, string unit)

    function openWith(initial, initUnit) {
        value = (initial !== undefined && initial !== null && !isNaN(initial) && initial > 0)
                ? String(initial) : "";
        if (initUnit && initUnit.length)
            unit = initUnit;
        open();
    }
    function _press(k) {
        if (k === "<") { value = value.slice(0, -1); return; }
        if (k === ".") {
            if (value.indexOf(".") === -1)
                value = (value.length ? value : "0") + ".";
            return;
        }
        value = value + k;
    }

    background: Rectangle {
        color: Style.panel
        border.color: Style.accent
        border.width: 1
        radius: 12
    }

    contentItem: ColumnLayout {
        spacing: 10

        Label { text: root.title; color: Style.accent; font.pixelSize: 18; font.bold: true }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            radius: 8
            color: Style.bannerHi
            border.color: Style.panelEdge
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                Label {
                    Layout.fillWidth: true
                    text: root.value.length ? root.value : "0"
                    color: Style.white; font.pixelSize: 30; font.bold: true
                }
                Label { text: root.unit; color: Style.accent; font.pixelSize: 22; font.bold: true }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.units.length > 0
            Repeater {
                model: root.units
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 6
                    color: modelData === root.unit ? Style.accent : Style.bannerHi
                    border.color: Style.panelEdge
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: modelData === root.unit ? Style.banner : Style.white
                        font.pixelSize: 15; font.bold: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.unit = modelData }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "<"]
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: kma.pressed ? Style.accent : Style.bannerHi
                    border.color: Style.panelEdge
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: kma.pressed ? Style.banner : Style.white
                        font.pixelSize: 24; font.bold: true
                    }
                    MouseArea { id: kma; anchors.fill: parent; onClicked: root._press(modelData) }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Button { text: qsTr("Clear"); onClicked: root.value = "" }
            Item { Layout.fillWidth: true }
            Button { text: qsTr("Cancel"); onClicked: root.close() }
            Button {
                text: qsTr("Enter")
                enabled: root.value.length > 0 && !isNaN(parseFloat(root.value))
                onClicked: {
                    root.accepted(parseFloat(root.value), root.unit);
                    root.close();
                }
            }
        }
    }
}
