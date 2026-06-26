import QtQuick 2.15
import "Style.js" as Style
import "Icons.js" as Icons

// Top banner: page-select buttons (left, data-driven), GPS health (centre),
// clock/source (right).
Rectangle {
    id: root
    property var runPages: []        // [{ id, title, glyph }]
    property string currentId: ""
    signal pageSelected(string id)

    implicitHeight: 64
    color: Style.banner

    function _curIdx() {
        for (var i = 0; i < runPages.length; ++i)
            if (runPages[i].id === currentId) return i;
        return -1;
    }
    function _step(d) {
        var n = runPages.length;
        if (n === 0) return;
        var i = _curIdx();
        var ni = (i < 0) ? (d > 0 ? 0 : n - 1) : ((i + d + n) % n);
        root.pageSelected(runPages[ni].id);
    }

    // left: page pager (arrows + number/name)
    Row {
        id: pager
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        spacing: 8

        property int count: root.runPages.length
        property int curIdx: root._curIdx()
        property int dispIdx: curIdx < 0 ? 0 : curIdx
        property bool onRun: curIdx >= 0

        // previous
        Rectangle {
            width: 44; height: 48; radius: 8
            color: prevMa.pressed ? Style.bannerHi : "transparent"
            border.color: Style.panelEdge; border.width: 1
            anchors.verticalCenter: parent.verticalCenter
            MdiIcon { anchors.centerIn: parent; icon: Icons.chevronLeft; color: Style.white; font.pixelSize: 24 }
            MouseArea { id: prevMa; anchors.fill: parent; onClicked: root._step(-1) }
        }

        // indicator
        Rectangle {
            width: ind.width + 26; height: 48; radius: 8
            color: pager.onRun ? Style.accent : Style.bannerHi
            anchors.verticalCenter: parent.verticalCenter
            Column {
                id: ind
                anchors.centerIn: parent
                spacing: -2
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    MdiIcon {
                        visible: pager.count > 0
                        icon: (pager.count > 0) ? root.runPages[pager.dispIdx].glyph : ""
                        color: pager.onRun ? Style.banner : Style.white
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: (pager.count > 0) ? root.runPages[pager.dispIdx].title : ""
                        color: pager.onRun ? Style.banner : Style.white; font.pixelSize: 16; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pager.onRun ? ((pager.dispIdx + 1) + " / " + pager.count) : qsTr("menu open")
                    color: pager.onRun ? Style.banner : Style.textDim; font.pixelSize: 11
                }
            }
        }

        // next
        Rectangle {
            width: 44; height: 48; radius: 8
            color: nextMa.pressed ? Style.bannerHi : "transparent"
            border.color: Style.panelEdge; border.width: 1
            anchors.verticalCenter: parent.verticalCenter
            MdiIcon { anchors.centerIn: parent; icon: Icons.chevronRight; color: Style.white; font.pixelSize: 24 }
            MouseArea { id: nextMa; anchors.fill: parent; onClicked: root._step(1) }
        }
    }

    // centre: GPS health
    GpsHealth {
        anchors.centerIn: parent
    }

    // right: clock + active source
    Column {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 14
        spacing: -2
        Text {
            text: gps.utcTime.length >= 6
                  ? gps.utcTime.substring(0,2) + ":" + gps.utcTime.substring(2,4)
                    + ":" + gps.utcTime.substring(4,6) + " UTC"
                  : "--:--:-- UTC"
            color: Style.white; font.pixelSize: 16
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
        }
        Text {
            text: app.running ? app.activeSource : "not connected"
            color: app.connected ? Style.accent : Style.textDim
            font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
        }
    }
}
