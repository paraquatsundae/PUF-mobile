#include "gpsmodel.h"

#include <QStringList>
#include <QTimer>
#include <QtMath>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTextStream>
#include <cmath>

GpsModel::GpsModel(QObject *parent) : QObject(parent)
{
    // Trailing edge of the fixChanged coalescer: guarantees the last fix in a
    // burst is delivered even if it arrived inside the rate-limit window.
    m_emitTimer = new QTimer(this);
    m_emitTimer->setSingleShot(true);
    connect(m_emitTimer, &QTimer::timeout, this, &GpsModel::emitFixNow);

    // JD bridge sends GGA+RMC+VTG+PANDA in one UDP datagram. Defer the ENU filter
    // to the next event-loop turn so PANDA's TCM heading/quality win, and so we
    // only take one filter step per fix (not four with tiny dt).
    m_filterTimer = new QTimer(this);
    m_filterTimer->setSingleShot(true);
    connect(m_filterTimer, &QTimer::timeout, this, &GpsModel::runScheduledFilter);
}

GpsModel::~GpsModel()
{
    setRawLogging(false); // flush + close any open capture
}

QString GpsModel::fixText() const
{
    switch (m_fixQuality) {
    case 0: return QStringLiteral("No fix");
    case 1: return QStringLiteral("GPS");
    case 2: return QStringLiteral("DGPS");
    case 3: return QStringLiteral("PPS");
    case 4: return QStringLiteral("RTK Fixed");
    case 5: return QStringLiteral("RTK Float");
    case 6: return QStringLiteral("Estimated");
    case 7: return QStringLiteral("Manual");
    case 8: return QStringLiteral("Simulation");
    default: return QStringLiteral("Unknown");
    }
}

double GpsModel::ageSeconds() const
{
    if (!m_lastFix.isValid())
        return 999.0;
    return m_lastFix.msecsTo(QDateTime::currentDateTimeUtc()) / 1000.0;
}

void GpsModel::tick()
{
    emit ageChanged();
}

bool GpsModel::checksumOk(const QString &sentence)
{
    const int star = sentence.indexOf('*');
    if (star < 0)
        return true; // no checksum present; accept

    int dollar = sentence.indexOf('$');
    if (dollar < 0)
        dollar = -1;

    unsigned char cs = 0;
    for (int i = dollar + 1; i < star; ++i)
        cs ^= static_cast<unsigned char>(sentence.at(i).toLatin1());

    bool ok = false;
    const QString hex = sentence.mid(star + 1, 2);
    const int given = hex.toInt(&ok, 16);
    return ok && given == cs;
}

double GpsModel::nmeaToDegrees(const QString &val, const QString &hemi)
{
    if (val.isEmpty())
        return 0.0;
    bool ok = false;
    const double raw = val.toDouble(&ok);
    if (!ok)
        return 0.0;
    const double deg = std::floor(raw / 100.0);
    const double minutes = raw - deg * 100.0;
    double result = deg + minutes / 60.0;
    if (hemi == QLatin1String("S") || hemi == QLatin1String("W"))
        result = -result;
    return result;
}

void GpsModel::feed(const QString &lineIn)
{
    QString line = lineIn.trimmed();
    if (line.isEmpty() || !line.startsWith('$'))
        return;
    if (!checksumOk(line))
        return;

    // Strip checksum for field splitting.
    const int star = line.indexOf('*');
    const QString body = (star >= 0) ? line.left(star) : line;
    const QStringList f = body.split(',');
    if (f.isEmpty())
        return;

    const QString type = f.at(0); // e.g. $GPGGA, $GNRMC, $PANDA
    const QString tail = type.right(3);

    bool changed = false;
    if (type == QLatin1String("$PANDA") || type == QLatin1String("$PAOGI"))
        changed = parsePANDA(f);
    else if (tail == QLatin1String("GGA"))
        changed = parseGGA(f);
    else if (tail == QLatin1String("RMC"))
        changed = parseRMC(f);
    else if (tail == QLatin1String("VTG"))
        changed = parseVTG(f);
    else if (tail == QLatin1String("HDT"))
        changed = parseHDT(f);

    if (changed) {
        m_lastSentence = line;
        ++m_count;
        m_lastFix = QDateTime::currentDateTimeUtc();
        // Append the RAW fix to the capture CSV (no-op unless logging is on).
        // Done before updateLocal so the log is purely raw, independent of the
        // filter — that is what the offline tuning harness needs.
        if (m_rawLog)
            logRawFix();
        scheduleFilterUpdate();
    }
}

void GpsModel::scheduleFilterUpdate()
{
    m_filterPending = true;
    if (!m_filterTimer->isActive())
        m_filterTimer->start(0);
}

void GpsModel::runScheduledFilter()
{
    if (!m_filterPending)
        return;
    m_filterPending = false;
    // First valid fix flips hasOrigin — deliver immediately (un-coalesced) so
    // boundary / AB / paddock bindings see the transition in the same tick.
    if (updateLocal())
        emitFixNow();
    else
        noteFixChanged();
}

void GpsModel::noteFixChanged()
{
    // First fix (or first after an idle gap) fires immediately so the UI is
    // responsive; further fixes within kMinEmitMs are coalesced into a single
    // trailing emit, capping QML/coverage churn at ~10 Hz regardless of how many
    // datagrams arrive in one readyRead burst.
    if (!m_emitClock.isValid() || m_emitClock.elapsed() >= kMinEmitMs) {
        emitFixNow();
        return;
    }
    m_emitPending = true;
    if (!m_emitTimer->isActive())
        m_emitTimer->start(kMinEmitMs - int(m_emitClock.elapsed()));
}

void GpsModel::emitFixNow()
{
    m_emitPending = false;
    m_emitClock.restart();
    emit fixChanged();
    emit ageChanged();
}

bool GpsModel::updateLocal()
{
    if (m_fixQuality <= 0)
        return false;
    // Never seed the local frame from (0,0) / empty NMEA — that put paddocks
    // off-screen (_maxLocalM clamp) when JD GPS connected before a real fix.
    if (!std::isfinite(m_lat) || !std::isfinite(m_lon)
        || m_lat < -90.0 || m_lat > 90.0 || m_lon < -180.0 || m_lon > 180.0
        || (std::fabs(m_lat) < 1e-7 && std::fabs(m_lon) < 1e-7))
        return false;
    bool originSet = false;
    if (!m_haveOrigin) {
        m_lat0 = m_lat;
        m_lon0 = m_lon;
        m_haveOrigin = true;
        originSet = true;
    }
    // Equirectangular approximation around the origin (fine at field scale).
    const double k = 111320.0; // metres per degree
    const double cosLat0 = qCos(qDegreesToRadians(m_lat0));
    const double rawX = (m_lon - m_lon0) * k * cosLat0;       // raw east metres
    const double rawY = (m_lat - m_lat0) * k;                 // raw north metres

    // ---- Automatic GPS smoothing (see gpsfilter.* / GPS_SMOOTHING.md) -----
    // The 1€ filter runs on ENU metres (avoids lat/lon scaling issues), is
    // speed-adaptive (heavy when slow/stationary, light when fast so boom lag
    // stays small), and heading is derived from the smoothed track with a
    // width-scaled EMA. Constants come from the fix-quality/HDOP tier.
    double dt = 0.0;
    if (m_filterClock.isValid())
        dt = m_filterClock.elapsed() / 1000.0;
    m_filterClock.restart();
    const gpsfilter::Tier tier = gpsfilter::tierFor(m_fixQuality, m_hdop, m_hdopValid);
    // Authoritative heading: $HDT or JD TCM yaw on $PANDA. Otherwise the filter
    // derives course from the smoothed track (noisy at RTK centimetre scale).
    const double trueHeading = m_haveTrueHeading ? m_heading : -1.0;
    const gpsfilter::GpsFilter::Output o =
        m_filter.update(rawX, rawY, m_speedKmh, dt, tier, m_implementWidth, trueHeading);

    m_localX = o.x;
    m_localY = o.y;
    // Mirror the filtered ENU back to WGS84 so latitude()/longitude() are the
    // canonical (smoothed) fix consumers read.
    m_fLat = m_lat0 + m_localY / k;
    m_fLon = m_lon0 + (cosLat0 != 0.0 ? m_localX / (k * cosLat0) : 0.0);
    // Until the track establishes a heading (e.g. before moving), fall back to
    // the raw course/HDT heading so the UI is not stuck pointing north.
    m_fHeading = o.headingValid ? o.headingDeg : m_heading;
    m_haveFiltered = true;
    return originSet;
}

void GpsModel::resetOrigin()
{
    m_haveOrigin = false;
    m_localX = 0.0;
    m_localY = 0.0;
    // Re-zeroing the frame invalidates the filter's accumulated track/position,
    // so restart it; the next fix re-initialises it at the new origin.
    m_filter.reset();
    m_filterClock.invalidate();
    m_haveFiltered = false;
    updateLocal();
    emit fixChanged();
}

void GpsModel::setOrigin(double lat, double lon)
{
    // Reject a non-finite or out-of-range origin (e.g. NaN/garbage from a corrupt
    // job metadata.json). A bad origin makes the whole local frame NaN/huge, which
    // turns every boundary/coverage polyline into a degenerate or enormous geometry
    // and crashes the Mali-400 GL ES2 backend. Keep any existing/live origin.
    if (!std::isfinite(lat) || !std::isfinite(lon)
        || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0)
        return;
    m_lat0 = lat;
    m_lon0 = lon;
    m_haveOrigin = true;
    // Pinning to a new origin (e.g. re-entering a saved job) breaks filter
    // continuity; restart so it re-seeds against this frame.
    m_filter.reset();
    m_filterClock.invalidate();
    m_haveFiltered = false;
    updateLocal();
    emit fixChanged();
}

QPointF GpsModel::toLocal(double lat, double lon) const
{
    if (!m_haveOrigin)
        return QPointF(0.0, 0.0);
    const double k = 111320.0;
    const double east = (lon - m_lon0) * k * qCos(qDegreesToRadians(m_lat0));
    const double north = (lat - m_lat0) * k;
    return QPointF(east, north);
}

QVariantMap GpsModel::toGeo(double east, double north) const
{
    QVariantMap m;
    const double k = 111320.0;
    const double cosLat0 = qCos(qDegreesToRadians(m_lat0));
    m["lat"] = m_lat0 + north / k;
    m["lon"] = m_lon0 + (cosLat0 != 0.0 ? east / (k * cosLat0) : 0.0);
    return m;
}

QVariantMap GpsModel::recordingPoint(double offset) const
{
    // Use the canonical (filtered) position + heading so captured boundary/AB
    // points line up with the smoothed coverage track.
    const double lat = m_haveFiltered ? m_fLat : m_lat;
    const double lon = m_haveFiltered ? m_fLon : m_lon;
    const double hr = qDegreesToRadians(m_fHeading);
    const double k = 111320.0;
    // Move `offset` metres opposite the travel direction (behind the tractor).
    const double dNorth = -offset * qCos(hr);
    const double dEast = -offset * qSin(hr);
    QVariantMap m;
    m["lat"] = lat + dNorth / k;
    m["lon"] = lon + dEast / (k * qCos(qDegreesToRadians(lat)));
    return m;
}

void GpsModel::setRawLogging(bool on)
{
    if (on == (m_rawLog != nullptr))
        return;

    if (!on) {
        if (m_rawLogStream)
            m_rawLogStream->flush();
        delete m_rawLogStream;
        m_rawLogStream = nullptr;
        if (m_rawLog)
            m_rawLog->close();
        delete m_rawLog;
        m_rawLog = nullptr;
        return;
    }

    // Capture lands in a user-reachable folder so the operator can pull a pass
    // over adb/MTP and feed it to tools/gps_replay for offline tuning.
#ifdef Q_OS_ANDROID
    const QString dir = QStringLiteral("/storage/emulated/0/Download/PUF-mobile/recordings");
#else
    QString base = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (base.isEmpty())
        base = QDir::homePath();
    const QString dir = base + QStringLiteral("/PUF-mobile/recordings");
#endif
    QDir().mkpath(dir);
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    m_rawLogPath = dir + QStringLiteral("/rawtrack_") + stamp + QStringLiteral(".csv");

    m_rawLog = new QFile(m_rawLogPath);
    if (!m_rawLog->open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Append)) {
        delete m_rawLog;
        m_rawLog = nullptr;
        m_rawLogPath.clear();
        return;
    }
    m_rawLogStream = new QTextStream(m_rawLog);
    // Header consumed by tools/gps_replay (skipped on parse if the first field
    // is non-numeric). timestamp is epoch milliseconds.
    (*m_rawLogStream) << "timestamp,raw_lat,raw_lon,raw_heading,raw_speed,fix_quality,hdop\n";
    m_rawLogStream->flush();
}

void GpsModel::logRawFix()
{
    if (!m_rawLogStream)
        return;
    (*m_rawLogStream)
        << QDateTime::currentMSecsSinceEpoch() << ','
        << QString::number(m_lat, 'f', 8) << ','
        << QString::number(m_lon, 'f', 8) << ','
        << QString::number(m_heading, 'f', 3) << ','
        << QString::number(m_speedKmh, 'f', 3) << ','
        << m_fixQuality << ',';
    if (m_hdopValid)
        (*m_rawLogStream) << QString::number(m_hdop, 'f', 2);
    (*m_rawLogStream) << '\n';
    m_rawLogStream->flush();
}

bool GpsModel::parseGGA(const QStringList &f)
{
    // $xxGGA,time,lat,N,lon,E,fixQ,sats,hdop,alt,M,...
    if (f.size() < 10)
        return false;
    m_utc = f.at(1);
    if (!f.at(2).isEmpty())
        m_lat = nmeaToDegrees(f.at(2), f.at(3));
    if (!f.at(4).isEmpty())
        m_lon = nmeaToDegrees(f.at(4), f.at(5));
    m_fixQuality = f.at(6).toInt();
    // Satellite count comes from StarFire PGN 0xFFFF (sub-msg 0x51) via the bridge;
    // HDOP stays blank (no GNSS DOP packet on this tap — see DEV_NOTES.md).
    // Treat empty fields as "unknown" rather than reporting a fake 0.
    m_satsValid = !f.at(7).isEmpty();
    if (m_satsValid)
        m_sats = f.at(7).toInt();
    m_hdopValid = !f.at(8).isEmpty();
    if (m_hdopValid)
        m_hdop = f.at(8).toDouble();
    m_alt = f.at(9).toDouble();
    return true;
}

bool GpsModel::parseRMC(const QStringList &f)
{
    // $xxRMC,time,status,lat,N,lon,E,knots,course,date,...
    if (f.size() < 9)
        return false;
    m_utc = f.at(1);
    const bool valid = (f.at(2) == QLatin1String("A"));
    if (valid && !f.at(3).isEmpty())
        m_lat = nmeaToDegrees(f.at(3), f.at(4));
    if (valid && !f.at(5).isEmpty())
        m_lon = nmeaToDegrees(f.at(5), f.at(6));
    if (!f.at(7).isEmpty())
        m_speedKmh = f.at(7).toDouble() * 1.852; // knots -> km/h
    // Course-over-ground is only meaningful when actually moving. Hold the last
    // heading at standstill, and never let COG override a true (HDT) heading.
    if (!m_haveTrueHeading && !f.at(8).isEmpty() && m_speedKmh >= kStationaryKmh)
        m_heading = f.at(8).toDouble();
    if (!valid && m_fixQuality == 0)
        m_fixQuality = 0;
    return true;
}

bool GpsModel::parseVTG(const QStringList &f)
{
    // $xxVTG,course,T,,M,knots,N,kmh,K,...
    if (f.size() < 8)
        return false;
    if (!f.at(7).isEmpty())
        m_speedKmh = f.at(7).toDouble();
    if (!m_haveTrueHeading && !f.at(1).isEmpty() && m_speedKmh >= kStationaryKmh)
        m_heading = f.at(1).toDouble();
    return true;
}

bool GpsModel::parseHDT(const QStringList &f)
{
    // $xxHDT,heading,T*cs  -- true heading (e.g. dual-antenna / INS).
    if (f.size() < 2 || f.at(1).isEmpty())
        return false;
    m_heading = f.at(1).toDouble();
    m_haveTrueHeading = true;
    return true;
}

bool GpsModel::parsePANDA(const QStringList &f)
{
    // $PANDA,time,lat,N,lon,E,fixQ,sats,hdop,alt,age,speed,heading,roll,pitch,yawrate
    if (f.size() < 10)
        return false;
    m_utc = f.at(1);
    if (!f.at(2).isEmpty())
        m_lat = nmeaToDegrees(f.at(2), f.at(3));
    if (!f.at(4).isEmpty())
        m_lon = nmeaToDegrees(f.at(4), f.at(5));
    m_fixQuality = f.at(6).toInt();
    // Sats from StarFire PGN 0xFFFF via bridge; HDOP blank (see parseGGA / DEV_NOTES.md).
    m_satsValid = !f.at(7).isEmpty();
    if (m_satsValid)
        m_sats = f.at(7).toInt();
    m_hdopValid = !f.at(8).isEmpty();
    if (m_hdopValid)
        m_hdop = f.at(8).toDouble();
    m_alt = f.at(9).toDouble();
    if (f.size() > 11 && !f.at(11).isEmpty())
        m_speedKmh = f.at(11).toDouble(); // AgOpenGPS PANDA speed (km/h)
    // TCM attitude fields (roll/pitch/yaw) — parsed for the GPS info page.
    // Terrain-comp into coverage is PARKED in RecordPoint.js (FEE6 roll bogus;
    // FEE8 pitch has a large constant bias). hasAttitude stays false so coverage
    // never pitch-only-shifts.
    if (f.size() > 13 && !f.at(13).isEmpty())
        m_roll = f.at(13).toDouble();
    if (f.size() > 14 && !f.at(14).isEmpty())
        m_pitch = f.at(14).toDouble();
    if (f.size() > 15 && !f.at(15).isEmpty())
        m_yawRate = f.at(15).toDouble();
    if (f.size() > 12 && !f.at(12).isEmpty()) {
        m_heading = f.at(12).toDouble();
        // True heading ONLY when TCM attitude accompanies the sentence (JD
        // StarFire FEE8 via the bridge). Tablet GPS also emits $PANDA with
        // Android Location.bearing but no roll/pitch — that bearing is often
        // stale/wrong when slow and must NOT lock haveTrueHeading (filter then
        // skips track-derived heading → wild boom swings).
        const bool hasTcm = (f.size() > 13 && !f.at(13).isEmpty())
                         || (f.size() > 14 && !f.at(14).isEmpty())
                         || (f.size() > 15 && !f.at(15).isEmpty());
        // Clear as well as set — switching JD → tablet must drop the lock.
        m_haveTrueHeading = hasTcm;
    }
    return true;
}
