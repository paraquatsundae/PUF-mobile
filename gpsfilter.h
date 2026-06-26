#pragma once

// Automatic, tier-aware GPS smoothing for PUF-mobile's shared C++ core.
//
// This file is intentionally Qt-free (only <cmath>) so the offline replay/
// tuning harness (tools/gps_replay) compiles the EXACT same filter code that
// runs on the phone/tablet. Do not add Qt dependencies here.
//
// Pipeline position: raw NMEA/$PANDA parse -> [GpsFilter] -> canonical
// lat/lon/heading consumed by coverage + UI. Raw values are kept separately
// for the raw-track logger. See Plans/PhonePort/GPS_SMOOTHING.md.

namespace gpsfilter {

// GPS accuracy tier, derived from fix quality (+ HDOP). Drives filter strength:
// cleaner source -> lighter filtering, noisier source -> heavier filtering.
enum class Tier {
    Rtk,   // fixQuality 4/5 — RTK fixed/float; data already clean
    Sbas,  // fixQuality 2/3 — DGPS/SBAS, or a low-HDOP single fix
    Gnss   // fixQuality 1/unknown — consumer phone GNSS; noisiest
};

// Map a fix quality + HDOP onto a tier. hdopValid==false means "no DOP packet"
// (common on this StarFire tap) and is treated as unknown.
Tier tierFor(int fixQuality, double hdop, bool hdopValid);

// One Euro filter (Casiez, Roussel & Vogel, 2012): a speed-adaptive low-pass.
// Heavy smoothing when the signal is slow/stationary (kills standstill drift),
// light smoothing when it moves fast (stays responsive, low lag). Tuned by
// mincutoff (Hz, the slow-signal smoothing floor) and beta (how fast the cutoff
// opens up with signal speed).
class OneEuro {
public:
    void reset() { m_init = false; }
    bool initialized() const { return m_init; }
    // dt in seconds (must be > 0). Returns the filtered value.
    double filter(double value, double dt, double mincutoff, double beta,
                  double dcutoff);

private:
    static double alpha(double dt, double cutoff);
    double m_xPrev = 0.0;
    double m_dxPrev = 0.0;
    bool m_init = false;
};

// Tier-aware smoothing of a 2D position (local ENU metres) plus a heading
// derived from the smoothed track. Stateful across samples; one instance per
// GPS stream. Feed raw ENU x/y (east/north metres vs a fixed origin), the
// current speed, dt, the tier and the implement width; read back filtered
// x/y and a steady heading.
class GpsFilter {
public:
    struct Output {
        double x = 0.0;            // filtered east metres
        double y = 0.0;            // filtered north metres
        double headingDeg = 0.0;   // 0 = north, 90 = east (compass), clockwise
        bool headingValid = false; // false until a track heading is established
    };

    void reset();

    // rawX/rawY: raw position in local ENU metres (east, north).
    // speedKmh:  ground speed (for the low-speed heading hold).
    // dtSec:     seconds since the previous sample (clamped internally).
    // widthM:    implement/boom width — wider booms get steadier heading.
    // trueHeadingDeg: >= 0 when an authoritative heading (e.g. dual-antenna
    //            $..HDT) is present, so we trust it instead of the track bearing;
    //            pass < 0 (the default) for course-over-ground / phone GNSS.
    Output update(double rawX, double rawY, double speedKmh, double dtSec,
                  Tier tier, double widthM, double trueHeadingDeg = -1.0);

private:
    OneEuro m_fx, m_fy;
    bool m_havePos = false;
    double m_lastX = 0.0;
    double m_lastY = 0.0;
    // Heading is held as a unit vector (sin/cos of the bearing) so the EMA wraps
    // correctly across 360/0 deg.
    bool m_haveHeading = false;
    double m_sinH = 0.0;
    double m_cosH = 1.0;
    double m_headingDeg = 0.0;
};

} // namespace gpsfilter
