import QtQuick 2.15
import QtQuick.Shapes 1.15
import "Style.js" as Style
import "Icons.js" as Icons

// Heading-up field view. Tractor locked centre pointing up; ground + coverage
// pan/rotate underneath. Coverage is recorded per-section at the implement
// (set back behind the tractor), with true non-overlapping area + section control.
Item {
    id: field
    clip: true

    property int mode: 1
    readonly property var modeNames: ["Top-down", "Chase", "Whole paddock"]

    // Whole-paddock (mode 2) = top-down, north-up, framed to the field. Frames the
    // boundary when there is one, else falls back to the worked coverage, else a
    // default span around the origin (see _fitScale / _fitBounds).
    readonly property bool fitField: mode === 2 && gps.hasOrigin

    // Chase tuned shallow (long view down the rows). Top-down + paddock = flat.
    property real tilt: mode === 1 ? 74 : 0
    property real userZoom: 1.0
    // Free pan / follow state. While `following` the view stays locked on the
    // tractor; the first drag clears it (freezing the view at the tractor anchor)
    // and the centre button re-arms follow. panX/panY are screen-space px added to
    // the view translate (applied after rotation), so a drag moves the map 1:1.
    property bool following: true
    property real panX: 0
    property real panY: 0
    property real _anchorX: 0
    property real _anchorY: 0
    // TEMP boundary diagnostics — on-screen readout to trace why the paddock
    // boundary may not render. Toggle _dbgOn off / remove once root-caused.
    property bool _dbgOn: false
    property string _dbgEnsure: "(not run)"
    // Default framing: at userZoom 1 the bottom edge sits ~80 m behind the
    // implement. Derived from the live screen size so it fits any tablet.
    readonly property real _frameMetres: app.implementOffset + 80
    readonly property real _framePx: Math.max(40, height - cy)
    readonly property real _baseScale: _framePx / Math.max(20, _frameMetres)

    Behavior on tilt { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
    Behavior on userZoom {
        enabled: !pinchArea.pinch.active     // crisp during pinch; smooth on +/- taps
        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
    }
    onModeChanged: { userZoom = 1.0; panX = 0; panY = 0; following = true }

    readonly property real cx: width / 2
    readonly property real cy: height * (mode === 1 ? 0.74 : 0.5)
    readonly property real horizonY: mode === 1 ? height * 0.34 : 0
    readonly property int sectionCount: app.sectionCount

    // ---- Geometry safety limits (Mali-400 GL ES2 hardening) ----
    // A local coordinate beyond this magnitude (metres from the origin) can only
    // come from a corrupt origin (e.g. a stale job whose metadata.json carries a
    // 0/garbage originLat/Lon) or a stray KML vertex. Such huge-but-finite values
    // pass an isFinite() guard yet overflow / segfault the GL ES2 triangulator, so
    // they are dropped rather than rendered. 200 km is far larger than any paddock.
    readonly property real _maxLocalM: 200000
    // A scanned/traced KML ring can carry thousands of vertices; a filled concave
    // polygon that large chokes the Mali-400. Decimate before it reaches a Shape.
    readonly property int _maxRingVerts: 1000
    // Above this vertex count the boundary is drawn as an outline only (no fill):
    // filling a large/complex ring triangulates on the UI thread and can wedge the
    // GL ES backend. The stroked outline is cheap and is what the operator needs.
    readonly property int _maxFillVerts: 200

    // True if a WGS84 lat/lon pair is finite, in range, and not the (0,0) sentinel
    // that older/aborted saves write when no real origin had been captured.
    function _validLatLon(la, lo) {
        return (typeof la === "number" && typeof lo === "number"
                && isFinite(la) && isFinite(lo)
                && la >= -90 && la <= 90 && lo >= -180 && lo <= 180
                && !(Math.abs(la) < 1e-7 && Math.abs(lo) < 1e-7));
    }

    // Mean WGS84 position of the active boundary, used as a self-heal origin when a
    // job's stored origin is missing/corrupt so the local frame can never go huge.
    function _boundaryCentroid() {
        var b = farm.activeBoundary;
        if (!b || b.length < 3) return null;
        var sLat = 0, sLon = 0, n = 0;
        for (var i = 0; i < b.length; ++i) {
            if (!field._validLatLon(b[i].lat, b[i].lon)) continue;
            sLat += b[i].lat; sLon += b[i].lon; ++n;
        }
        if (n < 1) return null;
        return { lat: sLat / n, lon: sLon / n };
    }

    // Stride-decimate a point array down to maxN, keeping the first + last vertex.
    function _decimate(pts, maxN) {
        var n = pts.length;
        if (n <= maxN || maxN < 2) return pts;
        var step = Math.ceil(n / maxN);
        var out = [];
        for (var i = 0; i < n; i += step) out.push(pts[i]);
        if ((n - 1) % step !== 0) out.push(pts[n - 1]);
        return out;
    }

    // Active-field bounds in world coords (x=east, y=-north) for fit mode. Drops
    // non-finite and out-of-band (corrupt-origin) vertices so the fit-to-screen
    // scale can never be derived from a garbage extent. Returns null if too few
    // valid vertices remain to fit.
    function _fieldBounds() {
        var b = farm.activeBoundary;
        if (!gps.hasOrigin || !b || b.length < 3) return null;
        var lim = field._maxLocalM;
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18, n = 0;
        for (var i = 0; i < b.length; ++i) {
            var p = gps.toLocal(b[i].lat, b[i].lon);
            if (!isFinite(p.x) || !isFinite(p.y)) continue;
            if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue;
            var wx = p.x, wy = -p.y;
            if (wx < minx) minx = wx; if (wx > maxx) maxx = wx;
            if (wy < miny) miny = wy; if (wy > maxy) maxy = wy;
            ++n;
        }
        if (n < 3) return null;
        return { minx: minx, miny: miny, maxx: maxx, maxy: maxy };
    }
    // Whole-field bounds: the boundary if there is one, else the worked coverage.
    // Both are in world coords (x=east, y=-north), consistent with _fieldBounds().
    function _coverageBounds() {
        var arr = field.doneStrokes;
        if (!arr || !arr.length) return null;
        var lim = field._maxLocalM;
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18, n = 0;
        for (var i = 0; i < arr.length; ++i) {
            var st = arr[i];
            if (!st || !st.pts) continue;
            for (var j = 0; j < st.pts.length; ++j) {
                var p = st.pts[j];
                if (!isFinite(p.x) || !isFinite(p.y)) continue;
                if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue;
                if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x;
                if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y;
                ++n;
            }
        }
        if (n < 2) return null;
        return { minx: minx, miny: miny, maxx: maxx, maxy: maxy };
    }
    function _fitBounds() {
        var b = field._fieldBounds();
        if (b) return b;
        return field._coverageBounds();
    }
    readonly property var fb: fitField ? _fitBounds() : null

    // Fit scale frames the whole field with ~8% padding; falls back to the driving
    // base scale when there is nothing to frame (no boundary/coverage yet).
    readonly property real _fitScale: {
        if (!fb) return _baseScale;
        var w = Math.max(1, fb.maxx - fb.minx);
        var h = Math.max(1, fb.maxy - fb.miny);
        return Math.min(width * 0.84 / w, height * 0.84 / h);
    }
    // Unified view transform. userZoom multiplies the driving or fit base so +/-
    // and pinch work in every mode; the result is clamped so it spans a whole
    // 1000 ha block out to a few metres across without going degenerate.
    readonly property real viewScale: {
        var base = fitField ? _fitScale : _baseScale;
        return Math.max(0.02, Math.min(400, base * userZoom));
    }
    readonly property real s: viewScale                       // px per metre (alias)
    readonly property real viewRot: fitField ? 0 : -gps.headingDeg
    readonly property real viewOffX: {
        if (fitField && fb) return width / 2 - viewScale * (fb.minx + fb.maxx) / 2 + panX;
        var a = viewRot * Math.PI / 180;
        var cwx = following ? gps.localX : _anchorX;
        var cwy = following ? gps.localY : _anchorY;
        var csx = cwx * viewScale, csy = -cwy * viewScale;
        return cx - (csx * Math.cos(a) - csy * Math.sin(a)) + panX;
    }
    readonly property real viewOffY: {
        if (fitField && fb) return height / 2 - viewScale * (fb.miny + fb.maxy) / 2 + panY;
        var a = viewRot * Math.PI / 180;
        var cwx = following ? gps.localX : _anchorX;
        var cwy = following ? gps.localY : _anchorY;
        var csx = cwx * viewScale, csy = -cwy * viewScale;
        return cy - (csx * Math.sin(a) + csy * Math.cos(a)) + panY;
    }
    // World (east, north) <-> screen helpers using the live transform, so the
    // run-line culling and the tractor sprite stay correct under pan/zoom/rotate.
    function _worldToScreenX(e, n) {
        var a = field.viewRot * Math.PI / 180;
        var wx = e * field.viewScale, wy = -n * field.viewScale;
        return field.viewOffX + (wx * Math.cos(a) - wy * Math.sin(a));
    }
    function _worldToScreenY(e, n) {
        var a = field.viewRot * Math.PI / 180;
        var wx = e * field.viewScale, wy = -n * field.viewScale;
        return field.viewOffY + (wx * Math.sin(a) + wy * Math.cos(a));
    }
    function _screenToWorld(sx, sy) {
        var a = field.viewRot * Math.PI / 180;
        var dx = sx - field.viewOffX, dy = sy - field.viewOffY;
        var rx = dx * Math.cos(a) + dy * Math.sin(a);
        var ry = -dx * Math.sin(a) + dy * Math.cos(a);
        var sc = Math.max(0.0001, field.viewScale);
        return { e: rx / sc, n: -(ry / sc) };
    }
    // Tractor screen position: derived from its world point so it is correct
    // whether following (locked centre), fitted, or panned off-centre.
    readonly property real tractorX: field._worldToScreenX(gps.localX, gps.localY)
    readonly property real tractorY: field._worldToScreenY(gps.localX, gps.localY)
    readonly property real tractorRot: fitField ? gps.headingDeg : 0

    function cyclePerspective() { mode = (mode + 1) % 3 }
    function zoomIn()  { userZoom = Math.min(80.0, userZoom * 1.2) }
    function zoomOut() { userZoom = Math.max(0.03, userZoom / 1.2) }
    function recenter() { userZoom = 1.0; panX = 0; panY = 0; following = true }
    function compass(deg) {
        var dirs = ["N","NE","E","SE","S","SW","W","NW"];
        return dirs[Math.round((deg % 360) / 45) % 8];
    }

    // ---- Coverage (per section) ----
    // Frozen chunks are triangulated once and never touched again; only the
    // small active chunk per section is re-evaluated each fix. This keeps the
    // per-fix render cost flat regardless of how much has been covered.
    property var doneStrokes: []    // frozen chunks {w, pts}; mutated in place (push)
    property int doneCount: 0
    property var activeStrokes: []  // per-section growing chunk {w, pts} or null
    property var sectionOn: []      // bool per section (bar state)
    property int activeVersion: 0
    // Paint refresh is throttled separately so GPS fixes can mark cells without
    // retessellating PathPolyline/Shape on the Mali-400 every fix (UI wedge).
    property int _paintVersion: 0
    property real _lastRx: NaN
    property real _lastRy: NaN
    property var _replayMarks: []
    property int _replayMarkIdx: 0
    readonly property int _chunkMax: 150
    // Identity of the job currently loaded into the coverage layer, so it can be
    // saved (under the right field) when the field is switched or work stops.
    property var _jobId: ({ fieldId: "", fieldName: "", farmId: "", farmName: "",
                            clientId: "", clientName: "" })

    function _nulls(n) { var a = []; for (var i = 0; i < n; ++i) a.push(null); return a; }

    // Per-section width + centre offset (metres, +x = machine right) from the boom
    // centre, honouring custom (asymmetric) section widths. Index 0 is the left-most
    // section so it lines up with the John Deere L../C/R.. labelling.
    function _secW(i) {
        var ws = app.sectionWidths;
        if (ws && i >= 0 && i < ws.length) return ws[i];
        return app.implementWidth / Math.max(1, field.sectionCount);
    }
    function _secCenter(i) {
        var cum = -app.implementWidth / 2;
        for (var k = 0; k < i; ++k) cum += field._secW(k);
        return cum + field._secW(i) / 2;
    }

    function clearCoverage() { coverage.reset(); }

    // World bbox (east, -north) of a chunk's points, padded by the swath width so
    // a chunk whose centreline is just off the view rect but whose edge is inside
    // still renders. Used to register the chunk in the coverage spatial index.
    function _chunkBbox(pts, pad) {
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18;
        for (var i = 0; i < pts.length; ++i) {
            var p = pts[i];
            if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x;
            if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y;
        }
        return { minx: minx - pad, miny: miny - pad, maxx: maxx + pad, maxy: maxy + pad };
    }

    function _freeze(st) {
        if (st && st.pts && st.pts.length >= 2) {
            var b = field._chunkBbox(st.pts, st.w || 0);
            st.bbox = b;
            coverage.addChunkBox(b.minx, b.miny, b.maxx, b.maxy);
            field.doneStrokes.push(st);
            field.doneCount++;
        }
    }
    function _freezeAllActive() {
        for (var i = 0; i < field.activeStrokes.length; ++i) field._freeze(field.activeStrokes[i]);
        field.activeStrokes = field._nulls(field.activeStrokes.length);
        field.activeVersion++;
        field._paintVersion = field.activeVersion;
    }

    // Mali-safe stroke tessellation (same approach as PhoneMapView._covPaintSegs).
    function _appendWorldStrokeSegs(st, out, maxN) {
        if (!st || !st.pts || st.pts.length < 1 || out.length >= maxN)
            return;
        var halfW = Math.max(0.25, (st.w || app.implementWidth) * 0.5);
        var pts = st.pts;
        var step = pts.length > 120 ? Math.ceil(pts.length / 120) : 1;
        for (var j = 0; j < pts.length; j += step) {
            if (out.length >= maxN)
                break;
            var p = pts[j];
            out.push({ x: p.x, y: p.y, w: halfW * 2, h: halfW * 2, rot: 0 });
        }
        for (var k = 0; k < pts.length - 1; k += step) {
            if (out.length >= maxN)
                break;
            var p0 = pts[k], p1 = pts[k + 1];
            var dx = p1.x - p0.x, dy = p1.y - p0.y;
            var len = Math.sqrt(dx * dx + dy * dy);
            if (len < 0.05)
                continue;
            out.push({
                x: (p0.x + p1.x) * 0.5,
                y: (p0.y + p1.y) * 0.5,
                w: len + halfW * 2,
                h: halfW * 2,
                rot: Math.atan2(dy, dx) * 180 / Math.PI
            });
        }
    }
    function _strokesForActivePaint() {
        var out = [];
        if (!field.activeStrokes)
            return out;
        for (var i = 0; i < field.activeStrokes.length; ++i) {
            var st = field.activeStrokes[i];
            if (st && st.pts && st.pts.length >= 2)
                out.push(st);
        }
        return out;
    }
    readonly property var _activePaintSegs: {
        var strokes = field._strokesForActivePaint();
        var _dep = [field._paintVersion, strokes.length].join("|");
        var out = [];
        var maxSeg = 240;
        for (var i = 0; i < strokes.length && out.length < maxSeg; ++i)
            field._appendWorldStrokeSegs(strokes[i], out, maxSeg);
        return out;
    }

    Timer {
        id: paintCoalesce
        interval: 250
        repeat: false
        onTriggered: { field._paintVersion = field.activeVersion; }
    }
    Timer {
        id: coverageReplayTimer
        interval: 16
        repeat: true
        onTriggered: {
            var end = Math.min(field._replayMarkIdx + 80, field._replayMarks.length);
            for (var i = field._replayMarkIdx; i < end; ++i) {
                var m = field._replayMarks[i];
                coverage.mark(m.x, m.y, m.hdg, m.w);
            }
            field._replayMarkIdx = end;
            if (field._replayMarkIdx >= field._replayMarks.length) {
                coverageReplayTimer.stop();
                field._replayMarks = [];
            }
        }
    }

    Connections {
        target: coverage
        function onCleared() {
            field.doneStrokes = []; field.doneCount = 0;
            field.activeStrokes = []; field.sectionOn = [];
            field.activeVersion++;
        }
    }

    Connections {
        target: app
        function onRecordingChanged() {
            if (app.recordingCoverage) {
                // Seed the last record point so the next fix does not treat the
                // whole world as "moved" (the old 1e9 sentinel forced an immediate
                // mark + GL retessellate on arm, wedging Mali on a parked machine).
                var rp = field._recordPoint();
                if (rp) {
                    field._lastRx = rp.x;
                    field._lastRy = rp.y;
                } else {
                    field._lastRx = NaN;
                    field._lastRy = NaN;
                }
            } else {
                field._lastRx = NaN;
                field._lastRy = NaN;
                field._freezeAllActive();       // close open chunks; lift implement
                field.sectionOn = [];
                // Persist off the hot path — GeoJSON serialisation can block the UI
                // on a large job when Stop is tapped on a slow tablet.
                Qt.callLater(field.saveActiveJob);
            }
        }
    }

    // ---- Rx (prescription) live target rate ----
    // The application may carry an Rx descriptor (rateMode == "rx"); keep the `rx`
    // model loaded from it so the target rate can be looked up by GPS position. A
    // flat rate is taken straight from the application's product/mix. The target
    // rate is DISPLAYED live and LOGGED per worked chunk (as-applied target). There
    // is no rate-controller feedback wired yet, so "actual" rate is a future hook
    // (see _coverageGeoJson: actual_rate is intentionally not emitted).
    readonly property var _appRx: (app.application && app.application.rateMode === "rx"
                                   && app.application.rx) ? app.application.rx : null
    property real _targetRate: 0
    property string _targetUnit: ""
    property bool _inZone: false

    function _flatRate() {
        var a = app.application;
        if (!a) return { v: 0, u: "" };
        if (a.kind === "mix" && a.mix) return { v: a.mix.rateHa || 0, u: a.mix.unit || "" };
        if (a.product) return { v: a.product.rate || 0, u: a.product.unit || "" };
        return { v: 0, u: "" };
    }
    function _updateTargetRate() {
        if (field._appRx) {
            field._targetUnit = field._appRx.unit ? field._appRx.unit : rx.unit;
            if (gps.hasFix) {
                field._inZone = rx.inAnyZone(gps.latitude, gps.longitude);
                field._targetRate = rx.rateAt(gps.latitude, gps.longitude);
            } else {
                field._inZone = false;
                field._targetRate = rx.noGpsRate;   // no-GPS fallback rate
            }
        } else {
            var f = field._flatRate();
            field._targetRate = f.v; field._targetUnit = f.u; field._inZone = true;
        }
    }

    Connections {
        target: app
        function onApplicationChanged() {
            // (Re)load the prescription zones so live lookup works after resume /
            // new job; reload only when the source shapefile changes.
            if (field._appRx && rx.sourceFile !== field._appRx.file)
                rx.loadFromDescriptor(field._appRx);
            field._updateTargetRate();
        }
    }

    // Rx target rate follows GPS; flat rate is constant until application changes.
    Connections {
        target: gps
        function onFixChanged() {
            if (field._appRx)
                field._updateTargetRate();
        }
    }

    // Tilt-corrected, set-back implement recording point in world metres
    // (x=east, y=north). Two corrections vs the raw antenna position:
    //   1) TCM terrain compensation — the GPS antenna rides high on the machine,
    //      so when it tilts the antenna shifts off the true ground point under it.
    //      Project it back down using roll/pitch and the antenna height:
    //      lateral ≈ h·sin(roll), longitudinal ≈ h·sin(pitch), rotated by heading.
    //   2) Implement set-back — the boom records implementOffset metres behind the
    //      tractor (aligned with the boom bar drawn behind the machine).
    // The map keeps the antenna at screen centre; only this recorded point moves.
    function _recordPoint() {
        var hr = gps.headingDeg * Math.PI / 180;
        var sinH = Math.sin(hr), cosH = Math.cos(hr);
        var gx = gps.localX, gy = gps.localY;
        var h = app.antennaHeight;
        if (gps.hasAttitude && h > 0.01) {
            // Clamp to a sane envelope so a bad TCM decode can't fling the point.
            var roll = Math.max(-30, Math.min(30, gps.rollDeg)) * Math.PI / 180;
            var pitch = Math.max(-30, Math.min(30, gps.pitchDeg)) * Math.PI / 180;
            var latOff = h * Math.sin(roll);   // antenna right of the ground point
            var lonOff = h * Math.sin(pitch);  // antenna ahead of the ground point
            // right (east,north) = (cosH, -sinH); forward (east,north) = (sinH, cosH)
            gx -= latOff * cosH + lonOff * sinH;
            gy -= latOff * (-sinH) + lonOff * cosH;
        }
        var off = app.implementOffset;
        var px = gx - off * sinH, py = gy - off * cosH;
        // A non-finite result (bad heading/attitude decode) must never reach the
        // coverage grid or a stroke point array — signal "no point" instead.
        if (!isFinite(px) || !isFinite(py))
            return null;
        return { x: px, y: py };
    }

    // ---- Job coverage persistence (re-enterable work) ----
    // Serialise the worked swaths to a WGS84 GeoJSON FeatureCollection (one
    // LineString per frozen chunk, width_m property). World-referenced so it
    // re-aligns across sessions and is ready for a future upload/sync system.
    function _coverageGeoJson() {
        field._freezeAllActive();   // close any open chunk so it is included
        var feats = [];
        for (var i = 0; i < field.doneStrokes.length; ++i) {
            var st = field.doneStrokes[i];
            if (!st || !st.pts || st.pts.length < 2)
                continue;
            var coords = [];
            for (var j = 0; j < st.pts.length; ++j) {
                // stored points are (east, -north) metres in the local frame
                var g = gps.toGeo(st.pts[j].x, -st.pts[j].y);
                coords.push([g.lon, g.lat]);
            }
            var props = { width_m: st.w };
            // As-applied target rate logged per chunk (Rx lookup or flat rate at the
            // time it was laid). actual_rate is omitted: no rate-controller feedback
            // is wired yet — that is the future hardware hook.
            if (st.tr !== undefined && st.tr > 0) {
                props.target_rate = st.tr;
                props.rate_unit = st.tu ? st.tu : "";
            }
            feats.push({ type: "Feature",
                         geometry: { type: "LineString", coordinates: coords },
                         properties: props });
        }
        return JSON.stringify({ type: "FeatureCollection", features: feats });
    }

    // Rebuild the swaths (and the coverage cells that drive area + section
    // control) from a GeoJSON FeatureCollection. Requires the origin to be set.
    function _loadCoverageGeoJson(text) {
        if (!text || !text.length || !gps.hasOrigin)
            return;
        var fc;
        try { fc = JSON.parse(text); } catch (e) { return; }
        if (!fc || !fc.features)
            return;
        var done = [];
        var marks = [];
        for (var i = 0; i < fc.features.length; ++i) {
            var ft = fc.features[i];
            if (!ft || !ft.geometry || ft.geometry.type !== "LineString")
                continue;
            var w = (ft.properties && ft.properties.width_m)
                    ? ft.properties.width_m : (app.implementWidth / field.sectionCount);
            var cs = ft.geometry.coordinates;
            if (!cs || !cs.length)
                continue;
            var pts = [], locals = [];
            for (var j = 0; j < cs.length; ++j) {
                var c = cs[j];
                if (!c || c.length < 2)
                    continue;
                var p = gps.toLocal(c[1], c[0]);   // (lat, lon) -> (east, north)
                if (!isFinite(p.x) || !isFinite(p.y))
                    continue;
                // Drop swath points flung off the local frame by a wrong/corrupt
                // origin so an enormous polyline never reaches the GL ES2 backend.
                if (Math.abs(p.x) > field._maxLocalM || Math.abs(p.y) > field._maxLocalM)
                    continue;
                pts.push(Qt.point(p.x, -p.y));
                locals.push(p);
            }
            if (pts.length < 2)
                continue;
            var bb = field._chunkBbox(pts, w);
            var tr = (ft.properties && ft.properties.target_rate) ? ft.properties.target_rate : undefined;
            var tu = (ft.properties && ft.properties.rate_unit) ? ft.properties.rate_unit : undefined;
            done.push({ w: w, pts: pts, bbox: bb, tr: tr, tu: tu });
            coverage.addChunkBox(bb.minx, bb.miny, bb.maxx, bb.maxy);
            // Queue cell replay — synchronous coverage.mark over a large resumed
            // job blocks the UI thread and looks like a record-start freeze.
            for (var k = 0; k < locals.length; ++k) {
                var a = locals[k];
                var b = locals[Math.min(k + 1, locals.length - 1)];
                var de = b.x - a.x, dn = b.y - a.y;
                var hdg = (de === 0 && dn === 0) ? gps.headingDeg
                                                 : Math.atan2(de, dn) * 180 / Math.PI;
                marks.push({ x: a.x, y: a.y, hdg: hdg, w: w });
            }
        }
        field.doneStrokes = done;
        field.doneCount = done.length;
        field.activeStrokes = [];
        field.activeVersion++;
        field._paintVersion = field.activeVersion;
        field._replayMarks = marks;
        field._replayMarkIdx = 0;
        if (marks.length)
            coverageReplayTimer.start();
    }

    function _saveJob(id) {
        if (!id || !id.fieldId || !id.fieldId.length || !gps.hasOrigin)
            return;
        var meta = {
            fieldId: id.fieldId, fieldName: id.fieldName,
            farmId: id.farmId, farmName: id.farmName,
            clientId: id.clientId, clientName: id.clientName,
            trackName: app.trackName,
            areaHa: coverage.areaHa,
            implementWidthM: app.implementWidth,
            implementOffsetM: app.implementOffset,
            antennaHeightM: app.antennaHeight,
            originLat: gps.originLat(), originLon: gps.originLon(),
            source: app.activeSource
        };
        if (app.application && Object.keys(app.application).length > 0)
            meta.application = app.application;
        jobs.saveJob(meta, field._coverageGeoJson());
    }

    function saveActiveJob() { field._saveJob(field._jobId); }

    // Apply a job's stored local-frame origin, but ONLY if it is finite, in range
    // and not the (0,0) sentinel. A bad origin would make every boundary/coverage
    // vertex resolve to millions of metres and crash the Mali-400. Returns whether
    // a valid origin was applied.
    function _applyJobOrigin(meta) {
        if (!meta)
            return false;
        if (!field._validLatLon(meta.originLat, meta.originLon))
            return false;
        gps.setOrigin(meta.originLat, meta.originLon);
        return true;
    }

    function restoreActiveJob() {
        var fid = field._jobId.fieldId;
        if (!fid || !fid.length)
            return;
        // Quarantine unreadable/corrupt job data instead of letting it throw up to
        // QML: any failure here just means "no resumable coverage", never a crash.
        var hasJob = false;
        try { hasJob = jobs.hasJob(fid); } catch (e) { hasJob = false; }
        if (!hasJob)
            return;
        var meta = null;
        try { meta = jobs.jobMeta(fid); } catch (e) { meta = null; }
        if (!field._applyJobOrigin(meta)) {
            // Self-heal: the stored origin is missing/corrupt. Derive a sane origin
            // from the boundary centroid so stored coverage still lines up roughly
            // and the local frame stays small/finite. If there is no usable
            // boundary either, leave the origin to the first live GPS fix.
            var c = field._boundaryCentroid();
            if (c)
                gps.setOrigin(c.lat, c.lon);
        }
        coverage.reset();    // clears cells + (via onCleared) the swath layer
        var cov = "";
        try { cov = jobs.loadCoverage(fid); } catch (e) { cov = ""; }
        field._loadCoverageGeoJson(cov);
    }

    // If no origin has been established yet (no live fix, no resumable job
    // origin), derive one from the active boundary centroid so the boundary and
    // the whole-paddock fit render immediately for a freshly imported field. The
    // local frame stays small/finite and the first live GPS fix is then drawn
    // relative to this origin (same as re-entering a saved job). Mirrors the
    // self-heal already used in restoreActiveJob().
    function _ensureOrigin() {
        // Only keep a genuinely good origin: a live GPS fix or a previously
        // derived boundary centroid (finite, in range, not the 0,0 sentinel).
        // A 0,0 / out-of-range / non-finite origin is treated as "not set" and
        // re-derived from the boundary — this is the recurring boundary failure:
        // setActiveField emits activeChanged before geometryChanged, so an early
        // self-heal could miss the ring, leaving the origin at 0,0 with the
        // boundary clamped out by _maxLocalM. Healing on every invalid origin
        // (and re-running on geometryChanged below) closes that race without ever
        // clobbering a valid live-fix origin.
        if (gps.hasOrigin && field._validLatLon(gps.originLat(), gps.originLon())) {
            if (field._dbgOn)
                field._dbgEnsure = "skip: valid origin "
                                   + gps.originLat().toFixed(6) + "," + gps.originLon().toFixed(6);
            return;
        }
        var c = field._boundaryCentroid();
        if (c) {
            gps.setOrigin(c.lat, c.lon);
            if (field._dbgOn)
                field._dbgEnsure = "healed centroid " + c.lat.toFixed(6) + "," + c.lon.toFixed(6)
                                   + " -> hasOrigin=" + gps.hasOrigin;
        } else if (field._dbgOn) {
            field._dbgEnsure = "no centroid (boundaryCount=" + farm.boundaryCount + ")";
        }
    }

    // Sync the loaded coverage to the active field: save the outgoing job, then
    // load the incoming one (re-entry). Called on field switch + at startup.
    function _syncActiveField() {
        var nf = { fieldId: farm.activeFieldId, fieldName: farm.activeFieldName,
                   farmId: farm.activeFarmId, farmName: farm.activeFarmName,
                   clientId: farm.activeClientId, clientName: farm.activeClientName };
        if (nf.fieldId === field._jobId.fieldId)
            return;
        if (field._jobId.fieldId.length && gps.hasOrigin && field.doneCount > 0)
            field._saveJob(field._jobId);
        coverage.reset();
        field._jobId = nf;
        app.clearApplication();
        if (nf.fieldId.length) {
            field.restoreActiveJob();
            field._ensureOrigin();
            var m = null;
            try { m = jobs.jobMeta(nf.fieldId); } catch (e) { m = null; }
            if (m && m.application)
                app.setApplication(m.application);
        }
    }

    Component.onCompleted: field._syncActiveField()

    Connections {
        target: farm
        function onActiveChanged() { field._syncActiveField(); }
        // setActiveField emits activeChanged before geometryChanged, and a freshly
        // imported/edited field's ring may only resolve here. Re-run the self-heal
        // once geometry is available so an invalid (0,0) origin is replaced by the
        // boundary centroid even with no live GPS fix. Idempotent: a valid origin
        // is left untouched.
        function onGeometryChanged() { field._ensureOrigin(); }
    }

    Connections {
        target: jobs
        function onSaveRequested() { field.saveActiveJob(); }
        function onNewRequested() {
            jobs.startNewJob(field._jobId.fieldId);
            coverage.reset();
        }
    }

    Connections {
        target: gps
        function onFixChanged() {
            if (!app.recordingCoverage || !gps.hasOrigin)
                return;
            var hr = gps.headingDeg * Math.PI / 180;
            // recording point: terrain-compensated + behind the tractor along travel
            var rp = field._recordPoint();
            if (!rp)
                return;
            var rx = rp.x, ry = rp.y;
            if (!isFinite(field._lastRx) || !isFinite(field._lastRy)) {
                field._lastRx = rx;
                field._lastRy = ry;
                return;
            }
            var dx = rx - field._lastRx, dy = ry - field._lastRy;
            if (dx * dx + dy * dy < 0.25)   // >= 0.5 m
                return;
            field._lastRx = rx; field._lastRy = ry;

            // Target rate active at this point (Rx lookup or flat), tagged onto any
            // chunk started here so the as-applied record carries the target rate.
            field._updateTargetRate();
            var tgt = field._targetRate, tgu = field._targetUnit;

            var N = field.sectionCount;
            var rex = Math.cos(hr), rny = -Math.sin(hr);  // right (east,north)
            if (field.activeStrokes.length !== N) field.activeStrokes = field._nulls(N);
            var onArr = [];
            var cum = -app.implementWidth / 2;            // left edge of the boom
            for (var i = 0; i < N; ++i) {
                var secW = field._secW(i);
                var t = cum + secW / 2;                   // this section's lateral centre
                cum += secW;
                var se = rx + t * rex;
                var sn = ry + t * rny;
                if (!isFinite(se) || !isFinite(sn)) { onArr.push(false); continue; }
                var on = !(app.sectionControl && coverage.isCovered(se, sn));
                onArr.push(on);
                if (on) {
                    coverage.mark(se, sn, gps.headingDeg, secW);
                    var st = field.activeStrokes[i];
                    if (!st || st.w !== secW) {
                        // new section, or its width was just edited: close the old
                        // chunk so the worked swath keeps the width it was laid at.
                        if (st) field._freeze(st);
                        st = { w: secW, pts: [], tr: tgt, tu: tgu }; field.activeStrokes[i] = st;
                    }
                    st.pts.push(Qt.point(se, -sn));
                    if (st.pts.length >= field._chunkMax) {
                        // freeze this chunk; continue a new one from the last point
                        field._freeze(st);
                        field.activeStrokes[i] = { w: secW, tr: tgt, tu: tgu,
                                                   pts: [ st.pts[st.pts.length - 1] ] };
                    }
                } else if (field.activeStrokes[i]) {
                    field._freeze(field.activeStrokes[i]);
                    field.activeStrokes[i] = null;
                }
            }
            field.sectionOn = onArr;
            field.activeVersion++;
            if (!paintCoalesce.running)
                paintCoalesce.start();
        }
    }

    // ---- lat/lon -> world (east, -north) helpers for stored geometry ----
    // Non-finite points are dropped: a degenerate origin/coord must never reach
    // a PathPolyline (an empty/NaN segment crashes the Mali-400 GL ES2 backend).
    function _mapRing(list, close) {
        if (!list) return [];
        var a = [];
        var lim = field._maxLocalM;
        for (var i = 0; i < list.length; ++i) {
            var p = gps.toLocal(list[i].lat, list[i].lon);
            if (!isFinite(p.x) || !isFinite(p.y)) continue;
            // Huge-but-finite = corrupt origin or stray vertex; never hand it to GL.
            if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue;
            a.push(Qt.point(p.x, -p.y));
        }
        // A very high-vertex filled ring can segfault the Mali-400 triangulator.
        a = field._decimate(a, field._maxRingVerts);
        if (close && a.length > 2) a.push(a[0]);
        return a;
    }

    // ---- Run-line guidance (spacing defaults to implement width) ----
    readonly property var _selAb: {
        var ls = farm.activeAbLines;
        for (var i = 0; i < ls.length; ++i)
            if (ls[i].selected) return ls[i];
        return null;
    }
    // Unit direction (A->B) + left perpendicular of the master AB line, in real
    // world (east, north) metres. Drives the John Deere E/W vs N/S labelling:
    // +koff parallels are shifted along the perpendicular (px, py), the same
    // sign convention _abPts() uses.
    readonly property var _abDir: {
        var ab = field._selAb;
        if (!ab || !gps.hasOrigin) return null;
        var A = gps.toLocal(ab.aLat, ab.aLon);
        var B = gps.toLocal(ab.bLat, ab.bLon);
        var dx = B.x - A.x, dy = B.y - A.y;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (!isFinite(len) || len < 0.001) return null;
        var ux = dx / len, uy = dy / len;
        return { ux: ux, uy: uy, px: -uy, py: ux };
    }

    // John Deere run-line label: line 0 is the master AB line; parallels are
    // numbered by distance and tagged with the compass side they sit on. The
    // side comes from the line's perpendicular in real-world (east, north), so a
    // roughly N-S line yields E/W parallels and an E-W line yields N/S — and the
    // letters match real geography regardless of the screen north=-y convention.
    function _lineLabel(koff) {
        if (koff === 0) return "0";
        var d = field._abDir;
        if (!d) return String(Math.abs(koff));
        var ex = (koff > 0) ? d.px : -d.px;   // real-world direction of this side
        var ny = (koff > 0) ? d.py : -d.py;
        var letter = (Math.abs(ex) >= Math.abs(ny)) ? (ex > 0 ? "E" : "W")
                                                    : (ny > 0 ? "N" : "S");
        return Math.abs(koff) + letter;
    }

    // World draw point (east, -north) on run line `koff` abreast of the tractor,
    // used to anchor that line's small number label. Clamped/finite-guarded like
    // every other geometry helper so a bad origin never places a wild label.
    function _lineAnchor(koff) {
        var d = field._abDir;
        var ab = field._selAb;
        if (!d || !ab || !gps.hasOrigin) return null;
        var A = gps.toLocal(ab.aLat, ab.aLon);
        if (!isFinite(A.x) || !isFinite(A.y)) return null;
        var along = (gps.localX - A.x) * d.ux + (gps.localY - A.y) * d.uy;
        var off = koff * app.trackSpacing;
        var ex = A.x + d.ux * along + d.px * off;
        var ny = A.y + d.uy * along + d.py * off;
        if (!isFinite(ex) || !isFinite(ny)) return null;
        if (Math.abs(ex) > field._maxLocalM || Math.abs(ny) > field._maxLocalM) return null;
        return Qt.point(ex, -ny);
    }
    // Field diagonal in metres (how far the run lines must reach).
    readonly property real _spanMeters: {
        var b = farm.activeBoundary;
        if (!gps.hasOrigin || !b || b.length < 3) return 200;
        var lim = field._maxLocalM;
        var minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18, n = 0;
        for (var i = 0; i < b.length; ++i) {
            var p = gps.toLocal(b[i].lat, b[i].lon);
            if (!isFinite(p.x) || !isFinite(p.y)) continue;
            if (Math.abs(p.x) > lim || Math.abs(p.y) > lim) continue;
            if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x;
            if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y;
            ++n;
        }
        if (n < 3) return 200;
        var w = maxx - minx, h = maxy - miny;
        return Math.sqrt(w * w + h * h);
    }
    // Full fill extent (passes each side of the master line) needed to reach the
    // field edges. Sized from the field diagonal / spacing — not a blind magic
    // number — with a generous absolute ceiling so a corrupt origin (which would
    // blow up _spanMeters) can never request tens of thousands of passes. 1500 at
    // 6 m reaches 9 km each side, far beyond a 1000 ha (≈3.2 km) block.
    readonly property int _fillSpan: {
        var wdt = Math.max(0.5, app.trackSpacing);
        return Math.max(2, Math.min(1500, Math.ceil(_spanMeters / wdt) + 2));
    }
    // Label only the active line + its nearest neighbours so on-map text stays
    // cheap on the Mali-400 even as the fill spans the whole field.
    readonly property var _labelKoffs: {
        var arr = [];
        if (!field._selAb || !gps.hasOrigin || farm.abLineName.length === 0)
            return arr;
        var c = field.activePass;
        for (var k = c - 2; k <= c + 2; ++k) {
            if (k < -field._fillSpan || k > field._fillSpan) continue;
            arr.push(k);
        }
        return arr;
    }
    // Pass index nearest the tractor (highlighted as the active run line).
    readonly property int activePass: {
        if (!_selAb || !gps.hasOrigin) return 0;
        var A = gps.toLocal(_selAb.aLat, _selAb.aLon);
        var B = gps.toLocal(_selAb.bLat, _selAb.bLon);
        var dx = B.x - A.x, dy = B.y - A.y;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 0.001) return 0;
        var px = -dy / len, py = dx / len;
        var dist = (gps.localX - A.x) * px + (gps.localY - A.y) * py;
        return Math.round(dist / Math.max(0.5, app.trackSpacing));
    }

    // ---- Viewport culling of run lines (1000 ha @ 6 m must stay smooth) ----
    // Instantiating every pass of a large field as its own Shape would push
    // 1000-2000 polylines at the Mali-400 GL ES2 backend. Instead only the passes
    // whose offset index intersects the current view are rendered, and when more
    // than _visMaxLines fall in view (deep zoom-out / narrow spacing) they are
    // strided so the on-screen count stays a few dozen at any field size or zoom.
    readonly property int _visMaxLines: 64
    // Cross-track world half-extent currently on screen (metres). Uses the screen
    // diagonal so it bounds the AB perpendicular at any heading-up rotation.
    readonly property real _viewHalfSpanM: {
        var diagPx = Math.sqrt(width * width + height * height) / 2;
        return diagPx / Math.max(0.0001, field.viewScale);
    }
    // Offset index of the run line through the centre of the view: the tractor in
    // chase/top-down, the field centre in whole-paddock fit. Centres the window.
    readonly property int _viewCenterKoff: {
        var d = field._abDir;
        var ab = field._selAb;
        if (!d || !ab || !gps.hasOrigin) return 0;
        var A = gps.toLocal(ab.aLat, ab.aLon);
        if (!isFinite(A.x) || !isFinite(A.y)) return 0;
        var cwx, cwn;
        if (field.fitField && field.fb) {
            cwx = (field.fb.minx + field.fb.maxx) / 2;
            cwn = -(field.fb.miny + field.fb.maxy) / 2;
        } else if (field.following) {
            cwx = gps.localX; cwn = gps.localY;
        } else {
            var c = field._screenToWorld(field.width / 2, field.height / 2);
            cwx = c.e; cwn = c.n;
        }
        var dist = (cwx - A.x) * d.px + (cwn - A.y) * d.py;
        return Math.round(dist / Math.max(0.5, app.trackSpacing));
    }
    readonly property int _visMargin: Math.ceil(field._viewHalfSpanM / Math.max(0.5, app.trackSpacing)) + 2
    readonly property int _visKMin: Math.max(-field._fillSpan, field._viewCenterKoff - field._visMargin)
    readonly property int _visKMax: Math.min(field._fillSpan, field._viewCenterKoff + field._visMargin)
    // Stride keeps the rendered count bounded; anchored on the active pass so the
    // highlighted line is always one of the instantiated lines.
    readonly property int _visStride: Math.max(1,
        Math.ceil((field._visKMax - field._visKMin + 1) / field._visMaxLines))
    readonly property int _visBase:
        field.activePass + Math.ceil((field._visKMin - field.activePass) / field._visStride) * field._visStride
    readonly property int _visCount: Math.max(0,
        Math.floor((field._visKMax - field._visBase) / field._visStride) + 1)

    // ---- Viewport culling of frozen coverage chunks (1000 ha worked stays smooth) ----
    // Same approach as the run lines: only frozen chunks whose world bbox intersects
    // the view are instantiated. The C++ Coverage store does the bbox query over a
    // compact vector; here we build a QUANTISED view rect so the visible set (and the
    // Repeater) changes only when the view moves a cell or a chunk freezes — never
    // per fix. Zoomed right out (fit), the query strides the result down to _covMaxN.
    readonly property int _covMaxN: 300
    readonly property real _covQuant: 64
    // View centre in swath coords (x = east, y = -north), matching the chunk bboxes.
    readonly property var _covCenter: {
        if (field.fitField && field.fb)
            return { x: (field.fb.minx + field.fb.maxx) / 2,
                     y: (field.fb.miny + field.fb.maxy) / 2 };
        if (field.following)
            return { x: gps.localX, y: -gps.localY };
        var c = field._screenToWorld(field.width / 2, field.height / 2);
        return { x: c.e, y: -c.n };
    }
    readonly property real _covHalf: Math.max(60, field._viewHalfSpanM * 1.5)
    readonly property real _covMinX: Math.floor((field._covCenter.x - field._covHalf) / field._covQuant) * field._covQuant
    readonly property real _covMaxX: Math.ceil((field._covCenter.x + field._covHalf) / field._covQuant) * field._covQuant
    readonly property real _covMinY: Math.floor((field._covCenter.y - field._covHalf) / field._covQuant) * field._covQuant
    readonly property real _covMaxY: Math.ceil((field._covCenter.y + field._covHalf) / field._covQuant) * field._covQuant
    // Bounded list of in-view chunk indices (into doneStrokes). Re-queried when the
    // quantised rect changes or a chunk freezes (doneCount), not on every fix.
    readonly property var _visChunks: (field.doneCount,
        coverage.visibleChunks(field._covMinX, field._covMinY,
                               field._covMaxX, field._covMaxY, field._covMaxN))

    function _abPts(line, koff) {
        if (!line) return [];
        var A = gps.toLocal(line.aLat, line.aLon);
        var B = gps.toLocal(line.bLat, line.bLon);
        if (!isFinite(A.x) || !isFinite(A.y) || !isFinite(B.x) || !isFinite(B.y))
            return [];
        var lim = field._maxLocalM;
        if (Math.abs(A.x) > lim || Math.abs(A.y) > lim
            || Math.abs(B.x) > lim || Math.abs(B.y) > lim)
            return [];                        // corrupt origin: skip this AB line
        var dx = B.x - A.x, dy = B.y - A.y;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 0.001) return [];       // degenerate A≈B: no line to draw
        var ux = dx / len, uy = dy / len;
        var px = -uy, py = ux;            // perpendicular (east, north)
        var off = koff * app.trackSpacing;
        var L = 1000.0;
        var ax = A.x - ux * L + px * off, ay = A.y - uy * L + py * off;
        var bx = B.x + ux * L + px * off, by = B.y + uy * L + py * off;
        if (!isFinite(ax) || !isFinite(ay) || !isFinite(bx) || !isFinite(by))
            return [];
        return [Qt.point(ax, -ay), Qt.point(bx, -by)];
    }

    // ---- Ground (tilted) ----
    Item {
        id: tiltContainer
        anchors.fill: parent
        transform: Rotation {
            origin.x: field.cx
            origin.y: field.cy
            axis.x: 1
            axis.y: 0
            axis.z: 0
            angle: field.tilt
        }

        Item {
            id: world
            transform: [
                Scale { xScale: field.viewScale; yScale: field.viewScale },
                Rotation { angle: field.viewRot },
                Translate { x: field.viewOffX; y: field.viewOffY }
            ]

            Rectangle {
                x: -2000; y: -2000; width: 4000; height: 4000
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Style.groundEdge }
                    GradientStop { position: 0.5; color: Style.ground }
                    GradientStop { position: 1.0; color: Style.groundEdge }
                }
            }

            Repeater {
                model: 41
                Rectangle { x: -800 + index * 40; y: -800; width: 0.25; height: 1600
                            color: Style.gridMinor; opacity: 0.5 }
            }
            Repeater {
                model: 41
                Rectangle { x: -800; y: -800 + index * 40; width: 1600; height: 0.25
                            color: Style.gridMinor; opacity: 0.5 }
            }
            Rectangle { x: -0.3; y: -800; width: 0.6; height: 1600; color: Style.gridMajor }
            Rectangle { x: -800; y: -0.3; width: 1600; height: 0.6; color: Style.gridMajor }
            Text { text: "N"; color: Style.cardinal; font.pixelSize: 14; x: -4; y: -120 }
            Text { text: "S"; color: Style.cardinal; font.pixelSize: 14; x: -4; y: 108 }
            Text { text: "E"; color: Style.cardinal; font.pixelSize: 14; x: 110; y: -8 }
            Text { text: "W"; color: Style.cardinal; font.pixelSize: 14; x: -118; y: -8 }

            // coverage swaths — frozen chunks, viewport-culled (see _visChunks). The
            // model is the bounded list of chunk indices whose bbox intersects the
            // view, so a fully-worked 1000 ha field renders O(visible) chunks, not
            // all of them. Each chunk is triangulated once; the same >= 2-point guard
            // applies so a null/short chunk never reaches the Mali-400 GL ES2 backend.
            Repeater {
                model: field._visChunks
                Shape {
                    id: doneShape
                    readonly property var _st: field.doneStrokes[modelData]
                    readonly property var _pts: (_st && _st.pts && _st.pts.length >= 2) ? _st.pts : []
                    readonly property real _w: (_st && _st.pts && _st.pts.length >= 2) ? _st.w : 0
                    visible: _pts.length >= 2
                    ShapePath {
                        strokeColor: "#883ddc84"
                        strokeWidth: doneShape._w
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline { path: doneShape._pts }
                    }
                }
            }

            // Active swaths — growing chunks only. Frozen chunks stay on Shape
            // (triangulated once); live strokes use cheap rotated rects so the
            // Mali-400 is not retessellating PathPolyline on every GPS fix.
            Repeater {
                model: field._activePaintSegs
                Item {
                    x: modelData.x - modelData.w * 0.5
                    y: modelData.y - modelData.h * 0.5
                    width: modelData.w
                    height: modelData.h
                    rotation: modelData.rot
                    transformOrigin: Item.Center
                    Rectangle {
                        anchors.fill: parent
                        radius: Math.min(width, height) * 0.45
                        color: "#883ddc84"
                    }
                }
            }

            // field boundary (filled + high-contrast pink outline). The ring is
            // computed once; the Shape only renders when it holds a real polyline
            // (>= 2 finite points) so an empty/degenerate ring never reaches the
            // GL ES2 triangulator (which segfaults on the Mali-400).
            Shape {
                id: boundaryShape
                readonly property var ring: (gps.hasOrigin && farm.boundaryCount >= 3)
                                            ? field._mapRing(farm.activeBoundary, true) : []
                visible: ring.length >= 2
                ShapePath {
                    strokeColor: "#ff1aa3"
                    strokeWidth: boundaryShape.visible ? Math.max(0.6, 2.5 / field.viewScale) : 0
                    // The faint fill triangulates the whole (often concave, traced)
                    // ring on the UI thread. A large/complex paddock ring can wedge
                    // the GL ES triangulator (documented Mali-400 choke; also froze
                    // an Android-11 import). The high-contrast outline is the part
                    // that matters, so only fill modest rings and skip the fill for
                    // large ones — the boundary still draws as a bright outline.
                    fillColor: boundaryShape.ring.length <= field._maxFillVerts ? "#22ff1aa3" : "transparent"
                    PathPolyline { path: boundaryShape.visible ? boundaryShape.ring : [] }
                }
            }

            // AB guidance run lines (spacing = track spacing). Only the passes that
            // intersect the current viewport are instantiated (see _visBase/_visCount),
            // so a 1000 ha field stays a few dozen Shapes on screen. Each line's
            // polyline is computed once; the Shape renders only when it has >= 2
            // points, so a null/degenerate (_selAb null or A≈B) line can't hand an
            // empty PathPolyline to the renderer while visible.
            Repeater {
                model: field._visCount
                Shape {
                    id: abShape
                    property int koff: field._visBase + index * field._visStride
                    property bool active: koff === field.activePass
                    readonly property var pts: (gps.hasOrigin && farm.abLineName.length > 0)
                                               ? field._abPts(field._selAb, koff) : []
                    visible: pts.length >= 2
                    ShapePath {
                        // High contrast over both the grey ground and the green
                        // coverage: the active run line is a bright non-green cyan
                        // and noticeably bolder; the rest are a deep, opaque blue.
                        strokeColor: abShape.active ? "#00e5ff" : "#dd11317a"
                        strokeWidth: abShape.visible
                                     ? (abShape.active ? 1.0 : 0.42) / Math.max(0.3, field.viewScale / 6) : 0
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathPolyline { path: abShape.visible ? abShape.pts : [] }
                    }
                }
            }

            // Run-line number labels (John Deere 0 / 1E / 2E … convention).
            // Only the active line + nearest neighbours are drawn. Counter-scaled
            // to a roughly constant pixel size and counter-rotated against the
            // view so the digits read upright as the map turns.
            Repeater {
                model: field._labelKoffs
                Item {
                    property int koff: modelData
                    readonly property var anchor: field._lineAnchor(koff)
                    visible: anchor !== null
                    x: anchor ? anchor.x : 0
                    y: anchor ? anchor.y : 0
                    rotation: -field.viewRot
                    Text {
                        anchors.centerIn: parent
                        text: field._lineLabel(parent.koff)
                        color: parent.koff === field.activePass ? "#00e5ff" : "#eaf2ff"
                        font.pixelSize: 13
                        font.bold: parent.koff === field.activePass
                        style: Text.Outline
                        styleColor: "#0a0f14"
                        transformOrigin: Item.Center
                        scale: 1 / Math.max(0.0001, field.viewScale)
                        renderType: Text.QtRendering
                        antialiasing: true
                    }
                }
            }
        }
    }

    // ---- Pan + pinch gestures ----
    // Sits above the map but below the overlay buttons (declared later), so the
    // zoom/perspective/Mark-A-B controls keep priority. Pinch-zoom is available in
    // every mode; in the tractor-following modes (chase/top-down) the view stays
    // locked on the machine so pinch zooms around the tractor without translating.
    // Drag-to-PAN is allowed ONLY in the whole-field (fitField) view, where there is
    // no machine lock to break; panning shifts viewOffX/Y, which the run-line +
    // coverage culling key off, so the visible window recomputes as the view moves.
    PinchArea {
        id: pinchArea
        anchors.fill: parent
        property real _z0: 1.0
        onPinchStarted: pinchArea._z0 = field.userZoom
        onPinchUpdated: field.userZoom = Math.max(0.03, Math.min(80.0, pinchArea._z0 * pinch.scale))
        MouseArea {
            id: panArea
            anchors.fill: parent
            enabled: field.fitField
            property real _sx: 0
            property real _sy: 0
            property real _bx: 0
            property real _by: 0
            onPressed: { _sx = mouse.x; _sy = mouse.y; _bx = field.panX; _by = field.panY; }
            onPositionChanged: {
                field.following = false;
                field.panX = _bx + (mouse.x - _sx);
                field.panY = _by + (mouse.y - _sy);
            }
        }
    }

    // ---- Sky cover above the horizon (chase only) ----
    Rectangle {
        visible: field.mode === 1
        x: 0; y: 0; width: parent.width; height: field.horizonY
        gradient: Gradient {
            GradientStop { position: 0.0; color: Style.skyTop }
            GradientStop { position: 1.0; color: Style.sky }
        }
    }
    Rectangle {
        visible: field.mode === 1
        x: 0; width: parent.width; height: 2
        y: field.horizonY - 2
        color: Style.horizon
    }

    // ---- Machine (true 3 m x 6 m; antenna front-centre anchored to the GPS point) ----
    Tractor {
        heading: field.tractorRot
        width: 3 * field.s
        height: 6 * field.s
        x: field.tractorX - width / 2
        y: field.tractorY
    }

    // ---- Implement boom + section bar -------------------------------------
    // Drawn inside the SAME tilt + world transform as the coverage swaths (in
    // metres), so the boom/bar scale, rotate and tilt identically and line up
    // with the recorded coverage across every perspective mode. The layer is
    // placed AFTER the Tractor so the bar (which sits implementOffset metres
    // behind the antenna, i.e. mid-sprite at the 3 m default) is not occluded
    // by the machine image. Anchored at the terrain-compensated record point.
    Item {
        visible: !field.fitField && gps.hasOrigin
        anchors.fill: parent
        transform: Rotation {
            origin.x: field.cx
            origin.y: field.cy
            axis.x: 1; axis.y: 0; axis.z: 0
            angle: field.tilt
        }
        Item {
            id: implWorld
            transform: [
                Scale { xScale: field.viewScale; yScale: field.viewScale },
                Rotation { angle: field.viewRot },
                Translate { x: field.viewOffX; y: field.viewOffY }
            ]
            // Record point in world drawing coords (east, -north); null on a bad
            // (non-finite) attitude/heading decode -> nothing drawn that fix.
            readonly property var rp: field._recordPoint()
            visible: rp !== null

            Item {
                // Anchored at the record point and rotated to heading: local +x
                // runs along the boom bar (perpendicular to travel) and local -y
                // points forward to the antenna, so the arm and bar are built in
                // simple machine-relative metres.
                x: implWorld.rp ? implWorld.rp.x : 0
                y: implWorld.rp ? -implWorld.rp.y : 0
                rotation: gps.headingDeg

                // boom arm: antenna (local 0,-offset) -> record point (local 0,0)
                Rectangle {
                    width: 0.4
                    height: app.implementOffset
                    x: -width / 2
                    y: -app.implementOffset
                    color: "#b9781b"
                    antialiasing: true
                }
                // section bar centred on the record point — each section at its own
                // width/offset (matches the per-section coverage geometry above), so
                // a custom/asymmetric layout shows correctly. Index 0 = machine left.
                Repeater {
                    model: field.sectionCount
                    Rectangle {
                        readonly property real _w: field._secW(index)
                        width: _w
                        height: 1.0
                        x: field._secCenter(index) - _w / 2
                        y: -0.5
                        color: (field.sectionOn[index] === false) ? "#5a5a5a" : "#f0a330"
                        border.color: "#7a5212"; border.width: 0.05
                        antialiasing: true
                    }
                }
            }
        }
    }

    // ---- Heading + run line (top centre) ----
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 10
        width: headCol.width + 28; height: headCol.height + 12
        radius: 8; color: "#cc0b1310"; border.color: Style.panelEdge; border.width: 1
        Column {
            id: headCol
            anchors.centerIn: parent
            spacing: -2
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Text { text: field.compass(gps.headingDeg); color: Style.accent
                       font.pixelSize: 22; font.bold: true }
                Text { text: gps.headingDeg.toFixed(0) + "\u00B0"; color: Style.white
                       font.pixelSize: 22; font.bold: true }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: farm.abLineName.length ? farm.abLineName
                      : (farm.hasActiveField ? farm.activeFieldName : qsTr("No field"))
                color: Style.textDim; font.pixelSize: 12
            }
        }
    }

    // ---- Recording badge (top-left) ----
    Rectangle {
        visible: app.recordingCoverage
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12
        width: recRow.width + 20; height: 32; radius: 16; color: "#aa000000"
        Row {
            id: recRow; anchors.centerIn: parent; spacing: 8
            Rectangle { width: 12; height: 12; radius: 6; color: "#e74c3c"
                        anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity {
                            running: app.recordingCoverage; loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        } }
            Text { text: "REC"; color: Style.white; font.pixelSize: 14
                   anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ---- Perspective toggle (top-right) ----
    Rectangle {
        id: persBtn
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12
        width: persLabel.width + 28; height: 44; radius: 8
        color: "#aa0b1310"; border.color: Style.accent; border.width: 1
        Row {
            id: persLabel; anchors.centerIn: parent; spacing: 8
            MdiIcon { icon: Icons.perspective; color: Style.accent; font.pixelSize: 20
                   anchors.verticalCenter: parent.verticalCenter }
            Text { text: field.modeNames[field.mode]; color: Style.white
                   font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; onClicked: field.cyclePerspective() }
    }

    // ---- Zoom / centre buttons (under perspective toggle) ----
    Column {
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.top: persBtn.bottom; anchors.topMargin: 10
        spacing: 8
        Repeater {
            model: [ { g: Icons.plus, a: "in" }, { g: Icons.minus, a: "out" }, { g: Icons.center, a: "center" } ]
            Rectangle {
                width: 48; height: 48; radius: 24
                color: zma.pressed ? Style.accent : "#aa0b1310"
                border.color: Style.accent; border.width: 1
                MdiIcon { anchors.centerIn: parent; icon: modelData.g
                       color: zma.pressed ? Style.banner : Style.white; font.pixelSize: 24 }
                MouseArea {
                    id: zma; anchors.fill: parent
                    onClicked: {
                        if (modelData.a === "in") field.zoomIn();
                        else if (modelData.a === "out") field.zoomOut();
                        else field.recenter();
                    }
                }
            }
        }
    }

    // The on-map "Mark A" / "Mark B" run-line buttons were removed: run-line
    // creation now lives in the Run Line popup and the Paddock Setup page.

    Text {
        visible: !gps.hasOrigin
        anchors.centerIn: parent
        text: qsTr("waiting for GPS fix\u2026")
        color: Style.cardinal; font.pixelSize: 16
    }

    // Live target-rate readout (Rx prescription or flat). Shows the as-applied
    // target rate being logged; flags out-of-zone / no-GPS fallbacks for Rx.
    Rectangle {
        id: ratePill
        visible: app.application && app.application.name !== undefined
                 && app.application.name.length > 0
        z: 4000
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        width: rateRow.implicitWidth + 24
        height: rateRow.implicitHeight + 12
        radius: 8
        color: "#cc101418"
        border.width: 1
        border.color: field._appRx ? (field._inZone ? Style.accent : "#d8a657") : Style.accent
        Row {
            id: rateRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: field._appRx ? qsTr("Rx") : qsTr("Rate")
                color: field._appRx ? (field._inZone ? Style.accent : "#d8a657") : Style.textDim
                font.pixelSize: 12; font.bold: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Number(field._targetRate).toFixed(field._targetRate < 10 ? 1 : 0)
                      + " " + field._targetUnit + (field._targetUnit.indexOf("/") >= 0 ? "" : qsTr("/ha"))
                color: Style.white; font.pixelSize: 18; font.bold: true
            }
            Text {
                visible: field._appRx && !field._inZone
                anchors.verticalCenter: parent.verticalCenter
                text: gps.hasFix ? qsTr("(out of zone)") : qsTr("(no GPS)")
                color: "#d8a657"; font.pixelSize: 11
            }
        }
    }

    // TEMP boundary diagnostics overlay. Reads the live values along the boundary
    // render path so the break can be pinpointed on-device (screencap is black on
    // Mali GL, and touch/GPS can't be driven headlessly). Remove with _dbgOn once
    // root-caused.
    Rectangle {
        visible: field._dbgOn
        z: 5000
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 8
        width: dbgCol.implicitWidth + 16
        height: dbgCol.implicitHeight + 12
        color: "#cc000000"
        border.color: "#ff1aa3"; border.width: 1; radius: 6
        Column {
            id: dbgCol
            anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 8
            spacing: 1
            property color k: "#7fe0d0"
            Text { color: "#ff66c2"; font.pixelSize: 12; font.bold: true; text: "BOUNDARY DEBUG" }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "mode=" + field.mode + "  fit=" + field.fitField + "  hasOrigin=" + gps.hasOrigin }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "origin=" + gps.originLat().toFixed(6) + "," + gps.originLon().toFixed(6) }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "boundaryCount=" + farm.boundaryCount + "  activeBndy.len=" + farm.activeBoundary.length }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "ring.len=" + boundaryShape.ring.length + "  bShape.vis=" + boundaryShape.visible }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "spanM=" + field._spanMeters.toFixed(0) + "  fitScale=" + field._fitScale.toFixed(3)
                         + "  viewScale=" + field.viewScale.toFixed(3) }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "fb=" + (field.fb ? (field.fb.minx.toFixed(0) + "," + field.fb.miny.toFixed(0)
                         + " .. " + field.fb.maxx.toFixed(0) + "," + field.fb.maxy.toFixed(0)) : "null") }
            Text { color: dbgCol.k; font.pixelSize: 11
                   text: "localXY=" + gps.localX.toFixed(0) + "," + gps.localY.toFixed(0)
                         + "  off=" + field.viewOffX.toFixed(0) + "," + field.viewOffY.toFixed(0) }
            Text { color: dbgCol.k; font.pixelSize: 11; wrapMode: Text.WordWrap; width: 280
                   text: "ensureOrigin: " + field._dbgEnsure }
        }
    }
}
