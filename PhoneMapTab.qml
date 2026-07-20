import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

// MAP tab: map is full-bleed; one compact top strip (GNSS + modes + area).
Item {
    id: mapTab
    property var recorder: null
    readonly property int _statusPad: Math.min(40, Math.max(16, platform.statusBarInset))
    readonly property int _chromeH: 36
    readonly property int _headerTotal: mapTab._statusPad + mapTab._chromeH
    readonly property int _bottomReserve: 50

    PhoneMapView {
        id: mapView
        anchors.fill: parent
        recorder: mapTab.recorder
        topChromeInset: mapTab._headerTotal
        bottomChromeInset: mapTab._bottomReserve
    }

    // Compact chrome row only — map bleeds under the status bar (no dead banner pad).
    Rectangle {
        z: 10
        clip: true
        anchors.top: parent.top
        anchors.topMargin: mapTab._statusPad
        anchors.left: parent.left
        anchors.right: parent.right
        height: mapTab._chromeH
        color: theme.banner
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 6
            spacing: 4
            GpsHealth {
                compact: true
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 28
                Layout.maximumWidth: 120
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: [
                            { id: 0, label: qsTr("Chase") },
                            { id: 1, label: qsTr("Top") },
                            { id: 2, label: qsTr("Pad") }
                        ]
                        Rectangle {
                            width: modeLbl.implicitWidth + 12
                            height: 26
                            radius: 4
                            color: modeMa.pressed ? theme.panel
                                 : (mapView.mode === modelData.id ? theme.accent : theme.bannerHi)
                            Text {
                                id: modeLbl
                                anchors.centerIn: parent
                                text: modelData.label
                                color: mapView.mode === modelData.id ? theme.accentText : theme.textDim
                                font.pixelSize: 11
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
            Text {
                text: Style.formatAreaHa(coverage.areaHa)
                color: theme.text
                font.pixelSize: 12
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: app.recordingCoverage ? 4 : 0
            }
            Text {
                visible: app.recordingCoverage && !gps.hasFix
                text: qsTr("No fix")
                color: "#f1c40f"
                font.pixelSize: 9
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 4
            }
            Rectangle {
                visible: app.recordingCoverage
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                Layout.rightMargin: 8
                Layout.alignment: Qt.AlignVCenter
                radius: 4
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

    // Debug strip — floats above map controls so it is never under the GNSS/mode chrome.
    Rectangle {
        z: 20
        visible: mapView.mapDebugOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 92
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
