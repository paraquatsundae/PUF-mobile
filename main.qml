import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons
import "FormFactor.js" as FormFactor

ApplicationWindow {
    id: shell
    visible: true
    width: Screen.width
    height: Screen.height
    title: qsTr("PUF-mobile")
    // Phone shell follows the runtime theme; tablet UI stays on the dark palette.
    color: isPhone ? theme.banner : Style.bg

    // Device class from physical short side (stable when the display rotates).
    readonly property bool isPhone: FormFactor.isPhone(Screen.width, Screen.height)
    // Meaningful soft-key band only (ignore spurious 1–7 px OEM noise).
    readonly property int tabletNavInset: platform.navigationBarInset >= 8 ? platform.navigationBarInset : 0
    // Bumped each deploy — visible on SETUP to confirm which build is on-device.
    readonly property string tabletBuildId: "26Jun-tablet-setup-polish"
    readonly property string phoneBuildId: "26Jun16:30-swath-paint"

    // Dark palette so every Controls text input (TextField/ComboBox) reads light
    // text on a dark base instead of the Default style's black-on-white (which made
    // light-coloured text invisible while typing). Cascades to popups too.
    palette.base: Style.bannerHi
    palette.text: Style.white
    palette.highlight: Style.accent
    palette.highlightedText: Style.banner

    // Material Design Icons webfont — loaded once; every icon Text references it
    // by its family name (Icons.family).
    FontLoader { id: mdiFont; source: "qrc:/fonts/materialdesignicons-webfont.ttf" }

    // Current page is referenced by string id (decoupled from stack order).
    property string currentPageId: "nav"
    onCurrentPageIdChanged: layout.currentPage = currentPageId
    Component.onCompleted: {
        if (!shell.isPhone) {
            platform.applySystemChrome(theme.dark)
            platform.refreshSystemInsets()
            tabletInsetRefresh.start()
        }
        layout.currentPage = currentPageId
    }

    // Android software nav bar: re-query until the JNI bridge reports a height
    // (Chinese Allwinner T3 often returns 0 on the first frame).
    Timer {
        id: tabletInsetRefresh
        interval: 100
        repeat: true
        onTriggered: {
            platform.refreshSystemInsets()
            if (tabletNavInset > 0 || ++tries >= 50)
                stop()
        }
        property int tries: 0
    }

    // Master page registry. `stack` must match the StackLayout child order.
    readonly property var pageInfo: ({
        "nav":    { title: qsTr("Nav"),       glyph: Icons.nav,       kind: "run",   stack: 0 },
        "data":   { title: qsTr("Data"),      glyph: Icons.data,      kind: "run",   stack: 1 },
        "work":   { title: qsTr("Work"),      glyph: Icons.work,      kind: "run",   stack: 2 },
        "setup":  { title: qsTr("Setup"),     glyph: Icons.setup,     kind: "hub",   stack: 3 },
        "farm":   { title: qsTr("Farm Setup"),glyph: Icons.farm,      kind: "setup", stack: 4, back: "paddock" },
        "impl":   { title: qsTr("Implement"), glyph: Icons.implement, kind: "setup", stack: 5, back: "setup" },
        "layout": { title: qsTr("Layout"),    glyph: Icons.layout,    kind: "setup", stack: 6, back: "setup" },
        "conn":   { title: qsTr("GPS"),       glyph: Icons.gps,       kind: "setup", stack: 7, back: "setup" },
        "gpsinfo":{ title: qsTr("GPS Information"), glyph: Icons.satellite, kind: "setup", stack: 8, back: "setup" },
        "paddock":{ title: qsTr("Paddock Setup"), glyph: Icons.farm,  kind: "setup", stack: 9, back: "setup" },
        "ablines":{ title: qsTr("Run Lines"), glyph: Icons.track,     kind: "setup", stack: 10, back: "paddock" },
        "catalog":{ title: qsTr("Products & Mixes"), glyph: Icons.work, kind: "setup", stack: 11, back: "setup" }
    })

    function go(id) { currentPageId = id; }
    function pageTitle(id) { return pageInfo[id] ? pageInfo[id].title : id; }
    function pageKind(id)  { return pageInfo[id] ? pageInfo[id].kind  : "run"; }
    function pageBack(id)  { return (pageInfo[id] && pageInfo[id].back) ? pageInfo[id].back : "setup"; }

    // Run pages (in the pager) = active pages from the layout manager.
    function runPages() {
        var out = [];
        var a = layout.activePages;
        for (var i = 0; i < a.length; ++i) {
            var inf = pageInfo[a[i]];
            if (inf) out.push({ id: a[i], title: inf.title, glyph: inf.glyph });
        }
        return out;
    }

    // ---- Persistent bottom banner (same on every page) ----
    property var bottomKeys: [
        { id: "home",    label: qsTr("Home"),  glyph: Icons.home },
        { id: "record",  label: app.recordingCoverage ? qsTr("Stop") : qsTr("Record"),
          glyph: app.recordingCoverage ? Icons.stop : Icons.record, active: app.recordingCoverage },
        { id: "section", label: qsTr("Section"), glyph: Icons.section, active: app.sectionControl },
        { id: "abselect", label: qsTr("Run Line"), glyph: Icons.track },
        { id: "setup",   label: qsTr("Setup"),   glyph: Icons.setup,
          active: shell.pageKind(shell.currentPageId) !== "run" }
    ]

    function bottomAction(keyId) {
        switch (keyId) {
        case "home":    go("nav"); break;
        case "record":  app.toggleRecording(); break;
        case "section": app.toggleSectionControl(); break;
        case "abselect": runLinePopup.open(); break;
        case "setup":   go("setup"); break;
        }
    }

    RunLinePopup { id: runLinePopup }

    // Day-start Resume popup: shown on launch and re-openable from the Work page.
    // Resuming/opening a job activates its field; jump to the map to see it.
    ResumeJobPopup { id: resumePopup; onOpened: shell.go("nav") }
    function openResume() { resumePopup.openFresh(); }

    // Launch the Resume popup once the shell is up (slight delay so the map +
    // stores finish constructing before a resume activates a field).
    Timer {
        id: bootResume
        interval: 500; repeat: false; running: !shell.isPhone
        onTriggered: resumePopup.openFresh()
    }

    header: TopBanner {
        visible: !shell.isPhone
        runPages: shell.runPages()
        currentId: shell.currentPageId
        onPageSelected: shell.go(id)
    }

    PhoneShell {
        anchors.fill: parent
        visible: shell.isPhone
        z: 10
        buildId: shell.phoneBuildId
    }

    RowLayout {
        visible: !shell.isPhone
        anchors.fill: parent
        spacing: 0

        InfoColumn {
            visible: layout.leftVisible
            Layout.fillHeight: true
            Layout.preferredWidth: 196
            elements: layout.leftElements
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Sub-page header (back to Setup) for setup pages only.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                visible: shell.pageKind(shell.currentPageId) === "setup"
                color: Style.banner
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        width: 96; height: 34; radius: 8
                        color: backMa.pressed ? Style.bannerHi : "transparent"
                        border.color: Style.accent; border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            anchors.centerIn: parent; spacing: 6
                            MdiIcon { icon: Icons.chevronLeft; color: Style.accent; font.pixelSize: 22
                                   anchors.verticalCenter: parent.verticalCenter }
                            Text { text: shell.pageTitle(shell.pageBack(shell.currentPageId))
                                   color: Style.white; font.pixelSize: 14
                                   anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: backMa; anchors.fill: parent
                                    onClicked: shell.go(shell.pageBack(shell.currentPageId)) }
                    }
                    Text {
                        text: shell.pageTitle(shell.currentPageId)
                        color: Style.white; font.pixelSize: 16; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: shell.pageInfo[shell.currentPageId].stack

                NavigationPage { }
                DataPage { }
                WorkSetupPage { onOpenJobsRequested: shell.openResume() }
                SetupPage { buildId: shell.tabletBuildId; onNavigate: shell.go(id) }
                FarmSetupPage { }
                ImplementPage { }
                LayoutManagerPage {
                    runTitles: ({
                        "nav":  shell.pageInfo["nav"].title,
                        "data": shell.pageInfo["data"].title,
                        "work": shell.pageInfo["work"].title
                    })
                }
                ConnectionPage { }
                GpsInfoPage { }
                PaddockSetupPage { onNavigate: shell.go(id) }
                AbLinesPage { }
                CatalogManagerPage { }
            }
        }

        InfoColumn {
            visible: layout.rightVisible
            Layout.fillHeight: true
            Layout.preferredWidth: 196
            elements: layout.rightElements
        }
    }

    // Lift soft keys above the on-screen Android nav bar (software buttons).
    footer: Item {
        visible: !shell.isPhone
        implicitHeight: tabletBottomBar.implicitHeight + tabletNavInset

        BottomBar {
            id: tabletBottomBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            keys: shell.bottomKeys
            onKeyActivated: shell.bottomAction(keyId)
        }

        Rectangle {
            visible: tabletNavInset > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabletBottomBar.bottom
            height: tabletNavInset
            color: Style.banner
        }
    }
}
