import QtQuick 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

Item {
    id: gpsScreen
    signal back()

    readonly property bool phoneGpsSource: app.lastSource === "tablet"

    function tierText() {
        if (gps.stale || !gps.hasFix) return qsTr("NO FIX")
        switch (gps.fixQuality) {
        case 4: return "RTK"
        case 5: return "RTK"
        case 2: return "DGPS"
        case 1: return phoneGpsSource ? qsTr("GNSS") : "GPS"
        default: return gps.fixText.toUpperCase()
        }
    }

    function sourceLabel(id) {
        switch (id) {
        case "tablet": return qsTr("Phone GNSS")
        case "bt": return qsTr("Bluetooth GPS")
        case "udp": return qsTr("UDP (StarFire bridge)")
        case "can": return qsTr("USB-CAN (John Deere)")
        case "serial": return qsTr("Serial")
        case "internal": return qsTr("Internal GPS")
        default: return id
        }
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
                    MouseArea { id: backMa; anchors.fill: parent; onClicked: gpsScreen.back() }
                }
                Text { text: qsTr("GPS"); color: theme.text; font.pixelSize: 18; font.bold: true }
                Item { Layout.fillWidth: true }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: body.implicitHeight + 24

            ColumnLayout {
                id: body
                width: parent.width
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 10

                // ---- Current fix ----
                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    color: theme.panel
                    border.color: theme.panelEdge
                    implicitHeight: fixCol.implicitHeight + 24

                    ColumnLayout {
                        id: fixCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            text: qsTr("Current fix")
                            color: theme.accent
                            font.pixelSize: 15
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Quality"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: tierText()
                                color: Style.fixColor(gps.fixQuality, gps.stale)
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Latitude"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: gps.hasFix ? gps.latitude.toFixed(7) + "\u00B0" : "\u2014"
                                color: theme.text
                                font.pixelSize: 14
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Longitude"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: gps.hasFix ? gps.longitude.toFixed(7) + "\u00B0" : "\u2014"
                                color: theme.text
                                font.pixelSize: 14
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Heading"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: gps.hasFix ? gps.headingDeg.toFixed(0) + "\u00B0" : "\u2014"
                                color: theme.text
                                font.pixelSize: 14
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Speed"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: gps.hasFix ? gps.speedKmh.toFixed(1) + " km/h" : "\u2014"
                                color: theme.text
                                font.pixelSize: 14
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("HDOP"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: gps.hdopValid ? gps.hdop.toFixed(2) : "\u2014"
                                color: theme.text
                                font.pixelSize: 14
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Satellites"); color: theme.textDim; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: gps.satellitesValid ? gps.satellites : "\u2014"
                                color: theme.text
                                font.pixelSize: 14
                            }
                        }
                    }
                }

                // ---- Source ----
                Text {
                    text: qsTr("Source")
                    color: theme.textDim
                    font.pixelSize: 13
                    font.bold: true
                    Layout.topMargin: 4
                }

                Repeater {
                    model: [
                        { id: "tablet", enabled: app.tabletGpsSupported, soon: false },
                        { id: "bt", enabled: false, soon: true },
                        { id: "udp", enabled: false, soon: true },
                        { id: "can", enabled: false, soon: true }
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 8
                        color: rowMa.pressed && modelData.enabled ? theme.bannerHi : theme.panel
                        border.color: (app.running && app.lastSource === modelData.id)
                                      ? theme.accent : theme.panelEdge
                        border.width: (app.running && app.lastSource === modelData.id) ? 2 : 1
                        opacity: modelData.enabled ? 1.0 : 0.55

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            Text {
                                text: gpsScreen.sourceLabel(modelData.id)
                                color: theme.text
                                font.pixelSize: 15
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: modelData.soon
                                text: qsTr("Coming soon")
                                color: theme.textDim
                                font.pixelSize: 13
                            }
                            Text {
                                visible: !modelData.soon && app.running && app.lastSource === modelData.id
                                text: qsTr("Active")
                                color: theme.accent
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            enabled: modelData.enabled
                            onClicked: {
                                if (modelData.id === "tablet")
                                    app.startTabletGps()
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Phone GNSS uses the device built-in receiver. External sources (Bluetooth, Wi-Fi bridge, UDP) will be selectable in a future update.")
                    color: theme.textDim
                    font.pixelSize: 12
                }
            }
        }
    }
}

