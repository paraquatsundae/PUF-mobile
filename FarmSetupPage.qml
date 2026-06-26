import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Client -> Farm -> Field setup, active-field selection, and KML import.
Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    property var importFiles: []

    function rowDelegateColor(active) { return active ? "#1b5e20" : Style.panel }

    // Simple name entry used for both "new" and "rename".
    Popup {
        id: nameDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 360
        padding: 16
        property string mode: ""      // client-new, client-ren, farm-new, ...
        property string targetId: ""
        function openFor(m, id, current) {
            mode = m; targetId = id || "";
            nameField.text = current || "";
            open(); nameField.forceActiveFocus();
        }
        background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 10 }
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Label { text: qsTr("Name"); color: Style.textDim; font.pixelSize: 14 }
            TextField { id: nameField; Layout.fillWidth: true; selectByMouse: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: nameDialog.close() }
                Button {
                    text: qsTr("OK")
                    onClicked: {
                        var n = nameField.text;
                        switch (nameDialog.mode) {
                        case "client-new": farm.addClient(n); break;
                        case "client-ren": farm.renameClient(nameDialog.targetId, n); break;
                        case "farm-new":   farm.addFarm(farm.browseClientId, n); break;
                        case "farm-ren":   farm.renameFarm(nameDialog.targetId, n); break;
                        case "field-new":  farm.addField(farm.browseClientId, farm.browseFarmId, n); break;
                        case "field-ren":  farm.renameField(nameDialog.targetId, n); break;
                        }
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

        Label { text: qsTr("Farm Setup"); color: Style.accent; font.pixelSize: 20; font.bold: true }

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
                    text: farm.hasActiveField
                          ? (farm.activeClientName + "  /  " + farm.activeFarmName + "  /  " + farm.activeFieldName)
                          : qsTr("(none selected)")
                    color: Style.white; font.pixelSize: 18; font.bold: true
                }
                Label {
                    visible: farm.hasActiveField
                    text: farm.activeAreaHa.toFixed(2) + " ha   \u2022   "
                          + farm.boundaryCount + " bndy pts   \u2022   " + farm.abCount + " AB"
                    color: Style.textDim; font.pixelSize: 13
                }
            }
        }

        // ---------- Clients ----------
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Clients"); color: Style.textDim; font.pixelSize: 14; Layout.fillWidth: true }
            Button { text: qsTr("New"); onClicked: nameDialog.openFor("client-new") }
        }
        Repeater {
            model: farm.clients
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46; radius: 6
                color: page.rowDelegateColor(modelData.id === farm.browseClientId)
                border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8
                    Text { text: modelData.name + "  (" + modelData.farmCount + ")"
                           color: Style.white; font.pixelSize: 15; Layout.fillWidth: true }
                    Button { text: Icons.pencil; font.family: Icons.family; implicitWidth: 40
                             onClicked: nameDialog.openFor("client-ren", modelData.id, modelData.name) }
                    Button { text: Icons.del; font.family: Icons.family; implicitWidth: 40
                             onClicked: farm.deleteClient(modelData.id) }
                }
                MouseArea { anchors.fill: parent; z: -1; onClicked: farm.browseClientId = modelData.id }
            }
        }

        // ---------- Farms ----------
        RowLayout {
            Layout.fillWidth: true
            visible: farm.browseClientId.length > 0
            Label { text: qsTr("Farms"); color: Style.textDim; font.pixelSize: 14; Layout.fillWidth: true }
            Button { text: qsTr("New"); onClicked: nameDialog.openFor("farm-new") }
        }
        Repeater {
            model: farm.browseClientId.length > 0 ? farm.farms : []
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46; radius: 6
                color: page.rowDelegateColor(modelData.id === farm.browseFarmId)
                border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8
                    Text { text: modelData.name + "  (" + modelData.fieldCount + ")"
                           color: Style.white; font.pixelSize: 15; Layout.fillWidth: true }
                    Button { text: Icons.pencil; font.family: Icons.family; implicitWidth: 40
                             onClicked: nameDialog.openFor("farm-ren", modelData.id, modelData.name) }
                    Button { text: Icons.del; font.family: Icons.family; implicitWidth: 40
                             onClicked: farm.deleteFarm(modelData.id) }
                }
                MouseArea { anchors.fill: parent; z: -1; onClicked: farm.browseFarmId = modelData.id }
            }
        }

        // ---------- Fields ----------
        RowLayout {
            Layout.fillWidth: true
            visible: farm.browseFarmId.length > 0
            Label { text: qsTr("Fields"); color: Style.textDim; font.pixelSize: 14; Layout.fillWidth: true }
            Button { text: qsTr("New"); onClicked: nameDialog.openFor("field-new") }
        }
        Repeater {
            model: farm.browseFarmId.length > 0 ? farm.fields : []
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52; radius: 6
                color: page.rowDelegateColor(modelData.active)
                border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8; spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: -2
                        Text { text: modelData.name; color: Style.white; font.pixelSize: 15 }
                        Text { text: modelData.areaHa.toFixed(2) + " ha \u2022 " + modelData.boundaryCount
                                     + " pts \u2022 " + modelData.abCount + " AB"
                               color: Style.textDim; font.pixelSize: 12 }
                    }
                    Button {
                        text: modelData.active ? qsTr("Active") : qsTr("Set active")
                        enabled: !modelData.active
                        onClicked: farm.setActiveField(farm.browseClientId, farm.browseFarmId, modelData.id)
                    }
                    Button { text: Icons.pencil; font.family: Icons.family; implicitWidth: 40
                             onClicked: nameDialog.openFor("field-ren", modelData.id, modelData.name) }
                    Button { text: Icons.del; font.family: Icons.family; implicitWidth: 40
                             onClicked: farm.deleteField(modelData.id) }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

        // ---------- Import KML / ISOXML ----------
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Import field data"); color: Style.textDim
                    font.pixelSize: 14; Layout.fillWidth: true }
            Button {
                text: qsTr("Scan")
                onClicked: {
                    farm.requestStoragePermission();
                    page.importFiles = farm.listImportFiles("");
                }
            }
        }
        Label {
            text: qsTr("Folder: ") + farm.defaultImportFolder()
            color: Style.textDim; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Label {
            text: qsTr("KML \u2192 one paddock per polygon into the selected farm (named from the placemark).  "
                       + "ISOXML (TASKDATA.XML or a task folder) \u2192 imports its own clients/farms/fields.")
            color: Style.textDim; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Label {
            visible: farm.browseFarmId.length === 0
            text: qsTr("Select a farm above before importing KML.")
            color: "#e0a030"; font.pixelSize: 12
        }
        Repeater {
            model: page.importFiles
            Rectangle {
                id: impRow
                Layout.fillWidth: true
                implicitHeight: 44; radius: 6; color: Style.panel
                border.color: Style.panelEdge; border.width: 1
                readonly property bool isKml: modelData.toLowerCase().endsWith(".kml")
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8; spacing: 8
                    Rectangle {
                        width: 56; height: 22; radius: 4
                        color: impRow.isKml ? "#1b5e20" : "#33408f"
                        Text { anchors.centerIn: parent; text: impRow.isKml ? "KML" : "ISOXML"
                               color: Style.white; font.pixelSize: 11; font.bold: true }
                    }
                    Text { text: modelData.split("/").pop(); color: Style.white
                           font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideMiddle }
                    Button {
                        text: qsTr("Import")
                        enabled: impRow.isKml ? (farm.browseFarmId.length > 0) : true
                        onClicked: {
                            if (impRow.isKml)
                                farm.importKmlToFarm(farm.browseClientId, farm.browseFarmId, modelData);
                            else
                                farm.importIsoxml(modelData);
                        }
                    }
                }
            }
        }
    }
}
