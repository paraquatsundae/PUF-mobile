import QtQuick 2.15
import "Sections.js" as Sections
import "RecordPoint.js" as RecordPoint

// Shared coverage recorder: marks cells (MAIN headless) + stroke geometry (MAP overlay).
Item {
    id: rec
    property real lastRx: NaN
    property real lastRy: NaN
    property real covHdg: NaN
    property var doneStrokes: []
    property int doneCount: 0
    property var activeStrokes: []
    property int activeVersion: 0
    // Ignore onCleared while PhoneWorkSync replays saved GeoJSON strokes.
    property bool loadingCoverage: false
    readonly property int _chunkMax: 400

    function sectionCount() { return app.sectionCount }
    function secW(i) {
        var sw = app.sectionWidths
        if (sw && sw.length > i) return sw[i]
        return app.implementWidth / sectionCount()
    }
    function recordPoint() {
        return RecordPoint.recordLocal(gps, app)
    }
    function _nulls(n) { var a = []; for (var i = 0; i < n; ++i) a.push(null); return a }
    function _hdgDelta(a, b) {
        var d = b - a
        while (d > 180) d -= 360
        while (d < -180) d += 360
        return d
    }
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
                rec.covHdg = gps.headingDeg
                return
            }
            var dx = rx - rec.lastRx, dy = ry - rec.lastRy
            if (dx * dx + dy * dy < 0.04) return  // >= 0.20 m — less paint churn
            rec.lastRx = rx; rec.lastRy = ry
            var rawH = gps.headingDeg
            if (!isFinite(rec.covHdg)) {
                rec.covHdg = rawH
            } else {
                var dh = rec._hdgDelta(rec.covHdg, rawH)
                if (Math.abs(dh) < 0.7)
                    dh = 0
                else if (dh > 1.8)
                    dh = 1.8
                else if (dh < -1.8)
                    dh = -1.8
                rec.covHdg = rec.covHdg + dh
                if (rec.covHdg >= 360) rec.covHdg -= 360
                if (rec.covHdg < 0) rec.covHdg += 360
            }
            var hr = rec.covHdg * Math.PI / 180
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
                if (!isFinite(se) || !isFinite(sn) || !(w > 0)) continue
                // Always mark + stroke while recording. isCovered must not freeze
                // the trail (see FieldView) — area cells stay unique in C++.
                var st = act[i]
                if (st && st.pts && st.pts.length > 0) {
                    var prev = st.pts[st.pts.length - 1]
                    coverage.markAlong(prev.x, -prev.y, se, sn, rec.covHdg, w)
                } else {
                    coverage.mark(se, sn, rec.covHdg, w)
                }
                if (!st || st.w !== w) {
                    if (st) rec._freeze(st)
                    st = { w: w, pts: [] }
                    act[i] = st
                }
                st.pts = (st.pts ? st.pts.slice() : []).concat(
                            [{ x: se, y: -sn, h: rec.covHdg }])
                act[i] = st
                if (st.pts.length >= rec._chunkMax) {
                    rec._freeze(st)
                    // Keep last 2 pts — a lone carry-over painted as a boom circle.
                    act[i] = { w: w, pts: st.pts.slice(-2) }
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
                rec.covHdg = gps.headingDeg
            } else {
                rec.lastRx = NaN; rec.lastRy = NaN
                rec.covHdg = NaN
                rec._freezeAllActive()
            }
        }
    }
}
