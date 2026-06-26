import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Catalog Manager (Setup hub): view + edit + delete the master work catalogs
// (tank mixes, products, crops, product types), all backed by WorkCatalog. The
// shell draws the back-to-Setup header; this page is just the content. Dark theme,
// reusing ListPicker / NumberPad for the editors.
Item {
    id: page

    property string tab: "mixes"        // mixes | products | crops | types

    // ---- product editor state ----
    property string peOrigName: ""
    property string peOrigType: ""
    property string peName: ""
    property string peType: ""

    // ---- mix editor state ----
    property string meOrig: ""
    property string meName: ""
    property real meRate: 0
    property string meUnit: "L"
    property string meCarrier: "Water"
    property var meProducts: []
    property string mePending: ""

    // ---- text editor (crop/type add + crop rename) ----
    property string teMode: ""          // addCrop | renameCrop | addType
    property string teOrig: ""

    // ---- delete confirm ----
    property string cdAction: ""        // deleteMix | deleteProduct | deleteCrop | deleteType
    property string cdA: ""
    property string cdB: ""
    property string cdLabel: ""

    function allProductNames() {
        var out = [];
        for (var i = 0; i < catalog.products.length; ++i) out.push(catalog.products[i].name);
        return out;
    }

    function openProductEditor(p) {
        peOrigName = p ? p.name : "";
        peOrigType = p ? p.type : "";
        peName = p ? p.name : "";
        peType = p ? p.type : (catalog.productTypes.length ? catalog.productTypes[0] : "");
        productEditor.open();
    }
    function openMixEditor(m) {
        meOrig = m ? m.name : "";
        meName = m ? m.name : "";
        meRate = m ? (m.rateHa ? m.rateHa : 0) : 0;
        meUnit = m && m.unit ? m.unit : "L";
        meCarrier = m && m.carrier ? m.carrier : "Water";
        meProducts = m && m.products ? m.products.slice() : [];
        mixEditor.open();
    }
    function openTextEditor(mode, orig) {
        teMode = mode; teOrig = orig ? orig : "";
        textEditor.open();
    }
    function askDelete(action, a, b, label) {
        cdAction = action; cdA = a; cdB = b ? b : ""; cdLabel = label;
        confirmDelete.open();
    }
    function doDelete() {
        if (cdAction === "deleteMix") catalog.deleteTankMix(cdA);
        else if (cdAction === "deleteProduct") catalog.deleteProduct(cdA, cdB);
        else if (cdAction === "deleteCrop") catalog.deleteCrop(cdA);
        else if (cdAction === "deleteType") catalog.deleteProductType(cdA);
        cdAction = "";
    }

    function addText() {
        if (tab === "crops") openTextEditor("addCrop", "");
        else if (tab === "types") openTextEditor("addType", "");
        else if (tab === "products") openProductEditor(null);
        else openMixEditor(null);
    }
    function addLabel() {
        if (tab === "crops") return qsTr("Add crop\u2026");
        if (tab === "types") return qsTr("Add type\u2026");
        if (tab === "products") return qsTr("Add product\u2026");
        return qsTr("Add tank mix\u2026");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Products & Mixes"); color: Style.accent
                    font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
            Button { text: page.addLabel(); onClicked: page.addText() }
        }

        // Category selector.
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: [ { id: "mixes", label: qsTr("Tank Mixes") },
                         { id: "products", label: qsTr("Products") },
                         { id: "crops", label: qsTr("Crops") },
                         { id: "types", label: qsTr("Types") } ]
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 44; radius: 8
                    color: page.tab === modelData.id ? Style.accent : Style.bannerHi
                    border.color: Style.panelEdge; border.width: 1
                    Text { anchors.centerIn: parent; text: modelData.label
                           color: page.tab === modelData.id ? Style.banner : Style.white
                           font.pixelSize: 14; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: page.tab = modelData.id }
                }
            }
        }

        // ---- Tank mixes ----
        ListView {
            visible: page.tab === "mixes"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 6; model: catalog.tankMixes
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Rectangle {
                width: ListView.view.width
                implicitHeight: 60; radius: 8
                color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 6; spacing: 6
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { text: modelData.name ? modelData.name : qsTr("(unnamed)")
                                color: Style.white; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                        Label {
                            color: Style.textDim; font.pixelSize: 12; elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: ((modelData.rateHa > 0 ? modelData.rateHa + " " + (modelData.unit ? modelData.unit : "") + "/ha" : qsTr("no rate"))
                                   + "  \u2022  " + (modelData.carrier ? modelData.carrier : qsTr("no carrier"))
                                   + "  \u2022  " + ((modelData.products ? modelData.products.length : 0) + qsTr(" products")))
                        }
                    }
                    Button { text: Icons.pencil; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             onClicked: page.openMixEditor(modelData) }
                    Button { text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             contentItem: Text { text: parent.text; font: parent.font; color: "#e05a5a"
                                                 horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                             background: Rectangle { color: "transparent" }
                             onClicked: page.askDelete("deleteMix", modelData.name, "", modelData.name) }
                }
            }
        }

        // ---- Products ----
        ListView {
            visible: page.tab === "products"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 6; model: catalog.products
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Rectangle {
                width: ListView.view.width
                implicitHeight: 56; radius: 8
                color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 6; spacing: 6
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { text: modelData.name; color: Style.white; font.pixelSize: 16
                                font.bold: true; elide: Text.ElideRight }
                        Label { text: modelData.type ? modelData.type : ""
                                color: Style.accent; font.pixelSize: 12 }
                    }
                    Button { text: Icons.pencil; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             onClicked: page.openProductEditor(modelData) }
                    Button { text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             contentItem: Text { text: parent.text; font: parent.font; color: "#e05a5a"
                                                 horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                             background: Rectangle { color: "transparent" }
                             onClicked: page.askDelete("deleteProduct", modelData.name, modelData.type, modelData.name) }
                }
            }
        }

        // ---- Crops ----
        ListView {
            visible: page.tab === "crops"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 6; model: catalog.crops
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Rectangle {
                width: ListView.view.width
                implicitHeight: 52; radius: 8
                color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 6; spacing: 6
                    Label { Layout.fillWidth: true; text: modelData; color: Style.white
                            font.pixelSize: 16; elide: Text.ElideRight }
                    Button { text: Icons.pencil; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             onClicked: page.openTextEditor("renameCrop", modelData) }
                    Button { text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             contentItem: Text { text: parent.text; font: parent.font; color: "#e05a5a"
                                                 horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                             background: Rectangle { color: "transparent" }
                             onClicked: page.askDelete("deleteCrop", modelData, "", modelData) }
                }
            }
        }

        // ---- Product types ----
        ListView {
            visible: page.tab === "types"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 6; model: catalog.productTypes
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Rectangle {
                width: ListView.view.width
                implicitHeight: 52; radius: 8
                color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 6; spacing: 6
                    Label { Layout.fillWidth: true; text: modelData; color: Style.white
                            font.pixelSize: 16; elide: Text.ElideRight }
                    Button { text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                             implicitWidth: 42; implicitHeight: 42
                             contentItem: Text { text: parent.text; font: parent.font; color: "#e05a5a"
                                                 horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                             background: Rectangle { color: "transparent" }
                             onClicked: page.askDelete("deleteType", modelData, "", modelData) }
                }
            }
        }
    }

    // ---- Product editor (name + type) ----
    Popup {
        id: productEditor
        modal: true; dim: true; padding: 16
        closePolicy: Popup.CloseOnEscape
        parent: Overlay.overlay
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        width: Math.min((parent ? parent.width : 420) - 24, 420)
        background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12 }
        contentItem: ColumnLayout {
            spacing: 12
            Label { text: page.peOrigName.length ? qsTr("Edit product") : qsTr("New product")
                    color: Style.accent; font.pixelSize: 18; font.bold: true }
            Label { text: qsTr("Name"); color: Style.textDim; font.pixelSize: 14 }
            TextField {
                id: peNameField
                Layout.fillWidth: true; text: page.peName
                placeholderText: qsTr("Product name")
                color: Style.white; placeholderTextColor: Style.textDim; selectByMouse: true
                background: Rectangle { color: Style.bannerHi
                    border.color: peNameField.activeFocus ? Style.accent : Style.panelEdge
                    border.width: 1; radius: 6 }
                onTextChanged: page.peName = text
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: qsTr("Type"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 80 }
                Button { Layout.fillWidth: true
                         text: page.peType.length ? page.peType : qsTr("Select type\u2026")
                         onClicked: typePicker.open() }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: productEditor.close() }
                Button {
                    text: qsTr("Save"); font.bold: true
                    enabled: page.peName.trim().length > 0 && page.peType.trim().length > 0
                    onClicked: {
                        if (page.peOrigName.length)
                            catalog.updateProduct(page.peOrigName, page.peOrigType,
                                                  page.peName.trim(), page.peType.trim());
                        else
                            catalog.addProduct(page.peName.trim(), page.peType.trim());
                        productEditor.close();
                    }
                }
            }
        }
    }

    ListPicker { id: typePicker; title: qsTr("Product type"); model: catalog.productTypes
        addPlaceholder: qsTr("New product type")
        onSelected: page.peType = value
        onAddRequested: { catalog.addProductType(text); page.peType = text; } }

    // ---- Mix editor ----
    Popup {
        id: mixEditor
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
            contentHeight: meCol.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: meCol
                width: parent.width; spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: page.meOrig.length ? qsTr("Edit tank mix") : qsTr("New tank mix")
                            color: Style.accent; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                    Button { text: Icons.close; font.family: Icons.family; font.pixelSize: 20
                             implicitWidth: 44; implicitHeight: 44; onClicked: mixEditor.close() }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: qsTr("Rate/ha"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 96 }
                    Button { Layout.fillWidth: true
                             text: (page.meRate > 0 ? page.meRate : "0") + " " + page.meUnit + qsTr(" /ha")
                             onClicked: meRatePad.openWith(page.meRate, page.meUnit) }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: qsTr("Carrier"); color: Style.textDim; font.pixelSize: 15; Layout.preferredWidth: 96 }
                    TextField {
                        id: meCarrierField
                        Layout.fillWidth: true; text: page.meCarrier
                        placeholderText: qsTr("e.g. Water")
                        color: Style.white; placeholderTextColor: Style.textDim; selectByMouse: true
                        background: Rectangle { color: Style.bannerHi
                            border.color: meCarrierField.activeFocus ? Style.accent : Style.panelEdge
                            border.width: 1; radius: 6 }
                        onTextChanged: page.meCarrier = text
                    }
                }
                Label { text: qsTr("Products"); color: Style.textDim; font.pixelSize: 14 }
                Repeater {
                    model: page.meProducts
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 44; radius: 6
                        color: Style.bannerHi; border.color: Style.panelEdge; border.width: 1
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8
                            Label { Layout.fillWidth: true; text: modelData.name; color: Style.white; font.pixelSize: 15 }
                            Label { text: modelData.rate + " " + modelData.unit + qsTr("/ha")
                                    color: Style.accent; font.pixelSize: 14 }
                            Button { text: Icons.del; font.family: Icons.family; font.pixelSize: 18
                                     implicitWidth: 40; implicitHeight: 40
                                     onClicked: { var arr = page.meProducts.slice(); arr.splice(index, 1); page.meProducts = arr; } }
                        }
                    }
                }
                Button { Layout.fillWidth: true; text: qsTr("Add product\u2026")
                         onClicked: { mixCompPicker.model = page.allProductNames(); mixCompPicker.open(); } }
                Label { text: qsTr("Name"); color: Style.textDim; font.pixelSize: 14 }
                TextField {
                    id: meNameField
                    Layout.fillWidth: true; text: page.meName
                    placeholderText: qsTr("e.g. Knockdown A")
                    color: Style.white; placeholderTextColor: Style.textDim; selectByMouse: true
                    background: Rectangle { color: Style.bannerHi
                        border.color: meNameField.activeFocus ? Style.accent : Style.panelEdge
                        border.width: 1; radius: 6 }
                    onTextChanged: page.meName = text
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Item { Layout.fillWidth: true }
                    Button { text: qsTr("Cancel"); onClicked: mixEditor.close() }
                    Button {
                        text: qsTr("Save mix"); font.bold: true
                        enabled: page.meName.trim().length > 0
                        onClicked: {
                            var nm = page.meName.trim();
                            // Renaming: drop the old entry so we don't leave an orphan.
                            if (page.meOrig.length && page.meOrig !== nm)
                                catalog.deleteTankMix(page.meOrig);
                            catalog.addTankMix({ name: nm, rateHa: page.meRate, unit: page.meUnit,
                                                 carrier: page.meCarrier, products: page.meProducts });
                            mixEditor.close();
                        }
                    }
                }
            }
        }
    }

    NumberPad { id: meRatePad; title: qsTr("Tank mix rate per hectare")
        onAccepted: { page.meRate = value; page.meUnit = unit; } }
    NumberPad { id: meCompPad; title: qsTr("Product rate per hectare")
        onAccepted: { var arr = page.meProducts.slice();
                      arr.push({ name: page.mePending, rate: value, unit: unit });
                      page.meProducts = arr; } }
    ListPicker { id: mixCompPicker; title: qsTr("Add product to mix"); model: []
        addPlaceholder: qsTr("New product")
        onSelected: { page.mePending = value; meCompPad.openWith(0, "L"); }
        onAddRequested: { catalog.addProduct(text, "Other"); page.mePending = text; meCompPad.openWith(0, "L"); } }

    // ---- Text editor (crop add/rename, type add) ----
    Popup {
        id: textEditor
        modal: true; dim: true; padding: 16
        closePolicy: Popup.CloseOnEscape
        parent: Overlay.overlay
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        width: Math.min((parent ? parent.width : 400) - 24, 400)
        background: Rectangle { color: Style.panel; border.color: Style.accent; border.width: 1; radius: 12 }
        onOpened: teField.text = page.teOrig
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                color: Style.accent; font.pixelSize: 18; font.bold: true
                text: page.teMode === "addCrop" ? qsTr("New crop")
                      : page.teMode === "renameCrop" ? qsTr("Rename crop")
                      : qsTr("New product type")
            }
            TextField {
                id: teField
                Layout.fillWidth: true
                placeholderText: qsTr("Name")
                color: Style.white; placeholderTextColor: Style.textDim; selectByMouse: true
                background: Rectangle { color: Style.bannerHi
                    border.color: teField.activeFocus ? Style.accent : Style.panelEdge
                    border.width: 1; radius: 6 }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Cancel"); onClicked: textEditor.close() }
                Button {
                    text: qsTr("Save"); font.bold: true
                    enabled: teField.text.trim().length > 0
                    onClicked: {
                        var v = teField.text.trim();
                        if (page.teMode === "addCrop") catalog.addCrop(v);
                        else if (page.teMode === "renameCrop") catalog.renameCrop(page.teOrig, v);
                        else if (page.teMode === "addType") catalog.addProductType(v);
                        textEditor.close();
                    }
                }
            }
        }
    }

    // ---- Delete confirm ----
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
            Label { text: qsTr("Delete?"); color: Style.accent; font.pixelSize: 19; font.bold: true }
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Style.white; font.pixelSize: 15
                    text: (page.cdLabel.length ? page.cdLabel : qsTr("This item"))
                          + "\n\n" + qsTr("This removes it from the catalog. This cannot be undone.") }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                Button { Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Cancel")
                         onClicked: confirmDelete.close() }
                Button {
                    Layout.fillWidth: true; implicitHeight: 48; text: qsTr("Delete"); font.bold: true
                    contentItem: Text { text: parent.text; font: parent.font; color: Style.white
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 8; color: parent.pressed ? "#b03030" : "#e05a5a" }
                    onClicked: { confirmDelete.close(); page.doDelete(); }
                }
            }
        }
    }
}
