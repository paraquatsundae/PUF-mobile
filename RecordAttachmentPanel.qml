import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Connection type + receiver-to-record-point distance (ute / 3PL / drawbar).
// large=true: tablet Implement page sizing; false: phone / boundary record.
ColumnLayout {
    id: root
    property bool large: false
    property bool useTabletStyle: false

    readonly property color _text: useTabletStyle ? Style.white : theme.text
    readonly property color _textDim: useTabletStyle ? Style.textDim : theme.textDim
    readonly property color _accent: useTabletStyle ? Style.accent : theme.accent
    readonly property color _panel: useTabletStyle ? Style.bannerHi : theme.panel
    readonly property color _panelEdge: useTabletStyle ? Style.panelEdge : theme.panelEdge
    readonly property color _accentText: useTabletStyle ? Style.banner : theme.accentText

    readonly property var attachmentOptions: [
        { value: 0, label: qsTr("No implement (ute) — at receiver") },
        { value: 1, label: qsTr("3PL rigid attachment") },
        { value: 2, label: qsTr("Drawbar with pivot") }
    ]

    spacing: large ? 12 : 8

    ComboBox {
        id: attachCombo
        Layout.fillWidth: true
        model: root.attachmentOptions
        textRole: "label"
        function syncIndex() {
            for (var i = 0; i < root.attachmentOptions.length; ++i) {
                if (root.attachmentOptions[i].value === app.recordAttachment) {
                    currentIndex = i
                    return
                }
            }
        }
        Component.onCompleted: syncIndex()
        onActivated: app.recordAttachment = root.attachmentOptions[currentIndex].value
        Connections {
            target: app
            function onRecordAttachmentChanged() { attachCombo.syncIndex() }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: app.recordAttachment === 0
        wrapMode: Text.WordWrap
        text: qsTr("Coverage and boundaries record at the GPS receiver (no rear offset).")
        color: root._textDim
        font.pixelSize: large ? 13 : 12
    }

    // 3PL offset
    ColumnLayout {
        Layout.fillWidth: true
        visible: app.recordAttachment === 1
        spacing: large ? 10 : 8
        Label {
            Layout.fillWidth: true
            text: qsTr("Distance behind receiver (antenna to boom / record point)")
            color: root._textDim
            font.pixelSize: large ? 14 : 13
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: large ? 16 : 8
            Button {
                visible: large
                text: Icons.minus
                font.family: Icons.family
                font.pixelSize: 26
                implicitWidth: 64
                implicitHeight: 64
                onClicked: app.implementOffset = Math.max(0, app.implementOffset - 0.5)
                autoRepeat: true
            }
            Rectangle {
                visible: !large
                implicitWidth: 40
                implicitHeight: 40
                radius: 6
                color: pl3m.pressed ? root._panel : root._panel
                border.color: root._panelEdge
                Text { anchors.centerIn: parent; text: "−"; color: root._text; font.bold: true }
                MouseArea {
                    id: pl3m
                    anchors.fill: parent
                    onClicked: app.implementOffset = Math.max(0, app.implementOffset - 0.5)
                }
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: app.implementOffset.toFixed(1) + " m"
                color: root._accent
                font.pixelSize: large ? 40 : 18
                font.bold: true
            }
            Button {
                visible: large
                text: Icons.plus
                font.family: Icons.family
                font.pixelSize: 26
                implicitWidth: 64
                implicitHeight: 64
                onClicked: app.implementOffset = Math.min(20, app.implementOffset + 0.5)
                autoRepeat: true
            }
            Rectangle {
                visible: !large
                implicitWidth: 40
                implicitHeight: 40
                radius: 6
                color: pl3p.pressed ? root._panel : root._panel
                border.color: root._panelEdge
                Text { anchors.centerIn: parent; text: "+"; color: root._text; font.bold: true }
                MouseArea {
                    id: pl3p
                    anchors.fill: parent
                    onClicked: app.implementOffset = Math.min(20, app.implementOffset + 0.5)
                }
            }
        }
        Slider {
            visible: large
            Layout.fillWidth: true
            from: 0.0
            to: 20.0
            stepSize: 0.5
            value: app.implementOffset
            onMoved: app.implementOffset = value
        }
    }

    // Drawbar offset
    ColumnLayout {
        Layout.fillWidth: true
        visible: app.recordAttachment === 2
        spacing: large ? 10 : 8
        Label {
            Layout.fillWidth: true
            text: qsTr("Distance behind receiver (antenna to drawbar pivot / record point)")
            color: root._textDim
            font.pixelSize: large ? 14 : 13
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: large ? 16 : 8
            Button {
                visible: large
                text: Icons.minus
                font.family: Icons.family
                font.pixelSize: 26
                implicitWidth: 64
                implicitHeight: 64
                onClicked: app.hitchOffsetM = Math.max(0, app.hitchOffsetM - 0.5)
                autoRepeat: true
            }
            Rectangle {
                visible: !large
                implicitWidth: 40
                implicitHeight: 40
                radius: 6
                color: dbm.pressed ? root._panel : root._panel
                border.color: root._panelEdge
                Text { anchors.centerIn: parent; text: "−"; color: root._text; font.bold: true }
                MouseArea {
                    id: dbm
                    anchors.fill: parent
                    onClicked: app.hitchOffsetM = Math.max(0, app.hitchOffsetM - 0.5)
                }
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: app.hitchOffsetM.toFixed(1) + " m"
                color: root._accent
                font.pixelSize: large ? 40 : 18
                font.bold: true
            }
            Button {
                visible: large
                text: Icons.plus
                font.family: Icons.family
                font.pixelSize: 26
                implicitWidth: 64
                implicitHeight: 64
                onClicked: app.hitchOffsetM = Math.min(20, app.hitchOffsetM + 0.5)
                autoRepeat: true
            }
            Rectangle {
                visible: !large
                implicitWidth: 40
                implicitHeight: 40
                radius: 6
                color: dbp.pressed ? root._panel : root._panel
                border.color: root._panelEdge
                Text { anchors.centerIn: parent; text: "+"; color: root._text; font.bold: true }
                MouseArea {
                    id: dbp
                    anchors.fill: parent
                    onClicked: app.hitchOffsetM = Math.min(20, app.hitchOffsetM + 0.5)
                }
            }
        }
        Slider {
            visible: large
            Layout.fillWidth: true
            from: 0.0
            to: 20.0
            stepSize: 0.5
            value: app.hitchOffsetM
            onMoved: app.hitchOffsetM = value
        }
    }

    Label {
        Layout.fillWidth: true
        visible: app.recordAttachment !== 0
        text: qsTr("Active recording offset: %1 m behind receiver").arg(app.recordOffsetM.toFixed(1))
        color: root._accent
        font.pixelSize: large ? 13 : 12
        font.bold: true
    }
}
