import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Modal run-line popup launched from the bottom banner. Lets the operator pick
// the active run line, add a new one (A+B / A+heading / lat-lon+heading), and
// set the controlled-traffic track spacing. Backed by the `farm`, `gps` and
// `app` context objects.
Popup {
    id: root
    modal: true
    dim: true
    padding: 16
    anchors.centerIn: Overlay.overlay
    width: Math.min(820, (parent ? parent.width : 820) - 40)
    height: Math.min(540, (parent ? parent.height : 540) - 30)
    // No CloseOnPressOutside — that press was falling through to the Record
    // softkey and stopping coverage mid-run.
    closePolicy: Popup.CloseOnEscape

    // 0 = select existing, 1 = A+B, 2 = A+heading, 3 = lat/lon+heading
    property int mode: 0
    readonly property var modeNames: [qsTr("Select"), qsTr("A + B"), qsTr("A + Heading"), qsTr("Lat / Lon")]

    // Captured A for the "A + heading" method.
    property bool aCaptured: false
    property double aLat: 0
    property double aLon: 0

    function _isNum(t) { return t !== undefined && t.length > 0 && !isNaN(parseFloat(t)); }
    function _compass(deg) {
        var dirs = ["N","NE","E","SE","S","SW","W","NW"];
        return dirs[Math.round((deg % 360) / 45) % 8];
    }

    onOpened: { mode = 0; aCaptured = false; }

    background: Rectangle {
        color: Style.panel
        border.color: Style.accent; border.width: 1
        radius: 12
    }

    contentItem: ColumnLayout {
        spacing: 12

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            MdiIcon { icon: Icons.track; color: Style.accent; font.pixelSize: 24 }
            Label { text: qsTr("Run Lines"); color: Style.accent; font.pixelSize: 20; font.bold: true }
            Item { Layout.fillWidth: true }
            Label {
                text: farm.hasActiveField ? farm.activeFieldName : qsTr("No active field")
                color: farm.hasActiveField ? Style.textDim : "#e0a030"; font.pixelSize: 14
            }
            Button {
                text: Icons.close; font.family: Icons.family; font.pixelSize: 22
                implicitWidth: 44; implicitHeight: 40
                onClicked: root.close()
            }
        }

        // ---- Track spacing (run-line spacing, independent of boom width) ----
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
            implicitHeight: tsRow.implicitHeight + 20
            RowLayout {
                id: tsRow
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 12
                ColumnLayout {
                    spacing: -2; Layout.fillWidth: true
                    Label { text: qsTr("Track spacing"); color: Style.textDim; font.pixelSize: 13 }
                    Label { text: qsTr("boom width %1 m").arg(app.implementWidth.toFixed(1))
                            color: Style.textDim; font.pixelSize: 11 }
                }
                Button {
                    text: Icons.minus; font.family: Icons.family; font.pixelSize: 22
                    implicitWidth: 52; implicitHeight: 52
                    autoRepeat: true
                    onClicked: app.trackSpacing = app.trackSpacing - 0.5
                }
                Label {
                    text: app.trackSpacing.toFixed(1) + " m"
                    color: Style.white; font.pixelSize: 28; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredWidth: 120
                }
                Button {
                    text: Icons.plus; font.family: Icons.family; font.pixelSize: 22
                    implicitWidth: 52; implicitHeight: 52
                    autoRepeat: true
                    onClicked: app.trackSpacing = app.trackSpacing + 0.5
                }
            }
        }

        // ---- Mode selector ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.modeNames
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42; radius: 6
                    color: index === root.mode ? Style.accent : Style.panel
                    border.color: index === root.mode ? Style.accent : Style.panelEdge
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: index === root.mode ? Style.banner : Style.white
                        font.pixelSize: 14; font.bold: index === root.mode
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.mode = index }
                }
            }
        }

        // ---- Panels ----
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.mode

            // --- 0: Select existing ---
            ColumnLayout {
                spacing: 8
                Label {
                    visible: farm.abCount === 0
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: qsTr("No run lines for this field yet. Use a tab above to add one.")
                    color: Style.textDim; font.pixelSize: 13
                }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: farm.activeAbLines
                    delegate: Rectangle {
                        width: ListView.view ? ListView.view.width : 0
                        implicitHeight: 56; radius: 8
                        color: modelData.selected ? "#1b5e20" : Style.panel
                        border.color: modelData.selected ? Style.accent : Style.panelEdge
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8; spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: -2
                                Text { text: (modelData.selected ? "\u25B6 " : "") + modelData.name
                                       color: Style.white; font.pixelSize: 15; font.bold: true }
                                Text { text: modelData.bearingDeg.toFixed(1) + "\u00B0 "
                                             + root._compass(modelData.bearingDeg)
                                             + "  \u2022  " + modelData.lengthM.toFixed(0) + " m"
                                       color: Style.textDim; font.pixelSize: 12 }
                            }
                            Button {
                                text: modelData.selected ? qsTr("Active") : qsTr("Select")
                                enabled: !modelData.selected
                                onClicked: { farm.selectAbLine(modelData.index); root.close(); }
                            }
                        }
                    }
                }
            }

            // --- 1: A + B ---
            ColumnLayout {
                spacing: 10
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: qsTr("Mark A at the current position, drive to the far end, then mark B and add.")
                    color: Style.textDim; font.pixelSize: 13
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Button {
                        Layout.fillWidth: true; implicitHeight: 56
                        text: farm.hasDraftA ? qsTr("A set \u2713") : qsTr("Mark A")
                        enabled: gps.hasFix && farm.hasActiveField
                        onClicked: farm.markA(gps.latitude, gps.longitude)
                    }
                    Button {
                        Layout.fillWidth: true; implicitHeight: 56
                        text: farm.hasDraftB ? qsTr("B set \u2713") : qsTr("Mark B")
                        enabled: gps.hasFix && farm.hasDraftA
                        onClicked: farm.markB(gps.latitude, gps.longitude)
                    }
                }
                TextField {
                    id: abName; Layout.fillWidth: true
                    placeholderText: qsTr("Line name (optional)"); selectByMouse: true
                    placeholderTextColor: Style.textDim
                }
                Button {
                    Layout.fillWidth: true; implicitHeight: 52
                    text: qsTr("Add AB line")
                    enabled: farm.hasDraftA && farm.hasDraftB && farm.hasActiveField
                    onClicked: { farm.commitAbLine(abName.text); abName.text = ""; root.mode = 0; }
                }
                Label {
                    visible: !gps.hasFix
                    text: qsTr("No GPS fix \u2014 cannot mark the current position.")
                    color: "#e0a030"; font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
            }

            // --- 2: A + heading ---
            ColumnLayout {
                spacing: 10
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: qsTr("Capture A at the current position, then enter a heading; the line runs from A along that bearing.")
                    color: Style.textDim; font.pixelSize: 13
                }
                Button {
                    Layout.fillWidth: true; implicitHeight: 56
                    text: root.aCaptured ? qsTr("A captured \u2713") : qsTr("Set A here")
                    enabled: gps.hasFix && farm.hasActiveField
                    onClicked: { root.aLat = gps.latitude; root.aLon = gps.longitude; root.aCaptured = true; }
                }
                Label {
                    visible: root.aCaptured
                    text: "A: " + root.aLat.toFixed(7) + ", " + root.aLon.toFixed(7)
                    color: Style.textDim; font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: qsTr("Heading"); color: Style.textDim; font.pixelSize: 14 }
                    TextField {
                        id: ahHeading; Layout.fillWidth: true
                        placeholderText: qsTr("deg 0\u2013360"); selectByMouse: true
                        placeholderTextColor: Style.textDim
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        validator: DoubleValidator { bottom: 0.0; top: 360.0; decimals: 1 }
                    }
                    Button {
                        text: qsTr("Use current");  enabled: gps.hasFix
                        onClicked: ahHeading.text = gps.headingDeg.toFixed(1)
                    }
                }
                TextField {
                    id: ahName; Layout.fillWidth: true
                    placeholderText: qsTr("Line name (optional)"); selectByMouse: true
                    placeholderTextColor: Style.textDim
                }
                Button {
                    Layout.fillWidth: true; implicitHeight: 52
                    text: qsTr("Add line from A + heading")
                    enabled: root.aCaptured && root._isNum(ahHeading.text) && farm.hasActiveField
                    onClicked: {
                        farm.addAbLineHeading(ahName.text, root.aLat, root.aLon, parseFloat(ahHeading.text));
                        ahName.text = ""; ahHeading.text = ""; root.aCaptured = false; root.mode = 0;
                    }
                }
                Label {
                    visible: !gps.hasFix && !root.aCaptured
                    text: qsTr("No GPS fix \u2014 cannot capture A.")
                    color: "#e0a030"; font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
            }

            // --- 3: lat/lon + heading ---
            ColumnLayout {
                spacing: 10
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: qsTr("Enter an explicit A latitude, longitude and heading.")
                    color: Style.textDim; font.pixelSize: 13
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { text: qsTr("Latitude"); color: Style.textDim; font.pixelSize: 13 }
                        TextField {
                            id: llLat; Layout.fillWidth: true; selectByMouse: true
                            placeholderText: qsTr("-90\u202690")
                            placeholderTextColor: Style.textDim
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: -90.0; top: 90.0; decimals: 8 }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { text: qsTr("Longitude"); color: Style.textDim; font.pixelSize: 13 }
                        TextField {
                            id: llLon; Layout.fillWidth: true; selectByMouse: true
                            placeholderText: qsTr("-180\u2026180")
                            placeholderTextColor: Style.textDim
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: -180.0; top: 180.0; decimals: 8 }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: qsTr("Heading"); color: Style.textDim; font.pixelSize: 14 }
                    TextField {
                        id: llHeading; Layout.fillWidth: true; selectByMouse: true
                        placeholderText: qsTr("deg 0\u2013360")
                        placeholderTextColor: Style.textDim
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        validator: DoubleValidator { bottom: 0.0; top: 360.0; decimals: 1 }
                    }
                }
                TextField {
                    id: llName; Layout.fillWidth: true
                    placeholderText: qsTr("Line name (optional)"); selectByMouse: true
                    placeholderTextColor: Style.textDim
                }
                Button {
                    Layout.fillWidth: true; implicitHeight: 52
                    text: qsTr("Add line from lat/lon + heading")
                    enabled: root._isNum(llLat.text) && root._isNum(llLon.text)
                             && root._isNum(llHeading.text) && farm.hasActiveField
                    onClicked: {
                        farm.addAbLineHeading(llName.text, parseFloat(llLat.text),
                                              parseFloat(llLon.text), parseFloat(llHeading.text));
                        llName.text = ""; root.mode = 0;
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
