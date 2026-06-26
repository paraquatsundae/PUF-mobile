import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Setup hub: large tiles that open each setup sub-page.
Flickable {
    id: page
    signal navigate(string id)

    property string buildId: ""

    contentWidth: width
    contentHeight: body.implicitHeight + pagePad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Short viewports (Allwinner T3): tighter chrome so tile text stays inside boxes.
    readonly property bool compactViewport: height < 580
    readonly property int pagePad: compactViewport ? 12 : 20
    readonly property int gridGap: compactViewport ? 12 : 16
    readonly property int tileMargin: compactViewport ? 5 : 8
    readonly property int tileRows: Math.ceil(tiles.length / 2)
    readonly property real gridViewport: Math.max(80, height - pagePad * 2 - headerBlock.implicitHeight)
    readonly property real idealTileH: (gridViewport - (tileRows - 1) * gridGap) / tileRows
    readonly property real minTileH: compactViewport ? 84 : 96
    readonly property real maxTileH: compactViewport ? 128 : 140
    // Prefer fitting the viewport; scroll when tiles need more than minTileH each.
    readonly property real tileHeight: Math.min(maxTileH, Math.max(idealTileH, minTileH))
    readonly property real iconSize: Math.min(compactViewport ? 38 : 48, Math.round(tileHeight * (compactViewport ? 0.34 : 0.42)))
    readonly property real titleSize: Math.min(compactViewport ? 16 : 20, Math.max(13, Math.round(tileHeight * (compactViewport ? 0.17 : 0.20))))
    readonly property real descSize: Math.min(compactViewport ? 11 : 13, Math.max(10, Math.round(tileHeight * (compactViewport ? 0.12 : 0.14))))
    readonly property int tileSpacing: Math.max(compactViewport ? 2 : 4, Math.round(tileHeight * (compactViewport ? 0.04 : 0.06)))

    property var tiles: [
        { id: "paddock",title: qsTr("Paddock Setup"), glyph: Icons.farm,    desc: qsTr("Fields, boundaries, run lines, import") },
        { id: "impl",   title: qsTr("Implement"),   glyph: Icons.implement, desc: qsTr("Width, sections, offset") },
        { id: "layout", title: qsTr("Layout"),      glyph: Icons.layout,    desc: qsTr("Pages, columns, elements") },
        { id: "conn",   title: qsTr("GPS / Source"), glyph: Icons.gps,      desc: qsTr("Connection and NMEA source") },
        { id: "gpsinfo",title: qsTr("GPS Information"), glyph: Icons.satellite, desc: qsTr("Fix, sats, HDOP, TCM, antenna height") },
        { id: "catalog",title: qsTr("Products & Mixes"), glyph: Icons.work, desc: qsTr("View, edit, delete products, tank mixes, crops") }
    ]

    ColumnLayout {
        id: body
        x: pagePad
        y: pagePad
        width: page.width - pagePad * 2
        spacing: gridGap

        ColumnLayout {
            id: headerBlock
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Setup"); color: Style.accent; font.pixelSize: 22; font.bold: true }
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Save Settings")
                    onClicked: app.saveSettings()
                }
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Build") + " " + page.buildId
                color: Style.textDim
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: page.tileRows * page.tileHeight + (page.tileRows - 1) * page.gridGap
            columns: 2
            rowSpacing: page.gridGap
            columnSpacing: page.gridGap

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
}
