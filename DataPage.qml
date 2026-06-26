import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Style.js" as Style

// Numeric GPS dashboard.
Flickable {
    id: page
    contentWidth: width
    contentHeight: grid.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    GridLayout {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        columns: 2
        columnSpacing: 12
        rowSpacing: 12

        FieldCard { label: qsTr("Latitude");   value: gps.hasFix ? gps.latitude.toFixed(7) + "\u00B0"  : "--" }
        FieldCard { label: qsTr("Longitude");  value: gps.hasFix ? gps.longitude.toFixed(7) + "\u00B0" : "--" }
        FieldCard { label: qsTr("Altitude");   value: gps.altitude.toFixed(1) + " m" }
        FieldCard { label: qsTr("Speed");      value: gps.speedKmh.toFixed(1) + " km/h" }
        FieldCard { label: qsTr("Heading");    value: gps.headingDeg.toFixed(1) + "\u00B0" }
        FieldCard { label: qsTr("Satellites"); value: gps.satellites.toString() }
        FieldCard { label: qsTr("HDOP");       value: gps.hdop.toFixed(2) }
        FieldCard { label: qsTr("Fix type");   value: gps.fixText }
        FieldCard { label: qsTr("UTC");        value: gps.utcTime.length ? gps.utcTime : "--" }
        FieldCard { label: qsTr("Fix age");    value: gps.ageSeconds < 100 ? gps.ageSeconds.toFixed(1) + " s" : "--" }
        FieldCard { label: qsTr("Sentences");  value: gps.sentenceCount.toString() }
        FieldCard { label: qsTr("Source");     value: app.running ? app.activeSource : "--" }
    }
}
