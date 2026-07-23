import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

// Shown after a boundary is imported or recorded when no offline pack covers it.
Dialog {
    id: dlg
    modal: true
    anchors.centerIn: parent
    width: Math.min(460, parent ? parent.width - 40 : 460)
    title: qsTr("Download satellite map?")
    standardButtons: Dialog.NoButton

    property var plan: basemap.pendingPrompt

    onOpened: plan = basemap.pendingPrompt

    Connections {
        target: basemap
        function onPendingPromptChanged() {
            if (basemap.hasPendingPrompt) {
                dlg.plan = basemap.pendingPrompt
                if (!dlg.visible)
                    dlg.open()
            }
        }
        function onDownloadFinished(ok) {
            if (dlg.visible && !basemap.downloading)
                dlg.close()
        }
    }

    ColumnLayout {
        width: dlg.availableWidth
        spacing: 12

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Style.white
            text: plan && plan.label
                  ? qsTr("Save paddock overview imagery for \"%1\" so the map works without data?").arg(plan.label)
                  : qsTr("Save paddock overview imagery?")
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Style.textDim
            font.pixelSize: 13
            visible: !!(plan && plan.ok)
            text: plan && plan.ok
                  ? qsTr("Overview pack about %1 (%2 tiles, z%3–%4). Wi‑Fi recommended. For max cab sharpness, download cab detail later from Offline maps.")
                        .arg(plan.mbLabel).arg(plan.tileCount)
                        .arg(plan.minZoom || 14).arg(plan.maxZoom || 17)
                  : ""
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: basemap.downloading
            value: basemap.progress
            from: 0; to: 1
        }
        Label {
            Layout.fillWidth: true
            visible: basemap.downloading
            text: basemap.statusText
            color: Style.textDim
            font.pixelSize: 12
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Item { Layout.fillWidth: true }
            Button {
                text: qsTr("Not now")
                enabled: !basemap.downloading
                onClicked: {
                    basemap.clearPendingPrompt()
                    dlg.close()
                }
            }
            Button {
                text: basemap.downloading ? qsTr("Cancel") : qsTr("Download")
                onClicked: {
                    if (basemap.downloading)
                        basemap.cancelDownload()
                    else
                        basemap.acceptPendingPrompt()
                }
            }
        }
    }
}
