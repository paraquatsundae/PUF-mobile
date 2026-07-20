import QtQuick 2.15
import QtQuick.Layouts 1.15

Item {
    id: setupTab
    property string buildId: ""
    signal openWidth()
    signal openPaddock()
    signal openGps()
    signal openBoundary()
    signal openGuide()

    ColumnLayout {
        anchors.fill: parent
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            color: theme.banner
            Text {
                anchors.centerIn: parent
                text: qsTr("SETUP")
                color: theme.text
                font.pixelSize: 18
                font.bold: true
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text { text: qsTr("Implement"); color: theme.text; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                Text {
                    text: {
                        var att = app.recordAttachment === 0 ? qsTr("ute")
                              : (app.recordAttachment === 2 ? qsTr("drawbar") : qsTr("3PL"))
                        return app.implementWidth.toFixed(1) + " m · " + att
                    }
                    color: theme.accent
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width * 0.5
                }
                Text { text: ">"; color: theme.textDim; font.pixelSize: 18 }
            }
            MouseArea { anchors.fill: parent; onClicked: setupTab.openWidth() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text { text: qsTr("GPS"); color: theme.text; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                Text {
                    text: {
                        if (!app.running) return qsTr("(not connected)")
                        if (app.lastSource === "tablet") return qsTr("Phone GNSS")
                        if (app.lastSource === "udp") return qsTr("ISOBUS WiFi")
                        return app.activeSource.length ? app.activeSource : qsTr("Phone GNSS")
                    }
                    color: theme.accent
                    font.pixelSize: 16
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width * 0.45
                }
                Text { text: ">"; color: theme.textDim; font.pixelSize: 18 }
            }
            MouseArea { anchors.fill: parent; onClicked: setupTab.openGps() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text { text: qsTr("Paddock"); color: theme.text; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                Text {
                    text: farm.hasActiveField ? farm.activeFieldName : qsTr("(none)")
                    color: theme.accent
                    font.pixelSize: 16
                }
                Text { text: ">"; color: theme.textDim; font.pixelSize: 18 }
            }
            MouseArea { anchors.fill: parent; onClicked: setupTab.openPaddock() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text { text: qsTr("Record boundary"); color: theme.text; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                Text {
                    text: farm.hasActiveField
                          ? (farm.boundaryCount >= 3
                             ? (farm.boundaryCount + " pts")
                             : qsTr("none"))
                          : qsTr("(no paddock)")
                    color: theme.accent
                    font.pixelSize: 16
                }
                Text { text: ">"; color: theme.textDim; font.pixelSize: 18 }
            }
            MouseArea {
                anchors.fill: parent
                enabled: farm.hasActiveField
                onClicked: setupTab.openBoundary()
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text { text: qsTr("How to use"); color: theme.text; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                Text { text: qsTr("Guide"); color: theme.accent; font.pixelSize: 16 }
                Text { text: ">"; color: theme.textDim; font.pixelSize: 18 }
            }
            MouseArea { anchors.fill: parent; onClicked: setupTab.openGuide() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 12
            implicitHeight: 56
            radius: 8
            color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text { text: qsTr("Theme"); color: theme.text; font.pixelSize: 16 }
                Item { Layout.fillWidth: true }
                Row {
                    spacing: 0
                    Rectangle {
                        width: 72; height: 40; radius: 6
                        color: theme.dark ? theme.accent : theme.bannerHi
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Dark")
                            color: theme.dark ? theme.accentText : theme.textDim
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: theme.dark = true }
                    }
                    Rectangle {
                        width: 72; height: 40; radius: 6
                        color: !theme.dark ? theme.accent : theme.bannerHi
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Light")
                            color: !theme.dark ? theme.accentText : theme.textDim
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: theme.dark = false }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 8
            text: qsTr("Build") + " " + setupTab.buildId
            color: theme.textDim
            font.pixelSize: 11
        }
    }
}
