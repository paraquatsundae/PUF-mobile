import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Live GPS / TCM information. Reads the `gps` model and `app` controller context
// objects. Satellite count is decoded from StarFire PGN 0xFFFF (sub-msg 0x51) by
// the bridge; HDOP/PDOP/VDOP show "—" (no GNSS DOP packet on this tap).
Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function num(v, dp, unit) {
        return v.toFixed(dp) + (unit ? " " + unit : "")
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        Label { text: qsTr("GPS Information"); color: Style.accent; font.pixelSize: 20; font.bold: true }

        // ---- Fix + DOP card ----
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.panel; border.color: Style.panelEdge; border.width: 1
            implicitHeight: fixGrid.implicitHeight + 24

            GridLayout {
                id: fixGrid
                x: 14; y: 14
                width: parent.width - 28
                columns: 2; columnSpacing: 18; rowSpacing: 10

                Label { text: qsTr("Fix quality"); color: Style.textDim; font.pixelSize: 15 }
                Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    text: gps.stale ? qsTr("STALE") : gps.fixText
                    color: Style.fixColor(gps.fixQuality, gps.stale); font.pixelSize: 16; font.bold: true
                }

                Label { text: qsTr("Satellites (used)"); color: Style.textDim; font.pixelSize: 15 }
                Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    text: gps.satellitesValid ? gps.satellites : "\u2014"
                    color: Style.white; font.pixelSize: 16
                }

                Label { text: qsTr("Satellites (in view)"); color: Style.textDim; font.pixelSize: 15 }
                Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    text: "\u2014"; color: Style.textDim; font.pixelSize: 16
                }

                Label { text: qsTr("HDOP"); color: Style.textDim; font.pixelSize: 15 }
                Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    text: gps.hdopValid ? page.num(gps.hdop, 2) : "\u2014"
                    color: Style.white; font.pixelSize: 16
                }

                Label { text: qsTr("PDOP / VDOP"); color: Style.textDim; font.pixelSize: 15 }
                Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    text: "\u2014"; color: Style.textDim; font.pixelSize: 16
                }
            }
        }

        // ---- Position card ----
        // Lat/lon + UTC come straight off the fix; localX/localY are metres
        // east/north of the session origin (only meaningful once an origin is
        // set), so the whole block is gated on gps.hasOrigin.
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.panel; border.color: Style.panelEdge; border.width: 1
            implicitHeight: posGrid.implicitHeight + 24

            GridLayout {
                id: posGrid
                x: 14; y: 14
                width: parent.width - 28
                columns: 2; columnSpacing: 18; rowSpacing: 10

                Label { text: qsTr("Position"); color: Style.accent; font.pixelSize: 15; font.bold: true
                        Layout.columnSpan: 2 }

                Label { text: qsTr("Latitude"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.hasOrigin ? gps.latitude.toFixed(7) + "\u00B0" : "\u2014"
                        color: gps.hasOrigin ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label { text: qsTr("Longitude"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.hasOrigin ? gps.longitude.toFixed(7) + "\u00B0" : "\u2014"
                        color: gps.hasOrigin ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label { text: qsTr("UTC time"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.utcTime.length ? gps.utcTime : "\u2014"
                        color: gps.utcTime.length ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label { text: qsTr("Local E / N"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.hasOrigin ? page.num(gps.localX, 1) + " / " + page.num(gps.localY, 1, "m")
                                            : "\u2014"
                        color: gps.hasOrigin ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label { text: qsTr("Sentences"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.sentenceCount + (gps.stale ? qsTr("  (stale)") : "")
                        color: gps.stale ? Style.cardinal : Style.white; font.pixelSize: 16 }

                Label {
                    Layout.columnSpan: 2
                    Layout.preferredWidth: page.width - 60
                    wrapMode: Text.WordWrap
                    visible: !gps.hasOrigin
                    text: qsTr("No origin yet — waiting for the first GPS fix.")
                    color: Style.textDim; font.pixelSize: 12
                }
            }
        }

        // ---- Motion card ----
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.panel; border.color: Style.panelEdge; border.width: 1
            implicitHeight: motionGrid.implicitHeight + 24

            GridLayout {
                id: motionGrid
                x: 14; y: 14
                width: parent.width - 28
                columns: 2; columnSpacing: 18; rowSpacing: 10

                Label { text: qsTr("Speed"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: page.num(gps.speedKmh, 1, "km/h"); color: Style.white; font.pixelSize: 16 }

                Label { text: qsTr("Heading"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.headingDeg.toFixed(0) + "\u00B0"; color: Style.white; font.pixelSize: 16 }

                Label { text: qsTr("Altitude"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: page.num(gps.altitude, 1, "m"); color: Style.white; font.pixelSize: 16 }
            }
        }

        // ---- TCM attitude card ----
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.panel; border.color: Style.panelEdge; border.width: 1
            implicitHeight: tcmGrid.implicitHeight + 24

            GridLayout {
                id: tcmGrid
                x: 14; y: 14
                width: parent.width - 28
                columns: 2; columnSpacing: 18; rowSpacing: 10

                Label { text: qsTr("TCM attitude"); color: Style.accent; font.pixelSize: 15; font.bold: true
                        Layout.columnSpan: 2 }

                Label { text: qsTr("Roll"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.hasAttitude ? gps.rollDeg.toFixed(1) + "\u00B0" : "\u2014"
                        color: gps.hasAttitude ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label { text: qsTr("Pitch"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.hasAttitude ? gps.pitchDeg.toFixed(1) + "\u00B0" : "\u2014"
                        color: gps.hasAttitude ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label { text: qsTr("Yaw rate"); color: Style.textDim; font.pixelSize: 15 }
                Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                        text: gps.hasAttitude ? gps.yawRateDegS.toFixed(1) + "\u00B0/s" : "\u2014"
                        color: gps.hasAttitude ? Style.white : Style.textDim; font.pixelSize: 16 }

                Label {
                    Layout.columnSpan: 2
                    Layout.preferredWidth: page.width - 60
                    wrapMode: Text.WordWrap
                    visible: !gps.hasAttitude
                    text: qsTr("No attitude yet — the bridge must emit $PANDA (roll/pitch/yaw).")
                    color: Style.textDim; font.pixelSize: 12
                }
            }
        }

        // ---- Antenna height (TCM tilt correction) ----
        Rectangle {
            Layout.fillWidth: true
            radius: 8; color: Style.panel; border.color: Style.panelEdge; border.width: 1
            implicitHeight: antCol.implicitHeight + 28

            ColumnLayout {
                id: antCol
                x: 14; y: 14
                width: parent.width - 28
                spacing: 12

                Label { text: qsTr("Antenna height above ground"); color: Style.textDim; font.pixelSize: 14 }

                RowLayout {
                    Layout.fillWidth: true; spacing: 16
                    Button {
                        text: Icons.minus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64; autoRepeat: true
                        onClicked: app.antennaHeight = app.antennaHeight - 0.1
                    }
                    Label {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                        text: app.antennaHeight.toFixed(1) + " m"
                        color: Style.white; font.pixelSize: 40; font.bold: true
                    }
                    Button {
                        text: Icons.plus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64; autoRepeat: true
                        onClicked: app.antennaHeight = app.antennaHeight + 0.1
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0.0; to: 6.0; stepSize: 0.1
                    value: app.antennaHeight
                    onMoved: app.antennaHeight = value
                }
            }
        }

        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            color: Style.textDim; font.pixelSize: 12
            text: qsTr("Antenna height drives terrain compensation: roll/pitch tilt is "
                       + "projected down to the true ground point under the machine before "
                       + "the implement set-back is applied to the recorded coverage.")
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            color: Style.textDim; font.pixelSize: 12
            text: qsTr("Satellite count is decoded from the StarFire's proprietary PGN 0xFFFF "
                       + "(sub-message 0x51) on the bus. HDOP/PDOP/VDOP are not transmitted on "
                       + "this tap (no GNSS DOP fast packet), so they read \u2014 (unknown) here.")
        }
    }
}
