import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: root
    modal: true
    dim: true
    padding: 16
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    // Parent is set from PhoneShell once ApplicationWindow.overlay exists.
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    width: Math.min((parent ? parent.width : 360) - 32, 340)

    property string clientId: ""
    property string farmId: ""
    property string fieldId: ""
    property string fieldName: ""
    property real savedAreaHa: 0
    property bool bootMode: false

    signal resumeChosen()
    signal newWorkChosen()
    signal otherJobsRequested()

    function _areaFromMeta(meta) {
        if (!meta || meta.areaHa === undefined) return 0
        return Number(meta.areaHa)
    }

    function openForField(cid, fid, fldId, fldName) {
        root.bootMode = false
        root.clientId = cid
        root.farmId = fid
        root.fieldId = fldId
        root.fieldName = fldName
        var meta = null
        try { meta = jobs.jobMeta(fldId) } catch (e) { meta = null }
        root.savedAreaHa = root._areaFromMeta(meta)
        open()
    }
    function openForCurrentField() {
        openForField(farm.activeClientId, farm.activeFarmId,
                     farm.activeFieldId, farm.activeFieldName)
    }
    function openOnBoot() {
        root.bootMode = true
        var lj = ({})
        try { lj = jobs.activeJob() } catch (e) { lj = ({}) }
        if (lj && lj.fieldId && lj.fieldId.length) {
            root.clientId = lj.clientId ? lj.clientId : ""
            root.farmId = lj.farmId ? lj.farmId : ""
            root.fieldId = lj.fieldId
            root.fieldName = lj.fieldName ? lj.fieldName : lj.fieldId
            root.savedAreaHa = root._areaFromMeta(lj)
        } else if (farm.hasActiveField && jobs.hasJob(farm.activeFieldId)) {
            openForCurrentField()
            root.bootMode = true
        } else {
            var lf = ""
            try { lf = jobs.lastActiveFieldId() } catch (e2) { lf = "" }
            if (lf.length && jobs.hasJob(lf)) {
                var m = null
                try { m = jobs.jobMeta(lf) } catch (e3) { m = null }
                root.clientId = m && m.clientId ? m.clientId : ""
                root.farmId = m && m.farmId ? m.farmId : ""
                root.fieldId = lf
                root.fieldName = m && m.fieldName ? m.fieldName : lf
                root.savedAreaHa = root._areaFromMeta(m)
            } else {
                root.fieldId = ""
                root.fieldName = ""
                root.savedAreaHa = 0
            }
        }
        open()
    }

    background: Rectangle {
        color: theme.panel
        border.color: theme.accent
        border.width: 1
        radius: 12
    }

    contentItem: ColumnLayout {
        spacing: 12
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.bootMode
                  ? qsTr("Welcome back")
                  : qsTr("Work on %1").arg(root.fieldName)
            color: theme.text
            font.pixelSize: 18
            font.bold: true
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: root.bootMode && root.fieldName.length > 0
            text: qsTr("Last job: %1").arg(root.fieldName)
            color: theme.textDim
            font.pixelSize: 14
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Saved coverage: %1 ha").arg(root.savedAreaHa.toFixed(2))
            color: theme.textDim
            font.pixelSize: 14
            visible: root.savedAreaHa > 0
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: 8
            visible: root.fieldId.length > 0 && root.savedAreaHa >= 0
                     && (root.bootMode || jobs.hasJob(root.fieldId))
            color: resumeMa.pressed ? theme.bannerHi : theme.accent
            Text {
                anchors.centerIn: parent
                text: root.bootMode
                      ? qsTr("Resume %1").arg(root.fieldName.length ? root.fieldName : qsTr("last job"))
                      : qsTr("Resume work")
                color: theme.accentText
                font.pixelSize: 16
                font.bold: true
            }
            MouseArea {
                id: resumeMa
                anchors.fill: parent
                onClicked: {
                    root.resumeChosen()
                    root.close()
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: 8
            color: otherMa.pressed ? theme.bannerHi : theme.banner
            border.color: theme.panelEdge
            Text {
                anchors.centerIn: parent
                text: qsTr("Other jobs\u2026")
                color: theme.text
                font.pixelSize: 16
                font.bold: true
            }
            MouseArea {
                id: otherMa
                anchors.fill: parent
                onClicked: {
                    root.close()
                    root.otherJobsRequested()
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: 8
            color: newMa.pressed ? theme.bannerHi : theme.banner
            border.color: theme.panelEdge
            Text {
                anchors.centerIn: parent
                text: root.bootMode ? qsTr("Start new work") : qsTr("Start new on this paddock")
                color: theme.text
                font.pixelSize: 16
                font.bold: true
            }
            MouseArea {
                id: newMa
                anchors.fill: parent
                onClicked: {
                    root.newWorkChosen()
                    root.close()
                }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Cancel")
            color: theme.textDim
            font.pixelSize: 14
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }
    }
}
