import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import "Style.js" as Style

Item {
    id: gpsScreen
    signal back()

    readonly property bool phoneGpsSource: app.lastSource === "tablet"
    property string expandedSource: app.lastSource === "udp" ? "udp" : ""

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
        case "udp": return qsTr("ISOBUS WiFi")
        case "can": return qsTr("USB-CAN (John Deere)")
        case "serial": return qsTr("Serial")
        case "internal": return qsTr("Internal GPS")
        default: return id
        }
    }

    function hubDashboardUrl() {
        var host = app.hubHost.trim()
        if (!host.length) return ""
        return "http://" + host + ":" + app.hubWebPort + "/"
    }

    function startUdpListen() {
        var p = parseInt(udpPortField.text)
        if (isNaN(p) || p < 1 || p > 65535)
            p = 9999
        app.udpPort = p
        app.hubHost = hubHostField.text.trim()
        app.saveSettings()
        app.startUdp()
    }

    onVisibleChanged: if (!visible) app.saveSettings()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PhoneSubScreenHeader {
            Layout.fillWidth: true
            backLabel: "< SETUP"
            title: qsTr("GPS")
            onBackClicked: gpsScreen.back()
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
                        { id: "udp", enabled: true, soon: false },
                        { id: "bt", enabled: false, soon: true },
                        { id: "can", enabled: false, soon: true }
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 8
                        color: rowMa.pressed && modelData.enabled ? theme.bannerHi : theme.panel
                        border.color: (app.running && app.lastSource === modelData.id)
                                      || gpsScreen.expandedSource === modelData.id
                                      ? theme.accent : theme.panelEdge
                        border.width: (app.running && app.lastSource === modelData.id)
                                      || gpsScreen.expandedSource === modelData.id ? 2 : 1
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
                                if (modelData.id === "tablet") {
                                    gpsScreen.expandedSource = ""
                                    app.startTabletGps()
                                } else if (modelData.id === "udp") {
                                    gpsScreen.expandedSource = "udp"
                                }
                            }
                        }
                    }
                }

                // ---- ISOBUS WiFi / UDP listen ----
                Rectangle {
                    visible: gpsScreen.expandedSource === "udp"
                    Layout.fillWidth: true
                    radius: 8
                    color: theme.panel
                    border.color: theme.panelEdge
                    implicitHeight: udpCol.implicitHeight + 24

                    ColumnLayout {
                        id: udpCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 10

                        Text {
                            text: qsTr("ISOBUS WiFi hub")
                            color: theme.accent
                            font.pixelSize: 15
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: qsTr("UDP port")
                                color: theme.textDim
                                font.pixelSize: 14
                                Layout.preferredWidth: 90
                            }
                            TextField {
                                id: udpPortField
                                Layout.fillWidth: true
                                text: app.udpPort.toString()
                                inputMethodHints: Qt.ImhDigitsOnly
                                color: theme.text
                                onEditingFinished: app.udpPort = parseInt(text)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: qsTr("Hub IP")
                                color: theme.textDim
                                font.pixelSize: 14
                                Layout.preferredWidth: 90
                            }
                            TextField {
                                id: hubHostField
                                Layout.fillWidth: true
                                text: app.hubHost
                                placeholderText: qsTr("e.g. 192.168.4.1")
                                color: theme.text
                                onEditingFinished: app.hubHost = text.trim()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            visible: gpsScreen.hubDashboardUrl().length > 0
                            text: qsTr("Hub dashboard: ") + gpsScreen.hubDashboardUrl()
                            color: theme.textDim
                            font.pixelSize: 12
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 8
                                color: listenMa.pressed ? theme.accent : theme.bannerHi
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("Listen")
                                    color: listenMa.pressed ? theme.accentText : theme.text
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                                MouseArea {
                                    id: listenMa
                                    anchors.fill: parent
                                    onClicked: gpsScreen.startUdpListen()
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 8
                                color: stopMa.pressed ? theme.bannerHi : theme.panel
                                border.color: theme.panelEdge
                                opacity: app.running ? 1.0 : 0.55
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("Stop")
                                    color: theme.text
                                    font.pixelSize: 15
                                }
                                MouseArea {
                                    id: stopMa
                                    anchors.fill: parent
                                    enabled: app.running
                                    onClicked: app.stop()
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("Status: ") + app.sourceStatus
                            color: app.connected ? theme.accent : theme.textDim
                            font.pixelSize: 13
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("This phone: ") + app.localAddresses
                            color: theme.textDim
                            font.pixelSize: 12
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("Run IsobusWifiHub on the laptop. Point hub unicast_client at this phone IP and UDP port. NMEA ($PANDA / $GPGGA) arrives here.")
                            color: theme.textDim
                            font.pixelSize: 12
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Phone GNSS uses the built-in receiver. ISOBUS WiFi listens for NMEA from the cab hub. Bluetooth and USB-CAN are coming in a future update.")
                    color: theme.textDim
                    font.pixelSize: 12
                }
            }
        }
    }
}
