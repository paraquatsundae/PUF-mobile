import QtQuick 2.15
import QtQuick.Layouts 1.15

Item {
    id: widthScreen
    signal back()

    property string value: app.implementWidth.toFixed(1)

    function syncFromApp() {
        widthScreen.value = app.implementWidth.toFixed(1)
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
                    MouseArea { id: backMa; anchors.fill: parent; onClicked: widthScreen.back() }
                }
                Text { text: qsTr("WIDTH"); color: theme.text; font.pixelSize: 18; font.bold: true }
                Item { Layout.fillWidth: true }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
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
            implicitHeight: 56
            radius: 8
            color: theme.accent
            Text {
                anchors.centerIn: parent
                text: qsTr("SET")
                color: theme.accentText
                font.pixelSize: 20
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var v = parseFloat(widthScreen.value)
                    if (!isNaN(v) && v > 0) {
                        app.implementWidth = v
                        app.saveSettings()
                        widthScreen.syncFromApp()
                    }
                    widthScreen.back()
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
