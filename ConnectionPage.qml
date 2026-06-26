import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        Label { text: qsTr("Connection"); color: Style.accent; font.pixelSize: 20; font.bold: true }

        // Internal GNSS (tablet built-in receiver)
        RowLayout {
            spacing: 10
            visible: app.internalSerialSupported
            Label { text: qsTr("Internal GPS"); color: Style.textDim; font.pixelSize: 15 }
            TextField { id: devField; text: app.internalDevice; implicitWidth: 140 }
            ComboBox { id: intBaud; model: [4800, 9600, 19200, 38400, 57600, 115200]; currentIndex: 5; implicitWidth: 110 }
            Button { text: qsTr("Connect Internal")
                     onClicked: app.startInternalSerial(devField.text, parseInt(intBaud.currentText)) }
            Button { text: qsTr("Stop"); enabled: app.running; onClicked: app.stop() }
        }

        // USB-CAN adapter (slcan/LAWICEL) -> John Deere StarFire GPS + TCM.
        // "usb" = Android USB-host; or a "/dev/ttyACM0" path on a rooted tablet.
        RowLayout {
            spacing: 10
            visible: app.canSupported
            Label { text: qsTr("USB-CAN (JD)"); color: Style.textDim; font.pixelSize: 15 }
            TextField { id: canField; text: app.canDevice; implicitWidth: 120 }
            // CAN bus bitrate — must match the JD bus.
            // 250k = ISO 11783 / X119 (StarFire tap); 500k = JD proprietary buses.
            Label { text: qsTr("CAN"); color: Style.textDim; font.pixelSize: 13 }
            ComboBox { id: canBitrate; model: [250000, 500000, 125000, 1000000]; currentIndex: 0; implicitWidth: 100 }
            // USB-serial line coding — match the known-good slcan config.
            Label { text: qsTr("ser"); color: Style.textDim; font.pixelSize: 13 }
            ComboBox { id: ttyBaud; model: [2000000, 115200, 200000, 921600, 230400]; currentIndex: 0; implicitWidth: 100 }
            Button { text: qsTr("Connect CAN")
                     onClicked: app.startCan(canField.text, parseInt(canBitrate.currentText), parseInt(ttyBaud.currentText)) }
            Button { text: qsTr("Stop"); enabled: app.running; onClicked: app.stop() }
        }
        Label {
            visible: app.canSupported
            text: qsTr("CAN bitrate must match the bus (250k = ISO/X119 StarFire tap, 500k = JD proprietary). " +
                       "Status shows the adapter VID:PID + slcan write codes, and live PGN/SA once frames arrive.")
            color: Style.textDim; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.maximumWidth: 470
        }

        // Bluetooth GPS (SPP/RFCOMM): NMEA from a paired CAN->BT host (laptop/Pi
        // running bt_gps_host.py) or an off-the-shelf Bluetooth GPS receiver.
        RowLayout {
            spacing: 10
            visible: app.btSupported
            Label { text: qsTr("Bluetooth GPS"); color: Style.textDim; font.pixelSize: 15 }
            ComboBox { id: btCombo; model: app.btDevices; implicitWidth: 240
                       Component.onCompleted: app.refreshBtDevices() }
            Button { text: qsTr("Refresh"); onClicked: app.refreshBtDevices() }
            Button { text: qsTr("Connect BT"); enabled: btCombo.currentIndex >= 0 && app.btDevices.length > 0
                     onClicked: app.startBt(app.btMacAt(btCombo.currentIndex)) }
            Button { text: qsTr("Stop"); enabled: app.running; onClicked: app.stop() }
        }
        Label {
            visible: app.btSupported
            text: qsTr("Pair the host (laptop/Pi) in Android Bluetooth settings first. Run " +
                       "bt_gps_host.py / bt_bridge.ps1 on the host. Also works with any SPP Bluetooth GPS.")
            color: Style.textDim; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.maximumWidth: 470
        }

        // Tablet GPS (the device's own GNSS via Android location services). It's an
        // explicit choice — selecting it starts the device-location source; it never
        // auto-overrides a live UDP/StarFire feed.
        RowLayout {
            spacing: 10
            visible: app.tabletGpsSupported
            Label { text: qsTr("Tablet GPS"); color: Style.textDim; font.pixelSize: 15 }
            Button { text: qsTr("Use Tablet GPS"); onClicked: app.startTabletGps() }
            Button { text: qsTr("Stop"); enabled: app.running; onClicked: app.stop() }
        }
        Label {
            visible: app.tabletGpsSupported
            text: qsTr("Uses the tablet's built-in GNSS receiver (Android location services). " +
                       "Grant the location permission when prompted on first use. No terrain/attitude (TCM).")
            color: Style.textDim; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.maximumWidth: 470
        }

        // UDP (StarFire via bridge / PC relay)
        RowLayout {
            spacing: 10
            Label { text: qsTr("UDP port"); color: Style.textDim; font.pixelSize: 15 }
            TextField {
                id: portField; text: app.udpPort.toString()
                inputMethodHints: Qt.ImhDigitsOnly; implicitWidth: 110
                onEditingFinished: app.udpPort = parseInt(text)
            }
            Button { text: qsTr("Listen UDP")
                     onClicked: { app.udpPort = parseInt(portField.text); app.startUdp() } }
            Button { text: qsTr("Stop"); enabled: app.running; onClicked: app.stop() }
        }

        // Desktop serial (dev builds only)
        RowLayout {
            spacing: 10
            visible: app.serialSupported
            Label { text: qsTr("Serial"); color: Style.textDim; font.pixelSize: 15 }
            ComboBox { id: portCombo; model: app.serialPorts; implicitWidth: 140 }
            ComboBox { id: baudCombo; model: [4800, 9600, 19200, 38400, 57600, 115200]; currentIndex: 5; implicitWidth: 110 }
            Button { text: qsTr("Refresh"); onClicked: app.refreshSerialPorts() }
            Button { text: qsTr("Open Serial"); enabled: portCombo.currentText.length > 0
                     onClicked: app.startSerial(portCombo.currentText, parseInt(baudCombo.currentText)) }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("Status: ") + app.sourceStatus
            color: app.connected ? Style.accent : Style.textDim; font.pixelSize: 14
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("This device: ") + app.localAddresses
            color: Style.textDim; font.pixelSize: 13
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: gps.lastSentence; color: "#6f8780"; font.pixelSize: 12; font.family: "monospace"
        }
    }
}
