#pragma once

#include "gpssource.h"

#include <QByteArray>

class QUdpSocket;
class QTimer;

// The tablet's own GNSS (Android location services) as a GPS source. A small Java
// helper (TabletGps.java) registers a LocationManager listener and forwards each fix
// to this object over localhost UDP as a "TGPS,lat,lon,alt,speedKmh,bearing,sats,
// hdop" line. We synthesise a $PANDA sentence from it and emit it, reusing the same
// Java->UDP->parser pattern as the Bluetooth/USB-CAN sources. Heading comes from the
// course-over-ground bearing; there is no TCM (roll/pitch) from the tablet, so those
// fields are left empty. The ACCESS_FINE_LOCATION runtime grant is obtained (via
// QtAndroid) before the Java listener is started.
class TabletGpsSource : public GpsSource
{
    Q_OBJECT
public:
    explicit TabletGpsSource(QObject *parent = nullptr);
    ~TabletGpsSource() override;

    void start() override;
    void stop() override;
    QString description() const override;

private slots:
    void onUdpReady();
    void onDiag();

private:
    // Start the Java location listener (after the location permission is granted).
    void beginUpdates();
    void handleLine(const QByteArray &line);

    QUdpSocket *m_udp = nullptr;
    QTimer *m_diag = nullptr;
    QByteArray m_buf;
    bool m_got = false;
    bool m_started = false;     // Java listener requested (permission granted)
    qint64 m_fixes = 0;
};
