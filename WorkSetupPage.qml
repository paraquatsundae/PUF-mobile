import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Work / job setup: choose the application (single product or tank mix) + crop,
// record it into the active field's job, show coverage totals + paddock history.
Flickable {
    id: page
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Open the day-start Resume / Jobs popup (owned by the shell).
    signal openJobsRequested()

    // Re-computed whenever a job is saved/cleared or the active field changes.
    property bool hasSavedJob: farm.hasActiveField && jobs.hasJob(farm.activeFieldId)
    property var savedMeta: (hasSavedJob ? jobs.jobMeta(farm.activeFieldId) : ({}))
    property var jobList: []
    function refreshJob() {
        hasSavedJob = farm.hasActiveField && jobs.hasJob(farm.activeFieldId);
        savedMeta = hasSavedJob ? jobs.jobMeta(farm.activeFieldId) : ({});
        jobList = farm.hasActiveField ? jobs.listJobs(farm.activeFieldId) : [];
        // Reflect the loaded job's rate type so editing stays in sync after a resume.
        if (savedMeta && savedMeta.application) {
            page.rateMode = savedMeta.application.rateMode ? savedMeta.application.rateMode : "flat";
            page.rxDesc = savedMeta.application.rx ? savedMeta.application.rx : null;
        }
    }
    Connections { target: jobs; function onChanged() { page.refreshJob(); } }
    Connections { target: farm; function onActiveChanged() { page.refreshJob(); } }
    Component.onCompleted: page.refreshJob()

    // --- Application state -------------------------------------------------
    property string appMode: "single"        // single | mix
    property string selProductType: ""
    property string selProduct: ""
    property real rateVal: 0
    property string rateUnit: "L"
    property string rateMode: "flat"          // flat | rx
    property var rxDesc: null
    property string selCrop: (catalog.crops.length ? catalog.crops[0] : "")
    property var selMix: null
    property string statusMsg: ""
    property string padTarget: ""             // rate | mixRate | comp

    // --- Tank-mix builder state -------------------------------------------
    property string mixName: ""
    property real mixRate: 0
    property string mixUnit: "L"
    property string mixCarrier: "Water"
    property var mixProducts: []              // [{name, rate, unit}]
    property string mixPendingProduct: ""

    function allProductNames() {
        var out = [];
        for (var i = 0; i < catalog.products.length; ++i)
            out.push(catalog.products[i].name);
        return out;
    }
    function findMix(name) {
        for (var i = 0; i < catalog.tankMixes.length; ++i)
            if (catalog.tankMixes[i].name === name)
                return catalog.tankMixes[i];
        return null;
    }
    function mixNames() {
        var out = [];
        for (var i = 0; i < catalog.tankMixes.length; ++i)
            out.push(catalog.tankMixes[i].name);
        return out;
    }
    function jobAppName(m) {
        if (m && m.application && m.application.name) return m.application.name;
        if (m && m.trackName && ("" + m.trackName).length) return m.trackName;
        return qsTr("(no application)");
    }
    function jobAppCrop(m) {
        return (m && m.application && m.application.crop) ? m.application.crop : "";
    }
    function shortDate(iso) {
        if (!iso) return "";
        var s = "" + iso;
        return s.length >= 16 ? s.substring(0, 16).replace("T", " ") : s;
    }

    function saveApplication() {
        var ts = new Date().toISOString();
        var a;
        if (page.appMode === "single") {
            if (!page.selProduct.length) { page.statusMsg = qsTr("Select a product first."); return; }
            a = { kind: "single", name: page.selProduct, crop: page.selCrop,
                  timestamp: ts, tankSizeL: app.tankSizeL,
                  product: { name: page.selProduct, type: page.selProductType,
                             rate: page.rateVal, unit: page.rateUnit } };
        } else {
            if (!page.selMix) { page.statusMsg = qsTr("Select a tank mix first."); return; }
            a = { kind: "mix", name: page.selMix.name, crop: page.selCrop,
                  timestamp: ts, tankSizeL: app.tankSizeL,
                  mix: { name: page.selMix.name, rateHa: page.selMix.rateHa,
                         unit: page.selMix.unit, carrier: page.selMix.carrier,
                         products: page.selMix.products } };
        }
        a.rateMode = page.rateMode;
        if (page.rateMode === "rx") {
            if (!page.rxDesc) { page.statusMsg = qsTr("Choose a prescription map first."); return; }
            a.rx = page.rxDesc;
            rx.loadFromDescriptor(page.rxDesc);   // ready for live lookup
        } else {
            rx.clear();
        }
        app.setApplication(a);
        jobs.requestSave();
        page.statusMsg = qsTr("Saved application: ") + a.name
                         + (page.rateMode === "rx" ? qsTr(" (Rx)") : "");
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Work Setup"); color: Style.accent; font.pixelSize: 20
                    font.bold: true; Layout.fillWidth: true }
            Button {
                text: qsTr("Jobs / Resume\u2026")
                onClicked: page.openJobsRequested()
            }
        }

        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            color: Style.white; font.pixelSize: 15
            text: farm.hasActiveField
                  ? (qsTr("Field: ") + farm.activeFieldName + "  (" + farm.activeAreaHa.toFixed(2) + " ha)")
                  : qsTr("No active field \u2014 set one on the Farm page.")
        }

        // Application setup
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge; border.width: 1
            implicitHeight: appCol.implicitHeight + 28

            ColumnLayout {
                id: appCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label { text: qsTr("Application"); color: Style.textDim; font.pixelSize: 14 }

                // Crop selector
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label { text: qsTr("Crop"); color: Style.textDim; font.pixelSize: 15
                            Layout.preferredWidth: 96 }
                    Button {
                        Layout.fillWidth: true
                        text: page.selCrop.length ? page.selCrop : qsTr("Select crop\u2026")
                        onClicked: cropPicker.open()
                    }
                }

                // Mode toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: [ { id: "single", label: qsTr("Single Product") },
                                 { id: "mix", label: qsTr("Tank Mix") } ]
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 48
                            radius: 8
                            color: page.appMode === modelData.id ? Style.accent : Style.bannerHi
                            border.color: Style.panelEdge; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: page.appMode === modelData.id ? Style.banner : Style.white
                                font.pixelSize: 15; font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { page.appMode = modelData.id; page.statusMsg = ""; }
                            }
                        }
                    }
                }

                // Rate type: flat rate (existing) or an Rx prescription map.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: [ { id: "flat", label: qsTr("Flat rate") },
                                 { id: "rx", label: qsTr("Prescription (Rx)") } ]
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 8
                            color: page.rateMode === modelData.id ? Style.accent : Style.bannerHi
                            border.color: Style.panelEdge; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: page.rateMode === modelData.id ? Style.banner : Style.white
                                font.pixelSize: 14; font.bold: true
                            }
                            MouseArea { anchors.fill: parent
                                        onClicked: { page.rateMode = modelData.id; page.statusMsg = ""; } }
                        }
                    }
                }

                // Rx chooser (shown when the rate is a prescription map).
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: page.rateMode === "rx"
                    Button {
                        Layout.fillWidth: true
                        text: page.rxDesc
                              ? (qsTr("Rx: ") + (page.rxDesc.column || "") + "  (" + (page.rxDesc.unit || "") + ", "
                                 + (page.rxDesc.zoneCount || 0) + qsTr(" zones)"))
                              : qsTr("Choose prescription map\u2026")
                        onClicked: rxImport.openFresh()
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        visible: page.rxDesc !== null
                        color: Style.textDim; font.pixelSize: 12
                        text: page.rxDesc
                              ? (qsTr("Out-of-zone ") + (page.rxDesc.outOfZoneRate || 0)
                                 + qsTr("  \u2022  no-GPS ") + (page.rxDesc.noGpsRate || 0)
                                 + "  \u2022  " + (page.rxDesc.crs || ""))
                              : ""
                    }
                }

                // Single-product path
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: page.appMode === "single" && page.rateMode === "flat"

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label { text: qsTr("Type"); color: Style.textDim; font.pixelSize: 15
                                Layout.preferredWidth: 96 }
                        Button {
                            Layout.fillWidth: true
                            text: page.selProductType.length ? page.selProductType : qsTr("Product type\u2026")
                            onClicked: typePicker.open()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label { text: qsTr("Product"); color: Style.textDim; font.pixelSize: 15
                                Layout.preferredWidth: 96 }
                        Button {
                            Layout.fillWidth: true
                            enabled: page.selProductType.length > 0
                            text: page.selProduct.length ? page.selProduct : qsTr("Select product\u2026")
                            onClicked: {
                                productPicker.model = catalog.productsForType(page.selProductType);
                                productPicker.open();
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label { text: qsTr("Rate/ha"); color: Style.textDim; font.pixelSize: 15
                                Layout.preferredWidth: 96 }
                        Button {
                            Layout.fillWidth: true
                            text: (page.rateVal > 0 ? page.rateVal : "0") + " " + page.rateUnit + qsTr(" /ha")
                            onClicked: { page.padTarget = "rate"; ratePad.openWith(page.rateVal, page.rateUnit); }
                        }
                    }
                }

                // Tank-mix path
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: page.appMode === "mix"

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label { text: qsTr("Mix"); color: Style.textDim; font.pixelSize: 15
                                Layout.preferredWidth: 96 }
                        Button {
                            Layout.fillWidth: true
                            text: page.selMix ? page.selMix.name : qsTr("Select tank mix\u2026")
                            onClicked: { mixPicker.model = page.mixNames(); mixPicker.open(); }
                        }
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        visible: page.selMix !== null
                        color: Style.textDim; font.pixelSize: 13
                        text: page.selMix
                              ? (qsTr("Rate ") + page.selMix.rateHa + " " + page.selMix.unit
                                 + qsTr("/ha \u2022 carrier ") + page.selMix.carrier
                                 + qsTr(" \u2022 ") + (page.selMix.products ? page.selMix.products.length : 0)
                                 + qsTr(" product(s)"))
                              : ""
                    }
                    Button {
                        Layout.fillWidth: true
                        text: qsTr("Add new tank mix\u2026")
                        onClicked: {
                            page.mixName = ""; page.mixRate = 0; page.mixUnit = "L";
                            page.mixCarrier = "Water"; page.mixProducts = [];
                            mixBuilder.open();
                        }
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Save application")
                    enabled: farm.hasActiveField && gps.hasOrigin
                    onClicked: page.saveApplication()
                }

                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    visible: page.statusMsg.length > 0
                    color: Style.accent; font.pixelSize: 13
                    text: page.statusMsg
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    visible: !(farm.hasActiveField && gps.hasOrigin)
                    color: Style.textDim; font.pixelSize: 13
                    text: !farm.hasActiveField
                          ? qsTr("Set an active field to record an application.")
                          : qsTr("Waiting for a GPS origin (active field boundary or first fix) "
                                 + "before the application can be saved with the job.")
                }
            }
        }

        // Coverage summary
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge; border.width: 1
            implicitHeight: covCol.implicitHeight + 28

            ColumnLayout {
                id: covCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label { text: qsTr("Worked area (true, no overlap)")
                        color: Style.textDim; font.pixelSize: 14 }
                Label { text: coverage.areaHa.toFixed(2) + " ha"
                        color: Style.white; font.pixelSize: 40; font.bold: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Switch {
                        checked: app.sectionControl
                        onToggled: app.setSectionControl(checked)
                    }
                    Label { text: qsTr("Section control"); color: Style.white; font.pixelSize: 15 }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: qsTr("Clear coverage")
                        onClicked: coverage.reset()
                    }
                }
            }
        }

        // Job persistence — save / re-enter the worked coverage for this field.
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge; border.width: 1
            implicitHeight: jobCol.implicitHeight + 28

            ColumnLayout {
                id: jobCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Label { text: qsTr("Job"); color: Style.textDim; font.pixelSize: 14 }

                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: Style.white; font.pixelSize: 14
                    text: !farm.hasActiveField
                          ? qsTr("Set an active field to save or resume a job.")
                          : (page.hasSavedJob
                             ? (qsTr("Saved job: ") + (page.savedMeta.areaHa !== undefined
                                    ? page.savedMeta.areaHa.toFixed(2) + " ha" : "")
                                + (page.savedMeta.modifiedUtc ? "  (" + page.savedMeta.modifiedUtc + ")" : ""))
                             : qsTr("No saved job for this field yet."))
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Button {
                        text: qsTr("Save job")
                        enabled: farm.hasActiveField && gps.hasOrigin
                        onClicked: jobs.requestSave()
                    }
                    Button {
                        text: qsTr("Start new job")
                        enabled: farm.hasActiveField && page.hasSavedJob
                        onClicked: jobs.requestNew()
                    }
                    Button {
                        text: qsTr("Complete job")
                        enabled: farm.hasActiveField && page.hasSavedJob
                                 && page.savedMeta.jobId !== undefined
                                 && page.savedMeta.state !== "complete"
                        onClicked: {
                            jobs.requestSave();   // flush latest coverage first
                            jobs.setJobState(farm.activeFieldId, page.savedMeta.jobId, "complete");
                        }
                    }
                }
            }
        }

        // Paddock history (read-only) — every saved job for this field, newest first.
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Style.panel
            border.color: Style.panelEdge; border.width: 1
            implicitHeight: histCol.implicitHeight + 28

            ColumnLayout {
                id: histCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Paddock history"); color: Style.textDim; font.pixelSize: 14
                            Layout.fillWidth: true }
                    Button {
                        text: Icons.center; font.family: Icons.family; font.pixelSize: 18
                        implicitWidth: 40; implicitHeight: 40
                        onClicked: page.refreshJob()
                    }
                }

                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    visible: !page.jobList || page.jobList.length === 0
                    color: Style.textDim; font.pixelSize: 13
                    text: qsTr("No saved jobs for this field yet.")
                }

                Repeater {
                    model: page.jobList
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: histRow.implicitHeight + 16
                        radius: 6
                        color: Style.bannerHi
                        border.color: Style.panelEdge; border.width: 1

                        ColumnLayout {
                            id: histRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 10
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: page.jobAppName(modelData)
                                    color: Style.white; font.pixelSize: 15; font.bold: true
                                    elide: Text.ElideRight
                                }
                                Label {
                                    text: (modelData.areaHa !== undefined
                                           ? Number(modelData.areaHa).toFixed(2) : "0.00") + " ha"
                                    color: Style.accent; font.pixelSize: 14; font.bold: true
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: page.shortDate(modelData.modifiedUtc)
                                      + (page.jobAppCrop(modelData).length
                                         ? ("  \u2022  " + page.jobAppCrop(modelData)) : "")
                                color: Style.textDim; font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Pickers + numpad --------------------------------------------------
    ListPicker {
        id: cropPicker
        title: qsTr("Crop")
        model: catalog.crops
        addPlaceholder: qsTr("New crop")
        onSelected: page.selCrop = value
        onAddRequested: { catalog.addCrop(text); page.selCrop = text; }
    }
    ListPicker {
        id: typePicker
        title: qsTr("Product type")
        model: catalog.productTypes
        addPlaceholder: qsTr("New product type")
        onSelected: { page.selProductType = value; page.selProduct = ""; }
        onAddRequested: { catalog.addProductType(text); page.selProductType = text; page.selProduct = ""; }
    }
    ListPicker {
        id: productPicker
        title: qsTr("Product")
        model: []
        addPlaceholder: qsTr("New product")
        onSelected: page.selProduct = value
        onAddRequested: {
            catalog.addProduct(text, page.selProductType);
            page.selProduct = text;
            model = catalog.productsForType(page.selProductType);
        }
    }
    ListPicker {
        id: mixPicker
        title: qsTr("Tank mix")
        model: []
        allowAdd: false
        onSelected: page.selMix = page.findMix(value)
    }
    ListPicker {
        id: compPicker
        title: qsTr("Add product to mix")
        model: []
        addPlaceholder: qsTr("New product")
        onSelected: { page.mixPendingProduct = value; page.padTarget = "comp"; compPad.openWith(0, "L"); }
        onAddRequested: {
            catalog.addProduct(text, "Other");
            page.mixPendingProduct = text;
            page.padTarget = "comp";
            compPad.openWith(0, "L");
        }
    }

    NumberPad {
        id: ratePad
        title: qsTr("Rate per hectare")
        onAccepted: { page.rateVal = value; page.rateUnit = unit; }
    }

    RxImportPopup {
        id: rxImport
        onAccepted: { page.rxDesc = descriptor; page.rateMode = "rx"; }
    }
    NumberPad {
        id: mixRatePad
        title: qsTr("Tank mix rate per hectare")
        onAccepted: { page.mixRate = value; page.mixUnit = unit; }
    }
    NumberPad {
        id: compPad
        title: qsTr("Product rate per hectare")
        onAccepted: {
            var arr = page.mixProducts.slice();
            arr.push({ name: page.mixPendingProduct, rate: value, unit: unit });
            page.mixProducts = arr;
        }
    }

    // --- Tank-mix builder --------------------------------------------------
    Popup {
        id: mixBuilder
        modal: true; dim: true; padding: 16
        closePolicy: Popup.CloseOnEscape
        parent: Overlay.overlay
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        width: Math.min(page.width - 24, 460)
        height: Math.min(page.height - 24, 620)

        background: Rectangle {
            color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12
        }

        contentItem: Flickable {
            contentWidth: width
            contentHeight: mb.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: mb
                width: parent.width
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("New tank mix"); color: Style.accent
                            font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                    Button {
                        text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                        implicitWidth: 44; implicitHeight: 44
                        onClicked: mixBuilder.close()
                    }
                }

                Label { text: qsTr("Name"); color: Style.textDim; font.pixelSize: 14 }
                TextField {
                    id: mixNameField
                    Layout.fillWidth: true
                    text: page.mixName
                    placeholderText: qsTr("e.g. Knockdown A")
                    color: Style.white
                    placeholderTextColor: Style.textDim
                    selectByMouse: true
                    background: Rectangle {
                        color: Style.bannerHi
                        border.color: mixNameField.activeFocus ? Style.accent : Style.panelEdge
                        border.width: 1
                        radius: 6
                    }
                    onTextChanged: page.mixName = text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label { text: qsTr("Rate/ha"); color: Style.textDim; font.pixelSize: 15
                            Layout.preferredWidth: 96 }
                    Button {
                        Layout.fillWidth: true
                        text: (page.mixRate > 0 ? page.mixRate : "0") + " " + page.mixUnit + qsTr(" /ha")
                        onClicked: mixRatePad.openWith(page.mixRate, page.mixUnit)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label { text: qsTr("Carrier"); color: Style.textDim; font.pixelSize: 15
                            Layout.preferredWidth: 96 }
                    TextField {
                        id: carrierField
                        Layout.fillWidth: true
                        text: page.mixCarrier
                        placeholderText: qsTr("e.g. Water")
                        color: Style.white
                        placeholderTextColor: Style.textDim
                        selectByMouse: true
                        background: Rectangle {
                            color: Style.bannerHi
                            border.color: carrierField.activeFocus ? Style.accent : Style.panelEdge
                            border.width: 1
                            radius: 6
                        }
                        onTextChanged: page.mixCarrier = text
                    }
                }

                Label { text: qsTr("Products"); color: Style.textDim; font.pixelSize: 14 }
                Repeater {
                    model: page.mixProducts
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 6
                        color: Style.bannerHi
                        border.color: Style.panelEdge; border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 8
                            Label { Layout.fillWidth: true; text: modelData.name
                                    color: Style.white; font.pixelSize: 15 }
                            Label { text: modelData.rate + " " + modelData.unit + qsTr("/ha")
                                    color: Style.accent; font.pixelSize: 14 }
                            Button {
                                text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                                implicitWidth: 40; implicitHeight: 40
                                onClicked: {
                                    var arr = page.mixProducts.slice();
                                    arr.splice(index, 1);
                                    page.mixProducts = arr;
                                }
                            }
                        }
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: qsTr("Add product\u2026")
                    onClicked: { compPicker.model = page.allProductNames(); compPicker.open(); }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    Button { text: qsTr("Cancel"); onClicked: mixBuilder.close() }
                    Button {
                        text: qsTr("Save mix")
                        enabled: page.mixName.trim().length > 0
                        onClicked: {
                            var mix = { name: page.mixName.trim(), rateHa: page.mixRate,
                                        unit: page.mixUnit, carrier: page.mixCarrier,
                                        products: page.mixProducts };
                            catalog.addTankMix(mix);
                            page.selMix = page.findMix(mix.name);
                            mixBuilder.close();
                        }
                    }
                }
            }
        }
    }
}
