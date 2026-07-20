import QtQuick 2.15
import "RecordPoint.js" as RecordPoint

// Keeps boundary point capture alive while the operator views the MAP tab.
Item {
    Connections {
        target: gps
        function onFixChanged() {
            if (!farm.boundaryRecording || farm.boundaryPaused || !gps.hasFix)
                return
            var pt = RecordPoint.recordLatLon(gps, app)
            if (pt)
                farm.appendBoundaryPoint(pt.lat, pt.lon)
        }
    }
}
