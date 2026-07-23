#include "gpsfilter.h"

#include <cmath>

namespace gpsfilter {

// ---------------------------------------------------------------------------
// Tuning constants (automatic — there are no user-facing knobs). These are
// reasonable starting points; tune them offline against a captured track with
// tools/gps_replay, then update both here and GPS_SMOOTHING.md.
// ---------------------------------------------------------------------------

namespace {

constexpr double kPi = 3.14159265358979323846;

// One Euro position filter, per tier. mincutoff is in Hz (lower = smoother when
// slow), beta scales the cutoff with motion (higher = snappier when moving).
struct EuroParams { double mincutoff; double beta; };
constexpr EuroParams kEuroRtk  = { 5.00, 0.50 }; // near pass-through (10 Hz clean)
constexpr EuroParams kEuroSbas = { 1.00, 0.20 }; // moderate
constexpr EuroParams kEuroGnss = { 0.30, 0.05 }; // aggressive (phone GNSS)
constexpr double kDcutoff = 1.0;                 // derivative low-pass cutoff (Hz)

// Heading: EMA on the track bearing whose time-constant grows with boom width.
// Lateral error at the boom tip ~= (width/2)*sin(heading_error), so a wider boom
// needs a steadier heading. tau = tauBase[tier] + kWidth*widthM, capped.
constexpr double kHeadTauRtk  = 0.20; // s
constexpr double kHeadTauSbas = 0.40; // s
// Tablet / phone GNSS COG is noisy — longer EMA before the boom follows.
constexpr double kHeadTauGnss = 1.60; // s
constexpr double kHeadKWidth  = 0.05; // s per metre of width
constexpr double kHeadTauMax  = 3.50; // s — cap so steering never feels dead

// Below this ground speed GPS course/track is meaningless: freeze heading so it
// cannot spin from position noise at standstill. GNSS needs a higher floor —
// Android often reports 1–2 km/h chatter while parked.
constexpr double kHoldSpeedRtkKmh  = 0.8;
constexpr double kHoldSpeedSbasKmh = 1.0;
constexpr double kHoldSpeedGnssKmh = 2.2;
// Minimum filtered displacement before a new bearing is computed (m). Guards
// against a near-zero step producing a garbage atan2 direction. Consumer GNSS
// position noise is metres-scale, so require a real move before updating.
constexpr double kMinStepRtkM  = 0.05;
constexpr double kMinStepSbasM = 0.25;
constexpr double kMinStepGnssM = 1.50;
// dt guards: a non-positive or absurd gap (first sample, stream stall) is
// replaced by a nominal 10 Hz step so the filter stays stable.
constexpr double kNominalDt = 0.1;
constexpr double kMaxDt = 1.0;

EuroParams euroFor(Tier t)
{
    switch (t) {
    case Tier::Rtk:  return kEuroRtk;
    case Tier::Sbas: return kEuroSbas;
    case Tier::Gnss: default: return kEuroGnss;
    }
}

double headTauBase(Tier t)
{
    switch (t) {
    case Tier::Rtk:  return kHeadTauRtk;
    case Tier::Sbas: return kHeadTauSbas;
    case Tier::Gnss: default: return kHeadTauGnss;
    }
}

double holdSpeedKmh(Tier t)
{
    switch (t) {
    case Tier::Rtk:  return kHoldSpeedRtkKmh;
    case Tier::Sbas: return kHoldSpeedSbasKmh;
    case Tier::Gnss: default: return kHoldSpeedGnssKmh;
    }
}

double minStepM(Tier t)
{
    switch (t) {
    case Tier::Rtk:  return kMinStepRtkM;
    case Tier::Sbas: return kMinStepSbasM;
    case Tier::Gnss: default: return kMinStepGnssM;
    }
}

double clampDt(double dt)
{
    if (!(dt > 0.0) || dt > kMaxDt)
        return kNominalDt;
    return dt;
}

double norm360(double deg)
{
    deg = std::fmod(deg, 360.0);
    if (deg < 0.0)
        deg += 360.0;
    return deg;
}

} // namespace

Tier tierFor(int fixQuality, double hdop, bool hdopValid)
{
    if (fixQuality == 4 || fixQuality == 5)
        return Tier::Rtk;
    if (fixQuality == 2 || fixQuality == 3)
        return Tier::Sbas;
    // fixQuality 1 or unknown — single-point GNSS. A genuinely low HDOP still
    // earns the moderate tier; otherwise assume noisy consumer GNSS.
    if (hdopValid && hdop > 0.0 && hdop < 1.0)
        return Tier::Sbas;
    return Tier::Gnss;
}

// ---------------------------------------------------------------------------
// OneEuro
// ---------------------------------------------------------------------------

double OneEuro::alpha(double dt, double cutoff)
{
    const double tau = 1.0 / (2.0 * kPi * cutoff);
    return 1.0 / (1.0 + tau / dt);
}

double OneEuro::filter(double value, double dt, double mincutoff, double beta,
                       double dcutoff)
{
    if (!m_init) {
        m_xPrev = value;
        m_dxPrev = 0.0;
        m_init = true;
        return value;
    }
    const double dx = (value - m_xPrev) / dt;
    const double aD = alpha(dt, dcutoff);
    const double dxHat = aD * dx + (1.0 - aD) * m_dxPrev;
    m_dxPrev = dxHat;

    const double cutoff = mincutoff + beta * std::fabs(dxHat);
    const double aC = alpha(dt, cutoff);
    const double xHat = aC * value + (1.0 - aC) * m_xPrev;
    m_xPrev = xHat;
    return xHat;
}

// ---------------------------------------------------------------------------
// GpsFilter
// ---------------------------------------------------------------------------

void GpsFilter::reset()
{
    m_fx.reset();
    m_fy.reset();
    m_havePos = false;
    m_haveHeading = false;
    m_sinH = 0.0;
    m_cosH = 1.0;
    m_headingDeg = 0.0;
}

GpsFilter::Output GpsFilter::update(double rawX, double rawY, double speedKmh,
                                    double dtSec, Tier tier, double widthM,
                                    double trueHeadingDeg)
{
    const double dt = clampDt(dtSec);
    const EuroParams ep = euroFor(tier);

    Output out;
    out.x = m_fx.filter(rawX, dt, ep.mincutoff, ep.beta, kDcutoff);
    out.y = m_fy.filter(rawY, dt, ep.mincutoff, ep.beta, kDcutoff);

    if (trueHeadingDeg >= 0.0) {
        // JD TCM / dual-antenna yaw is authoritative. A 50 ms EMA let single-
        // sample TCM jitter whip wide booms (tips move ~0.3 m per 1° on 36 m).
        // Full boom-width τ (~2 s) lagged too much; 0.28 s + slew cap keeps the
        // implement steady without the old “sway” look.
        constexpr double kTrueHeadTau = 0.28; // seconds
        constexpr double kTrueHeadMaxDegPerSec = 40.0;
        double target = trueHeadingDeg;
        if (m_haveHeading) {
            double d = target - m_headingDeg;
            while (d > 180.0) d -= 360.0;
            while (d < -180.0) d += 360.0;
            const double maxStep = kTrueHeadMaxDegPerSec * dt;
            if (d > maxStep) d = maxStep;
            if (d < -maxStep) d = -maxStep;
            // Ignore sub-degree chatter that still moves boom tips a lot.
            if (std::fabs(d) < 0.35)
                d = 0.0;
            target = m_headingDeg + d;
        }
        const double aTrue = dt / (kTrueHeadTau + dt);
        const double br = target * kPi / 180.0;
        const double s = std::sin(br), c = std::cos(br);
        if (!m_haveHeading) {
            m_sinH = s; m_cosH = c; m_haveHeading = true;
        } else {
            m_sinH += aTrue * (s - m_sinH);
            m_cosH += aTrue * (c - m_cosH);
        }
        m_headingDeg = norm360(std::atan2(m_sinH, m_cosH) * 180.0 / kPi);
    } else if (m_havePos && speedKmh >= holdSpeedKmh(tier)) {
        // Track-derived COG: width-scaled EMA (noisy at RTK centimetre scale).
        double tau = headTauBase(tier) + kHeadKWidth * (widthM > 0.0 ? widthM : 0.0);
        if (tau > kHeadTauMax)
            tau = kHeadTauMax;
        const double aHead = dt / (tau + dt);
        const double dEast = out.x - m_lastX;
        const double dNorth = out.y - m_lastY;
        if (std::sqrt(dEast * dEast + dNorth * dNorth) >= minStepM(tier)) {
            // Compass bearing: 0 = north, 90 = east -> atan2(east, north).
            const double br = std::atan2(dEast, dNorth);
            const double s = std::sin(br), c = std::cos(br);
            if (!m_haveHeading) {
                m_sinH = s; m_cosH = c; m_haveHeading = true;
            } else {
                m_sinH += aHead * (s - m_sinH);
                m_cosH += aHead * (c - m_cosH);
            }
            m_headingDeg = norm360(std::atan2(m_sinH, m_cosH) * 180.0 / kPi);
        }
        // else: too small a step this tick — hold the last heading.
    }
    // else: below the hold speed (or first fix) — freeze the last good heading.

    m_lastX = out.x;
    m_lastY = out.y;
    m_havePos = true;

    out.headingDeg = m_headingDeg;
    out.headingValid = m_haveHeading;
    return out;
}

} // namespace gpsfilter
