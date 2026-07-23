import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Offline satellite imagery — two-tier Esri packs:
//   overview z14–18 for the whole paddock, detail z18–19 around GPS (~cab patch).
Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    property string searchText: ""
    property var selectedPlan: ({})
    property var detailPlan: ({})

    function refreshActivePlan() {
        if (!farm.hasActiveField || farm.boundaryCount < 3) {
            selectedPlan = ({})
        } else {
            selectedPlan = basemap.planForPoints(farm.activeBoundary, 250)
            if (selectedPlan.ok) {
                selectedPlan.packId = farm.activeFieldId
                selectedPlan.label = farm.activeFieldName
            }
        }
        refreshDetailPlan()
    }

    function refreshDetailPlan() {
        if (!gps.hasFix) {
            detailPlan = ({})
            return
        }
        detailPlan = basemap.planDetailAround(gps.latitude, gps.longitude, 220)
        if (detailPlan.ok) {
            detailPlan.packId = farm.hasActiveField
                    ? (farm.activeFieldId + "-detail")
                    : ("detail-" + Date.now())
            detailPlan.label = farm.hasActiveField
                    ? (farm.activeFieldName + " (detail)")
                    : qsTr("Cab detail")
        }
    }

    Component.onCompleted: refreshActivePlan()
    Connections {
        target: farm
        function onGeometryChanged() { page.refreshActivePlan() }
        function onActiveChanged() { page.refreshActivePlan() }
    }
    Connections {
        target: gps
        function onFixChanged() { page.refreshDetailPlan() }
    }

    ColumnLayout {
        id: col
        x: 16; y: 16
        width: page.width - 32
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: qsTr("Offline satellite maps")
            color: Style.accent
            font.pixelSize: 20
            font.bold: true
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Style.textDim
            font.pixelSize: 13
            text: qsTr("Large paddocks use two packs: overview (z14–17) for the whole boundary, and cab detail (z17–18) around the machine. Esri has no finer imagery for most rural WA — higher zooms only show “Map data not yet available”.")
        }
        Label {
            Layout.fillWidth: true
            visible: !basemap.sslAvailable
            wrapMode: Text.WordWrap
            color: "#ff8a80"
            font.pixelSize: 13
            text: qsTr("HTTPS/SSL is not available in this build — tile download will fail. Redeploy an APK that bundles OpenSSL.")
        }

        // ---- Active field overview ----
        Rectangle {
            Layout.fillWidth: true
            radius: 10
            color: Style.panel
            border.color: Style.accent
            border.width: 1
            implicitHeight: activeCol.implicitHeight + 24
            ColumnLayout {
                id: activeCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                Label {
                    text: qsTr("Paddock overview")
                    color: Style.white
                    font.bold: true
                    font.pixelSize: 15
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Style.textDim
                    font.pixelSize: 13
                    text: !farm.hasActiveField
                          ? qsTr("No active field.")
                          : (farm.boundaryCount < 3
                             ? qsTr("%1 — no boundary yet.").arg(farm.activeFieldName)
                             : (selectedPlan.ok
                                ? qsTr("%1 — about %2 (%3 tiles, z%4–%5)")
                                      .arg(farm.activeFieldName)
                                      .arg(selectedPlan.mbLabel || "")
                                      .arg(selectedPlan.tileCount || 0)
                                      .arg(selectedPlan.minZoom || 0)
                                      .arg(selectedPlan.maxZoom || 0)
                                : (selectedPlan.error || qsTr("Cannot plan pack."))))
                }
                Label {
                    Layout.fillWidth: true
                    visible: !!(selectedPlan && selectedPlan.zoomReduced)
                    wrapMode: Text.WordWrap
                    color: "#ffcc80"
                    font.pixelSize: 12
                    text: qsTr("Detail reduced to fit the tile budget — download cab detail separately for sharp zoom.")
                }
                Button {
                    text: qsTr("Download paddock overview")
                    enabled: selectedPlan.ok && !basemap.downloading
                    onClicked: {
                        basemap.startDownload(selectedPlan.packId, selectedPlan.label,
                                              selectedPlan.south, selectedPlan.west,
                                              selectedPlan.north, selectedPlan.east)
                    }
                }
            }
        }

        // ---- Cab detail ----
        Rectangle {
            Layout.fillWidth: true
            radius: 10
            color: Style.panel
            border.color: Style.bannerHi
            border.width: 1
            implicitHeight: detailCol.implicitHeight + 24
            ColumnLayout {
                id: detailCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                Label {
                    text: qsTr("Cab detail around machine")
                    color: Style.white
                    font.bold: true
                    font.pixelSize: 15
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Style.textDim
                    font.pixelSize: 13
                    text: !gps.hasFix
                          ? qsTr("Waiting for GPS fix…")
                          : (detailPlan.ok
                             ? qsTr("Around current position — about %1 (%2 tiles, z%3–%4). Re-run when you move to a new part of the paddock.")
                                   .arg(detailPlan.mbLabel || "")
                                   .arg(detailPlan.tileCount || 0)
                                   .arg(detailPlan.minZoom || 0)
                                   .arg(detailPlan.maxZoom || 0)
                             : (detailPlan.error || qsTr("Cannot plan detail pack.")))
                }
                Button {
                    text: qsTr("Download cab detail here")
                    enabled: detailPlan.ok && !basemap.downloading && gps.hasFix
                    onClicked: {
                        basemap.startDetailDownload(detailPlan.packId, detailPlan.label,
                                                    gps.latitude, gps.longitude, 220)
                    }
                }
            }
        }

        // ---- Search ----
        Label {
            text: qsTr("Search location")
            color: Style.white
            font.bold: true
            font.pixelSize: 15
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("Farm name, town, or address…")
                color: Style.white
                onAccepted: basemap.searchLocation(text)
            }
            Button {
                text: basemap.searching ? qsTr("…") : qsTr("Search")
                enabled: !basemap.searching && searchField.text.trim().length > 0
                onClicked: basemap.searchLocation(searchField.text)
            }
        }

        Repeater {
            model: basemap.searchResults
            delegate: Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: Style.bannerHi
                border.color: Style.accent
                border.width: 1
                implicitHeight: Math.max(52, sCol.implicitHeight + 16)
                ColumnLayout {
                    id: sCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    Label {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Style.white
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                    }
                    Button {
                        text: qsTr("Download overview of this area")
                        enabled: !basemap.downloading
                        onClicked: {
                            var plan = basemap.planForBbox(modelData.south, modelData.west,
                                                           modelData.north, modelData.east)
                            if (!plan.ok)
                                return
                            basemap.startDownload(
                                "search-" + Date.now(),
                                modelData.label,
                                plan.south, plan.west, plan.north, plan.east)
                        }
                    }
                }
            }
        }

        // ---- Progress ----
        Rectangle {
            Layout.fillWidth: true
            visible: basemap.downloading || basemap.statusText.length > 0
            radius: 8
            color: Style.panel
            implicitHeight: progCol.implicitHeight + 20
            ColumnLayout {
                id: progCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                Label {
                    Layout.fillWidth: true
                    text: basemap.statusText
                    color: Style.white
                    font.pixelSize: 13
                }
                ProgressBar {
                    Layout.fillWidth: true
                    visible: basemap.downloading
                    value: basemap.progress
                    from: 0; to: 1
                }
                Button {
                    visible: basemap.downloading
                    text: qsTr("Cancel")
                    onClicked: basemap.cancelDownload()
                }
                Label {
                    Layout.fillWidth: true
                    visible: basemap.errorText.length > 0
                    text: basemap.errorText
                    color: "#ff8a80"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                }
            }
        }

        // ---- Installed packs ----
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("On device")
                color: Style.white
                font.bold: true
                font.pixelSize: 15
                Layout.fillWidth: true
            }
            Button {
                text: qsTr("Clear all maps")
                enabled: !basemap.downloading && basemap.packs.length > 0
                onClicked: basemap.clearAllMaps()
            }
        }
        Label {
            visible: basemap.packs.length < 1
            text: qsTr("No offline packs yet.")
            color: Style.textDim
            font.pixelSize: 13
        }
        Repeater {
            model: basemap.packs
            delegate: Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: Style.panel
                border.color: Style.bannerHi
                border.width: 1
                implicitHeight: pCol.implicitHeight + 16
                ColumnLayout {
                    id: pCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    Label {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Style.white
                        wrapMode: Text.WordWrap
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("%1 · %2 · %3 tiles · z%4–%5")
                              .arg(modelData.kind === "detail" ? qsTr("detail") : qsTr("overview"))
                              .arg(modelData.mbLabel)
                              .arg(modelData.tileCount)
                              .arg(modelData.minZoom)
                              .arg(modelData.maxZoom)
                        color: Style.textDim
                        font.pixelSize: 12
                    }
                    Button {
                        text: qsTr("Delete pack + tiles")
                        enabled: !basemap.downloading
                        onClicked: basemap.deletePack(modelData.id)
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Style.textDim
            font.pixelSize: 11
            text: basemap.attribution()
        }
    }
}
