import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

Item {
    id: mainTab
    signal openWidth()
    signal openPaddock()
    signal resumeWorkRequested()
    signal newWorkRequested()
    signal otherJobsRequested()

    function _safeHasJob(fieldId) {
        if (!fieldId || !fieldId.length)
            return false
        try { return jobs.hasJob(fieldId) } catch (e) { return false }
    }
    readonly property bool hasSavedWork: farm.hasActiveField
                                       && mainTab._safeHasJob(farm.activeFieldId)
    readonly property bool hasAnySavedJobs: mainTab._anySavedJobs()
    function _anySavedJobs() {
        try { return jobs.hasAnySavedJobs() } catch (e) { return false }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        PhoneGpsBanner { Layout.fillWidth: true; showTitle: true }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 12
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("AREA COVERED")
                    color: theme.textDim
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Style.formatAreaHa(coverage.areaHa)
                    color: theme.text
                    font.pixelSize: 52
                    font.bold: true
                }
                MouseArea {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: paddockLabel.width
                    implicitHeight: paddockLabel.height + 16
                    onClicked: mainTab.openPaddock()
                    Text {
                        id: paddockLabel
                        anchors.centerIn: parent
                        text: farm.hasActiveField
                              ? qsTr("Paddock: %1").arg(farm.activeFieldName)
                              : qsTr("Paddock: (none)")
                        color: theme.accent
                        font.pixelSize: 16
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    visible: (mainTab.hasSavedWork || mainTab.hasAnySavedJobs) && !app.recordingCoverage
                    Rectangle {
                        implicitWidth: resumeLbl.width + 24
                        implicitHeight: 36
                        radius: 6
                        color: resumeMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.accent
                        visible: mainTab.hasSavedWork
                        Text {
                            id: resumeLbl
                            anchors.centerIn: parent
                            text: qsTr("Resume")
                            color: theme.accent
                            font.bold: true
                        }
                        MouseArea {
                            id: resumeMa
                            anchors.fill: parent
                            onClicked: mainTab.resumeWorkRequested()
                        }
                    }
                    Rectangle {
                        implicitWidth: jobsLbl.width + 24
                        implicitHeight: 36
                        radius: 6
                        color: jobsMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.panelEdge
                        visible: mainTab.hasAnySavedJobs
                        Text {
                            id: jobsLbl
                            anchors.centerIn: parent
                            text: qsTr("Jobs")
                            color: theme.text
                            font.bold: true
                        }
                        MouseArea {
                            id: jobsMa
                            anchors.fill: parent
                            onClicked: mainTab.otherJobsRequested()
                        }
                    }
                    Rectangle {
                        implicitWidth: newLbl.width + 24
                        implicitHeight: 36
                        radius: 6
                        color: newMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.panelEdge
                        visible: farm.hasActiveField
                        Text {
                            id: newLbl
                            anchors.centerIn: parent
                            text: qsTr("New job")
                            color: theme.text
                            font.bold: true
                        }
                        MouseArea {
                            id: newMa
                            anchors.fill: parent
                            onClicked: mainTab.newWorkRequested()
                        }
                    }
                }

            Item { Layout.fillHeight: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 52
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                Text {
                    text: qsTr("Width: %1 m").arg(app.implementWidth.toFixed(1))
                    color: theme.text
                    font.pixelSize: 18
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 88
                    implicitHeight: 36
                    radius: 6
                    color: editMa.pressed ? theme.bannerHi : theme.banner
                    border.color: theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("EDIT")
                        color: theme.accent
                        font.bold: true
                    }
                    MouseArea {
                        id: editMa
                        anchors.fill: parent
                        onClicked: mainTab.openWidth()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                Text {
                    text: qsTr("OVERLAP")
                    color: theme.text
                    font.pixelSize: 16
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Row {
                    spacing: 0
                    Rectangle {
                        width: 72; height: 40; radius: 6
                        color: app.sectionControl ? theme.accent : theme.bannerHi
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("ON")
                            color: app.sectionControl ? theme.accentText : theme.textDim
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: app.setSectionControl(true) }
                    }
                    Rectangle {
                        width: 72; height: 40; radius: 6
                        color: !app.sectionControl ? theme.accent : theme.bannerHi
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("off")
                            color: !app.sectionControl ? theme.accentText : theme.textDim
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: app.setSectionControl(false) }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            implicitHeight: 72
            radius: 10
            color: app.recordingCoverage ? "#c0392b" : theme.accent
            RowLayout {
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    visible: app.recordingCoverage
                    width: 14; height: 14; radius: 7
                    color: "#ffffff"
                    SequentialAnimation on opacity {
                        running: app.recordingCoverage
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.2; duration: 600 }
                        NumberAnimation { from: 0.2; to: 1; duration: 600 }
                    }
                }
                Text {
                    text: app.recordingCoverage ? qsTr("■  STOP") : qsTr("●  RECORD")
                    color: theme.accentText
                    font.pixelSize: 24
                    font.bold: true
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: app.toggleRecording()
            }
        }
    }
}
