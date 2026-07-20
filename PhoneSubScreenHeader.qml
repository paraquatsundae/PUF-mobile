import QtQuick 2.15
import QtQuick.Layouts 1.15

// Back + title bar for phone setup/sub-screens — content sits below status bar inset.
Rectangle {
    id: bar
    property string backLabel: "< BACK"
    property string title: ""
    signal backClicked()

    readonly property int _statusPad: Math.min(40, Math.max(16, platform.statusBarInset))
    readonly property int _rowH: 44

    implicitHeight: bar._statusPad + bar._rowH
    color: theme.banner

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: bar._rowH
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8
        Rectangle {
            implicitWidth: Math.max(80, backLbl.implicitWidth + 20)
            implicitHeight: 36
            radius: 6
            color: backMa.pressed ? theme.bannerHi : "transparent"
            border.color: theme.accent
            Text {
                id: backLbl
                anchors.centerIn: parent
                text: bar.backLabel
                color: theme.accent
                font.bold: true
            }
            MouseArea {
                id: backMa
                anchors.fill: parent
                onClicked: bar.backClicked()
            }
        }
        Text {
            text: bar.title
            color: theme.text
            font.pixelSize: 18
            font.bold: true
        }
        Item { Layout.fillWidth: true }
    }
}
