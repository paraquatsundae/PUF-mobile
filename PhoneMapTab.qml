import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

// MAP tab: map is full-bleed; GNSS + mode tabs float on top (no black layout band).
Item {
    id: mapTab
    property var recorder: null
    readonly property int _statusPad: Math.max(24, platform.statusBarInset)

    PhoneMapView {
        id: mapView
        anchors.fill: parent
        recorder: mapTab.recorder
    }

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        z: 10

        // GNSS + area — status-bar band is theme fill, content sits at bottom of band.
        Rectangle {
            width: parent.width
            height: mapTab._statusPad + 36
            color: theme.banner
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 36
                spacing: 0
                PhoneGpsBanner {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    showTitle: false
                }
                Text {
                    text: Style.formatAreaHa(coverage.areaHa)
                    color: theme.text
                    font.pixelSize: 14
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: app.recordingCoverage ? 6 : 12
                }
                Text {
                    visible: app.recordingCoverage && !gps.hasFix
                    text: qsTr("No GPS fix")
                    color: "#f1c40f"
                    font.pixelSize: 10
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 6
                }
                Rectangle {
                    visible: app.recordingCoverage
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    Layout.rightMargin: 10
                    Layout.alignment: Qt.AlignVCenter
                    radius: 5
                    color: "#c0392b"
                    SequentialAnimation on opacity {
                        running: app.recordingCoverage
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.25; duration: 600 }
                        NumberAnimation { from: 0.25; to: 1; duration: 600 }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 36
            color: theme.bannerHi
            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4
                Repeater {
                    model: [
                        { id: 0, label: qsTr("Chase") },
                        { id: 1, label: qsTr("Top") },
                        { id: 2, label: qsTr("Paddock") }
                    ]
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 5
                        color: modeMa.pressed ? theme.panel
                             : (mapView.mode === modelData.id ? theme.accent : "transparent")
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: mapView.mode === modelData.id ? theme.accentText : theme.textDim
                            font.pixelSize: 13
                            font.bold: mapView.mode === modelData.id
                        }
                        MouseArea {
                            id: modeMa
                            anchors.fill: parent
                            onClicked: mapView.mode = modelData.id
                        }
                    }
                }
            }
        }
    }

    // Debug strip — floats above map controls so it is never under the GNSS/mode chrome.
    Rectangle {
        z: 20
        visible: mapView.mapDebugOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 118
        width: parent.width - 16
        height: Math.max(32, covDbg.contentHeight + 10)
        radius: 4
        color: "#ee000000"
        border.color: "#ffff00"
        border.width: 2
        Text {
            id: covDbg
            anchors.fill: parent
            anchors.margins: 5
            text: mapView.debugLine
            color: "#ffff00"
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
