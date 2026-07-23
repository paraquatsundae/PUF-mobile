import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Item {
    id: paddockScreen
    signal back()
    signal fieldSelected(string clientId, string farmId, string fieldId, string fieldName)
    signal recordBoundaryRequested()

    property var importFiles: []
    property bool showNewPaddock: false
    property string newPaddockName: ""

    function ensureFarmTree() {
        var cid = farm.browseClientId
        if (farm.clients.length === 0)
            cid = farm.addClient(qsTr("Operator"))
        else if (!cid.length) {
            cid = farm.clients[0].id
            farm.browseClientId = cid
        }
        var fid = farm.browseFarmId
        if (farm.farms.length === 0)
            fid = farm.addFarm(cid, qsTr("Farm"))
        else if (!fid.length) {
            fid = farm.farms[0].id
            farm.browseFarmId = fid
        }
        return { clientId: cid, farmId: fid }
    }

    function createPaddock(name) {
        var n = (name || "").trim()
        if (!n.length)
            return
        var t = paddockScreen.ensureFarmTree()
        var fieldId = farm.addField(t.clientId, t.farmId, n)
        farm.setActiveField(t.clientId, t.farmId, fieldId)
        paddockScreen.showNewPaddock = false
        paddockScreen.newPaddockName = ""
        newPaddockDlg.close()
        paddockScreen.recordBoundaryRequested()
    }

    Connections {
        target: paddockScreen
        function onShowNewPaddockChanged() {
            if (paddockScreen.showNewPaddock)
                newPaddockDlg.open()
            else
                newPaddockDlg.close()
        }
    }

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

        PhoneSubScreenHeader {
            Layout.fillWidth: true
            backLabel: "< SETUP"
            title: qsTr("PADDOCK")
            onBackClicked: paddockScreen.back()
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
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 8
                        color: newPadMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("New paddock")
                            color: theme.accent
                            font.bold: true
                        }
                        MouseArea {
                            id: newPadMa
                            anchors.fill: parent
                            onClicked: paddockScreen.showNewPaddock = true
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 8
                        color: recBndMa.pressed ? theme.bannerHi : theme.panel
                        border.color: theme.panelEdge
                        opacity: farm.hasActiveField ? 1.0 : 0.45
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Record boundary")
                            color: theme.text
                            font.bold: true
                        }
                        MouseArea {
                            id: recBndMa
                            anchors.fill: parent
                            enabled: farm.hasActiveField
                            onClicked: paddockScreen.recordBoundaryRequested()
                        }
                    }
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
                        implicitWidth: 80
                        implicitHeight: 36
                        radius: 6
                        color: browseMa.pressed ? theme.bannerHi : theme.banner
                        border.color: theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Browse")
                            color: theme.accent
                            font.bold: true
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: browseMa
                            anchors.fill: parent
                            onClicked: farmImport.openBrowser()
                        }
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
                    text: qsTr("Browse device files to copy or move into Farm_data, or use Scan for files already in Download/Farm_data.")
                    color: theme.textDim
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: paddockScreen.importFiles.length === 0
                    text: qsTr("No import files found. ISOXML adds its own clients/farms; KML needs a farm selected above.")
                    color: "#e0a030"
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
                                        var n = 0
                                        if (impRow.isKml)
                                            n = farm.importKmlToFarm(farm.browseClientId, farm.browseFarmId, modelData)
                                        else
                                            n = farm.importIsoxml(modelData)
                                        if (n > 0 && farm.boundaryCount >= 3)
                                            basemap.suggestForPoints(farm.activeFieldId, farm.activeFieldName,
                                                                     farm.activeBoundary, 250)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: newPaddockDlg
        modal: true
        anchors.centerIn: parent
        width: Math.min(paddockScreen.width - 32, 360)
        padding: 16
        onClosed: paddockScreen.showNewPaddock = false
        background: Rectangle {
            color: theme.panel
            border.color: theme.accent
            radius: 10
        }
        ColumnLayout {
            width: parent.width
            spacing: 12
            Text {
                text: qsTr("New paddock name")
                color: theme.text
                font.pixelSize: 16
                font.bold: true
            }
            TextField {
                id: newPadField
                Layout.fillWidth: true
                text: paddockScreen.newPaddockName
                onTextChanged: paddockScreen.newPaddockName = text
                placeholderText: qsTr("e.g. North block")
                color: theme.text
                selectByMouse: true
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: cancelPadMa.pressed ? theme.bannerHi : theme.panel
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: theme.text
                    }
                    MouseArea {
                        id: cancelPadMa
                        anchors.fill: parent
                        onClicked: {
                            paddockScreen.showNewPaddock = false
                            paddockScreen.newPaddockName = ""
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: okPadMa.pressed ? theme.bannerHi : theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Create")
                        color: theme.accentText
                        font.bold: true
                    }
                    MouseArea {
                        id: okPadMa
                        anchors.fill: parent
                        onClicked: paddockScreen.createPaddock(newPadField.text)
                    }
                }
            }
        }
        onVisibleChanged: if (visible) { newPadField.text = ""; newPadField.forceActiveFocus() }
    }

    FarmDataImportPopup {
        id: farmImport
        phoneLayout: true
        parent: paddockScreen
        onImportFinished: paddockScreen.importFiles = farm.listImportFiles("")
    }
}
