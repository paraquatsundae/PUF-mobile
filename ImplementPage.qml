import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons
import "Sections.js" as Sections

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
        anchors.margins: 16
        spacing: 16

        Label { text: qsTr("Implement"); color: Style.accent; font.pixelSize: 20; font.bold: true }

        // Width control
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge
            border.width: 1
            implicitHeight: widthCol.implicitHeight + 28

            ColumnLayout {
                id: widthCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label { text: qsTr("Working width"); color: Style.textDim; font.pixelSize: 14 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Button {
                        text: Icons.minus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64
                        onClicked: app.implementWidth = app.implementWidth - 0.5
                        autoRepeat: true
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: app.implementWidth.toFixed(1) + " m"
                        color: Style.white; font.pixelSize: 40; font.bold: true
                    }

                    Button {
                        text: Icons.plus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64
                        onClicked: app.implementWidth = app.implementWidth + 0.5
                        autoRepeat: true
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 1.0; to: 48.0; stepSize: 0.5
                    value: app.implementWidth
                    onMoved: app.implementWidth = value
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [3, 6, 9, 12, 18, 24, 36]
                        Button {
                            text: modelData + " m"
                            onClicked: app.implementWidth = modelData
                        }
                    }
                }
            }
        }

        // Sections — count + per-section width (John Deere L../C/R.. numbering).
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge
            border.width: 1
            implicitHeight: secCol.implicitHeight + 28

            ColumnLayout {
                id: secCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Sections"); color: Style.textDim; font.pixelSize: 14; Layout.fillWidth: true }
                    Label { text: qsTr("total %1 m").arg(app.implementWidth.toFixed(1))
                            color: Style.white; font.pixelSize: 14; font.bold: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Button {
                        text: Icons.minus; font.family: Icons.family; font.pixelSize: 24
                        implicitWidth: 56; implicitHeight: 56
                        onClicked: app.sectionCount = app.sectionCount - 1
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: app.sectionCount + qsTr(" sections")
                        color: Style.white; font.pixelSize: 28; font.bold: true
                    }
                    Button {
                        text: Icons.plus; font.family: Icons.family; font.pixelSize: 24
                        implicitWidth: 56; implicitHeight: 56
                        onClicked: app.sectionCount = app.sectionCount + 1
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Distribute evenly")
                    onClicked: app.distributeEvenly()
                }

                Repeater {
                    model: app.sectionCount
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label {
                            text: Sections.label(index, app.sectionCount)
                            color: Style.accent; font.pixelSize: 16; font.bold: true
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Button {
                            text: Icons.minus; font.family: Icons.family; font.pixelSize: 20
                            implicitWidth: 48; implicitHeight: 48
                            onClicked: app.setSectionWidth(index, app.sectionWidths[index] - 0.5)
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: (app.sectionWidths[index] !== undefined
                                   ? app.sectionWidths[index].toFixed(1) : "0.0") + " m"
                            color: Style.white; font.pixelSize: 20
                        }
                        Button {
                            text: Icons.plus; font.family: Icons.family; font.pixelSize: 20
                            implicitWidth: 48; implicitHeight: 48
                            onClicked: app.setSectionWidth(index, app.sectionWidths[index] + 0.5)
                        }
                    }
                }
            }
        }

        // Track spacing (run-line / controlled-traffic tram spacing). Independent
        // of the boom width: a wide boom can run on narrower trams.
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge
            border.width: 1
            implicitHeight: trackCol.implicitHeight + 28

            ColumnLayout {
                id: trackCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label { text: qsTr("Track spacing (run-line spacing)"); color: Style.textDim; font.pixelSize: 14 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Button {
                        text: Icons.minus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64
                        onClicked: app.trackSpacing = app.trackSpacing - 0.5
                        autoRepeat: true
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: app.trackSpacing.toFixed(1) + " m"
                        color: Style.white; font.pixelSize: 40; font.bold: true
                    }
                    Button {
                        text: Icons.plus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64
                        onClicked: app.trackSpacing = app.trackSpacing + 0.5
                        autoRepeat: true
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 1.0; to: 48.0; stepSize: 0.5
                    value: app.trackSpacing
                    onMoved: app.trackSpacing = value
                }

                Button {
                    text: qsTr("Match boom width (%1 m)").arg(app.implementWidth.toFixed(1))
                    onClicked: app.trackSpacing = app.implementWidth
                }
            }
        }

        // Connection type + distance from GPS receiver to record point
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge
            border.width: 1
            implicitHeight: attachCol.implicitHeight + 28

            ColumnLayout {
                id: attachCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label {
                    text: qsTr("Connection type & receiver offset")
                    color: Style.textDim
                    font.pixelSize: 14
                }

                RecordAttachmentPanel {
                    Layout.fillWidth: true
                    large: true
                    useTabletStyle: true
                }
            }
        }

        // Tank size (capacity). Recorded with each application on the Work page.
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge
            border.width: 1
            implicitHeight: tankCol.implicitHeight + 28

            ColumnLayout {
                id: tankCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label { text: qsTr("Tank size (capacity)"); color: Style.textDim; font.pixelSize: 14 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Button {
                        text: Icons.minus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64
                        onClicked: app.tankSizeL = app.tankSizeL - 50
                        autoRepeat: true
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Math.round(app.tankSizeL) + " L"
                        color: Style.white; font.pixelSize: 40; font.bold: true
                    }
                    Button {
                        text: Icons.plus; font.family: Icons.family; font.pixelSize: 26
                        implicitWidth: 64; implicitHeight: 64
                        onClicked: app.tankSizeL = app.tankSizeL + 50
                        autoRepeat: true
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 12000; stepSize: 50
                    value: app.tankSizeL
                    onMoved: app.tankSizeL = value
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [600, 1000, 2000, 3000, 4000, 6000]
                        Button {
                            text: modelData + " L"
                            onClicked: app.tankSizeL = modelData
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Style.textDim
            font.pixelSize: 13
            text: qsTr("Coverage records at the point set by connection type above "
                       + "(ute = at receiver; 3PL / drawbar = offset behind receiver). "
                       + "Section control shuts off sections that pass over already-covered ground.")
        }
    }
}
