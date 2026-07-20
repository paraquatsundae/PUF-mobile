import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Simple getting-started guide for new operators (phone + tablet).
Popup {
    id: root
    modal: true
    dim: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property bool firstRun: false

    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 24 : 360, 400)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 48 : 560, 520)
    anchors.centerIn: Overlay.overlay

    function openGuide(first) {
        root.firstRun = !!first
        open()
    }

    function dismiss() {
        theme.setUserGuideSeen(true)
        close()
    }

    background: Rectangle {
        color: theme.panel
        border.color: theme.accent
        border.width: 1
        radius: 12
    }

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            radius: 12
            color: theme.bannerHi
            Text {
                anchors.centerIn: parent
                text: root.firstRun ? qsTr("Welcome to PUF-mobile") : qsTr("How to use")
                color: theme.text
                font.pixelSize: 18
                font.bold: true
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            contentHeight: guideCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: guideCol
                width: parent.width
                spacing: 14

                Repeater {
                    model: [
                        {
                            title: qsTr("1. Before you drive"),
                            body: qsTr("Open SETUP and check:\n"
                                       + "• GPS — phone location or your receiver is connected\n"
                                       + "• Width — boom / spreader width is correct\n"
                                       + "• Paddock — select a field, or import one (see below)")
                        },
                        {
                            title: qsTr("2. Import a paddock (first time)"),
                            body: qsTr("Copy ISOXML (TASKDATA.XML or JD export folder) or a KML file into:\n"
                                       + "SETUP → Paddock → Browse to pick ISOXML or KML on the phone,\n"
                                       + "copy or move into Farm_data, then import.\n"
                                       + "Or place files in Download/Farm_data and tap Scan.")
                        },
                        {
                            title: qsTr("3. MAIN tab"),
                            body: qsTr("Shows the active paddock and saved work.\n"
                                       + "Resume a previous job or start new coverage on the current field.")
                        },
                        {
                            title: qsTr("4. MAP tab"),
                            body: qsTr("Live map while you work.\n"
                                       + "• Record — start / stop coverage (green swaths)\n"
                                       + "• Chase / top-down / whole-paddock views at the bottom\n"
                                       + "• Boundary outline when a paddock is loaded\n"
                                       + "Record boundary: SETUP → Record boundary, drive the perimeter, Save.")
                        },
                        {
                            title: qsTr("5. SETUP tab"),
                            body: qsTr("Width, GPS source, paddock list, boundary recording, and theme.\n"
                                       + "Tap this guide any time from How to use.")
                        },
                        {
                            title: qsTr("6. Tips"),
                            body: qsTr("• Wait for a GPS fix before recording\n"
                                       + "• Pause boundary recording if you leave the fence line\n"
                                       + "• Install updates over the old app — your paddocks are kept")
                        }
                    ]
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: theme.accent
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.body
                            color: theme.text
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            lineHeight: 1.25
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            color: theme.bannerHi
            radius: 12
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height / 2
                color: parent.color
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 32
                height: 44
                radius: 8
                color: gotMa.pressed ? theme.bannerHi : theme.accent
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Got it")
                    color: theme.accentText
                    font.pixelSize: 16
                    font.bold: true
                }
                MouseArea {
                    id: gotMa
                    anchors.fill: parent
                    onClicked: root.dismiss()
                }
            }
        }
    }

    onClosed: {
        if (!theme.userGuideSeen)
            theme.setUserGuideSeen(true)
    }
}
