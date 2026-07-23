import QtQuick 2.15

// Phone job/coverage persistence — mirrors FieldView job hooks without tablet WorkSetup.
Item {
    id: sync
    property var recorder: null
    property var _jobId: ({
        fieldId: "", fieldName: "",
        farmId: "", farmName: "",
        clientId: "", clientName: ""
    })
    property string _loadedJobId: ""

    // Background job index (populated on boot; no coverage applied until user resumes).
    property bool indexReady: false
    property var lastJob: ({})
    property var allJobs: []
    property int savedJobCount: 0

    readonly property real _maxLocalM: 200000

    function refreshJobIndex() {
        var lj = ({}), aj = [], cnt = 0
        try { lj = jobs.activeJob() } catch (e) { lj = ({}) }
        try { aj = jobs.listAllJobs(0) } catch (e) { aj = [] }
        try { cnt = aj.length } catch (e2) { cnt = 0 }
        if (cnt === 0) {
            try {
                if (jobs.hasAnySavedJobs())
                    cnt = 1
            } catch (e3) {}
        }
        lastJob = lj
        allJobs = aj
        savedJobCount = cnt
        indexReady = true
    }

    function hasAnySavedWork() {
        if (savedJobCount > 0)
            return true
        if (lastJob && lastJob.fieldId && lastJob.fieldId.length)
            return true
        if (farm.hasActiveField && sync._safeHasJob(farm.activeFieldId))
            return true
        try { return jobs.hasAnySavedJobs() } catch (e) { return false }
    }

    function _safeHasJob(fieldId) {
        if (!fieldId || !fieldId.length)
            return false
        try { return jobs.hasJob(fieldId) } catch (e) { return false }
    }

    function rememberLastField() {
        if (!farm.hasActiveField)
            return
        var jid = ""
        try { jid = jobs.jobMeta(farm.activeFieldId).jobId || "" } catch (e) { jid = "" }
        try { jobs.rememberLastActive(farm.activeFieldId, jid) } catch (e2) {}
    }

    function shortDate(iso) {
        if (!iso) return ""
        var s = "" + iso
        return s.length >= 16 ? s.substring(0, 16).replace("T", " ") : s
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
            if (!sync._validLatLon(b[i].lat, b[i].lon)) continue
            sLat += b[i].lat; sLon += b[i].lon; ++n
        }
        if (n < 1) return null
        return { lat: sLat / n, lon: sLon / n }
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
    function _freezeAllActive() {
        if (!recorder) return
        var ds = recorder.doneStrokes ? recorder.doneStrokes.slice() : []
        for (var i = 0; i < recorder.activeStrokes.length; ++i) {
            var st = recorder.activeStrokes[i]
            if (st && st.pts && st.pts.length >= 2) {
                if (!st.bbox) {
                    var b = sync._chunkBbox(st.pts, st.w || 0)
                    st.bbox = b
                    coverage.addChunkBox(b.minx, b.miny, b.maxx, b.maxy)
                }
                ds.push(st)
            }
        }
        recorder.doneStrokes = ds
        recorder.doneCount = ds.length
        recorder.activeStrokes = []
        recorder.activeVersion++
    }
    function _coverageGeoJson() {
        if (!recorder) return JSON.stringify({ type: "FeatureCollection", features: [] })
        sync._freezeAllActive()
        var feats = []
        for (var i = 0; i < recorder.doneStrokes.length; ++i) {
            var st = recorder.doneStrokes[i]
            if (!st || !st.pts || st.pts.length < 2) continue
            var coords = []
            for (var j = 0; j < st.pts.length; ++j) {
                var g = gps.toGeo(st.pts[j].x, -st.pts[j].y)
                coords.push([g.lon, g.lat])
            }
            feats.push({ type: "Feature",
                         geometry: { type: "LineString", coordinates: coords },
                         properties: { width_m: st.w } })
        }
        return JSON.stringify({ type: "FeatureCollection", features: feats })
    }
    property var _replayMarks: []
    property int _replayMarkIdx: 0

    function _loadCoverageGeoJson(text) {
        if (!text || !text.length || !gps.hasOrigin || !recorder) return
        sync._replayMarks = []
        sync._replayMarkIdx = 0
        coverageReplayTimer.stop()
        recorder.loadingCoverage = true
        var fc
        try { fc = JSON.parse(text) } catch (e) {
            recorder.loadingCoverage = false
            return
        }
        if (!fc || !fc.features) {
            recorder.loadingCoverage = false
            return
        }
        var done = []
        var marks = []
        for (var i = 0; i < fc.features.length; ++i) {
            var ft = fc.features[i]
            if (!ft || !ft.geometry || ft.geometry.type !== "LineString") continue
            var w = (ft.properties && ft.properties.width_m)
                    ? ft.properties.width_m : (app.implementWidth / app.sectionCount)
            var cs = ft.geometry.coordinates
            if (!cs || !cs.length) continue
            var locals = []
            for (var j = 0; j < cs.length; ++j) {
                var c = cs[j]
                if (!c || c.length < 2) continue
                var p = gps.toLocal(c[1], c[0])
                if (!isFinite(p.x) || !isFinite(p.y)) continue
                if (Math.abs(p.x) > sync._maxLocalM || Math.abs(p.y) > sync._maxLocalM) continue
                locals.push(p)
            }
            if (locals.length < 2) continue
            var pts = []
            for (var j2 = 0; j2 < locals.length; ++j2) {
                var a0 = locals[j2]
                var a1 = locals[Math.min(j2 + 1, locals.length - 1)]
                var de0 = a1.x - a0.x, dn0 = a1.y - a0.y
                var hdg0 = (de0 === 0 && dn0 === 0) ? gps.headingDeg
                                                    : Math.atan2(de0, dn0) * 180 / Math.PI
                if (hdg0 < 0) hdg0 += 360
                pts.push({ x: a0.x, y: -a0.y, h: hdg0 })
            }
            var bb = sync._chunkBbox(pts, w)
            done.push({ w: w, pts: pts, bbox: bb })
            for (var k = 0; k < locals.length; ++k)
                marks.push({ x: locals[k].x, y: locals[k].y, hdg: pts[k].h, w: w })
        }
        if (done.length < 1 && marks.length < 1) {
            recorder.loadingCoverage = false
            return
        }
        // Single reset here — loadingCoverage guards onCleared stroke wipe.
        coverage.reset()
        recorder.doneStrokes = done.slice()
        recorder.doneCount = done.length
        recorder.activeStrokes = []
        recorder.activeVersion++
        for (var ci = 0; ci < done.length; ++ci) {
            var box = done[ci].bbox
            coverage.addChunkBox(box.minx, box.miny, box.maxx, box.maxy)
        }
        sync._replayMarks = marks
        sync._replayMarkIdx = 0
        recorder.loadingCoverage = false
        if (marks.length)
            coverageReplayTimer.start()
    }
    function _saveJob(id) {
        if (!id || !id.fieldId || !id.fieldId.length || !gps.hasOrigin) return
        var meta = {
            fieldId: id.fieldId, fieldName: id.fieldName,
            farmId: id.farmId, farmName: id.farmName,
            clientId: id.clientId, clientName: id.clientName,
            trackName: app.trackName,
            areaHa: coverage.areaHa,
            implementWidthM: app.implementWidth,
            implementOffsetM: app.recordOffsetM,
            antennaHeightM: app.antennaHeight,
            originLat: gps.originLat(), originLon: gps.originLon(),
            source: app.activeSource
        }
        jobs.saveJob(meta, sync._coverageGeoJson())
        sync.rememberLastField()
        sync.refreshJobIndex()
    }
    function saveActiveJob() { sync._saveJob(sync._jobId) }
    function _applyJobOrigin(meta) {
        if (!meta || !sync._validLatLon(meta.originLat, meta.originLon)) return false
        gps.setOrigin(meta.originLat, meta.originLon)
        return true
    }
    function restoreActiveJob() {
        var fid = sync._jobId.fieldId
        if (!fid || !fid.length) return
        var hasJob = sync._safeHasJob(fid)
        if (!hasJob) return
        var meta = null
        try { meta = jobs.jobMeta(fid) } catch (e) { meta = null }
        if (!sync._applyJobOrigin(meta))
            sync._ensureOrigin()
        if (!gps.hasOrigin)
            return
        var cov = ""
        try { cov = jobs.loadCoverage(fid) } catch (e) { cov = "" }
        sync._loadCoverageGeoJson(cov)
    }
    function restoreJobById(fieldId, jobId) {
        if (!fieldId || !fieldId.length) return
        if (jobId && jobId.length)
            jobs.openJob(fieldId, jobId)
        var meta = null
        try { meta = jobs.jobMeta(fieldId) } catch (e) { meta = null }
        sync._jobId.fieldId = fieldId
        sync._jobId.fieldName = meta && meta.fieldName ? meta.fieldName : sync._jobId.fieldName
        sync._jobId.farmId = meta && meta.farmId ? meta.farmId : sync._jobId.farmId
        sync._jobId.farmName = meta && meta.farmName ? meta.farmName : sync._jobId.farmName
        sync._jobId.clientId = meta && meta.clientId ? meta.clientId : sync._jobId.clientId
        sync._jobId.clientName = meta && meta.clientName ? meta.clientName : sync._jobId.clientName
        sync._loadedJobId = (meta && meta.jobId) ? meta.jobId : (jobId || "")
        sync.restoreActiveJob()
        sync.rememberLastField()
    }
    function _ensureOrigin() {
        if (gps.hasOrigin && sync._validLatLon(gps.originLat(), gps.originLon())) return
        var c = sync._boundaryCentroid()
        if (c) gps.setOrigin(c.lat, c.lon)
    }
    function _currentFieldId() {
        return {
            fieldId: farm.activeFieldId, fieldName: farm.activeFieldName,
            farmId: farm.activeFarmId, farmName: farm.activeFarmName,
            clientId: farm.activeClientId, clientName: farm.activeClientName
        }
    }
    function _saveOutgoingIfNeeded() {
        if (!sync._jobId.fieldId.length || !gps.hasOrigin)
            return
        if (coverage.cellCount > 0 || (recorder && recorder.doneCount > 0))
            sync._saveJob(sync._jobId)
    }
    function _hasLiveCoverage() {
        return coverage.cellCount > 0 || (recorder && recorder.doneCount > 0)
    }
    function _clearSessionCoverage() {
        coverage.reset()
        if (recorder) {
            recorder.doneStrokes = []
            recorder.doneCount = 0
            recorder.activeStrokes = []
            recorder.activeVersion++
        }
    }
    function handleJobDeleted(entry) {
        if (!entry || !entry.fieldId)
            return
        var wasLoaded = (sync._loadedJobId.length > 0
                         && sync._loadedJobId === entry.jobId
                         && farm.hasActiveField
                         && farm.activeFieldId === entry.fieldId)
        sync.refreshJobIndex()
        if (wasLoaded
                || (farm.hasActiveField && farm.activeFieldId === entry.fieldId
                    && !sync._safeHasJob(entry.fieldId))) {
            sync._clearSessionCoverage()
            sync._loadedJobId = ""
        }
    }
    function activateField(clientId, farmId, fieldId, resume) {
        var sameField = (fieldId.length > 0 && fieldId === sync._jobId.fieldId
                         && fieldId === farm.activeFieldId)
        if (fieldId !== sync._jobId.fieldId)
            sync._saveOutgoingIfNeeded()
        farm.setActiveField(clientId, farmId, fieldId)
        sync._jobId = sync._currentFieldId()
        sync.rememberLastField()
        sync._ensureOrigin()
        if (resume) {
            // Resume on the field already in memory must not wipe live cells.
            if (sameField && sync._hasLiveCoverage())
                return
            sync.restoreActiveJob()
        } else {
            if (sameField && sync._hasLiveCoverage())
                sync.saveActiveJob()
            coverage.reset()
            if (recorder) {
                recorder.doneStrokes = []
                recorder.doneCount = 0
                recorder.activeStrokes = []
                recorder.activeVersion++
            }
            jobs.startNewJob(fieldId)
            sync._loadedJobId = ""
        }
        sync.refreshJobIndex()
    }
    function resumeJobEntry(entry) {
        if (!entry || !entry.fieldId) return
        sync._saveOutgoingIfNeeded()
        var cid = entry.clientId ? entry.clientId : ""
        var fid = entry.farmId ? entry.farmId : ""
        farm.setActiveField(cid, fid, entry.fieldId)
        sync._jobId = sync._currentFieldId()
        sync._ensureOrigin()
        sync.restoreJobById(entry.fieldId, entry.jobId || "")
        sync.refreshJobIndex()
    }
    function resumeCurrentField() {
        if (!farm.hasActiveField) return
        if (sync._hasLiveCoverage())
            return
        sync._jobId = sync._currentFieldId()
        sync.restoreActiveJob()
        sync.rememberLastField()
    }
    function resumeLastJob() {
        var lj = sync.lastJob
        if (lj && lj.fieldId && lj.fieldId.length) {
            sync.resumeJobEntry(lj)
            return
        }
        var fid = ""
        try { fid = jobs.lastActiveFieldId() } catch (e) { fid = "" }
        if (fid.length && sync._safeHasJob(fid)) {
            farm.setActiveField("", "", fid)
            sync._jobId = sync._currentFieldId()
            sync.restoreActiveJob()
            sync.rememberLastField()
        } else if (farm.hasActiveField) {
            sync.resumeCurrentField()
        }
    }
    function startNewOnCurrentField() {
        if (!farm.hasActiveField) return
        sync.saveActiveJob()
        sync._jobId = sync._currentFieldId()
        jobs.startNewJob(farm.activeFieldId)
        coverage.reset()
        if (recorder) {
            recorder.doneStrokes = []
            recorder.doneCount = 0
            recorder.activeStrokes = []
            recorder.activeVersion++
        }
        sync.rememberLastField()
        sync.refreshJobIndex()
    }

    Component.onCompleted: {
        sync.refreshJobIndex()
        if (farm.hasActiveField)
            sync._jobId = sync._currentFieldId()
    }

    Connections {
        target: farm
        function onGeometryChanged() { sync._ensureOrigin() }
        function onActiveChanged() { sync.rememberLastField() }
    }
    Connections {
        target: jobs
        function onSaveRequested() { sync.saveActiveJob() }
        function onChanged() { sync.refreshJobIndex() }
    }
    Connections {
        target: app
        function onRecordingChanged() {
            if (!app.recordingCoverage)
                sync.saveActiveJob()
        }
    }
    Connections {
        target: Qt.application
        function onStateChanged(state) {
            if (state === Qt.ApplicationInactive || state === Qt.ApplicationSuspended)
                sync.saveActiveJob()
        }
    }

    Timer {
        id: periodicSave
        interval: 30000
        repeat: true
        running: app.recordingCoverage
        onTriggered: sync.saveActiveJob()
    }
    Timer {
        id: coverageReplayTimer
        interval: 16
        repeat: true
        onTriggered: {
            var end = Math.min(sync._replayMarkIdx + 80, sync._replayMarks.length)
            for (var i = sync._replayMarkIdx; i < end; ++i) {
                var m = sync._replayMarks[i]
                coverage.mark(m.x, m.y, m.hdg, m.w)
            }
            sync._replayMarkIdx = end
            if (sync._replayMarkIdx >= sync._replayMarks.length) {
                coverageReplayTimer.stop()
                sync._replayMarks = []
            }
        }
    }
}
