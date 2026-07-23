import QtQuick 2.15
import QtQuick.Layouts 1.15

Item {
    id: widthScreen
    signal back()

    property string value: app.implementWidth.toFixed(1)

    function syncFromApp() {
        widthScreen.value = app.implementWidth.toFixed(1)
    }

    onVisibleChanged: if (!visible) app.saveSettings()

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 0

            PhoneSubScreenHeader {
                Layout.fillWidth: true
                backLabel: "< SETUP"
                title: qsTr("IMPLEMENT")
                onBackClicked: widthScreen.back()
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                text: qsTr("Working width")
                color: theme.textDim
                font.pixelSize: 14
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: widthScreen.value + "  m"
                color: theme.text
                font.pixelSize: 40
                font.bold: true
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                columns: 3
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: ["7","8","9","4","5","6","1","2","3",".","0","<"]
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: 8
                        color: kma.pressed ? theme.accent : theme.bannerHi
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: kma.pressed ? theme.accentText : theme.text
                            font.pixelSize: 24
                            font.bold: true
                        }
                        MouseArea {
                            id: kma
                            anchors.fill: parent
                            onClicked: {
                                if (modelData === "<") {
                                    widthScreen.value = widthScreen.value.slice(0, -1)
                                    return
                                }
                                if (modelData === ".") {
                                    if (widthScreen.value.indexOf(".") === -1)
                                        widthScreen.value = (widthScreen.value.length ? widthScreen.value : "0") + "."
                                    return
                                }
                                widthScreen.value = widthScreen.value + modelData
                            }
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 16
                implicitHeight: 48
                radius: 8
                color: theme.accent
                Text {
                    anchors.centerIn: parent
                    text: qsTr("SET WIDTH")
                    color: theme.accentText
                    font.pixelSize: 16
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var v = parseFloat(widthScreen.value)
                        if (!isNaN(v) && v > 0) {
                            app.implementWidth = v
                            widthScreen.syncFromApp()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.topMargin: 8
                radius: 8
                color: theme.panel
                border.color: theme.panelEdge
                implicitHeight: attachPanel.implicitHeight + 24
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8
                    Text {
                        text: qsTr("Connection & receiver offset")
                        color: theme.text
                        font.pixelSize: 15
                        font.bold: true
                    }
                    RecordAttachmentPanel {
                        id: attachPanel
                        Layout.fillWidth: true
                        large: false
                    }
                }
            }

            Item { Layout.preferredHeight: 24 }
        }
    }
}
