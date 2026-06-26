import QtQuick 2.15
import "Style.js" as Style

// Bottom banner of soft keys, driven by a layout model so keys can be changed
// from a layout manager. Emits keyActivated(id) for the shell to handle.
Rectangle {
    id: root
    property var keys: []   // [{ id, label, glyph, enabled }]
    signal keyActivated(string keyId)

    implicitHeight: 76
    color: Style.banner

    Row {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8
        Repeater {
            model: root.keys
            SoftKey {
                width: (root.width - 16 - (root.keys.length - 1) * 8) / Math.max(1, root.keys.length)
                height: parent.height
                label: modelData.label
                glyph: modelData.glyph !== undefined ? modelData.glyph : ""
                enabledKey: modelData.enabled !== undefined ? modelData.enabled : true
                active: modelData.active !== undefined ? modelData.active : false
                onActivated: root.keyActivated(modelData.id)
            }
        }
    }
}
