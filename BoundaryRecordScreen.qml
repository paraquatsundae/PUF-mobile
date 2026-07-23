import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import "Style.js" as Style

// Shared boundary capture UI (phone + tablet). Saved via farm.commitBoundary().
Item {
    id: root
    property bool phoneMode: false
    signal back()

    Connections {
        target: farm
        function onBoundaryAutoClosed() {
            autoCloseBanner.visible = true
            autoCloseTimer.restart()
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 5000
        onTriggered: autoCloseBanner.visible = false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PhoneSubScreenHeader {
            visible: root.phoneMode
            Layout.fillWidth: true
            backLabel: "< SETUP"
            title: qsTr("Record boundary")
            onBackClicked: root.requestBack()
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: scrollCol.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: scrollCol
                width: parent.width
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    color: theme.panel
                    border.color: theme.bannerHi
                    implicitHeight: infoCol.implicitHeight + 20
                    ColumnLayout {
                        id: infoCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: farm.hasActiveField ? farm.activeFieldName : qsTr("No paddock selected")
                            color: theme.text
                            font.pixelSize: 18
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            visible: farm.hasActiveField
                            text: farm.activeClientName + " / " + farm.activeFarmName
                            color: theme.textDim
                            font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("Drive the perimeter. Auto-closes within 1 m of start. Pause/resume draws a straight line across the gap.")
                            color: theme.textDim
                            font.pixelSize: 13
                        }
                    }
                }

                Rectangle {
                    id: autoCloseBanner
                    Layout.fillWidth: true
                    visible: false
                    radius: 8
                    color: "#1b5e20"
                    border.color: theme.accent
                    implicitHeight: 36
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Loop closed — tap Save boundary")
                        color: theme.accent
                        font.bold: true
                    }
                }

                // Recording point / attachment (from Implement setup)
                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    color: theme.panel
                    border.color: theme.panelEdge
                    implicitHeight: attachPanel.implicitHeight + 20
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8
                        Text {
                            text: qsTr("Recording point")
                            color: theme.text
                            font.pixelSize: 14
                            font.bold: true
                        }
                        RecordAttachmentPanel {
                            id: attachPanel
                            Layout.fillWidth: true
                            large: false
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    GpsHealth {
                        compact: true
                        Layout.preferredHeight: 28
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: farm.boundaryDraftCount + " " + qsTr("pts")
                        color: theme.text
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Text {
                        visible: farm.boundaryDraftCount >= 3
                        text: Style.formatAreaHa(farm.boundaryDraftAreaHa)
                        color: theme.accent
                        font.pixelSize: 14
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: farm.boundaryPaused
                    text: qsTr("Paused — tap Resume to continue")
                    color: "#f1c40f"
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: !gps.hasFix
                    text: qsTr("Waiting for GPS fix…")
                    color: "#f1c40f"
                    font.pixelSize: 13
                    font.bold: true
                }

                // Archive section
                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    color: theme.panel
                    border.color: theme.panelEdge
                    implicitHeight: archiveCol.implicitHeight + 20
                    ColumnLayout {
                        id: archiveCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Boundary archive")
                                color: theme.text
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Rectangle {
                                implicitWidth: archiveBtnMa.implicitWidth + 16
                                implicitHeight: 32
                                radius: 6
                                opacity: farm.boundaryCount >= 3 && !farm.boundaryRecording ? 1.0 : 0.45
                                color: archiveBtnMa.pressed ? theme.bannerHi : theme.panel
                                border.color: theme.panelEdge
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("Archive current")
                                    color: theme.text
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: archiveBtnMa
                                    anchors.fill: parent
                                    enabled: farm.boundaryCount >= 3 && !farm.boundaryRecording
                                    onClicked: farm.archiveActiveBoundary()
                                }
                            }
                        }
                        Repeater {
                            model: farm.archivedBoundaries
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: 6
                                color: theme.bannerHi
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.areaHa.toFixed(2) + " ha · "
                                              + modelData.pointCount + " pts · "
                                              + modelData.archivedUtc.substring(0, 10)
                                        color: theme.textDim
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        implicitWidth: 56; implicitHeight: 28; radius: 4
                                        color: delMa.pressed ? "#922b21" : theme.panel
                                        border.color: theme.panelEdge
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("Delete")
                                            color: "#e74c3c"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: delMa
                                            anchors.fill: parent
                                            onClicked: deleteConfirm.openFor(modelData.id, modelData.areaHa)
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: farm.archivedBoundaries.length === 0
                            text: qsTr("No archived boundaries for this paddock.")
                            color: theme.textDim
                            font.pixelSize: 12
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: 8
                    visible: !farm.boundaryRecording
                    color: startMa.pressed ? theme.bannerHi : theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("START RECORDING")
                        color: theme.accentText
                        font.pixelSize: 16
                        font.bold: true
                    }
                    MouseArea {
                        id: startMa
                        anchors.fill: parent
                        enabled: farm.hasActiveField && gps.hasFix
                        onClicked: farm.startBoundaryRecording()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: farm.boundaryRecording
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 8
                        visible: !farm.boundaryPaused
                        color: pauseMa.pressed ? theme.bannerHi : "#d68910"
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("PAUSE")
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.bold: true
                        }
                        MouseArea {
                            id: pauseMa
                            anchors.fill: parent
                            onClicked: farm.pauseBoundaryRecording()
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 8
                        visible: farm.boundaryPaused
                        color: resumeMa.pressed ? theme.bannerHi : theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("RESUME")
                            color: theme.accentText
                            font.pixelSize: 16
                            font.bold: true
                        }
                        MouseArea {
                            id: resumeMa
                            anchors.fill: parent
                            onClicked: farm.resumeBoundaryRecording()
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 100
                        Layout.fillHeight: true
                        implicitHeight: 52
                        radius: 8
                        color: stopMa.pressed ? "#922b21" : "#c0392b"
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("STOP")
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.bold: true
                        }
                        MouseArea {
                            id: stopMa
                            anchors.fill: parent
                            onClicked: farm.stopBoundaryRecording()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 8
                        color: discardMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.panelEdge
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Discard")
                            color: theme.text
                            font.bold: true
                        }
                        MouseArea {
                            id: discardMa
                            anchors.fill: parent
                            onClicked: farm.cancelBoundaryRecording()
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 8
                        color: saveMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.accent
                        opacity: farm.boundaryDraftCount >= 3 && !farm.boundaryRecording ? 1.0 : 0.45
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Save boundary")
                            color: theme.accent
                            font.bold: true
                        }
                        MouseArea {
                            id: saveMa
                            anchors.fill: parent
                            enabled: farm.boundaryDraftCount >= 3 && !farm.boundaryRecording
                            onClicked: {
                                if (farm.commitBoundary()) {
                                    if (typeof shell !== "undefined" && shell.suggestBasemapForActive)
                                        shell.suggestBasemapForActive()
                                    else
                                        basemap.suggestForPoints(farm.activeFieldId,
                                                                 farm.activeFieldName,
                                                                 farm.activeBoundary, 250)
                                    root.back()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: deleteConfirm
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(360, root.width - 32)
        padding: 16
        property string archiveId: ""
        property double areaHa: 0
        function openFor(id, ha) {
            archiveId = id
            areaHa = ha
            open()
        }
        background: Rectangle { color: theme.panel; border.color: theme.accent; radius: 10 }
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Permanently delete archived boundary (%1 ha)?").arg(deleteConfirm.areaHa.toFixed(2))
                color: theme.text
                font.pixelSize: 15
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Cancel")
                    onClicked: deleteConfirm.close()
                }
                Button {
                    text: qsTr("Delete")
                    onClicked: {
                        farm.deleteArchivedBoundary(deleteConfirm.archiveId)
                        deleteConfirm.close()
                    }
                }
            }
        }
    }

    function requestBack() {
        if (farm.boundaryRecording)
            farm.stopBoundaryRecording()
        root.back()
    }
}
