#pragma once

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QPointF>
#include <QVariantMap>
#include <QElapsedTimer>

#include "gpsfilter.h"

class QTimer;
class QFile;
class QTextStream;

// Holds the current GPS fix and parses NMEA-0183 (GGA/RMC/VTG/GSA) plus the
// AgOpenGPS $PANDA/$PAOGI sentences. Exposed to QML as a context property.
class GpsModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double latitude READ latitude NOTIFY fixChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY fixChanged)
    Q_PROPERTY(double altitude READ altitude NOTIFY fixChanged)
    Q_PROPERTY(double speedKmh READ speedKmh NOTIFY fixChanged)
    Q_PROPERTY(double headingDeg READ headingDeg NOTIFY fixChanged)
    Q_PROPERTY(int fixQuality READ fixQuality NOTIFY fixChanged)
    Q_PROPERTY(QString fixText READ fixText NOTIFY fixChanged)
    Q_PROPERTY(int satellites READ satellites NOTIFY fixChanged)
    Q_PROPERTY(bool satellitesValid READ satellitesValid NOTIFY fixChanged)
    Q_PROPERTY(double hdop READ hdop NOTIFY fixChanged)
    Q_PROPERTY(bool hdopValid READ hdopValid NOTIFY fixChanged)
    // TCM (terrain compensation) attitude — carried by the $PANDA sentence.
    Q_PROPERTY(double rollDeg READ rollDeg NOTIFY fixChanged)
    Q_PROPERTY(double pitchDeg READ pitchDeg NOTIFY fixChanged)
    Q_PROPERTY(double yawRateDegS READ yawRateDegS NOTIFY fixChanged)
    Q_PROPERTY(bool hasAttitude READ hasAttitude NOTIFY fixChanged)
    Q_PROPERTY(QString utcTime READ utcTime NOTIFY fixChanged)
    Q_PROPERTY(bool hasFix READ hasFix NOTIFY fixChanged)
    Q_PROPERTY(double ageSeconds READ ageSeconds NOTIFY ageChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY ageChanged)
    Q_PROPERTY(QString lastSentence READ lastSentence NOTIFY fixChanged)
    Q_PROPERTY(int sentenceCount READ sentenceCount NOTIFY fixChanged)
    Q_PROPERTY(double localX READ localX NOTIFY fixChanged)   // metres east of origin
    Q_PROPERTY(double localY READ localY NOTIFY fixChanged)   // metres north of origin
    Q_PROPERTY(bool hasOrigin READ hasOrigin NOTIFY fixChanged)

public:
    explicit GpsModel(QObject *parent = nullptr);
    ~GpsModel() override;

    // Canonical (filtered) values consumed by coverage + UI. Before the local
    // frame origin is set (and thus before the filter has run) these fall back
    // to the raw parse so the very first fix is never (0,0)/NaN.
    double latitude() const { return m_haveFiltered ? m_fLat : m_lat; }
    double longitude() const { return m_haveFiltered ? m_fLon : m_lon; }
    double altitude() const { return m_alt; }
    double speedKmh() const { return m_speedKmh; }
    double headingDeg() const { return m_fHeading; }

    // Raw, unfiltered parse — used by the raw-track logger and available to any
    // consumer that needs the unsmoothed fix.
    double rawLatitude() const { return m_lat; }
    double rawLongitude() const { return m_lon; }
    double rawHeadingDeg() const { return m_heading; }
    int fixQuality() const { return m_fixQuality; }
    QString fixText() const;
    int satellites() const { return m_sats; }
    bool satellitesValid() const { return m_satsValid; }
    double hdop() const { return m_hdop; }
    bool hdopValid() const { return m_hdopValid; }
    double rollDeg() const { return m_roll; }
    double pitchDeg() const { return m_pitch; }
    double yawRateDegS() const { return m_yawRate; }
    bool hasAttitude() const { return m_haveAttitude; }
    QString utcTime() const { return m_utc; }
    bool hasFix() const { return m_fixQuality > 0; }
    double ageSeconds() const;
    bool stale() const { return ageSeconds() > 2.0; }
    QString lastSentence() const { return m_lastSentence; }
    int sentenceCount() const { return m_count; }
    double localX() const { return m_localX; }
    double localY() const { return m_localY; }
    bool hasOrigin() const { return m_haveOrigin; }
    Q_INVOKABLE double originLat() const { return m_lat0; }
    Q_INVOKABLE double originLon() const { return m_lon0; }

    // Current implement/boom width (metres). Fed in from AppController so the
    // automatic GPS smoothing can damp heading more for wider booms. Does not
    // emit — it only tunes the filter on the next fix.
    void setImplementWidth(double w) { m_implementWidth = w; }

    // Raw-track logger: when enabled, every parsed fix is appended to a CSV in
    // the Download/PUF-mobile/recordings folder (see rawLogPath). Toggled on
    // with coverage recording so the user can drive one pass and capture real
    // data for offline filter tuning (tools/gps_replay).
    Q_INVOKABLE void setRawLogging(bool on);
    Q_INVOKABLE bool rawLogging() const { return m_rawLog != nullptr; }
    Q_INVOKABLE QString rawLogPath() const { return m_rawLogPath; }

    // Re-zero the local frame to the current position.
    Q_INVOKABLE void resetOrigin();
    // Pin the local frame to a specific WGS84 point. Used when re-entering a
    // saved job so stored coverage lines up with this session's fixes.
    Q_INVOKABLE void setOrigin(double lat, double lon);

    // Convert a WGS84 point to local metres (x=east, y=north) vs the origin,
    // for drawing stored geometry on the heading-up map.
    Q_INVOKABLE QPointF toLocal(double lat, double lon) const;
    // Inverse of toLocal: local metres (east, north) back to WGS84 lat/lon,
    // for serialising worked coverage to a world-referenced (GeoJSON) file.
    Q_INVOKABLE QVariantMap toGeo(double east, double north) const;
    // Lat/lon of the implement recording point, `offset` metres behind the
    // tractor along the current heading (used for boundary/AB capture).
    Q_INVOKABLE QVariantMap recordingPoint(double offset) const;

public slots:
    // Feed one NMEA/PANDA sentence (with or without checksum).
    void feed(const QString &line);
    // Recompute age/stale (call ~2 Hz from a timer).
    void tick();

signals:
    void fixChanged();
    void ageChanged();

private:
    bool parseGGA(const QStringList &f);
    bool parseRMC(const QStringList &f);
    bool parseVTG(const QStringList &f);
    bool parseHDT(const QStringList &f);
    bool parsePANDA(const QStringList &f);
    static bool checksumOk(const QString &sentence);
    static double nmeaToDegrees(const QString &val, const QString &hemi);

    // Coalesce fixChanged to <= ~10 Hz. State is updated on every parsed sentence,
    // but the UI/coverage notification is rate-limited so a burst/backlog of
    // datagrams (e.g. when the bridge first connects) cannot wedge the GUI thread
    // with one full QML relayout + coverage pass per datagram.
    void noteFixChanged();
    void emitFixNow();
    // Run the ENU filter once per NMEA burst (GGA+RMC+VTG+PANDA arrive together
    // from the JD bridge). Filtering every sentence with ~0 dt causes boom jitter.
    void scheduleFilterUpdate();
    void runScheduledFilter();
    QTimer *m_emitTimer = nullptr;
    QTimer *m_filterTimer = nullptr;
    QElapsedTimer m_emitClock;
    bool m_emitPending = false;
    bool m_filterPending = false;
    // ~20 Hz UI/coverage updates. Lower felt like the machine was jolting.
    static constexpr int kMinEmitMs = 50;

    double m_lat = 0.0;
    double m_lon = 0.0;
    double m_alt = 0.0;
    double m_speedKmh = 0.0;
    double m_heading = 0.0;
    int m_fixQuality = 0;
    int m_sats = 0;
    bool m_satsValid = false;
    double m_hdop = 0.0;
    bool m_hdopValid = false;
    double m_roll = 0.0;
    double m_pitch = 0.0;
    double m_yawRate = 0.0;
    bool m_haveAttitude = false; // set once a $PANDA roll/pitch field is seen
    QString m_utc;
    QString m_lastSentence;
    int m_count = 0;
    QDateTime m_lastFix;
    // Authoritative heading: $..HDT or JD TCM yaw on $PANDA (FEE8 via bridge).
    bool m_haveTrueHeading = false;

    // Returns true if this call established the local-frame origin for the first
    // time, so the caller can deliver the hasOrigin true-transition immediately
    // (un-coalesced) — bindings on gps.hasOrigin must not wait for a trailing emit.
    bool updateLocal();
    double m_localX = 0.0;   // FILTERED east metres (canonical, fed to coverage)
    double m_localY = 0.0;   // FILTERED north metres
    double m_lat0 = 0.0;
    double m_lon0 = 0.0;
    bool m_haveOrigin = false;

    // ---- Automatic GPS smoothing -----------------------------------------
    // The filter runs on local ENU metres (in updateLocal) between the raw parse
    // and what coverage/UI read. m_lat/m_lon/m_heading stay raw; the canonical
    // filtered fix is mirrored back into these members + m_localX/m_localY.
    gpsfilter::GpsFilter m_filter;
    QElapsedTimer m_filterClock;  // dt between fixes for the speed-adaptive filter
    double m_fLat = 0.0;          // filtered latitude (canonical)
    double m_fLon = 0.0;          // filtered longitude (canonical)
    double m_fHeading = 0.0;      // filtered, track-derived heading (canonical)
    bool m_haveFiltered = false;  // true once the filter has produced a fix
    double m_implementWidth = 6.0;// boom width fed from AppController (heading damp)

    // ---- Raw-track logger -------------------------------------------------
    void logRawFix();
    QFile *m_rawLog = nullptr;
    QTextStream *m_rawLogStream = nullptr;
    QString m_rawLogPath;

    // Below this ground speed, GPS course-over-ground is meaningless, so we hold
    // the last heading instead of letting it jitter.
    static constexpr double kStationaryKmh = 1.0;
};
