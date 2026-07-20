import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Browse device storage, copy/move ISOXML or KML into Farm_data, then import.
Popup {
    id: root
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    parent: Overlay.overlay
    padding: 0

    property bool phoneLayout: false
    property string currentPath: ""
    property string selectedPath: ""
    property string selectedKind: ""
    property bool moveNotCopy: false
    property string statusText: ""
    property var pendingCheck: null

    signal importFinished()

    function openBrowser() {
        farm.requestStoragePermission()
        statusText = ""
        selectedPath = ""
        selectedKind = ""
        moveNotCopy = false
        var roots = farm.browseRoots()
        currentPath = roots.length > 0 ? roots[0] : farm.defaultImportFolder
        refreshEntries()
        open()
    }

    function refreshEntries() {
        entryList.model = farm.listBrowseEntries(currentPath)
    }

    function selectEntry(entry) {
        if (entry.isDir) {
            currentPath = entry.path
            selectedPath = ""
            selectedKind = ""
            refreshEntries()
            return
        }
        selectedPath = entry.path
        selectedKind = entry.kind
        statusText = ""
    }

    function goUp() {
        var parent = currentPath.replace(/\\/g, "/")
        var slash = parent.lastIndexOf("/")
        if (slash <= 0)
            return
        var up = parent.substring(0, slash)
        if (up.length < "/storage/emulated/0".length)
            return
        currentPath = up
        selectedPath = ""
        selectedKind = ""
        refreshEntries()
    }

    function beginImport() {
        if (!selectedPath.length) {
            statusText = qsTr("Select an ISOXML or KML file first.")
            return
        }
        pendingCheck = farm.checkImportSelection(selectedPath)
        if (!pendingCheck.ok) {
            statusText = pendingCheck.error || qsTr("Not a supported import file.")
            return
        }
        if (pendingCheck.fileConflict)
            fileConflictDlg.open()
        else if (pendingCheck.paddockConflicts && pendingCheck.paddockConflicts.length > 0)
            paddockConflictDlg.open()
        else
            runStageAndImport(false)
    }

    function runStageAndImport(replacePaddocks) {
        var err = ""
        if (!pendingCheck.alreadyStaged) {
            err = farm.stageImportFile(selectedPath, moveNotCopy, true)
            if (err.length) {
                statusText = err
                return
            }
        }
        var importPath = pendingCheck.alreadyStaged ? selectedPath : pendingCheck.destPath
        var n = 0
        if (pendingCheck.kind === "kml") {
            if (!farm.browseFarmId.length) {
                statusText = qsTr("Select a farm before importing KML.")
                return
            }
            n = farm.importKmlToFarm(farm.browseClientId, farm.browseFarmId, importPath)
        } else {
            n = farm.importIsoxml(importPath, replacePaddocks)
        }
        if (n > 0) {
            statusText = qsTr("Imported %1 field(s).").arg(n)
            importFinished()
            close()
        } else {
            statusText = qsTr("Import failed — check the file is valid ISOXML or KML.")
        }
    }

    width: phoneLayout
           ? (parent ? parent.width : 400)
           : Math.min((parent ? parent.width : 480) - 24, 520)
    height: phoneLayout
            ? (parent ? parent.height : 600)
            : Math.min((parent ? parent.height : 640) - 24, 620)
    x: phoneLayout ? 0 : (parent ? (parent.width - width) / 2 : 0)
    y: phoneLayout ? 0 : (parent ? (parent.height - height) / 2 : 0)

    background: Rectangle {
        color: theme.bg
        border.color: theme.accent
        border.width: phoneLayout ? 0 : 1
        radius: phoneLayout ? 0 : 12
    }

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: phoneLayout ? 52 : 48
            color: theme.banner
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8
                Rectangle {
                    implicitWidth: Math.max(72, upLbl.implicitWidth + 16)
                    implicitHeight: 36
                    radius: 6
                    color: upMa.pressed ? theme.bannerHi : "transparent"
                    border.color: theme.accent
                    Text {
                        id: upLbl
                        anchors.centerIn: parent
                        text: qsTr("Up")
                        color: theme.accent
                        font.bold: true
                    }
                    MouseArea {
                        id: upMa
                        anchors.fill: parent
                        onClicked: root.goUp()
                    }
                }
                Text {
                    text: qsTr("Import from device")
                    color: theme.text
                    font.pixelSize: phoneLayout ? 17 : 16
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 36
                    radius: 6
                    color: closeMa.pressed ? theme.bannerHi : "transparent"
                    border.color: theme.panelEdge
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: theme.text
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            text: currentPath.replace(/\\/g, "/")
            color: theme.textDim
            font.pixelSize: 11
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 2
            elide: Text.ElideMiddle
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 6
            radius: 8
            color: theme.panel
            border.color: theme.panelEdge
            ListView {
                id: entryList
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                delegate: Rectangle {
                    width: entryList.width
                    implicitHeight: 44
                    radius: 6
                    readonly property bool isSelected: !modelData.isDir && root.selectedPath === modelData.path
                    color: rowMa.pressed ? theme.bannerHi
                           : (isSelected ? "#cc1f9d57" : theme.banner)
                    border.color: isSelected ? theme.accent : theme.panelEdge
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        Text {
                            text: modelData.isDir ? "📁" : (modelData.kind.indexOf("kml") >= 0 ? "🗺" : "📄")
                            font.pixelSize: 16
                        }
                        Text {
                            text: modelData.name
                            color: theme.text
                            font.pixelSize: 14
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                        Rectangle {
                            visible: modelData.kind === "isoxml_folder" || modelData.kind === "isoxml_xml"
                            width: 56
                            height: 20
                            radius: 4
                            color: "#33408f"
                            Text {
                                anchors.centerIn: parent
                                text: "ISOXML"
                                color: "#ffffff"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                        Rectangle {
                            visible: modelData.kind === "kml"
                            width: 40
                            height: 20
                            radius: 4
                            color: "#1b5e20"
                            Text {
                                anchors.centerIn: parent
                                text: "KML"
                                color: "#ffffff"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        onClicked: root.selectEntry(modelData)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            spacing: 8
            Text {
                text: qsTr("Into Farm_data:")
                color: theme.textDim
                font.pixelSize: 12
            }
            Rectangle {
                implicitWidth: 64
                implicitHeight: 32
                radius: 6
                color: !moveNotCopy ? theme.accent : theme.panel
                border.color: theme.accent
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Copy")
                    color: !moveNotCopy ? theme.accentText : theme.text
                    font.pixelSize: 12
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: moveNotCopy = false
                }
            }
            Rectangle {
                implicitWidth: 64
                implicitHeight: 32
                radius: 6
                color: moveNotCopy ? theme.accent : theme.panel
                border.color: theme.accent
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Move")
                    color: moveNotCopy ? theme.accentText : theme.text
                    font.pixelSize: 12
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: moveNotCopy = true
                }
            }
            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            visible: statusText.length > 0
            text: statusText
            color: "#e0a030"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            Layout.topMargin: 4
            implicitHeight: 48
            radius: 8
            color: importMa.pressed ? theme.bannerHi : theme.accent
            opacity: selectedPath.length > 0 ? 1.0 : 0.45
            Text {
                anchors.centerIn: parent
                text: moveNotCopy ? qsTr("Move to Farm_data & Import") : qsTr("Copy to Farm_data & Import")
                color: theme.accentText
                font.bold: true
                font.pixelSize: 14
            }
            MouseArea {
                id: importMa
                anchors.fill: parent
                enabled: selectedPath.length > 0
                onClicked: root.beginImport()
            }
        }
    }

    Popup {
        id: fileConflictDlg
        modal: true
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 360)
        padding: 16
        background: Rectangle {
            color: theme.panel
            border.color: theme.accent
            radius: 10
        }
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("A file or folder with the same name already exists in Farm_data. Overwrite it?")
                color: theme.text
                font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: pendingCheck ? pendingCheck.destPath : ""
                color: theme.textDim
                font.pixelSize: 11
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: fcCancelMa.pressed ? theme.bannerHi : theme.panel
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: theme.text
                    }
                    MouseArea {
                        id: fcCancelMa
                        anchors.fill: parent
                        onClicked: fileConflictDlg.close()
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: fcOkMa.pressed ? theme.bannerHi : theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Overwrite")
                        color: theme.accentText
                        font.bold: true
                    }
                    MouseArea {
                        id: fcOkMa
                        anchors.fill: parent
                        onClicked: {
                            fileConflictDlg.close()
                            if (pendingCheck.paddockConflicts && pendingCheck.paddockConflicts.length > 0)
                                paddockConflictDlg.open()
                            else
                                runStageAndImport(false)
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: paddockConflictDlg
        modal: true
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 380)
        height: Math.min(root.height - 80, 420)
        padding: 16
        background: Rectangle {
            color: theme.panel
            border.color: theme.accent
            radius: 10
        }
        contentItem: ColumnLayout {
            spacing: 10
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Some paddocks in this file already exist in the app (same client / farm / field names):")
                color: theme.text
                font.pixelSize: 14
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: theme.banner
                border.color: theme.panelEdge
                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 4
                    model: pendingCheck ? pendingCheck.paddockConflicts : []
                    delegate: Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: modelData.client + " / " + modelData.farm + " / " + modelData.field
                        color: theme.textDim
                        font.pixelSize: 12
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Overwrite replaces matching paddocks. Keep both adds duplicates.")
                color: theme.textDim
                font.pixelSize: 11
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: pcCancelMa.pressed ? theme.bannerHi : theme.panel
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: theme.text
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: pcCancelMa
                        anchors.fill: parent
                        onClicked: paddockConflictDlg.close()
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: pcKeepMa.pressed ? theme.bannerHi : theme.panel
                    border.color: theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Keep both")
                        color: theme.accent
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: pcKeepMa
                        anchors.fill: parent
                        onClicked: {
                            paddockConflictDlg.close()
                            runStageAndImport(false)
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: pcReplaceMa.pressed ? theme.bannerHi : theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Overwrite")
                        color: theme.accentText
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: pcReplaceMa
                        anchors.fill: parent
                        onClicked: {
                            paddockConflictDlg.close()
                            runStageAndImport(true)
                        }
                    }
                }
            }
        }
    }
}
