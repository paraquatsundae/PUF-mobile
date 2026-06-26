import QtQuick 2.15
import "Style.js" as Style
import "Elements.js" as Elements

// One info card in a side column. `elementId` selects what it shows.
Rectangle {
    id: root
    property string elementId: ""

    width: parent ? parent.width : 180
    implicitHeight: 64
    radius: 8
    color: Style.panel
    border.color: Style.panelEdge
    border.width: 1

    function valueFor(id) {
        switch (id) {
        case "area":       return coverage.areaHa.toFixed(2) + " ha";
        case "speed":      return gps.speedKmh.toFixed(1) + " km/h";
        case "heading":    return gps.headingDeg.toFixed(0) + "\u00B0";
        case "location":   return gps.hasFix ? gps.latitude.toFixed(6) + "\n" + gps.longitude.toFixed(6) : "--";
        case "satellites": return gps.satellites.toString();
        case "hdop":       return gps.hdop.toFixed(2);
        case "fix":        return gps.stale ? "STALE" : gps.fixText;
        case "altitude":   return gps.altitude.toFixed(1) + " m";
        case "implwidth":  return app.implementWidth.toFixed(1) + " m";
        case "track":      return app.trackName.length ? app.trackName : "No track";
        default:           return "--";
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 9
        spacing: 1
        Text { text: Elements.label(root.elementId); color: Style.textDim; font.pixelSize: 12 }
        Text {
            text: root.valueFor(root.elementId)
            color: Style.white; font.pixelSize: root.elementId === "location" ? 16 : 22
            font.bold: true; width: parent.width; elide: Text.ElideRight
        }
    }
}
