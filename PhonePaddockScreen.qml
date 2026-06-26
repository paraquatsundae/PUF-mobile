import QtQuick 2.15
import QtQuick.Layouts 1.15

Item {
    id: paddockScreen
    signal back()
    signal fieldSelected(string clientId, string farmId, string fieldId, string fieldName)

    property var importFiles: []

    function rowColor(selected) {
        return selected ? theme.accent : theme.panel
    }
    function rowTextColor(selected) {
        return selected ? theme.accentText : theme.text
    }
    function rowSubColor(selected) {
        return selected ? theme.accentText : theme.textDim
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
                    Text { anchors.centerIn: parent; text: "< SETUP"; color: theme.accent; font.bold: true }
                    MouseArea { id: backMa; anchors.fill: parent; onClicked: paddockScreen.back() }
                }
                Text { text: qsTr("PADDOCK"); color: theme.text; font.pixelSize: 18; font.bold: true }
                Item { Layout.fillWidth: true }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: col.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: paddockScreen.width
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    color: theme.panel
                    border.color: theme.bannerHi
                    implicitHeight: actCol.implicitHeight + 20
                    ColumnLayout {
                        id: actCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 4
                        Text {
                            text: qsTr("Active paddock")
                            color: theme.textDim
                            font.pixelSize: 13
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: farm.hasActiveField
                                  ? (farm.activeFarmName + "  /  " + farm.activeFieldName)
                                  : qsTr("(tap a field below)")
                            color: theme.text
                            font.pixelSize: 17
                            font.bold: true
                        }
                        Text {
                            visible: farm.hasActiveField
                            text: farm.activeAreaHa.toFixed(2) + " ha  \u2022  "
                                  + farm.boundaryCount + " pts"
                            color: theme.textDim
                            font.pixelSize: 12
                        }
                    }
                }

                Text {
                    visible: farm.clients.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("No farm data loaded.\nBundled TASKDATA seeds on first run,\nor import ISOXML/KML below.")
                    color: theme.textDim
                    font.pixelSize: 14
                }

                Text {
                    visible: farm.clients.length > 0
                    text: qsTr("Client")
                    color: theme.textDim
                    font.pixelSize: 13
                }
                Repeater {
                    model: farm.clients
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 8
                        color: paddockScreen.rowColor(modelData.id === farm.browseClientId)
                        border.color: theme.bannerHi
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            Text {
                                text: modelData.name + "  (" + modelData.farmCount + ")"
                                color: paddockScreen.rowTextColor(modelData.id === farm.browseClientId)
                                font.pixelSize: 15
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: modelData.id === farm.browseClientId
                                text: "\u2713"
                                color: paddockScreen.rowTextColor(true)
                                font.bold: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: farm.browseClientId = modelData.id
                        }
                    }
                }

                Text {
                    visible: farm.browseClientId.length > 0
                    text: qsTr("Farm")
                    color: theme.textDim
                    font.pixelSize: 13
                }
                Repeater {
                    model: farm.browseClientId.length > 0 ? farm.farms : []
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 8
                        color: paddockScreen.rowColor(modelData.id === farm.browseFarmId)
                        border.color: theme.bannerHi
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            Text {
                                text: modelData.name + "  (" + modelData.fieldCount + ")"
                                color: paddockScreen.rowTextColor(modelData.id === farm.browseFarmId)
                                font.pixelSize: 15
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: modelData.id === farm.browseFarmId
                                text: "\u2713"
                                color: paddockScreen.rowTextColor(true)
                                font.bold: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: farm.browseFarmId = modelData.id
                        }
                    }
                }

                Text {
                    visible: farm.browseFarmId.length > 0
                    text: qsTr("Fields")
                    color: theme.textDim
                    font.pixelSize: 13
                }
                Repeater {
                    model: farm.browseFarmId.length > 0 ? farm.fields : []
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 54
                        radius: 8
                        color: modelData.active ? theme.accent : theme.panel
                        border.color: modelData.active ? theme.accent : theme.bannerHi
                        border.width: modelData.active ? 2 : 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: modelData.name
                                    color: modelData.active ? theme.accentText : theme.text
                                    font.pixelSize: 16
                                    font.bold: modelData.active
                                }
                                Text {
                                    text: modelData.areaHa.toFixed(2) + " ha  \u2022  "
                                          + modelData.boundaryCount + " pts"
                                    color: modelData.active ? theme.accentText : theme.textDim
                                    font.pixelSize: 12
                                }
                            }
                            Text {
                                visible: modelData.active
                                text: qsTr("ACTIVE")
                                color: theme.accentText
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: paddockScreen.fieldSelected(
                                farm.browseClientId, farm.browseFarmId,
                                modelData.id, modelData.name)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    height: 1
                    color: theme.bannerHi
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: qsTr("Import farm data")
                        color: theme.textDim
                        font.pixelSize: 13
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        implicitWidth: 72
                        implicitHeight: 36
                        radius: 6
                        color: scanMa.pressed ? theme.bannerHi : theme.banner
                        border.color: theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Scan")
                            color: theme.accent
                            font.bold: true
                        }
                        MouseArea {
                            id: scanMa
                            anchors.fill: parent
                            onClicked: {
                                farm.requestStoragePermission()
                                paddockScreen.importFiles = farm.listImportFiles("")
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Folder: %1").arg(farm.defaultImportFolder())
                    color: theme.textDim
                    font.pixelSize: 11
                }
                Repeater {
                    model: paddockScreen.importFiles
                    Rectangle {
                        id: impRow
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 8
                        color: theme.panel
                        border.color: theme.bannerHi
                        readonly property bool isKml: modelData.toLowerCase().endsWith(".kml")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            Rectangle {
                                width: 56; height: 22; radius: 4
                                color: impRow.isKml ? "#1b5e20" : "#33408f"
                                Text {
                                    anchors.centerIn: parent
                                    text: impRow.isKml ? "KML" : "ISOXML"
                                    color: "#ffffff"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                            Text {
                                text: {
                                    var p = modelData.replace(/\\/g, "/")
                                    return p.substring(p.lastIndexOf("/") + 1)
                                }
                                color: theme.text
                                font.pixelSize: 13
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }
                            Rectangle {
                                implicitWidth: 64
                                implicitHeight: 32
                                radius: 6
                                color: impMa.pressed ? theme.bannerHi : theme.banner
                                border.color: theme.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("Import")
                                    color: theme.accent
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                MouseArea {
                                    id: impMa
                                    anchors.fill: parent
                                    enabled: !impRow.isKml || farm.browseFarmId.length > 0
                                    onClicked: {
                                        if (impRow.isKml)
                                            farm.importKmlToFarm(farm.browseClientId, farm.browseFarmId, modelData)
                                        else
                                            farm.importIsoxml(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
