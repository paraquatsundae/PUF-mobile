import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Prescription (Rx) import: pick a shapefile zone set, map the rate column + units
// (names/units are out-of-band), and set out-of-zone / no-GPS fallback rates. On
// accept, emits the rx descriptor for storage with the job. Backed by the `rx`
// (RxMap) context object.
Popup {
    id: root
    modal: true; dim: true; padding: 16
    closePolicy: Popup.CloseOnEscape
    parent: Overlay.overlay
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    width: Math.min((parent ? parent.width : 480) - 24, 480)
    height: Math.min((parent ? parent.height : 600) - 24, 600)

    // Emitted with the rx descriptor (file, column, unit, fallbacks) once mapped.
    signal accepted(var descriptor)

    property string unitChoice: rx.unit
    readonly property var unitOptions: ["L/ha", "mL/ha", "kg/ha", "g/ha", "t/ha", "seeds/ha", "units/ha"]
    property real outRate: 0
    property real noGpsRate: 0

    function openFresh() {
        rx.clear();
        root.outRate = 0; root.noGpsRate = 0;
        fileList.model = rx.listShapefiles(rx.defaultFolder());
        open();
    }

    background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12 }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Prescription (Rx) map"); color: Style.accent
                        font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                Button { text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                         implicitWidth: 44; implicitHeight: 44; onClicked: root.close() }
            }

            // 1. Shapefile picker
            Label { text: qsTr("1. Shapefile (.shp + .dbf, optional .prj)")
                    color: Style.textDim; font.pixelSize: 14 }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 132; radius: 8
                color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                ListView {
                    id: fileList
                    anchors.fill: parent; anchors.margins: 6
                    clip: true; spacing: 4; model: []
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    delegate: Rectangle {
                        width: fileList.width
                        implicitHeight: 40; radius: 6
                        color: fma.pressed ? Style.accent
                               : (rx.sourceFile === modelData ? "#cc1b5e20" : Style.panel)
                        border.color: Style.panelEdge; border.width: 1
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.split("/").pop()
                            color: fma.pressed ? Style.banner : Style.white
                            font.pixelSize: 14; elide: Text.ElideMiddle
                        }
                        MouseArea { id: fma; anchors.fill: parent
                                    onClicked: { rx.loadShapefile(modelData);
                                                 root.unitChoice = rx.unit; } }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: rx.loaded ? Style.accent : Style.textDim; font.pixelSize: 12
                    text: rx.loaded
                          ? (rx.zoneCount + qsTr(" zones \u2022 ") + rx.crsNote)
                          : qsTr("No shapefile selected. Place Rx exports in Download/QtAgGPS.")
                }
                Button { text: qsTr("Refresh")
                         onClicked: fileList.model = rx.listShapefiles(rx.defaultFolder()) }
            }

            // 2. Rate column
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                visible: rx.loaded
                Label { text: qsTr("2. Rate column"); color: Style.textDim
                        font.pixelSize: 15; Layout.preferredWidth: 130 }
                Button {
                    Layout.fillWidth: true
                    text: rx.rateColumn.length ? rx.rateColumn : qsTr("Pick column\u2026")
                    onClicked: { colPicker.model = rx.fieldNames; colPicker.open(); }
                }
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                visible: rx.loaded && rx.rateColumn.length > 0
                color: Style.textDim; font.pixelSize: 12
                text: qsTr("Sample values: ") + rx.previewValues(rx.rateColumn, 6).join(", ")
            }

            // 3. Units
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                visible: rx.loaded
                Label { text: qsTr("3. Units"); color: Style.textDim
                        font.pixelSize: 15; Layout.preferredWidth: 130 }
                Button {
                    Layout.fillWidth: true
                    text: root.unitChoice
                    onClicked: { unitPicker.model = root.unitOptions; unitPicker.open(); }
                }
            }

            // 4. Fallbacks
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                visible: rx.loaded
                Label { text: qsTr("Out-of-zone rate"); color: Style.textDim
                        font.pixelSize: 14; Layout.preferredWidth: 130 }
                Button {
                    Layout.fillWidth: true
                    text: root.outRate + " " + root.unitChoice
                    onClicked: outPad.openWith(root.outRate, root.unitChoice)
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                visible: rx.loaded
                Label { text: qsTr("No-GPS rate"); color: Style.textDim
                        font.pixelSize: 14; Layout.preferredWidth: 130 }
                Button {
                    Layout.fillWidth: true
                    text: root.noGpsRate + " " + root.unitChoice
                    onClicked: noGpsPad.openWith(root.noGpsRate, root.unitChoice)
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: root.close() }
                Button {
                    text: qsTr("Use prescription")
                    enabled: rx.loaded && rx.rateColumn.length > 0
                    onClicked: {
                        rx.unit = root.unitChoice;
                        rx.outOfZoneRate = root.outRate;
                        rx.noGpsRate = root.noGpsRate;
                        root.accepted(rx.descriptor());
                        root.close();
                    }
                }
            }
        }
    }

    ListPicker {
        id: colPicker
        title: qsTr("Rate column")
        allowAdd: false
        onSelected: rx.rateColumn = value
    }
    ListPicker {
        id: unitPicker
        title: qsTr("Rate units")
        allowAdd: false
        onSelected: root.unitChoice = value
    }
    NumberPad {
        id: outPad
        title: qsTr("Out-of-zone rate")
        units: root.unitOptions
        onAccepted: { root.outRate = value; root.unitChoice = unit; }
    }
    NumberPad {
        id: noGpsPad
        title: qsTr("No-GPS rate")
        units: root.unitOptions
        onAccepted: { root.noGpsRate = value; root.unitChoice = unit; }
    }
}
