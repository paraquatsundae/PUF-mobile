import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Shapes 1.15
import "Style.js" as Style
import "FormFactor.js" as FormFactor
import "RecordPoint.js" as RecordPoint

// Phone MAP: boundary outline + live coverage swaths. Modes: 0=chase, 1=top-down, 2=whole paddock.
Item {
    id: map
    clip: true

    property var recorder: null
    property int mode: 0

    Dialog {
        id: stopRecordDialog
        modal: true
        title: qsTr("Stop recording?")
        standardButtons: Dialog.Yes | Dialog.No
        anchors.centerIn: parent
        width: Math.min(360, parent.width - 40)
        onAccepted: app.setRecording(false)
        Label {
            text: qsTr("Coverage recording will stop.")
            wrapMode: Text.WordWrap
            width: stopRecordDialog.availableWidth
            color: theme.text
        }
    }
    // Set by PhoneMapTab so chase framing clears the floating header.
    property int topChromeInset: 0
    property int bottomChromeInset: 0

    readonly property bool _phoneLayout: FormFactor.isPhone(Screen.width, Screen.height)
    readonly property bool fitField: mode === 2 && gps.hasOrigin
    readonly property bool headingUp: mode === 0
    property real userZoom: 1.0
    // Five zoom-in taps (phone uses ×1.25 per click).
    readonly property real _chaseDefaultZoom: Math.pow(1.25, 5)
    property bool following: true
    property real panX: 0
    property real panY: 0
    property real _anchorX: 0
    property real _anchorY: 0

    readonly property real _maxLocalM: 200000
    readonly property int _maxRingVerts: 1000

    // Usable map band between floating header and bottom zoom row.
    readonly property real _viewTop: map.topChromeInset
    readonly property real _viewBot: Math.max(map._viewTop + 80,
                                              map.height - map.bottomChromeInset)
    readonly property real _viewH: Math.max(1, map._viewBot - map._viewTop)
    readonly property real _viewMidY: map._viewTop + map._viewH * 0.5

    readonly property real cx: width / 2
    readonly property real cy: {
        if (mode !== 0)
            return map._viewMidY
        return map._viewTop + map._viewH * (map._phoneLayout ? 0.90 : 0.74)
    }
    readonly property real horizonY: {
        if (mode !== 0)
            return map._viewTop
        if (map._phoneLayout)
            return map._viewTop + Math.min(28, map._viewH * 0.05)
        return height * 0.34
    }
    readonly property bool chaseView: mode === 0 && !fitField
    property real tilt: chaseView ? 74 : 0
    readonly property real _frameMetres: app.recordOffsetM + 80
    readonly property real _framePx: Math.max(40, map._viewBot - cy)
    readonly property real _baseScale: _framePx / Math.max(20, _frameMetres)

    Behavior on userZoom {
        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
    }
    Behavior on tilt {
        NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
    }
    onModeChanged: {
        userZoom = chaseView ? _chaseDefaultZoom : 1.0
        panX = 0; panY = 0; following = true
    }

    function _validLatLon(la, lo) {
        return (typeof la === "number" && typeof lo === "number"
                && isFinite(la) && isFinite(lo)
                && la >= -90 && la <= 90 && lo >= -180 && lo <= 180
                && !(Math.abs(la) < 1e-7 && Math.abs(lo) < 1e-7))
    }
    function _boundaryCentroid() {
        var b = farm.activeBoundary
        if (!b || b.length < 3) return null
        var sLat = 0, sLon = 0, n = 0
        for (var i = 0; i < b.length; ++i) {
            if (!map._validLatLon(b[i].lat, b[i].lon)) continue
            sLat += b[i].lat; sLon += b[i].lon; ++n
        }
        if (n < 1) return null
        return { lat: sLat / n, lon: sLon / n }
    }
    function _decimate(pts, maxN) {
        var n = pts.length
        if (n <= maxN || maxN < 2) return pts
        var step = Math.ceil(n / maxN)
        var out = []
        for (var i = 0; i < n; i += step) out.push(pts[i])
        if ((n - 1) % step !== 0) out.push(pts[n - 1])
        return out
    }
    function _fieldBounds() {
        var b = farm.activeBoundary
        if (!gps.hasOrigin || !b || b.length < 3) return null
        var lim = map._maxLocalM
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18, n = 0
        for (var i = 0; i < b.length; ++i) {
            var p = gps.toLocal(b[i].lat, b[i].lon)
            if (!isFinite(p.x) || !isFinite(p.y)) continue
            if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue
            var wx = p.x, wy = -p.y
            if (wx < minx) minx = wx; if (wx > maxx) maxx = wx
            if (wy < miny) miny = wy; if (wy > maxy) maxy = wy
            ++n
        }
        if (n < 3) return null
        return { minx: minx, miny: miny, maxx: maxx, maxy: maxy }
    }
    function _coverageBounds() {
        if (!recorder) return null
        var arr = recorder.doneStrokes
        var lim = map._maxLocalM
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18, n = 0
        function _eatStroke(st) {
            if (!st || !st.pts) return
            for (var j = 0; j < st.pts.length; ++j) {
                var p = st.pts[j]
                if (!isFinite(p.x) || !isFinite(p.y)) continue
                if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue
                if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x
                if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y
                ++n
            }
        }
        for (var i = 0; i < arr.length; ++i)
            _eatStroke(arr[i])
        if (recorder.activeStrokes) {
            for (var k = 0; k < recorder.activeStrokes.length; ++k)
                _eatStroke(recorder.activeStrokes[k])
        }
        if (n < 2) return null
        return { minx: minx, miny: miny, maxx: maxx, maxy: maxy }
    }
    function _fitBounds() {
        var b = map._fieldBounds()
        var c = map._coverageBounds()
        if (b && c) {
            return {
                minx: Math.min(b.minx, c.minx), miny: Math.min(b.miny, c.miny),
                maxx: Math.max(b.maxx, c.maxx), maxy: Math.max(b.maxy, c.maxy)
            }
        }
        if (b) return b
        return c
    }
    function _screenToWorld(sx, sy) {
        var a = map.viewRot * Math.PI / 180
        var dx = sx - map.viewOffX, dy = sy - map.viewOffY
        var rx = dx * Math.cos(a) + dy * Math.sin(a)
        var ry = -dx * Math.sin(a) + dy * Math.cos(a)
        var sc = Math.max(0.0001, map.viewScale)
        return { e: rx / sc, n: -(ry / sc) }
    }
    readonly property var fb: fitField ? _fitBounds() : null
    readonly property real _fitScale: {
        if (!fb) return _baseScale
        var w = Math.max(1, fb.maxx - fb.minx)
        var h = Math.max(1, fb.maxy - fb.miny)
        return Math.min(width * 0.84 / w, map._viewH * 0.84 / h)
    }
    readonly property real viewScale: {
        var base = fitField ? _fitScale : _baseScale
        return Math.max(0.02, Math.min(400, base * userZoom))
    }
    readonly property real s: viewScale
    readonly property real viewRot: fitField ? 0 : (headingUp ? -gps.headingDeg : 0)
    readonly property real viewOffX: {
        if (fitField && fb) return width / 2 - viewScale * (fb.minx + fb.maxx) / 2 + panX
        var a = viewRot * Math.PI / 180
        var cwx = following ? gps.localX : _anchorX
        var cwy = following ? gps.localY : _anchorY
        var csx = cwx * viewScale, csy = -cwy * viewScale
        return cx - (csx * Math.cos(a) - csy * Math.sin(a)) + panX
    }
    readonly property real viewOffY: {
        if (fitField && fb) return map._viewMidY - viewScale * (fb.miny + fb.maxy) / 2 + panY
        var a = viewRot * Math.PI / 180
        var cwx = following ? gps.localX : _anchorX
        var cwy = following ? gps.localY : _anchorY
        var csx = cwx * viewScale, csy = -cwy * viewScale
        return cy - (csx * Math.sin(a) + csy * Math.cos(a)) + panY
    }
    readonly property real tractorX: map._worldToScreenX(gps.localX, gps.localY)
    readonly property real tractorY: map._worldToScreenY(gps.localX, gps.localY)
    readonly property real tractorRot: map.fitField ? gps.headingDeg : 0
    readonly property int sectionCount: app.sectionCount
    function _secW(i) {
        var ws = app.sectionWidths
        if (ws && i >= 0 && i < ws.length) return ws[i]
        return app.implementWidth / Math.max(1, map.sectionCount)
    }
    function _secCenter(i) {
        var cum = -app.implementWidth / 2
        for (var k = 0; k < i; ++k) cum += map._secW(k)
        return cum + map._secW(i) / 2
    }
    function _recordPoint() {
        if (map.recorder)
            return map.recorder.recordPoint()
        return map._implPos
    }
    function _centerStroke() {
        if (!map.recorder || !map.recorder.activeStrokes)
            return null
        var arr = map.recorder.activeStrokes
        var mid = Math.floor(arr.length / 2)
        var st = arr[mid]
        if (st && st.pts && st.pts.length >= 2)
            return st
        for (var i = 0; i < arr.length; ++i) {
            st = arr[i]
            if (st && st.pts && st.pts.length >= 2)
                return st
        }
        return null
    }
    // S911B Mali: thick Shape strokeWidth (boom m) is invisible; use rect swaths.
    property bool preferRectSwaths: true
    // Cell spans only as fallback / paddock overview (axis-aligned = chunky up close).
    property bool preferCellPaint: true
    readonly property real _minCellScreenPx: 8.0
    readonly property int _cellPaintMax: map.fitField ? 2500 : (map.chaseView ? 1500 : 2000)
    readonly property int _rowMergeCells: Math.max(1,
        Math.ceil((map._minCellScreenPx / Math.max(0.05, map.viewScale)) / 0.5))
    readonly property var _visCellPaint: {
        // preferCellPaint only — never depend on cellCount/areaHa (rebuilds every mark).
        if (!map.preferCellPaint)
            return []
        var _dep = [
            map._paintTick,
            map._covMinX, map._covMinY, map._covMaxX, map._covMaxY,
            map.viewScale, map.mode, map._rowMergeCells
        ].join("|")
        var spans = coverage.visibleCellSpans(map._covMinX, map._covMinY,
                                            map._covMaxX, map._covMaxY,
                                            map._cellPaintMax,
                                            map._rowMergeCells)
        var out = []
        for (var i = 0; i < spans.length; ++i) {
            var t = spans[i]
            out.push({ x: t.x, y: t.y, w: t.w, h: t.h })
        }
        return out
    }
    // Frozen swaths — viewport-culled indices with fair per-chunk budget.
    readonly property var _frozenPaintSegs: {
        if (!map.recorder || map.recorder.doneCount < 1)
            return []
        var idxs = map._visChunks
        var _dep = [
            map._paintTick, map.recorder.doneCount,
            map._covMinX, map._covMinY, map._covMaxX, map._covMaxY,
            idxs ? idxs.length : 0
        ].join("|")
        var out = []
        if (!idxs || !idxs.length)
            return out
        var n = Math.max(1, idxs.length)
        var per = Math.max(50, Math.floor(1800 / n))
        for (var i = 0; i < idxs.length; ++i) {
            var st = map.recorder.doneStrokes[idxs[i]]
            if (st)
                map._appendWorldStrokeSegs(st, out, per)
        }
        return out
    }
    readonly property var _coveragePaintSegs: {
        var _dep = [map._paintTick, map.recorder ? map.recorder.activeVersion : 0].join("|")
        var out = []
        var frz = map._frozenPaintSegs
        for (var i = 0; i < frz.length; ++i)
            out.push(frz[i])
        var strokes = map._strokesForActivePaint()
        var n = Math.max(1, strokes.length)
        var per = Math.max(40, Math.floor(900 / n))
        for (var j = 0; j < strokes.length; ++j)
            map._appendWorldStrokeSegs(strokes[j], out, per)
        return out
    }
    function _hdgDelta(a, b) {
        var d = b - a
        while (d > 180) d -= 360
        while (d < -180) d += 360
        return d
    }
    function _ptHdg(p, fallback) {
        if (p && typeof p.h === "number" && isFinite(p.h))
            return p.h
        return fallback
    }
    // One square boom-bar per sample (matched to FieldView) — no tip subdiv.
    function _appendWorldStrokeSegs(st, out, budgetN) {
        if (!st || !st.pts || st.pts.length < 2 || budgetN < 1)
            return
        var halfW = Math.max(0.25, (st.w || app.implementWidth) * 0.5)
        var band = halfW * 2
        var overlap = 0.18
        var pts = st.pts
        var startLen = out.length
        var limit = startLen + budgetN
        var stride = 1
        if (pts.length > 120)
            stride = 2
        if (pts.length > 240)
            stride = 3
        for (var k = 0; k < pts.length - 1; k += stride) {
            if (out.length >= limit)
                return
            var p0 = pts[k]
            var p1 = pts[Math.min(k + stride, pts.length - 1)]
            var dx = p1.x - p0.x, dy = p1.y - p0.y
            var chord = Math.sqrt(dx * dx + dy * dy)
            if (chord < 0.02)
                continue
            var fall = Math.atan2(dx, -dy) * 180 / Math.PI
            if (fall < 0) fall += 360
            var hm = map._ptHdg(p0, fall)
            var h1 = map._ptHdg(p1, fall)
            hm = hm + map._hdgDelta(hm, h1) * 0.5
            var hr = hm * Math.PI / 180
            var fx = Math.sin(hr), fy = -Math.cos(hr)
            var along = dx * fx + dy * fy
            if (Math.abs(along) < 0.04)
                along = chord
            out.push({
                x: (p0.x + p1.x) * 0.5,
                y: (p0.y + p1.y) * 0.5,
                w: Math.abs(along) + overlap * 2,
                h: band,
                rot: Math.atan2(fy, fx) * 180 / Math.PI
            })
        }
    }
    function _chunkSegs(st, maxN) {
        var out = []
        if (st && st.pts && st.pts.length >= 2)
            map._appendWorldStrokeSegs(st, out, maxN || 300)
        return out
    }
    function _worldToScreenX(e, n) {
        var a = map.viewRot * Math.PI / 180
        var wx = e * map.viewScale, wy = -n * map.viewScale
        return map.viewOffX + (wx * Math.cos(a) - wy * Math.sin(a))
    }
    function _worldToScreenY(e, n) {
        var a = map.viewRot * Math.PI / 180
        var wx = e * map.viewScale, wy = -n * map.viewScale
        return map.viewOffY + (wx * Math.sin(a) + wy * Math.cos(a))
    }
    function zoomIn()  { userZoom = Math.min(80.0, userZoom * 1.25) }
    function zoomOut() { userZoom = Math.max(0.03, userZoom / 1.25) }
    function recenter() {
        userZoom = chaseView ? _chaseDefaultZoom : 1.0
        panX = 0; panY = 0; following = true
    }

    function _mapRing(list, close) {
        if (!list) return []
        var a = []
        var lim = map._maxLocalM
        for (var i = 0; i < list.length; ++i) {
            var p = gps.toLocal(list[i].lat, list[i].lon)
            if (!isFinite(p.x) || !isFinite(p.y)) continue
            if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue
            a.push(Qt.point(p.x, -p.y))
        }
        a = map._decimate(a, map._maxRingVerts)
        if (close && a.length > 2) a.push(a[0])
        return a
    }
    function _ensureOrigin() {
        if (gps.hasOrigin && map._validLatLon(gps.originLat(), gps.originLon()))
            return
        var c = map._boundaryCentroid()
        if (c) gps.setOrigin(c.lat, c.lon)
    }
    function _haversineM(lat1, lon1, lat2, lon2) {
        var R = 6371000.0
        var p1 = lat1 * Math.PI / 180, p2 = lat2 * Math.PI / 180
        var dLat = (lat2 - lat1) * Math.PI / 180
        var dLon = (lon2 - lon1) * Math.PI / 180
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
              + Math.cos(p1) * Math.cos(p2) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
        return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }
    function _healOriginIfGpsFarFromPaddock() {
        if (!gps.hasFix || !map._validLatLon(gps.latitude, gps.longitude))
            return
        var c = map._boundaryCentroid()
        if (!c)
            return
        var d = map._haversineM(gps.latitude, gps.longitude, c.lat, c.lon)
        if (d < 5000)
            return
        if (!gps.hasOrigin || !map._validLatLon(gps.originLat(), gps.originLon())
                || map._haversineM(gps.originLat(), gps.originLon(), c.lat, c.lon) > 2500)
            gps.setOrigin(c.lat, c.lon)
    }

    readonly property real _viewHalfSpanM: {
        var diagPx = Math.sqrt(width * width + height * height) / 2
        var span = diagPx / Math.max(0.0001, map.viewScale)
        // Chase tilt exposes more ground toward the horizon — extend span so grid
        // and ground fill reach the visible edge instead of cutting off mid-view.
        if (map.chaseView)
            span = Math.max(span, span * 1.0 / Math.max(0.35, Math.cos(map.tilt * Math.PI / 180)))
        return span
    }
    readonly property real _gridStep: 20
    readonly property real _gridHalf: {
        var half = Math.ceil(map._viewHalfSpanM * 1.35 / map._gridStep) * map._gridStep + map._gridStep
        return Math.max(120, half)
    }
    // World-lattice snap (same as FieldView) — grid stays on the paddock, not the tractor.
    readonly property real _gridStartX: Math.floor(
        (map._covCenter.x - map._gridHalf) / map._gridStep) * map._gridStep
    readonly property real _gridStartY: Math.floor(
        (map._covCenter.y - map._gridHalf) / map._gridStep) * map._gridStep
    // Cap grid repeaters — uncapped lines × pan/zoom updates can abort hwuiTask on Mali.
    readonly property int _gridLines: Math.min(100,
        Math.floor(map._gridHalf * 2 / map._gridStep) + 2)
    readonly property real _satQuantDeg: 0.0008
    readonly property real _satChaseAheadM: 2200
    readonly property real _satChaseSideM: 450
    readonly property real _satNearAheadM: 320

    function _satGeoFromSamples(samples, mpp) {
        var south = 90, north = -90, west = 180, east = -180
        var any = false
        for (var i = 0; i < samples.length; ++i) {
            var p = samples[i]
            var g = gps.toGeo(p.e, p.n)
            if (!g || !isFinite(g.lat) || !isFinite(g.lon))
                continue
            any = true
            south = Math.min(south, g.lat)
            north = Math.max(north, g.lat)
            west = Math.min(west, g.lon)
            east = Math.max(east, g.lon)
        }
        if (!any)
            return null
        var q = map._satQuantDeg
        return {
            south: Math.floor(south / q) * q,
            west: Math.floor(west / q) * q,
            north: Math.ceil(north / q) * q,
            east: Math.ceil(east / q) * q,
            mpp: mpp
        }
    }

    function _satChaseSamples(aheadM, sideM) {
        var hdg = gps.headingDeg * Math.PI / 180
        var fx = Math.sin(hdg), fy = Math.cos(hdg)
        var sx = Math.cos(hdg), sy = -Math.sin(hdg)
        var ox, oy
        if (map.following) {
            ox = gps.localX; oy = gps.localY
        } else {
            var c0 = map._screenToWorld(width * 0.5, height * 0.5)
            ox = c0.e; oy = c0.n
        }
        var samples = []
        var fracs = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
        for (var fi = 0; fi < fracs.length; ++fi) {
            var d = aheadM * fracs[fi]
            var bx = ox + fx * d
            var by = oy + fy * d
            var side = sideM * (0.35 + 0.65 * fracs[fi])
            samples.push({ e: bx, n: by })
            samples.push({ e: bx + sx * side, n: by + sy * side })
            samples.push({ e: bx - sx * side, n: by - sy * side })
        }
        samples.push({ e: ox - fx * Math.min(120, sideM * 0.4),
                       n: oy - fy * Math.min(120, sideM * 0.4) })
        return samples
    }

    function _satMergeTiles(baseList, detailList) {
        var seen = ({})
        var out = []
        function add(list) {
            if (!list)
                return
            for (var i = 0; i < list.length; ++i) {
                var t = list[i]
                var k = t.path || (t.z + "/" + t.x + "/" + t.y)
                if (seen[k])
                    continue
                seen[k] = 1
                out.push(t)
            }
        }
        add(baseList)
        add(detailList)
        return out
    }

    readonly property var _satViewGeo: {
        if (!gps.hasOrigin || width < 8 || height < 8)
            return null
        var dpr = Math.max(1.0, Screen.devicePixelRatio)
        var mpp = ((1.0 / Math.max(0.02, map.viewScale)) / dpr) * 0.28
        if (map.chaseView)
            return map._satGeoFromSamples(
                        map._satChaseSamples(map._satNearAheadM,
                                             Math.max(120, map._viewHalfSpanM * 0.9)),
                        mpp)
        var samples = [
            map._screenToWorld(0, 0),
            map._screenToWorld(width, 0),
            map._screenToWorld(0, height),
            map._screenToWorld(width, height),
            map._screenToWorld(width * 0.5, height * 0.5)
        ]
        return map._satGeoFromSamples(samples, mpp)
    }
    readonly property var _satFarGeo: {
        if (!gps.hasOrigin || !map.chaseView || width < 8)
            return null
        var dpr = Math.max(1.0, Screen.devicePixelRatio)
        var mpp = ((1.0 / Math.max(0.02, map.viewScale)) / dpr) * 6.0
        return map._satGeoFromSamples(
                    map._satChaseSamples(map._satChaseAheadM, map._satChaseSideM),
                    mpp)
    }
    readonly property var _satTiles: {
        var rev = basemap.packRevision
        var packsN = basemap.packs.length
        var g = map._satViewGeo
        if (!gps.hasOrigin || packsN < 1 || !g)
            return []
        var _dep = [rev, packsN, g.south, g.west, g.north, g.east,
                    Math.round(Math.log(Math.max(0.02, map.viewScale)) * 8),
                    map.chaseView ? 1 : 0].join("|")
        var detailCap = map.fitField ? 100 : (map.chaseView ? 200 : 160)
        var detail = basemap.visibleTiles(g.south, g.west, g.north, g.east,
                                          g.mpp, detailCap)
        if (!map.chaseView)
            return detail
        var far = map._satFarGeo
        if (!far)
            return detail
        var base = basemap.visibleTiles(far.south, far.west, far.north, far.east,
                                        far.mpp, 90)
        return map._satMergeTiles(base, detail)
    }
    readonly property var _covCenter: {
        if (map.fitField && map.fb)
            return { x: (map.fb.minx + map.fb.maxx) / 2,
                     y: (map.fb.miny + map.fb.maxy) / 2 }
        if (map.following)
            return { x: gps.localX, y: -gps.localY }
        var c = map._screenToWorld(map.width / 2, map.height / 2)
        return { x: c.e, y: -c.n }
    }
    readonly property real _covHalf: Math.max(60, map._viewHalfSpanM * 1.5)
    readonly property real _covQuant: 64
    // Viewport query — same as tablet FieldView (no full-bbox union; that forced
    // every cell into the query and stride-decimation made solid fill look dashed).
    readonly property var _covQuery: {
        var cx = map._covCenter.x, cy = map._covCenter.y, half = map._covHalf
        var q = map._covQuant
        return {
            minx: Math.floor((cx - half) / q) * q,
            miny: Math.floor((cy - half) / q) * q,
            maxx: Math.ceil((cx + half) / q) * q,
            maxy: Math.ceil((cy + half) / q) * q
        }
    }
    readonly property real _covMinX: map._covQuery.minx
    readonly property real _covMinY: map._covQuery.miny
    readonly property real _covMaxX: map._covQuery.maxx
    readonly property real _covMaxY: map._covQuery.maxy
    // Same viewport culling as tablet FieldView (_covMaxN = 300).
    readonly property int _covMaxN: 300
    readonly property var _visChunks: (map.recorder ? map.recorder.doneCount : 0,
        map.recorder ? map.recorder.activeVersion : 0,
        coverage.chunkCount, coverage.areaHa,
        map._covMinX, map._covMinY, map._covMaxX, map._covMaxY,
        map.viewScale, map.mode, map.userZoom, map.fitField,
        gps.localX, gps.localY,
        coverage.visibleChunks(map._covMinX, map._covMinY,
                               map._covMaxX, map._covMaxY, map._covMaxN))
    // Paint refresh throttled like tablet FieldView — GPS marks cells without
    // rebuilding every visible chunk delegate on each fix.
    property int _paintVersion: 0
    property int _paintTick: 0
    function _strokesForActivePaint() {
        var out = []
        if (!map.recorder || !map.recorder.activeStrokes)
            return out
        var act = map.recorder.activeStrokes
        for (var i = 0; i < act.length; ++i) {
            var st = act[i]
            if (st && st.pts && st.pts.length >= 2)
                out.push(st)
        }
        return out
    }
    readonly property var _activePaintSegs: {
        var strokes = map._strokesForActivePaint()
        var _dep = [map._paintVersion, strokes.length, map._paintTick].join("|")
        var out = []
        var n = Math.max(1, strokes.length)
        var per = Math.max(40, Math.floor(900 / n))
        for (var i = 0; i < strokes.length; ++i)
            map._appendWorldStrokeSegs(strokes[i], out, per)
        return out
    }
    // Implement recording point (behind tractor) for position marker on phone.
    readonly property var _implPos: RecordPoint.recordLocal(gps, app)
    // Temporary field diagnosis — flip on only when debugging paint on device.
    property bool mapDebugOverlay: false
    onRecorderChanged: map._paintTick++
    readonly property string debugLine: {
        var r = map.recorder
        var actN = 0
        var ptN = 0
        if (r && r.activeStrokes) {
            for (var i = 0; i < r.activeStrokes.length; ++i) {
                var st = r.activeStrokes[i]
                if (st && st.pts && st.pts.length >= 2)
                    actN++
                if (st && st.pts)
                    ptN += st.pts.length
            }
        }
        var _d = [map._paintTick, coverage.cellCount, coverage.areaHa].join("|")
        return "rec:" + (r ? "Y" : "N")
               + " act:" + actN + " pts:" + ptN
               + " done:" + (r ? r.doneCount : 0)
               + " ds:" + (r && r.doneStrokes ? r.doneStrokes.length : 0)
               + " area:" + Style.formatAreaHa(coverage.areaHa)
               + " cells:" + coverage.cellCount
               + " ck:" + coverage.chunkCount
               + " vis:" + map._visChunks.length
               + " cellp:" + map._visCellPaint.length
               + " swp:" + map._coveragePaintSegs.length
               + " row:" + map._rowMergeCells
               + " live:" + map._activePaintSegs.length
               + " mode:" + map.mode
    }
    Component.onCompleted: {
        if (map.chaseView)
            map.userZoom = map._chaseDefaultZoom
        map._ensureOrigin()
    }
    Timer {
        id: paintCoalesce
        interval: 180
        repeat: false
        onTriggered: {
            map._paintVersion = map.recorder ? map.recorder.activeVersion : 0
            map._paintTick++
        }
    }
    Connections {
        target: coverage
        // Every coverage.mark that adds a cell emits changed(). Rebuilding the
        // full cell-span paint list on each mark wedges the UI as cellCount
        // grows — coalesce to the same 250 ms paint tick as live strokes.
        function onChanged() {
            if (!paintCoalesce.running)
                paintCoalesce.start()
        }
    }
    Connections {
        target: map.recorder
        enabled: map.recorder !== null
        function onDoneCountChanged() {
            if (!paintCoalesce.running)
                paintCoalesce.start()
        }
        function onActiveVersionChanged() {
            if (!paintCoalesce.running)
                paintCoalesce.start()
        }
    }
    Connections {
        target: farm
        function onGeometryChanged() { map._ensureOrigin() }
        function onActiveChanged() { map._ensureOrigin() }
    }
    Connections {
        target: gps
        function onFixChanged() { map._healOriginIfGpsFarFromPaddock() }
    }

    // Full-bleed grey ground — never fall back to theme.bg (reads as flat black).
    Rectangle {
        anchors.fill: parent
        color: Style.ground
    }

    // Static ground fill below the horizon so chase tilt never exposes theme.bg.
    Rectangle {
        visible: map.chaseView
        x: 0
        y: map.horizonY
        width: parent.width
        height: Math.max(0, parent.height - map.horizonY)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Style.groundEdge }
            GradientStop { position: 0.5; color: Style.ground }
            GradientStop { position: 1.0; color: Style.groundEdge }
        }
    }

    Item {
        id: tiltContainer
        anchors.fill: parent
        transform: Rotation {
            origin.x: map.cx
            origin.y: map.cy
            axis.x: 1
            axis.y: 0
            axis.z: 0
            angle: map.tilt
        }

        Item {
            id: worldLayer
            transform: [
                Scale { xScale: map.viewScale; yScale: map.viewScale },
                Rotation { angle: map.viewRot },
                Translate { x: map.viewOffX; y: map.viewOffY }
            ]

            readonly property real _groundCx: map._covCenter.x
            readonly property real _groundCy: map._covCenter.y
            readonly property real _groundHalf: map.fitField && map.fb
                    ? Math.max(map._gridHalf,
                               Math.max(map.fb.maxx - map.fb.minx,
                                        map.fb.maxy - map.fb.miny) * 0.65 + 40)
                    : (map.chaseView
                       ? Math.max(map._gridHalf * 2.5, map._satChaseAheadM * 1.05)
                       : map._gridHalf * 2.5)

            Rectangle {
                x: worldLayer._groundCx - worldLayer._groundHalf
                y: worldLayer._groundCy - worldLayer._groundHalf
                width: worldLayer._groundHalf * 2
                height: worldLayer._groundHalf * 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Style.groundEdge }
                    GradientStop { position: 0.5; color: Style.ground }
                    GradientStop { position: 1.0; color: Style.groundEdge }
                }
                visible: map.chaseView || map.mode === 1 || map.fitField
            }
            Rectangle {
                x: worldLayer._groundCx - worldLayer._groundHalf
                y: worldLayer._groundCy - worldLayer._groundHalf
                width: worldLayer._groundHalf * 2
                height: worldLayer._groundHalf * 2
                color: theme.mapField
                visible: !map.chaseView && map.mode !== 1 && !map.fitField
            }
            Repeater {
                model: map._satTiles
                Image {
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.Stretch
                    source: modelData.path
                    sourceSize.width: 256
                    sourceSize.height: 256
                    readonly property var _nw: gps.toLocal(modelData.north, modelData.west)
                    readonly property var _se: gps.toLocal(modelData.south, modelData.east)
                    x: _nw.x
                    y: -_nw.y
                    width: Math.max(0.5, _se.x - _nw.x)
                    height: Math.max(0.5, _nw.y - _se.y)
                    opacity: 1.0
                }
            }
            Repeater {
                model: map._gridLines
                Rectangle {
                    x: map._gridStartX + index * map._gridStep - 0.125
                    y: map._gridStartY
                    width: 0.25; height: map._gridHalf * 2 + map._gridStep
                    color: Style.gridMinor; opacity: map._satTiles.length ? 0.18 : 0.35
                }
            }
            Repeater {
                model: map._gridLines
                Rectangle {
                    x: map._gridStartX
                    y: map._gridStartY + index * map._gridStep - 0.125
                    width: map._gridHalf * 2 + map._gridStep; height: 0.25
                    color: Style.gridMinor; opacity: map._satTiles.length ? 0.18 : 0.35
                }
            }

            // Cell spans only when swaths empty or paddock overview (avoids stair-steps).
            Repeater {
                model: (map.preferCellPaint
                        && (map.fitField || map._coveragePaintSegs.length < 1))
                       ? map._visCellPaint : []
                Rectangle {
                    x: modelData.x - 0.05
                    y: modelData.y - 0.05
                    width: modelData.w + 0.1
                    height: modelData.h + 0.1
                    color: "#883ddc84"
                }
            }

            // Boom-width square bars — solid painted strip (no stadium circles).
            Repeater {
                model: map.preferRectSwaths ? map._coveragePaintSegs : []
                Item {
                    x: modelData.x - modelData.w * 0.5
                    y: modelData.y - modelData.h * 0.5
                    width: modelData.w
                    height: modelData.h
                    rotation: modelData.rot
                    transformOrigin: Item.Center
                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: "#883ddc84"
                    }
                }
            }

            Shape {
                id: boundaryShape
                readonly property var ring: (gps.hasOrigin && farm.boundaryCount >= 3)
                                            ? map._mapRing(farm.activeBoundary, true) : []
                visible: ring.length >= 2
                ShapePath {
                    strokeColor: "#ff1aa3"
                    strokeWidth: boundaryShape.visible ? Math.max(0.5, 2.0 / map.viewScale) : 0
                    fillColor: "transparent"
                    PathPolyline { path: boundaryShape.visible ? boundaryShape.ring : [] }
                }
                Component.onDestruction: boundaryShape.visible = false
            }

            Shape {
                id: draftBoundaryShape
                readonly property var ring: (gps.hasOrigin && farm.boundaryDraftCount >= 2)
                                            ? map._mapRing(farm.boundaryDraftPoints,
                                                           !farm.boundaryRecording && farm.boundaryDraftCount >= 3)
                                            : []
                visible: ring.length >= 2
                ShapePath {
                    strokeColor: farm.boundaryRecording ? "#ffee00" : "#ffaa00"
                    strokeWidth: draftBoundaryShape.visible ? Math.max(0.8, 2.5 / map.viewScale) : 0
                    fillColor: "transparent"
                    PathPolyline { path: draftBoundaryShape.visible ? draftBoundaryShape.ring : [] }
                }
            }
        }
    }

    // Sky band above the horizon (drawn after world so it covers the top strip only).
    Rectangle {
        visible: map.chaseView
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: map.horizonY
        gradient: Gradient {
            GradientStop { position: 0.0; color: Style.skyTop }
            GradientStop { position: 1.0; color: Style.sky }
        }
    }
    Rectangle {
        visible: map.chaseView
        anchors.left: parent.left
        anchors.right: parent.right
        y: map.horizonY - 2
        height: 2
        color: Style.horizon
    }

    // Machine sprite + boom bar (same as tablet FieldView — not just GPS dots).
    Tractor {
        z: 5
        visible: gps.hasOrigin && map.s > 0.05
        heading: map.tractorRot
        width: Math.max(12, 3 * map.s)
        height: Math.max(24, 6 * map.s)
        x: map.tractorX - width / 2
        y: map.tractorY
    }

    Item {
        z: 4
        visible: !map.fitField && gps.hasOrigin
        anchors.fill: parent
        transform: Rotation {
            origin.x: map.cx
            origin.y: map.cy
            axis.x: 1; axis.y: 0; axis.z: 0
            angle: map.tilt
        }
        Item {
            id: implWorld
            transform: [
                Scale { xScale: map.viewScale; yScale: map.viewScale },
                Rotation { angle: map.viewRot },
                Translate { x: map.viewOffX; y: map.viewOffY }
            ]
            readonly property var rp: map._recordPoint()
            visible: implWorld.rp !== null

            Item {
                x: implWorld.rp ? implWorld.rp.x : 0
                y: implWorld.rp ? -implWorld.rp.y : 0
                rotation: gps.headingDeg

                Rectangle {
                    width: 0.4
                    height: app.recordOffsetM
                    x: -width / 2
                    y: -app.recordOffsetM
                    color: "#b9781b"
                }
                Repeater {
                    model: map.sectionCount
                    Rectangle {
                        readonly property real _w: map._secW(index)
                        width: _w
                        height: 1.0
                        x: map._secCenter(index) - _w / 2
                        y: -0.5
                        color: app.recordingCoverage ? "#f0a330" : "#5a5a5a"
                        border.color: "#7a5212"
                        border.width: 0.05
                    }
                }
            }
        }
    }

    // Pan (whole-paddock) or break-follow drag (chase/top-down)
    MouseArea {
        id: panMa
        anchors.fill: parent
        property real _sx: 0
        property real _sy: 0
        property real _bx: 0
        property real _by: 0
        property real _pendingPanX: 0
        property real _pendingPanY: 0
        Timer {
            id: panThrottle
            interval: 32
            repeat: false
            onTriggered: {
                map.panX = panMa._pendingPanX
                map.panY = panMa._pendingPanY
            }
        }
        onPressed: {
            _sx = mouse.x; _sy = mouse.y
            _bx = map.panX; _by = map.panY
            panThrottle.stop()
            if (!map.fitField) {
                map._anchorX = gps.localX
                map._anchorY = gps.localY
            }
        }
        onReleased: {
            panThrottle.stop()
            map.panX = _pendingPanX
            map.panY = _pendingPanY
        }
        onPositionChanged: {
            if (!map.fitField) map.following = false
            _pendingPanX = _bx + (mouse.x - _sx)
            _pendingPanY = _by + (mouse.y - _sy)
            if (!panThrottle.running)
                panThrottle.start()
            else
                panThrottle.restart()
        }
    }

    // Empty state hint
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: zoomRow.top
        anchors.bottomMargin: 12
        visible: farm.boundaryCount < 3 && coverage.cellCount === 0
                 && (!recorder || recorder.doneCount === 0)
        text: qsTr("No paddock boundary — drive to record coverage")
        color: theme.textDim
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        width: parent.width * 0.85
        horizontalAlignment: Text.AlignHCenter
    }

    // Recording feedback when GPS is not ready or operator is stationary.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: zoomRow.top
        anchors.bottomMargin: 12
        visible: app.recordingCoverage && !gps.hasFix
        text: qsTr("Waiting for GPS fix to record")
        color: "#f1c40f"
        font.pixelSize: 13
        font.bold: true
        wrapMode: Text.WordWrap
        width: parent.width * 0.85
        horizontalAlignment: Text.AlignHCenter
        z: 6
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: zoomRow.top
        anchors.bottomMargin: 12
        visible: app.recordingCoverage && gps.hasFix && coverage.cellCount === 0
        text: qsTr("Drive to mark coverage")
        color: theme.textDim
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        width: parent.width * 0.85
        horizontalAlignment: Text.AlignHCenter
        z: 6
    }

    Row {
        id: zoomRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(4, map.bottomChromeInset - 46)
        spacing: map._phoneLayout ? 12 : 24
        z: 6
        readonly property int _btn: map._phoneLayout ? 46 : 56
        Rectangle {
            width: zoomRow._btn; height: zoomRow._btn; radius: zoomRow._btn / 2
            color: zoomOutMa.pressed ? theme.bannerHi : theme.panel
            border.color: theme.panelEdge
            Text { anchors.centerIn: parent; text: "−"; color: theme.text; font.pixelSize: 28; font.bold: true }
            MouseArea { id: zoomOutMa; anchors.fill: parent; onClicked: map.zoomOut() }
        }
        Rectangle {
            visible: !map.following && !map.fitField
            width: zoomRow._btn; height: zoomRow._btn; radius: zoomRow._btn / 2
            color: recMa.pressed ? theme.bannerHi : theme.panel
            border.color: theme.accent
            Text { anchors.centerIn: parent; text: "◎"; color: theme.accent; font.pixelSize: 22 }
            MouseArea { id: recMa; anchors.fill: parent; onClicked: map.recenter() }
        }
        Rectangle {
            width: zoomRow._btn; height: zoomRow._btn; radius: zoomRow._btn / 2
            color: zoomInMa.pressed ? theme.bannerHi : theme.panel
            border.color: theme.panelEdge
            Text { anchors.centerIn: parent; text: "+"; color: theme.text; font.pixelSize: 28; font.bold: true }
            MouseArea { id: zoomInMa; anchors.fill: parent; onClicked: map.zoomIn() }
        }
        Rectangle {
            width: recordBtnMa.width + (map._phoneLayout ? 16 : 24)
            height: zoomRow._btn
            radius: zoomRow._btn / 2
            color: app.recordingCoverage
                   ? (recordBtnMa.pressed ? "#922b21" : "#c0392b")
                   : (recordBtnMa.pressed ? theme.bannerHi : theme.panel)
            border.color: app.recordingCoverage ? "#641e16" : theme.accent
            Row {
                id: recordBtnMa
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    visible: app.recordingCoverage
                    width: 8; height: 8; radius: 4
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        running: app.recordingCoverage
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.25; duration: 600 }
                        NumberAnimation { from: 0.25; to: 1; duration: 600 }
                    }
                }
                Text {
                    text: app.recordingCoverage ? qsTr("STOP") : qsTr("RECORD")
                    color: app.recordingCoverage ? "#ffffff" : theme.accent
                    font.pixelSize: 13
                    font.bold: true
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (app.recordingCoverage)
                        map.stopRecordDialog.open()
                    else
                        app.setRecording(true)
                }
            }
        }
    }
}
