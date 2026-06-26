import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import "Icons.js" as Icons

Item {
    id: jobList
    signal back()
    signal jobSelected(var entry)
    signal jobDeleted(var entry)

    property var jobsModel: []
    property var pendingDelete: ({})

    function refresh() {
        var list = []
        try { list = jobs.listAllJobs(0) } catch (e) { list = [] }
        jobsModel = list
    }
    function askDelete(entry) {
        if (!entry || !entry.fieldId || !entry.jobId)
            return
        pendingDelete = entry
        confirmDelete.open()
    }
    function doDelete() {
        var e = jobList.pendingDelete
        if (e && e.fieldId && e.jobId)
            jobs.deleteJob(e.fieldId, e.jobId)
        jobList.pendingDelete = ({})
        jobList.refresh()
        jobList.jobDeleted(e)
        confirmDelete.close()
    }

    Component.onCompleted: jobList.refresh()
    Connections {
        target: jobs
        function onChanged() { jobList.refresh() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            color: theme.banner
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                Rectangle {
                    implicitWidth: 80; implicitHeight: 36; radius: 6
                    color: backMa.pressed ? theme.bannerHi : "transparent"
                    border.color: theme.accent
                    Text { anchors.centerIn: parent; text: "< BACK"; color: theme.accent; font.bold: true }
                    MouseArea { id: backMa; anchors.fill: parent; onClicked: jobList.back() }
                }
                Text { text: qsTr("Saved jobs"); color: theme.text; font.pixelSize: 18; font.bold: true }
                Item { Layout.fillWidth: true }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.margins: 12
            wrapMode: Text.WordWrap
            visible: jobList.jobsModel.length === 0
            text: qsTr("No saved jobs yet. Record coverage on a paddock to create one.")
            color: theme.textDim
            font.pixelSize: 14
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: listCol.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: jobList.jobsModel.length > 0

            ColumnLayout {
                id: listCol
                width: jobList.width
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Repeater {
                    model: jobList.jobsModel
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowCol.implicitHeight + 20
                        radius: 8
                        color: pickMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.bannerHi
                        ColumnLayout {
                            id: rowCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 48
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: modelData.fieldName ? modelData.fieldName : qsTr("Field")
                                color: theme.text
                                font.pixelSize: 17
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: (modelData.farmName ? modelData.farmName : "")
                                      + (modelData.clientName ? ("  /  " + modelData.clientName) : "")
                                color: theme.textDim
                                font.pixelSize: 12
                                visible: text.length > 0
                            }
                            Text {
                                text: (modelData.areaHa !== undefined
                                       ? Number(modelData.areaHa).toFixed(2) : "0.00") + " ha"
                                      + "  \u2022  "
                                      + jobList._shortDate(modelData.modifiedUtc)
                                color: theme.textDim
                                font.pixelSize: 12
                            }
                        }
                        MouseArea {
                            id: pickMa
                            anchors.fill: parent
                            anchors.rightMargin: 48
                            onClicked: jobList.jobSelected(modelData)
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: 6
                            color: delMa.pressed ? theme.bannerHi : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: Icons.del
                                font.family: Icons.family
                                font.pixelSize: 22
                                color: "#e05a5a"
                            }
                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                onClicked: jobList.askDelete(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    function _shortDate(iso) {
        if (!iso) return ""
        var s = "" + iso
        return s.length >= 16 ? s.substring(0, 16).replace("T", " ") : s
    }

    Popup {
        id: confirmDelete
        modal: true
        dim: true
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        parent: jobList
        anchors.centerIn: parent
        width: Math.min(jobList.width - 32, 400)
        background: Rectangle {
            color: theme.panel
            border.color: "#e05a5a"
            border.width: 1
            radius: 12
        }
        contentItem: ColumnLayout {
            spacing: 14
            Text {
                Layout.fillWidth: true
                text: qsTr("Delete job?")
                color: theme.accent
                font.pixelSize: 18
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: theme.text
                font.pixelSize: 14
                text: (jobList.pendingDelete && jobList.pendingDelete.displayName
                       ? jobList.pendingDelete.displayName
                       : (jobList.pendingDelete && jobList.pendingDelete.fieldName
                          ? jobList.pendingDelete.fieldName : qsTr("This job")))
                      + "\n\n" + qsTr("Permanently removes coverage and metadata. Cannot be undone.")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: cancelDelMa.pressed ? theme.bannerHi : theme.panel
                    border.color: theme.panelEdge
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: theme.text
                        font.bold: true
                    }
                    MouseArea {
                        id: cancelDelMa
                        anchors.fill: parent
                        onClicked: confirmDelete.close()
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: okDelMa.pressed ? "#922b21" : "#c0392b"
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Delete")
                        color: "#ffffff"
                        font.bold: true
                    }
                    MouseArea {
                        id: okDelMa
                        anchors.fill: parent
                        onClicked: jobList.doDelete()
                    }
                }
            }
        }
    }
}
