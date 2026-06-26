import QtQuick 2.15
import "Icons.js" as Icons

// A single Material Design Icon glyph. Set `icon` to one of the Icons.* values.
Text {
    property string icon: ""
    text: icon
    font.family: Icons.family
    font.pixelSize: 22
    color: "#ffffff"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.QtRendering
    antialiasing: true
}
