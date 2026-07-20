import QtQuick 2.15

// High-definition top-down self-propelled sprayer sprite. The caller sizes the
// item to the real footprint (width = 3 m in px). The machine front (cab) sits at
// the item TOP, which is the GPS receiver position and the rotation pivot, so the
// icon turns about the receiver point on the map.
Item {
    id: root
    property real heading: 0
    width: 24
    height: 48
    antialiasing: true
    transformOrigin: Item.Top        // pivot about the antenna (front-centre)
    rotation: heading
    // No Behavior — a 200 ms rotation lerp lagged JD RTK/TCM and looked like boom jitter.

    // Native sprite is 623 x 1014 (w x h); preserve that aspect off the width so
    // the machine stays dimensionally honest as the map scales.
    readonly property real _aspect: 1014 / 623

    Image {
        id: sprite
        source: "qrc:/assets/sprayer_topdown.png"
        width: root.width
        height: width * root._aspect
        x: 0
        y: 0                          // front aligned to the receiver point
        smooth: true
        mipmap: true                  // crisp when scaled down on the map
        antialiasing: true
        fillMode: Image.Stretch       // width/height already match native aspect
        sourceSize.width: 311         // cap decode size (machine is small on screen)
    }

    // GPS receiver marker (front-centre = map centre / rotation pivot)
    Rectangle {
        width: Math.max(4, root.width * 0.16)
        height: width
        radius: width / 2
        x: root.width / 2 - width / 2
        y: -height / 2
        color: "#ff5a5f"
        border.color: "#ffffff"
        border.width: Math.max(1, root.width * 0.03)
        antialiasing: true
    }
}
