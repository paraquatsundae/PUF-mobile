import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Paddock Setup sub-hub: groups the field/boundary work (Farm Setup) and the
// run-line management page. Opened from the Setup hub; the sub-page header
// (with a back to Setup) is supplied by main.qml.
Flickable {
    id: page
    signal navigate(string id)

    contentWidth: width
    contentHeight: body.implicitHeight + pagePad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property bool compactViewport: height < 580
    readonly property int pagePad: compactViewport ? 12 : 20
    readonly property int gridGap: compactViewport ? 12 : 16
    readonly property int tileMargin: compactViewport ? 5 : 8
    readonly property int tileRows: Math.ceil(tiles.length / 2)
    readonly property real gridViewport: Math.max(80, height - pagePad * 2)
    readonly property real idealTileH: (gridViewport - (tileRows - 1) * gridGap) / tileRows
    readonly property real minTileH: compactViewport ? 84 : 96
    readonly property real maxTileH: compactViewport ? 148 : 160
    readonly property real tileHeight: Math.min(maxTileH, Math.max(idealTileH, minTileH))
    readonly property real iconSize: Math.min(compactViewport ? 38 : 48, Math.round(tileHeight * (compactViewport ? 0.34 : 0.42)))
    readonly property real titleSize: Math.min(compactViewport ? 16 : 20, Math.max(13, Math.round(tileHeight * (compactViewport ? 0.17 : 0.20))))
    readonly property real descSize: Math.min(compactViewport ? 11 : 13, Math.max(10, Math.round(tileHeight * (compactViewport ? 0.12 : 0.14))))
    readonly property int tileSpacing: Math.max(compactViewport ? 2 : 4, Math.round(tileHeight * (compactViewport ? 0.04 : 0.06)))

    property var tiles: [
        { id: "farm",    title: qsTr("Farm Setup"), glyph: Icons.farm,  desc: qsTr("Clients, farms, fields, boundaries, import") },
        { id: "ablines", title: qsTr("Run Lines"),  glyph: Icons.track, desc: qsTr("Rename, delete, select, view AB lines") }
    ]

    GridLayout {
        id: body
        x: pagePad
        y: pagePad
        width: page.width - pagePad * 2
        columns: 2
        rowSpacing: gridGap
        columnSpacing: gridGap

        Repeater {
            model: page.tiles
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: page.tileHeight
                radius: 12
                color: tileMa.pressed ? Style.bannerHi : Style.panel
                border.color: Style.accent; border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: page.tileMargin
                    spacing: page.tileSpacing

                    MdiIcon {
                        icon: modelData.glyph
                        color: Style.accent
                        font.pixelSize: page.iconSize
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: modelData.title
                        color: Style.white
                        font.pixelSize: page.titleSize
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: modelData.desc
                        color: Style.textDim
                        font.pixelSize: page.descSize
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Item { Layout.fillHeight: true }
                }
                MouseArea { id: tileMa; anchors.fill: parent; onClicked: page.navigate(modelData.id) }
            }
        }
    }
}
