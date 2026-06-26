#include "tabletgpssource.h"

#include <QUdpSocket>
#include <QHostAddress>
#include <QTimer>
#include <QDateTime>
#include <QStringList>
#include <QPointer>

#include <cmath>

#ifdef Q_OS_ANDROID
#include <QtAndroid>
#include <QAndroidJniObject>
#endif

// Localhost UDP port the Java TabletGps helper delivers fixes on. Distinct from the
// USB-CAN (17626) and Bluetooth (17627) helper ports so none can collide.
static constexpr quint16 kTabletHostPort = 17628;

static QString toNmeaLat(double lat)
{
    const double a = std::abs(lat);
    const int deg = int(a);
    const double minutes = (a - deg) * 60.0;
    return QString::asprintf("%02d%08.5f", deg, minutes); // ddmm.mmmmm
}

static QString toNmeaLon(double lon)
{
    const double a = std::abs(lon);
    const int deg = int(a);
    const double minutes = (a - deg) * 60.0;
    return QString::asprintf("%03d%08.5f", deg, minutes); // dddmm.mmmmm
}

static QString nmeaChecksum(const QString &body)
{
    unsigned char cs = 0;
    const QByteArray b = body.toLatin1();
    for (char c : b)
        cs ^= static_cast<unsigned char>(c);
    return QString::asprintf("%02X", cs);
}

TabletGpsSource::TabletGpsSource(QObject *parent)
    : GpsSource(parent)
{
}

TabletGpsSource::~TabletGpsSource()
{
    stop();
}

QString TabletGpsSource::description() const
{
    return QStringLiteral("Tablet GPS (Android location)");
}

void TabletGpsSource::start()
{
    stop();
    m_got = false;
    m_started = false;
    m_fixes = 0;

    m_udp = new QUdpSocket(this);
    if (!m_udp->bind(QHostAddress::LocalHost, kTabletHostPort)) {
        emit status(QStringLiteral("Tablet GPS: local port busy (%1)").arg(m_udp->errorString()), false);
        m_udp->deleteLater();
        m_udp = nullptr;
        return;
    }
    connect(m_udp, &QUdpSocket::readyRead, this, &TabletGpsSource::onUdpReady);

#ifdef Q_OS_ANDROID
    const QString fine = QStringLiteral("android.permission.ACCESS_FINE_LOCATION");
    const QString coarse = QStringLiteral("android.permission.ACCESS_COARSE_LOCATION");
    if (QtAndroid::checkPermission(fine) == QtAndroid::PermissionResult::Granted) {
        beginUpdates();
    } else {
        emit status(QStringLiteral("Tablet GPS: requesting location permission\u2026"), false);
        QPointer<TabletGpsSource> self(this);
        QtAndroid::requestPermissions(QStringList() << fine << coarse,
            [self, fine](const QtAndroid::PermissionResultMap &res) {
                if (!self)
                    return;
                if (res.value(fine) == QtAndroid::PermissionResult::Granted)
                    self->beginUpdates();
                else
                    emit self->status(QStringLiteral("Tablet GPS: location permission denied"), false);
            });
    }
#else
    emit status(QStringLiteral("Tablet GPS needs the Android build"), false);
#endif

    if (!m_diag) {
        m_diag = new QTimer(this);
        m_diag->setInterval(1000);
        connect(m_diag, &QTimer::timeout, this, &TabletGpsSource::onDiag);
    }
    m_diag->start();
}

void TabletGpsSource::beginUpdates()
{
    m_started = true;
#ifdef Q_OS_ANDROID
    const QAndroidJniObject res = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/TabletGps", "start",
        "(I)Ljava/lang/String;", int(kTabletHostPort));
    const QString msg = res.isValid() ? res.toString() : QStringLiteral("start failed");
    emit status(QStringLiteral("Tablet GPS: %1").arg(msg), false);
#endif
}

void TabletGpsSource::onDiag()
{
    if (m_got) {
        emit status(QStringLiteral("Tablet GPS live  (%1 fixes)").arg(m_fixes), true);
        return;
    }
    if (!m_started) {
        emit status(QStringLiteral("Tablet GPS: waiting for location permission"), false);
        return;
    }
    QString rep;
#ifdef Q_OS_ANDROID
    const QAndroidJniObject r = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/TabletGps", "report", "()Ljava/lang/String;");
    if (r.isValid())
        rep = r.toString();
#endif
    emit status(rep.isEmpty() ? QStringLiteral("Tablet GPS: waiting for first fix\u2026")
                              : QStringLiteral("Tablet GPS: %1").arg(rep), false);
}

void TabletGpsSource::onUdpReady()
{
    if (!m_udp)
        return;
    while (m_udp->hasPendingDatagrams()) {
        QByteArray dg;
        dg.resize(int(m_udp->pendingDatagramSize()));
        m_udp->readDatagram(dg.data(), dg.size());
        if (!dg.isEmpty())
            handleLine(dg);
    }
}

void TabletGpsSource::handleLine(const QByteArray &line)
{
    const QString s = QString::fromLatin1(line).trimmed();
    if (!s.startsWith(QLatin1String("TGPS,")))
        return;
    // TGPS,lat,lon,alt,speedKmh,bearing,sats,hdop  (trailing fields may be empty)
    const QStringList p = s.split(QLatin1Char(','));
    if (p.size() < 3)
        return;
    bool okLat = false, okLon = false;
    const double lat = p.at(1).toDouble(&okLat);
    const double lon = p.at(2).toDouble(&okLon);
    if (!okLat || !okLon)
        return;
    const QString alt = p.value(3);
    const QString spd = p.value(4);   // km/h
    const QString brg = p.value(5);   // bearing (course over ground)
    const QString sats = p.value(6);
    const QString hdop = p.value(7);

    const QString utc = QDateTime::currentDateTimeUtc().toString(QStringLiteral("hhmmss.zz"));

    // $PANDA,time,lat,N,lon,E,fixQ,sats,hdop,alt,age,speed,heading[,roll,pitch,yaw]
    // Fix quality 1 (GPS). No TCM, so roll/pitch/yaw are omitted entirely.
    QStringList f;
    f << QStringLiteral("PANDA")
      << utc
      << toNmeaLat(lat) << (lat >= 0.0 ? QStringLiteral("N") : QStringLiteral("S"))
      << toNmeaLon(lon) << (lon >= 0.0 ? QStringLiteral("E") : QStringLiteral("W"))
      << QStringLiteral("1")
      << sats
      << hdop
      << (alt.isEmpty() ? QStringLiteral("0") : alt)
      << QString()        // age
      << spd
      << brg;
    const QString body = f.join(QLatin1Char(','));
    const QString nmea = QStringLiteral("$%1*%2").arg(body, nmeaChecksum(body));

    if (!m_got) {
        m_got = true;
        emit status(QStringLiteral("Tablet GPS live"), true);
    }
    ++m_fixes;
    emit sentence(nmea);
}

void TabletGpsSource::stop()
{
    if (m_diag)
        m_diag->stop();
    if (m_udp) {
#ifdef Q_OS_ANDROID
        QAndroidJniObject::callStaticMethod<void>(
            "org/qtproject/example/TabletGps", "stop", "()V");
#endif
        m_udp->deleteLater();
        m_udp = nullptr;
    }
    m_buf.clear();
}
