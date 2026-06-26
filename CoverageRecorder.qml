import QtQuick 2.15
import "Sections.js" as Sections

// Shared coverage recorder: marks cells (MAIN headless) + stroke geometry (MAP overlay).
Item {
    id: rec
    property real lastRx: NaN
    property real lastRy: NaN
    property var doneStrokes: []
    property int doneCount: 0
    property var activeStrokes: []
    property int activeVersion: 0
    // Ignore onCleared while PhoneWorkSync replays saved GeoJSON strokes.
    property bool loadingCoverage: false
    readonly property int _chunkMax: 150

    function sectionCount() { return app.sectionCount }
    function secW(i) {
        var sw = app.sectionWidths
        if (sw && sw.length > i) return sw[i]
        return app.implementWidth / sectionCount()
    }
    function recordPoint() {
        if (!gps.hasFix)
            return null
        if (!gps.hasOrigin)
            gps.setOrigin(gps.latitude, gps.longitude)
        var hr = gps.headingDeg * Math.PI / 180
        var sinH = Math.sin(hr), cosH = Math.cos(hr)
        var gx = gps.localX, gy = gps.localY
        var h = app.antennaHeight
        if (gps.hasAttitude && h > 0.01) {
            var roll = Math.max(-30, Math.min(30, gps.rollDeg)) * Math.PI / 180
            var pitch = Math.max(-30, Math.min(30, gps.pitchDeg)) * Math.PI / 180
            var latOff = h * Math.sin(roll)
            var lonOff = h * Math.sin(pitch)
            gx -= latOff * cosH + lonOff * sinH
            gy -= latOff * (-sinH) + lonOff * cosH
        }
        var off = app.implementOffset
        var px = gx - off * sinH, py = gy - off * cosH
        if (!isFinite(px) || !isFinite(py))
            return null
        return { x: px, y: py }
    }
    function _nulls(n) { var a = []; for (var i = 0; i < n; ++i) a.push(null); return a }
    function _chunkBbox(pts, pad) {
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18
        for (var i = 0; i < pts.length; ++i) {
            var p = pts[i]
            if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x
            if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y
        }
        return { minx: minx - pad, miny: miny - pad, maxx: maxx + pad, maxy: maxy + pad }
    }
    function _freeze(st) {
        if (st && st.pts && st.pts.length >= 2) {
            var b = rec._chunkBbox(st.pts, st.w || 0)
            st.bbox = b
            coverage.addChunkBox(b.minx, b.miny, b.maxx, b.maxy)
            var ds = rec.doneStrokes.slice()
            ds.push(st)
            rec.doneStrokes = ds
            rec.doneCount = ds.length
        }
    }
    function _freezeAllActive() {
        for (var i = 0; i < rec.activeStrokes.length; ++i) rec._freeze(rec.activeStrokes[i])
        rec.activeStrokes = rec._nulls(rec.activeStrokes.length)
        rec.activeVersion++
    }
    function _clearStrokes() {
        rec.doneStrokes = []; rec.doneCount = 0
        rec.activeStrokes = []; rec.activeVersion++
        coverage.clearChunks()
    }
    function _commitActive() {
        // Reassign so element mutations persist on Android QML engines.
        rec.activeStrokes = rec.activeStrokes.slice()
        rec.activeVersion++
    }

    Connections {
        target: coverage
        function onCleared() {
            if (rec.loadingCoverage)
                return
            rec._clearStrokes()
        }
    }

    Connections {
        target: gps
        function onFixChanged() {
            if (!app.recordingCoverage) return
            var rp = rec.recordPoint()
            if (!rp) return
            var rx = rp.x, ry = rp.y
            if (!isFinite(rec.lastRx) || !isFinite(rec.lastRy)) {
                rec.lastRx = rx; rec.lastRy = ry
                return
            }
            var dx = rx - rec.lastRx, dy = ry - rec.lastRy
            if (dx * dx + dy * dy < 0.25) return
            rec.lastRx = rx; rec.lastRy = ry
            var hr = gps.headingDeg * Math.PI / 180
            var N = rec.sectionCount()
            var rex = Math.cos(hr), rny = -Math.sin(hr)
            if (rec.activeStrokes.length !== N)
                rec.activeStrokes = rec._nulls(N)
            var act = rec.activeStrokes.slice()
            var cum = -app.implementWidth / 2
            for (var i = 0; i < N; ++i) {
                var w = rec.secW(i)
                var t = cum + w / 2
                cum += w
                var se = rx + t * rex, sn = ry + t * rny
                if (!isFinite(se) || !isFinite(sn)) continue
                var on = !(app.sectionControl && coverage.isCovered(se, sn))
                if (on) {
                    coverage.mark(se, sn, gps.headingDeg, w)
                    var st = act[i]
                    if (!st || st.w !== w) {
                        if (st) rec._freeze(st)
                        st = { w: w, pts: [] }
                        act[i] = st
                    }
                    st.pts.push(Qt.point(se, -sn))
                    if (st.pts.length >= rec._chunkMax) {
                        rec._freeze(st)
                        act[i] = { w: w, pts: [ st.pts[st.pts.length - 1] ] }
                    }
                } else if (act[i]) {
                    rec._freeze(act[i])
                    act[i] = null
                }
            }
            rec.activeStrokes = act
            rec._commitActive()
        }
    }
    Connections {
        target: app
        function onRecordingChanged() {
            if (app.recordingCoverage) {
                var rp = rec.recordPoint()
                if (rp) {
                    rec.lastRx = rp.x
                    rec.lastRy = rp.y
                } else {
                    rec.lastRx = NaN
                    rec.lastRy = NaN
                }
            } else {
                rec.lastRx = NaN; rec.lastRy = NaN
                rec._freezeAllActive()
            }
        }
    }
}
