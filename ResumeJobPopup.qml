import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Day-start Resume popup (PLAN §1/§A): the last open job up top with a prominent
// Resume, a chronological list of recent jobs below (most recent first), and a
// Start New Job action. Opening a job points the field at it and activates the
// field so FieldView restores its coverage + application context.
Popup {
    id: root
    modal: true; dim: true; padding: 16
    closePolicy: Popup.CloseOnEscape
    parent: Overlay.overlay
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    width: Math.min((parent ? parent.width : 560) - 24, 560)
    height: Math.min((parent ? parent.height : 640) - 24, 640)

    // Emitted after a job is resumed/opened so the shell can navigate to the map.
    signal opened()

    property var active: ({})
    property var jobList: []

    function refresh() {
        active = jobs.activeJob();
        jobList = jobs.listAllJobs(40);
    }
    function openFresh() { refresh(); open(); }

    function stateLabel(s) {
        if (s === "complete") return qsTr("Complete");
        if (s === "paused") return qsTr("Paused");
        return qsTr("Open");
    }
    function stateColor(s) {
        if (s === "complete") return Style.textDim;
        if (s === "paused") return "#d8a657";
        return Style.accent;
    }
    function shortDate(iso) {
        if (!iso) return "";
        var s = "" + iso;
        return s.length >= 16 ? s.substring(0, 16).replace("T", " ") : s;
    }
    function areaText(m) {
        return (m && m.areaHa !== undefined ? Number(m.areaHa).toFixed(2) : "0.00") + " ha";
    }

    function resumeJob(m) {
        if (!m || !m.fieldId || !m.jobId) return;
        jobs.openJob(m.fieldId, m.jobId);
        farm.setActiveField(m.clientId ? m.clientId : "", m.farmId ? m.farmId : "", m.fieldId);
        root.opened();
        root.close();
    }

    property var pendingDelete: ({})
    function askDelete(m) {
        if (!m || !m.fieldId || !m.jobId) return;
        pendingDelete = m;
        confirmDelete.open();
    }
    function doDelete() {
        var m = root.pendingDelete;
        if (m && m.fieldId && m.jobId)
            jobs.deleteJob(m.fieldId, m.jobId);
        pendingDelete = ({});
        root.refresh();
    }

    Connections { target: jobs; function onChanged() { if (root.visible) root.refresh(); } }

    background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12 }

    contentItem: ColumnLayout {
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Resume work"); color: Style.accent
                    font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
            Button { text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                     implicitWidth: 44; implicitHeight: 44; onClicked: root.close() }
        }

        // ---- Last open job (prominent) ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: lastCol.implicitHeight + 24
            radius: 10
            color: "#11ff1aa3"
            border.color: Style.accent; border.width: 2
            visible: root.active && root.active.jobId !== undefined

            ColumnLayout {
                id: lastCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 12
                spacing: 8
                Label { text: qsTr("Last open job"); color: Style.textDim; font.pixelSize: 13 }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.active.displayName ? root.active.displayName : qsTr("Job")
                    color: Style.white; font.pixelSize: 19; font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    text: (root.active.fieldName ? root.active.fieldName : "")
                          + "   \u2022   " + root.areaText(root.active)
                          + (root.active.application && root.active.application.rateMode === "rx"
                             ? "   \u2022   " + qsTr("Rx") : "")
                    color: Style.textDim; font.pixelSize: 14
                }
                Button {
                    Layout.fillWidth: true; implicitHeight: 56
                    text: qsTr("Resume")
                    font.pixelSize: 18; font.bold: true
                    onClicked: root.resumeJob(root.active)
                }
            }
        }

        Label {
            visible: !(root.active && root.active.jobId !== undefined)
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("No open job. Start a new one to begin recording.")
            color: Style.textDim; font.pixelSize: 15
        }

        // ---- Start new ----
        Button {
            Layout.fillWidth: true; implicitHeight: 52
            text: qsTr("Start New Job")
            font.pixelSize: 16; font.bold: true
            onClicked: { root.close(); newJob.openFresh(); }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

        Label { text: qsTr("Recent jobs"); color: Style.textDim; font.pixelSize: 14 }

        ListView {
            id: lv
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 6; model: root.jobList
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Rectangle {
                width: lv.width
                implicitHeight: row.implicitHeight + 16
                radius: 8
                color: rma.pressed ? Style.accent : Style.bannerHi
                border.color: Style.panelEdge; border.width: 1
                // Resume MouseArea declared first so it sits beneath the content and
                // the delete button (which capture their own taps).
                MouseArea { id: rma; anchors.fill: parent; onClicked: root.resumeJob(modelData) }
                ColumnLayout {
                    id: row
                    anchors.left: parent.left
                    anchors.right: parent.right; anchors.rightMargin: 52
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Label { Layout.fillWidth: true
                                text: modelData.displayName ? modelData.displayName : qsTr("Job")
                                color: rma.pressed ? Style.banner : Style.white
                                font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                        Label { text: root.stateLabel(modelData.state)
                                color: rma.pressed ? Style.banner : root.stateColor(modelData.state)
                                font.pixelSize: 12; font.bold: true }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: (modelData.fieldName ? modelData.fieldName : "")
                              + "   \u2022   " + root.areaText(modelData)
                              + "   \u2022   " + root.shortDate(modelData.modifiedUtc)
                        color: rma.pressed ? Style.banner : Style.textDim; font.pixelSize: 12
                    }
                }
                // Delete affordance (declared last -> topmost). Confirms before
                // removing so a test job can be cleared without losing real work.
                Button {
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 40; implicitHeight: 40
                    text: Icons.del; font.family: Icons.family; font.pixelSize: 20
                    flat: true
                    contentItem: Text { text: parent.text; font: parent.font
                                        color: "#e05a5a"; horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: "transparent" }
                    onClicked: root.askDelete(modelData)
                }
            }
        }

        Label {
            visible: !root.jobList || root.jobList.length === 0
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("No saved jobs yet.")
            color: Style.textDim; font.pixelSize: 13
        }
    }

    NewJobPopup { id: newJob; onCreated: { root.opened(); } }

    // Delete confirmation (dark-theme). Deleting the active/open job is handled in
    // JobStore::deleteJob (it releases the active + current pointers first).
    Popup {
        id: confirmDelete
        modal: true; dim: true; padding: 16
        closePolicy: Popup.CloseOnEscape
        parent: Overlay.overlay
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        width: Math.min((parent ? parent.width : 420) - 24, 420)
        background: Rectangle { color: Style.panel; border.color: "#e05a5a"; border.width: 1; radius: 12 }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: qsTr("Delete job?"); color: Style.accent
                    font.pixelSize: 19; font.bold: true }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                color: Style.white; font.pixelSize: 15
                text: (root.pendingDelete && root.pendingDelete.displayName
                       ? root.pendingDelete.displayName : qsTr("This job"))
                      + "\n\n" + qsTr("This permanently removes its coverage and metadata. This cannot be undone.")
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                Button { Layout.fillWidth: true; implicitHeight: 48
                         text: qsTr("Cancel"); onClicked: confirmDelete.close() }
                Button {
                    Layout.fillWidth: true; implicitHeight: 48
                    text: qsTr("Delete"); font.bold: true
                    contentItem: Text { text: parent.text; font: parent.font
                                        color: Style.white; horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: parent.pressed ? "#b03030" : "#e05a5a" }
                    onClicked: { confirmDelete.close(); root.doDelete(); }
                }
            }
        }
    }
}
