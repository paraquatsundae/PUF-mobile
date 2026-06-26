import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Run-line (AB line) management for the active field: rename, delete, select as
// active, and view per-line details (bearing, length, A/B coords). Backed by
// FarmStore (activeAbLines / selectAbLine / renameAbLine / deleteAbLine).
Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function _compass(deg) {
        var dirs = ["N","NE","E","SE","S","SW","W","NW"];
        return dirs[Math.round((deg % 360) / 45) % 8];
    }

    // Rename dialog (mirrors FarmSetupPage's name entry).
    Popup {
        id: nameDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 360
        padding: 16
        property int targetIndex: -1
        function openFor(index, current) {
            targetIndex = index;
            nameField.text = current || "";
            open(); nameField.forceActiveFocus();
        }
        background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 10 }
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Label { text: qsTr("Run line name"); color: Style.textDim; font.pixelSize: 14 }
            TextField { id: nameField; Layout.fillWidth: true; selectByMouse: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: nameDialog.close() }
                Button {
                    text: qsTr("OK")
                    onClicked: {
                        farm.renameAbLine(nameDialog.targetIndex, nameField.text);
                        nameDialog.close();
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 14

        Label { text: qsTr("Run Lines"); color: Style.accent; font.pixelSize: 20; font.bold: true }

        // Active field summary
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.panel; border.color: Style.panelEdge; border.width: 1
            implicitHeight: actCol.implicitHeight + 24
            ColumnLayout {
                id: actCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 12; spacing: 4
                Label { text: qsTr("Active field"); color: Style.textDim; font.pixelSize: 13 }
                Label {
                    text: farm.hasActiveField ? farm.activeFieldName : qsTr("(none selected)")
                    color: Style.white; font.pixelSize: 18; font.bold: true
                }
                Label {
                    text: farm.abCount + " " + (farm.abCount === 1 ? qsTr("run line") : qsTr("run lines"))
                    color: Style.textDim; font.pixelSize: 13
                }
            }
        }

        Label {
            visible: !farm.hasActiveField
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("Select an active field in Paddock Setup \u2192 Farm Setup to manage its run lines.")
            color: "#e0a030"; font.pixelSize: 13
        }
        Label {
            visible: farm.hasActiveField && farm.abCount === 0
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("No run lines yet. Mark A then B on the Nav map to record an AB line, "
                       + "or import one from KML/ISOXML.")
            color: Style.textDim; font.pixelSize: 13
        }

        // ---------- Run-line list ----------
        Repeater {
            model: farm.activeAbLines
            Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: modelData.selected ? "#1b5e20" : Style.panel
                border.color: modelData.selected ? Style.accent : Style.panelEdge
                border.width: 1
                implicitHeight: rowCol.implicitHeight + 24

                ColumnLayout {
                    id: rowCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 12; spacing: 8

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text {
                                text: (modelData.selected ? "\u25B6 " : "") + modelData.name
                                color: Style.white; font.pixelSize: 16; font.bold: true
                            }
                            Text {
                                text: modelData.bearingDeg.toFixed(1) + "\u00B0 "
                                      + page._compass(modelData.bearingDeg)
                                      + "  \u2022  " + modelData.lengthM.toFixed(1) + " m"
                                color: Style.textDim; font.pixelSize: 13
                            }
                            Text {
                                text: "A " + modelData.aLat.toFixed(7) + ", " + modelData.aLon.toFixed(7)
                                color: Style.textDim; font.pixelSize: 11
                            }
                            Text {
                                text: "B " + modelData.bLat.toFixed(7) + ", " + modelData.bLon.toFixed(7)
                                color: Style.textDim; font.pixelSize: 11
                            }
                        }
                        Button { text: Icons.pencil; font.family: Icons.family; implicitWidth: 44
                                 onClicked: nameDialog.openFor(modelData.index, modelData.name) }
                        Button { text: Icons.del; font.family: Icons.family; implicitWidth: 44
                                 onClicked: farm.deleteAbLine(modelData.index) }
                    }
                    Button {
                        Layout.fillWidth: true
                        text: modelData.selected ? qsTr("Active line") : qsTr("Set as active line")
                        enabled: !modelData.selected
                        onClicked: farm.selectAbLine(modelData.index)
                    }
                }
            }
        }
    }
}
