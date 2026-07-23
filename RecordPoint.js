.pragma library

// Shared GPS → coverage/boundary record point (behind tractor per attachment type).

// Terrain-comp (antenna-height × roll/pitch) is PARKED for JD StarFire:
//   • FEE6 roll is bogus upstream → always 0 on the wire path
//   • FEE8 pitch sits at a large constant bias (~−9°) even on flat ground
//   • Enabling hasAttitude then applied pitch-only TCM → ~0.5 m along-track
//     coverage shift at 3 m antenna height (looks like “crossed wires”)
// Heading still comes from TCM yaw (FEE8) via GpsModel — that path is fine.
// Flip to true after field-validating both roll and pitch against the cab TCM.
var TERRAIN_COMP_LIVE = false

function recordLatLon(gps, app) {
    if (!gps || !gps.hasFix)
        return null
    // Q_PROPERTY — access as a property, not a callable (QML TypeError otherwise).
    var off = app.recordOffsetM
    return gps.recordingPoint(off)
}

function recordLocal(gps, app) {
    if (!gps || !gps.hasFix)
        return null
    if (!gps.hasOrigin)
        gps.setOrigin(gps.latitude, gps.longitude)
    var hr = gps.headingDeg * Math.PI / 180
    var sinH = Math.sin(hr), cosH = Math.cos(hr)
    var gx = gps.localX, gy = gps.localY
    var h = app.antennaHeight
    if (TERRAIN_COMP_LIVE && gps.hasAttitude && h > 0.01) {
        // Body axes: +roll = right-down, +pitch = nose-up (verify in field).
        // ground = antenna − (h·sin roll)·right − (h·sin pitch)·forward
        var roll = Math.max(-30, Math.min(30, gps.rollDeg)) * Math.PI / 180
        var pitch = Math.max(-30, Math.min(30, gps.pitchDeg)) * Math.PI / 180
        var latOff = h * Math.sin(roll)   // lateral metres
        var lonOff = h * Math.sin(pitch)  // longitudinal metres
        gx -= latOff * cosH + lonOff * sinH
        gy -= latOff * (-sinH) + lonOff * cosH
    }
    var off = app.recordOffsetM
    var px = gx - off * sinH, py = gy - off * cosH
    if (!isFinite(px) || !isFinite(py))
        return null
    return { x: px, y: py }
}
