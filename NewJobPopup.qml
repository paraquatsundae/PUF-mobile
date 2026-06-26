import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// New Job flow (PLAN §1/§B): Farm -> Field -> Product / Tank-mix selection, with a
// flat rate OR an Rx prescription. On create, sets the field active, sets the
// application context, starts a fresh job and saves it open. Reuses the dark-theme
// ListPicker / NumberPad / RxImportPopup, and builds the same `application` map the
// Work page uses so resume/restore is identical.
Popup {
    id: root
    modal: true; dim: true; padding: 16
    closePolicy: Popup.CloseOnEscape
    parent: Overlay.overlay
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    width: Math.min((parent ? parent.width : 520) - 24, 520)
    height: Math.min((parent ? parent.height : 640) - 24, 640)

    signal created()

    // ---- field selection ----
    property string selClientId: ""
    property string selClientName: ""
    property string selFarmId: ""
    property string selFarmName: ""
    property string selFieldId: ""
    property string selFieldName: ""

    // ---- application ----
    property string appMode: "single"      // single | mix
    property string selCrop: (catalog.crops.length ? catalog.crops[0] : "")
    property string selProductType: ""
    property string selProduct: ""
    property string rateMode: "flat"        // flat | rx
    property real rateVal: 0
    property string rateUnit: "L"
    property var selMix: null
    property var rxDesc: null
    property string statusMsg: ""

    // ---- tank-mix builder (create + NAME a new mix from the New Job flow) ----
    property string mixName: ""
    property real mixRate: 0
    property string mixUnit: "L"
    property string mixCarrier: "Water"
    property var mixProducts: []            // [{name, rate, unit}]
    property string mixPendingProduct: ""

    function openFresh() {
        // Seed from the current browse/active selection so the common case is 1 tap.
        selClientId = farm.activeClientId.length ? farm.activeClientId : farm.browseClientId;
        selFarmId = farm.activeFarmId.length ? farm.activeFarmId : farm.browseFarmId;
        selFieldId = farm.hasActiveField ? farm.activeFieldId : "";
        selClientName = farm.activeClientName; selFarmName = farm.activeFarmName;
        selFieldName = farm.hasActiveField ? farm.activeFieldName : "";
        appMode = "single"; selProductType = ""; selProduct = "";
        rateMode = "flat"; rateVal = 0; rateUnit = "L"; selMix = null; rxDesc = null;
        selCrop = catalog.crops.length ? catalog.crops[0] : "";
        statusMsg = "";
        open();
    }

    function _nameToId(list, name) {
        for (var i = 0; i < list.length; ++i)
            if (list[i].name === name) return list[i].id;
        return "";
    }
    function mixNames() {
        var out = [];
        for (var i = 0; i < catalog.tankMixes.length; ++i) out.push(catalog.tankMixes[i].name);
        return out;
    }
    function findMix(name) {
        for (var i = 0; i < catalog.tankMixes.length; ++i)
            if (catalog.tankMixes[i].name === name) return catalog.tankMixes[i];
        return null;
    }
    function allProductNames() {
        var out = [];
        for (var i = 0; i < catalog.products.length; ++i) out.push(catalog.products[i].name);
        return out;
    }
    function openMixBuilder() {
        mixName = ""; mixRate = 0; mixUnit = "L"; mixCarrier = "Water"; mixProducts = [];
        mixBuilder.open();
    }
    function rateText() {
        if (rateMode === "rx")
            return rxDesc ? (qsTr("Rx: ") + (rxDesc.column || "") + " (" + (rxDesc.unit || "") + ")")
                          : qsTr("Pick prescription\u2026");
        return (rateVal > 0 ? rateVal : "0") + " " + rateUnit + qsTr(" /ha");
    }

    function buildApplication() {
        var ts = new Date().toISOString();
        var a;
        if (appMode === "single") {
            a = { kind: "single", name: selProduct, crop: selCrop, timestamp: ts,
                  tankSizeL: app.tankSizeL,
                  product: { name: selProduct, type: selProductType, rate: rateVal, unit: rateUnit } };
        } else {
            a = { kind: "mix", name: selMix ? selMix.name : "", crop: selCrop, timestamp: ts,
                  tankSizeL: app.tankSizeL,
                  mix: selMix ? { name: selMix.name, rateHa: selMix.rateHa, unit: selMix.unit,
                                  carrier: selMix.carrier, products: selMix.products } : {} };
        }
        a.rateMode = rateMode;
        if (rateMode === "rx" && rxDesc)
            a.rx = rxDesc;
        return a;
    }

    function canCreate() {
        if (!selFieldId.length) return false;
        if (appMode === "single" && !selProduct.length) return false;
        if (appMode === "mix" && !selMix) return false;
        if (rateMode === "rx" && !rxDesc) return false;
        return true;
    }

    function createJob() {
        if (!canCreate()) { statusMsg = qsTr("Complete field, product and rate first."); return; }
        farm.setActiveField(selClientId, selFarmId, selFieldId);
        if (rateMode === "rx" && rxDesc)
            rx.loadFromDescriptor(rxDesc);
        else
            rx.clear();
        // Fresh job: clear any existing current-job pointer + coverage for the field.
        jobs.requestNew();
        app.setApplication(buildApplication());
        // FieldView.saveActiveJob() persists metadata.json (incl. application) +
        // coverage.geojson and sets this the active/open job.
        jobs.requestSave();
        root.created();
        root.close();
    }

    background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12 }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Start New Job"); color: Style.accent
                        font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                Button { text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                         implicitWidth: 44; implicitHeight: 44; onClicked: root.close() }
            }

            // ---- 1. Field ----
            Label { text: qsTr("1. Field"); color: Style.textDim; font.pixelSize: 14 }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: qsTr("Client"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                Button { Layout.fillWidth: true
                         text: root.selClientName.length ? root.selClientName : qsTr("Select client\u2026")
                         onClicked: { clientPicker.model = farm.clients.map(function(c){return c.name;}); clientPicker.open(); } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: qsTr("Farm"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                Button { Layout.fillWidth: true; enabled: root.selClientId.length > 0
                         text: root.selFarmName.length ? root.selFarmName : qsTr("Select farm\u2026")
                         onClicked: { farm.browseClientId = root.selClientId;
                                      farmPicker.model = farm.farms.map(function(f){return f.name;}); farmPicker.open(); } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: qsTr("Field"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                Button { Layout.fillWidth: true; enabled: root.selFarmId.length > 0
                         text: root.selFieldName.length ? root.selFieldName : qsTr("Select field\u2026")
                         onClicked: { farm.browseClientId = root.selClientId; farm.browseFarmId = root.selFarmId;
                                      fieldPicker.model = farm.fields.map(function(f){return f.name;}); fieldPicker.open(); } }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

            // ---- 2. Application ----
            Label { text: qsTr("2. Application"); color: Style.textDim; font.pixelSize: 14 }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: qsTr("Crop"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                Button { Layout.fillWidth: true
                         text: root.selCrop.length ? root.selCrop : qsTr("Select crop\u2026")
                         onClicked: cropPicker.open() }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Repeater {
                    model: [ { id: "single", label: qsTr("Single Product") }, { id: "mix", label: qsTr("Tank Mix") } ]
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 46; radius: 8
                        color: root.appMode === modelData.id ? Style.accent : Style.bannerHi
                        border.color: Style.panelEdge; border.width: 1
                        Text { anchors.centerIn: parent; text: modelData.label
                               color: root.appMode === modelData.id ? Style.banner : Style.white
                               font.pixelSize: 15; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.appMode = modelData.id }
                    }
                }
            }
            // single-product
            ColumnLayout {
                Layout.fillWidth: true; spacing: 10; visible: root.appMode === "single"
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Label { text: qsTr("Type"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                    Button { Layout.fillWidth: true
                             text: root.selProductType.length ? root.selProductType : qsTr("Product type\u2026")
                             onClicked: typePicker.open() }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Label { text: qsTr("Product"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                    Button { Layout.fillWidth: true; enabled: root.selProductType.length > 0
                             text: root.selProduct.length ? root.selProduct : qsTr("Select product\u2026")
                             onClicked: { productPicker.model = catalog.productsForType(root.selProductType); productPicker.open(); } }
                }
            }
            // tank-mix
            ColumnLayout {
                Layout.fillWidth: true; spacing: 10; visible: root.appMode === "mix"
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Label { text: qsTr("Mix"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 90 }
                    Button { Layout.fillWidth: true
                             text: root.selMix ? root.selMix.name : qsTr("Select tank mix\u2026")
                             onClicked: { mixPicker.model = root.mixNames(); mixPicker.open(); } }
                }
                // Build + NAME a new mix here (workshop spec): products + carrier,
                // then a Name, saved to the tank-mix catalog and selected as the job.
                Button {
                    Layout.fillWidth: true
                    text: qsTr("New tank mix\u2026")
                    onClicked: root.openMixBuilder()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Style.panelEdge }

            // ---- 3. Rate (flat or Rx) ----
            Label { text: qsTr("3. Rate"); color: Style.textDim; font.pixelSize: 14 }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Repeater {
                    model: [ { id: "flat", label: qsTr("Flat rate") }, { id: "rx", label: qsTr("Prescription (Rx)") } ]
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 46; radius: 8
                        color: root.rateMode === modelData.id ? Style.accent : Style.bannerHi
                        border.color: Style.panelEdge; border.width: 1
                        Text { anchors.centerIn: parent; text: modelData.label
                               color: root.rateMode === modelData.id ? Style.banner : Style.white
                               font.pixelSize: 15; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.rateMode = modelData.id }
                    }
                }
            }
            Button {
                Layout.fillWidth: true
                text: root.rateText()
                onClicked: {
                    if (root.rateMode === "rx") rxImport.openFresh();
                    else ratePad.openWith(root.rateVal, root.rateUnit);
                }
            }

            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                visible: root.statusMsg.length > 0
                color: "#e0a13c"; font.pixelSize: 13; text: root.statusMsg
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                visible: root.selFieldId.length > 0 && !gps.hasOrigin
                color: Style.textDim; font.pixelSize: 12
                text: qsTr("Waiting for a GPS origin (field boundary or first fix) before the job can be saved.")
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: root.close() }
                Button {
                    text: qsTr("Create job")
                    enabled: root.canCreate() && gps.hasOrigin
                    onClicked: root.createJob()
                }
            }
        }
    }

    // ---- pickers ----
    ListPicker { id: clientPicker; title: qsTr("Client"); allowAdd: false
        onSelected: { root.selClientName = value; root.selClientId = root._nameToId(farm.clients, value);
                      root.selFarmId = ""; root.selFarmName = ""; root.selFieldId = ""; root.selFieldName = ""; } }
    ListPicker { id: farmPicker; title: qsTr("Farm"); allowAdd: false
        onSelected: { root.selFarmName = value; root.selFarmId = root._nameToId(farm.farms, value);
                      root.selFieldId = ""; root.selFieldName = ""; } }
    ListPicker { id: fieldPicker; title: qsTr("Field"); allowAdd: false
        onSelected: { root.selFieldName = value; root.selFieldId = root._nameToId(farm.fields, value); } }

    ListPicker { id: cropPicker; title: qsTr("Crop"); model: catalog.crops; addPlaceholder: qsTr("New crop")
        onSelected: root.selCrop = value
        onAddRequested: { catalog.addCrop(text); root.selCrop = text; } }
    ListPicker { id: typePicker; title: qsTr("Product type"); model: catalog.productTypes; addPlaceholder: qsTr("New product type")
        onSelected: { root.selProductType = value; root.selProduct = ""; }
        onAddRequested: { catalog.addProductType(text); root.selProductType = text; root.selProduct = ""; } }
    ListPicker { id: productPicker; title: qsTr("Product"); model: []; addPlaceholder: qsTr("New product")
        onSelected: root.selProduct = value
        onAddRequested: { catalog.addProduct(text, root.selProductType); root.selProduct = text;
                          model = catalog.productsForType(root.selProductType); } }
    ListPicker { id: mixPicker; title: qsTr("Tank mix"); model: []; allowAdd: false
        onSelected: root.selMix = root.findMix(value) }

    NumberPad { id: ratePad; title: qsTr("Rate per hectare")
        onAccepted: { root.rateVal = value; root.rateUnit = unit; } }

    RxImportPopup { id: rxImport
        onAccepted: { root.rxDesc = descriptor; root.rateMode = "rx"; } }

    NumberPad { id: mixRatePad; title: qsTr("Tank mix rate per hectare")
        onAccepted: { root.mixRate = value; root.mixUnit = unit; } }
    NumberPad { id: compPad; title: qsTr("Product rate per hectare")
        onAccepted: { var arr = root.mixProducts.slice();
                      arr.push({ name: root.mixPendingProduct, rate: value, unit: unit });
                      root.mixProducts = arr; } }
    ListPicker { id: compPicker; title: qsTr("Add product to mix"); model: []
        addPlaceholder: qsTr("New product")
        onSelected: { root.mixPendingProduct = value; compPad.openWith(0, "L"); }
        onAddRequested: { catalog.addProduct(text, "Other"); root.mixPendingProduct = text;
                          compPad.openWith(0, "L"); } }

    // ---- Tank-mix builder: products + carrier + NAME -> WorkCatalog ----------
    Popup {
        id: mixBuilder
        modal: true; dim: true; padding: 16
        closePolicy: Popup.CloseOnEscape
        parent: Overlay.overlay
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        width: Math.min((parent ? parent.width : 460) - 24, 460)
        height: Math.min((parent ? parent.height : 620) - 24, 620)
        background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12 }

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
                    Button { text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                             implicitWidth: 44; implicitHeight: 44; onClicked: mixBuilder.close() }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: qsTr("Rate/ha"); color: Style.textDim; font.pixelSize: 15
                            Layout.preferredWidth: 96 }
                    Button { Layout.fillWidth: true
                             text: (root.mixRate > 0 ? root.mixRate : "0") + " " + root.mixUnit + qsTr(" /ha")
                             onClicked: mixRatePad.openWith(root.mixRate, root.mixUnit) }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: qsTr("Carrier"); color: Style.textDim; font.pixelSize: 15
                            Layout.preferredWidth: 96 }
                    TextField {
                        id: carrierField
                        Layout.fillWidth: true
                        text: root.mixCarrier
                        placeholderText: qsTr("e.g. Water")
                        color: Style.white
                        placeholderTextColor: Style.textDim
                        selectByMouse: true
                        background: Rectangle { color: Style.bannerHi
                            border.color: carrierField.activeFocus ? Style.accent : Style.panelEdge
                            border.width: 1; radius: 6 }
                        onTextChanged: root.mixCarrier = text
                    }
                }

                Label { text: qsTr("Products"); color: Style.textDim; font.pixelSize: 14 }
                Repeater {
                    model: root.mixProducts
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 44; radius: 6
                        color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 8
                            Label { Layout.fillWidth: true; text: modelData.name
                                    color: Style.white; font.pixelSize: 15 }
                            Label { text: modelData.rate + " " + modelData.unit + qsTr("/ha")
                                    color: Style.accent; font.pixelSize: 14 }
                            Button { text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                                     implicitWidth: 40; implicitHeight: 40
                                     onClicked: { var arr = root.mixProducts.slice();
                                                  arr.splice(index, 1); root.mixProducts = arr; } }
                        }
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: qsTr("Add product\u2026")
                    onClicked: { compPicker.model = root.allProductNames(); compPicker.open(); }
                }

                // Name comes after products + carrier (workshop spec): it becomes
                // the application name and the saved tank-mix list entry.
                Label { text: qsTr("Name"); color: Style.textDim; font.pixelSize: 14 }
                TextField {
                    id: mixNameField
                    Layout.fillWidth: true
                    text: root.mixName
                    placeholderText: qsTr("e.g. Knockdown A")
                    color: Style.white
                    placeholderTextColor: Style.textDim
                    selectByMouse: true
                    background: Rectangle { color: Style.bannerHi
                        border.color: mixNameField.activeFocus ? Style.accent : Style.panelEdge
                        border.width: 1; radius: 6 }
                    onTextChanged: root.mixName = text
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Item { Layout.fillWidth: true }
                    Button { text: qsTr("Cancel"); onClicked: mixBuilder.close() }
                    Button {
                        text: qsTr("Save mix")
                        enabled: root.mixName.trim().length > 0
                        onClicked: {
                            var mix = { name: root.mixName.trim(), rateHa: root.mixRate,
                                        unit: root.mixUnit, carrier: root.mixCarrier,
                                        products: root.mixProducts };
                            catalog.addTankMix(mix);
                            root.selMix = root.findMix(mix.name);
                            mixBuilder.close();
                        }
                    }
                }
            }
        }
    }
}
