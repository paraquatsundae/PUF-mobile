import QtQuick 2.15

import QtQuick.Layouts 1.15



Item {

    id: phone

    property string tab: "main"

    property string setupScreen: ""

    property bool showJobList: false

    property string buildId: ""



    CoverageRecorder { id: recorder }

    PhoneWorkSync { id: workSync; recorder: recorder }



    function _findOverlay() {

        var p = phone

        while (p) {

            if (p.overlay !== undefined)

                return p.overlay

            p = p.parent

        }

        return null

    }

    function _safeHasJob(fieldId) {

        if (!fieldId || !fieldId.length)

            return false

        try { return jobs.hasJob(fieldId) } catch (e) { return false }

    }

    function _attachWorkChoice() {

        var ov = phone._findOverlay()

        if (ov && workChoice.parent !== ov)

            workChoice.parent = ov

        return workChoice.parent !== null && workChoice.parent !== undefined

    }



    function offerWorkChoice(clientId, farmId, fieldId, fieldName) {

        if (phone._safeHasJob(fieldId)) {

            if (phone._attachWorkChoice())

                workChoice.openForField(clientId, farmId, fieldId, fieldName)

            else

                workSync.activateField(clientId, farmId, fieldId, true)

        } else {

            workSync.activateField(clientId, farmId, fieldId, false)

        }

    }



    function openWorkChoice() {

        if (!phone._attachWorkChoice())

            return false

        if (farm.hasActiveField && phone._safeHasJob(farm.activeFieldId))

            workChoice.openForCurrentField()

        else

            workChoice.openOnBoot()

        return true

    }



    function openJobList() {

        phone.showJobList = true

        jobListScreen.refresh()

    }



    PhoneWorkChoicePopup {

        id: workChoice

        onResumeChosen: {

            if (workChoice.bootMode || !workChoice.fieldId.length

                    || workChoice.fieldId !== farm.activeFieldId) {

                workSync.resumeJobEntry({

                    fieldId: workChoice.fieldId,

                    jobId: workChoice.bootMode ? (workSync.lastJob.jobId || "") : "",

                    clientId: workChoice.clientId,

                    farmId: workChoice.farmId,

                    fieldName: workChoice.fieldName

                })

            } else {

                workSync.activateField(workChoice.clientId, workChoice.farmId,

                                       workChoice.fieldId, true)

            }

        }

        onNewWorkChosen: {

            if (workChoice.fieldId.length) {

                workSync.activateField(workChoice.clientId, workChoice.farmId,

                                       workChoice.fieldId, false)

            } else if (farm.hasActiveField) {

                workSync.startNewOnCurrentField()

            } else {

                phone.tab = "setup"

                phone.setupScreen = "paddock"

            }

        }

        onOtherJobsRequested: phone.openJobList()

    }



    Component.onCompleted: {

        platform.applySystemChrome(theme.dark)

        platform.refreshSystemInsets()

        insetRefreshTimer.start()

        platform.refreshCellularGeneration()

        if (!app.running && app.tabletGpsSupported)

            app.startTabletGps()

        workSync.refreshJobIndex()

        bootWorkChoice.start()

    }



    property int bootAttachRetries: 0

    Timer {

        id: bootWorkChoice

        interval: 800

        repeat: false

        onTriggered: phone._tryBootWorkChoice()

    }

    function _tryBootWorkChoice() {

        workSync.refreshJobIndex()

        if (!workSync.hasAnySavedWork())

            return

        if (!phone._attachWorkChoice()) {

            if (phone.bootAttachRetries < 3) {

                phone.bootAttachRetries++

                bootWorkChoice.interval = 400

                bootWorkChoice.start()

            }

            return

        }

        workChoice.openOnBoot()

    }



    Connections {

        target: theme

        function onDarkChanged() {

            platform.applySystemChrome(theme.dark)

            platform.refreshSystemInsets()

        }

    }



    Timer {

        id: insetRefreshTimer

        interval: 100

        repeat: true

        property int tries: 0

        onTriggered: {

            platform.refreshSystemInsets()

            tries++

            if (platform.statusBarInset > 0 || tries >= 30)

                stop()

        }

    }



    Connections {

        target: app

        function onRecordingChanged() {

            platform.setKeepScreenOn(app.recordingCoverage)

            platform.setBackgroundRecording(app.recordingCoverage)

        }

    }



    Timer {

        interval: 5000; running: true; repeat: true

        onTriggered: platform.refreshCellularGeneration()

    }



    Rectangle {

        anchors.left: parent.left

        anchors.right: parent.right

        anchors.bottom: parent.bottom

        height: platform.navigationBarInset

        color: theme.banner

        z: 19

    }



    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: platform.navigationBarInset
        spacing: 0

        StackLayout {

            id: stack

            Layout.fillWidth: true

            Layout.fillHeight: true

            currentIndex: phone.showJobList ? 6

                        : setupScreen === "width" ? 3

                        : setupScreen === "paddock" ? 4

                        : setupScreen === "gps" ? 5

                        : tab === "map" ? 1

                        : tab === "setup" ? 2 : 0



            PhoneMainTab {

                onOpenWidth: { phone.tab = "setup"; phone.setupScreen = "width" }

                onOpenPaddock: { phone.tab = "setup"; phone.setupScreen = "paddock" }

                onResumeWorkRequested: phone.openWorkChoice()

                onNewWorkRequested: {

                    if (farm.hasActiveField)

                        workSync.startNewOnCurrentField()

                    else {

                        phone.tab = "setup"

                        phone.setupScreen = "paddock"

                    }

                }

                onOtherJobsRequested: phone.openJobList()

            }

            PhoneMapTab { recorder: recorder }

            PhoneSetupTab {

                buildId: phone.buildId

                onOpenWidth: phone.setupScreen = "width"

                onOpenPaddock: phone.setupScreen = "paddock"

                onOpenGps: phone.setupScreen = "gps"

            }

            PhoneWidthScreen {

                onBack: phone.setupScreen = ""

                Component.onCompleted: syncFromApp()

                onVisibleChanged: if (visible) syncFromApp()

            }

            PhonePaddockScreen {

                onBack: phone.setupScreen = ""

                onFieldSelected: function(cid, fid, fldId, fldName) {

                    phone.offerWorkChoice(cid, fid, fldId, fldName)

                }

            }

            PhoneGpsScreen { onBack: phone.setupScreen = "" }

            PhoneJobListScreen {

                id: jobListScreen

                onBack: phone.showJobList = false

                onJobSelected: function(entry) {

                    phone.showJobList = false

                    workSync.resumeJobEntry(entry)

                    phone.tab = "main"

                }

                onJobDeleted: function(entry) { workSync.handleJobDeleted(entry) }

            }

        }

        PhoneBottomNav {

            visible: setupScreen === "" && !phone.showJobList

            Layout.fillWidth: true

            currentTab: phone.tab

            onTabSelected: function(t) { phone.tab = t; phone.setupScreen = "" }

        }

    }

}


