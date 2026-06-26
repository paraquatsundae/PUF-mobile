#include "cangpssource.h"

#include <QDateTime>
#include <QtMath>
#include <QUdpSocket>
#include <QHostAddress>
#include <QStringList>
#include <QTimer>

#include <cmath>
#include <cstring>

#ifdef HAVE_POSIX_SERIAL
#include <QSocketNotifier>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <cerrno>
#endif

#ifdef Q_OS_ANDROID
#include <QAndroidJniObject>
#include <jni.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>
#include <errno.h>

// JNI shim called from JdUsbCan.java. Android's UsbDeviceConnection.claimInterface(
// force=true) is meant to kick the in-kernel cdc_acm driver off the device, but on
// some kernels (seen on Samsung) it returns true WITHOUT detaching, so every URB on
// the otherwise-valid fd fails with -1. Issuing USBDEVFS_DISCONNECT directly on the
// raw fd evicts the kernel driver for real; a follow-up CLAIMINTERFACE takes the
// interface at the kernel level. Returns 0 on success, -errno on failure
// (ENODATA/ENODEV = "no driver was attached", which is harmless).
extern "C" JNIEXPORT jint JNICALL
Java_org_qtproject_example_JdUsbCan_nativeDetach(JNIEnv *, jclass, jint fd, jint ifno)
{
    usbdevfs_ioctl cmd;
    cmd.ifno = ifno;
    cmd.ioctl_code = USBDEVFS_DISCONNECT;
    cmd.data = nullptr;
    int r = ::ioctl(fd, USBDEVFS_IOCTL, &cmd);
    if (r != 0 && errno != ENODATA && errno != ENODEV)
        return -errno;
    unsigned int n = static_cast<unsigned int>(ifno);
    r = ::ioctl(fd, USBDEVFS_CLAIMINTERFACE, &n);
    return r == 0 ? 0 : -errno;
}

// USBDEVFS_RESET: port-reset the device to clear a wedged state before bring-up.
// Returns 0 on success, -errno otherwise.
extern "C" JNIEXPORT jint JNICALL
Java_org_qtproject_example_JdUsbCan_nativeReset(JNIEnv *, jclass, jint fd)
{
    int r = ::ioctl(fd, USBDEVFS_RESET, 0);
    return r == 0 ? 0 : -errno;
}

// Raw usbfs control transfer. Android's UsbDeviceConnection.controlTransfer returns
// -1 on this device even with a valid fd + kernel claim, so we issue USBDEVFS_CONTROL
// directly (proven to work, since the DISCONNECT/CLAIM ioctls above succeed).
// Returns bytes transferred (>=0) or -errno.
extern "C" JNIEXPORT jint JNICALL
Java_org_qtproject_example_JdUsbCan_nativeControl(
    JNIEnv *env, jclass, jint fd, jint reqType, jint req, jint val, jint idx,
    jbyteArray jdata, jint len, jint timeout)
{
    unsigned char buf[64];
    if (len > (jint)sizeof(buf)) len = sizeof(buf);
    if (jdata && len > 0)
        env->GetByteArrayRegion(jdata, 0, len, reinterpret_cast<jbyte *>(buf));
    usbdevfs_ctrltransfer ct;
    ct.bRequestType = (unsigned char)reqType;
    ct.bRequest     = (unsigned char)req;
    ct.wValue       = (unsigned short)val;
    ct.wIndex       = (unsigned short)idx;
    ct.wLength      = (unsigned short)len;
    ct.timeout      = (unsigned int)timeout;
    ct.data         = (len > 0) ? buf : nullptr;
    int r = ::ioctl(fd, USBDEVFS_CONTROL, &ct);
    if (r < 0) return -errno;
    if (jdata && (reqType & 0x80) && r > 0)
        env->SetByteArrayRegion(jdata, 0, r, reinterpret_cast<jbyte *>(buf));
    return r;
}

// Raw usbfs synchronous bulk transfer (direction taken from the endpoint address's
// 0x80 bit). Returns bytes transferred (>=0, 0 = none) or -errno.
extern "C" JNIEXPORT jint JNICALL
Java_org_qtproject_example_JdUsbCan_nativeBulk(
    JNIEnv *env, jclass, jint fd, jint ep, jbyteArray jdata, jint len, jint timeout)
{
    unsigned char buf[4096];
    if (len > (jint)sizeof(buf)) len = sizeof(buf);
    const bool isIn = (ep & 0x80) != 0;
    if (!isIn && jdata && len > 0)
        env->GetByteArrayRegion(jdata, 0, len, reinterpret_cast<jbyte *>(buf));
    usbdevfs_bulktransfer bt;
    bt.ep      = (unsigned int)ep;
    bt.len     = (unsigned int)len;
    bt.timeout = (unsigned int)timeout;
    bt.data    = buf;
    int r = ::ioctl(fd, USBDEVFS_BULK, &bt);
    if (r < 0) return -errno;
    if (isIn && jdata && r > 0)
        env->SetByteArrayRegion(jdata, 0, r, reinterpret_cast<jbyte *>(buf));
    return r;
}
#endif

// Localhost UDP port used by the Java USB-host helper to deliver raw slcan bytes.
static constexpr quint16 kUsbHostPort = 17626;

// ---- J1939 / JD ATX constants ----
static constexpr quint32 kAtxSa  = 0x1C;
static constexpr quint32 kPgnFEF3 = 0xFEF3; // position
static constexpr quint32 kPgnFEE8 = 0xFEE8; // heading/speed/pitch/alt
static constexpr quint32 kPgnFEE6 = 0xFEE6; // roll
static constexpr quint32 kPgnFFFF = 0xFFFF; // JD proprietary GNSS quality multiplex
static constexpr quint32 kPgnFEF1 = 0xFEF1; // wheel speed

static quint32 pgnOf(quint32 canId)  { return (canId >> 8) & 0x3FFFF; }
static quint32 saOf(quint32 canId)   { return canId & 0xFF; }

static int u16le(const QByteArray &b, int off)
{
    return (static_cast<quint8>(b[off]) | (static_cast<quint8>(b[off + 1]) << 8));
}

static double bearingDeg(double lat1, double lon1, double lat2, double lon2)
{
    const double r1 = qDegreesToRadians(lat1), r2 = qDegreesToRadians(lat2);
    const double dl = qDegreesToRadians(lon2 - lon1);
    const double y = qSin(dl) * qCos(r2);
    const double x = qCos(r1) * qSin(r2) - qSin(r1) * qCos(r2) * qCos(dl);
    double d = qRadiansToDegrees(qAtan2(y, x));
    return std::fmod(d + 360.0, 360.0);
}

bool JdCanDecoder::isPositionFrame(quint32 canId)
{
    return pgnOf(canId) == kPgnFEF3 && saOf(canId) == kAtxSa;
}

void JdCanDecoder::applyFee8(const QByteArray &b, qint64 tsMs)
{
    if (b.size() < 8)
        return;
    const int rawH = u16le(b, 0);
    const int rawS = u16le(b, 2);
    const int rawP = u16le(b, 4);
    const int rawA = u16le(b, 6);
    if (rawH != 0xFFFF) {
        const double hdg = rawH / 128.0;
        if (m_havePrevHeading) {
            const double dt = (tsMs - m_prevHeadingTs) / 1000.0;
            if (dt > 0.0 && dt < 2.0) {
                double dh = hdg - m_prevHeading;
                if (dh > 180.0) dh -= 360.0; else if (dh < -180.0) dh += 360.0;
                m_yawRate = dh / dt;
            }
        }
        m_prevHeading = hdg;
        m_prevHeadingTs = tsMs;
        m_havePrevHeading = true;
        m_headingDeg = hdg;
    }
    if (rawP != 0xFFFF)
        m_pitchDeg = rawP / 128.0 - 210.0;
    if (rawA != 0xFFFF)
        m_altM = rawA * 0.125 - 2500.0;
    // FEE8 speed is phantom on a stationary machine; prefer FEF1 once seen.
    if (rawS != 0xFFFF && !m_fef1Speed)
        m_speedKmh = rawS / 256.0;
}

bool JdCanDecoder::update(quint32 canId, const QByteArray &data)
{
    const quint32 pgn = pgnOf(canId);
    const quint32 sa = saOf(canId);
    const qint64 ts = QDateTime::currentMSecsSinceEpoch();

    if (sa == kAtxSa && pgn == kPgnFEF3) {
        if (data.size() < 8)
            return false;
        qint32 latRaw, lonRaw;
        std::memcpy(&latRaw, data.constData() + 0, 4);
        std::memcpy(&lonRaw, data.constData() + 4, 4);
        const double lat = latRaw * 1e-7 - 210.0; // JD ATX offset
        const double lon = lonRaw * 1e-7;
        if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0)
            return false;
        if (!m_havePrevHeading && m_havePrevLL) {
            const double dist = qFabs(lat - m_prevLat) + qFabs(lon - m_prevLon);
            if (dist > 1e-7)
                m_headingDeg = bearingDeg(m_prevLat, m_prevLon, lat, lon);
        }
        m_prevLat = lat; m_prevLon = lon; m_havePrevLL = true;
        m_lat = lat; m_lon = lon; m_haveLatLon = true;
        return true;
    }
    if (sa == kAtxSa && pgn == kPgnFEE8) {
        applyFee8(data, ts);
        return true;
    }
    if (sa == kAtxSa && pgn == kPgnFEE6) {
        if (data.size() >= 4) {
            const int raw = u16le(data, 2);
            if (raw != 0xFFFF) { m_rollDeg = raw / 128.0; return true; }
        }
        return false;
    }
    if (sa == kAtxSa && pgn == kPgnFFFF) {
        // JD proprietary multiplex: byte0 selects the sub-message. Sub-msg 0x51
        // (signature 0x51 0x03 0x02) carries the GNSS solution summary; byte3 =
        // total satellites used. Field-validated across 25+ 616R captures
        // (~25-39 sats). Mirrors gps_bridge_lib.decode_gnss_sats_ffff(). Must be
        // SA-gated to 0x1C (DISP 0xF0 also emits 0xFFFF with other content).
        if (data.size() >= 4
            && static_cast<quint8>(data[0]) == 0x51
            && static_cast<quint8>(data[1]) == 0x03
            && static_cast<quint8>(data[2]) == 0x02) {
            const int s = static_cast<quint8>(data[3]);
            if (s > 0 && s <= 64) { m_sats = s; m_haveSats = true; return true; }
        }
        return false;
    }
    if (pgn == kPgnFEF1) {
        if (data.size() >= 3) {
            const int raw = static_cast<quint8>(data[1]) | (static_cast<quint8>(data[2]) << 8);
            if (raw != 0xFFFF) { m_fef1Speed = true; m_speedKmh = raw / 256.0; return true; }
        }
        return false;
    }
    return false;
}

static QString latToNmea(double deg)
{
    const QString hemi = deg >= 0 ? QStringLiteral("N") : QStringLiteral("S");
    const double ad = qFabs(deg);
    const int d = int(ad);
    const double m = (ad - d) * 60.0;
    return QStringLiteral("%1%2,%3").arg(d, 2, 10, QChar('0'))
            .arg(m, 7, 'f', 4, QChar('0')).arg(hemi);
}

static QString lonToNmea(double deg)
{
    const QString hemi = deg >= 0 ? QStringLiteral("E") : QStringLiteral("W");
    const double ad = qFabs(deg);
    const int d = int(ad);
    const double m = (ad - d) * 60.0;
    return QStringLiteral("%1%2,%3").arg(d, 3, 10, QChar('0'))
            .arg(m, 7, 'f', 4, QChar('0')).arg(hemi);
}

// Wrap an NMEA body (no leading '$', no '*CS') as "$body*CS" with an uppercase
// 2-hex XOR checksum — matching gps_bridge_lib.nmea_checksum/_nmea_wrap. Only the
// checksum is upper-cased (the bodies we build are already uppercase).
static QString nmeaWrap(const QString &body)
{
    unsigned char cs = 0;
    for (const QChar &c : body)
        cs ^= static_cast<unsigned char>(c.toLatin1());
    return QStringLiteral("$%1*%2").arg(body,
               QStringLiteral("%1").arg(cs, 2, 16, QChar('0')).toUpper());
}

// UTC HH:MM:SS.ss (two decimals) — same as the bridge's _utc_hhmmss_ss().
static QString utcHms()
{
    return QDateTime::currentDateTimeUtc().toString(QStringLiteral("hhmmss.zzz")).left(9);
}

// Satellites-in-use field: zero-padded two digits when known (from PGN 0xFFFF/0x51),
// empty otherwise — exactly as the bridge emits it.
QString JdCanDecoder::panda() const
{
    if (!m_haveLatLon)
        return QString();
    const QString sats = m_haveSats ? QStringLiteral("%1").arg(m_sats, 2, 10, QChar('0')) : QString();
    // $PANDA,time,lat,N,lon,E,fixQ,sats,hdop,alt,age,speed,heading,roll,pitch,yawrate
    // HDOP is empty (no GNSS DOP PGN on the JD implement tap); sats are real,
    // decoded from PGN 0xFFFF/0x51 just like the bridge. Field layout + precision
    // match gps_bridge_lib.nmea_panda() so GpsModel parses it identically.
    QString body = QStringLiteral("PANDA,%1,%2,%3,%4,%5,%6,%7,%8,%9")
            .arg(utcHms())
            .arg(latToNmea(m_lat))
            .arg(lonToNmea(m_lon))
            .arg(m_fixQuality)
            .arg(sats)        // sats — from 0xFFFF/0x51 (empty if not yet seen)
            .arg(QString())   // hdop — not on this tap
            .arg(m_altM, 0, 'f', 1)
            .arg(0.0, 0, 'f', 1)
            .arg(m_speedKmh, 0, 'f', 2);
    body += QStringLiteral(",%1,%2,%3,%4")
            .arg(m_headingDeg, 0, 'f', 1)
            .arg(m_rollDeg, 0, 'f', 2)
            .arg(m_pitchDeg, 0, 'f', 2)
            .arg(m_yawRate, 0, 'f', 2);
    return nmeaWrap(body);
}

QStringList JdCanDecoder::bundle() const
{
    QStringList out;
    if (!m_haveLatLon)
        return out;
    const QString t = utcHms();
    const QString lat = latToNmea(m_lat);  // "ddmm.mmmm,N"
    const QString lon = lonToNmea(m_lon);  // "dddmm.mmmm,E"
    const QString sats = m_haveSats ? QStringLiteral("%1").arg(m_sats, 2, 10, QChar('0')) : QString();
    const double spdKn = m_speedKmh / 1.852;

    // $GPGGA,t,lat,N,lon,E,fixQ,sats,hdop,alt,M,0.0,M,,  (hdop empty)
    out << nmeaWrap(QStringLiteral("GPGGA,%1,%2,%3,%4,%5,,%6,M,0.0,M,,")
                        .arg(t).arg(lat).arg(lon).arg(m_fixQuality).arg(sats)
                        .arg(m_altM, 0, 'f', 1));
    // $GPRMC,t,A,lat,N,lon,E,knots,cog,date,,,A  (mag-var fields empty, then mode A)
    const QString date = QDateTime::currentDateTimeUtc().toString(QStringLiteral("ddMMyy"));
    out << nmeaWrap(QStringLiteral("GPRMC,%1,A,%2,%3,%4,%5,%6,,,A")
                        .arg(t).arg(lat).arg(lon)
                        .arg(spdKn, 0, 'f', 2).arg(m_headingDeg, 0, 'f', 1).arg(date));
    // $GPVTG,cog,T,,M,knots,N,kmh,K
    out << nmeaWrap(QStringLiteral("GPVTG,%1,T,,M,%2,N,%3,K")
                        .arg(m_headingDeg, 0, 'f', 1).arg(spdKn, 0, 'f', 2)
                        .arg(m_speedKmh, 0, 'f', 2));
    // $PANDA last so its full attitude payload wins if a consumer parses all four.
    out << panda();
    return out;
}

// ---------------------------------------------------------------------------

CanGpsSource::CanGpsSource(const QString &device, int ttyBaud, int canBitrate, QObject *parent)
    : GpsSource(parent), m_device(device), m_ttyBaud(ttyBaud), m_canBitrate(canBitrate)
{
}

CanGpsSource::~CanGpsSource()
{
    stop();
}

char CanGpsSource::slcanCode(int bitrate)
{
    switch (bitrate) {
    case 10000:   return '0';
    case 20000:   return '1';
    case 50000:   return '2';
    case 100000:  return '3';
    case 125000:  return '4';
    case 250000:  return '5';
    case 500000:  return '6';
    case 800000:  return '7';
    case 1000000: return '8';
    default:      return '5';
    }
}

QString CanGpsSource::description() const
{
    return QStringLiteral("USB-CAN (JD) %1 @ CAN %2k")
        .arg(m_device).arg(m_canBitrate / 1000);
}

void CanGpsSource::handleToken(const QByteArray &token)
{
    if (token.isEmpty())
        return;
    const char k = token.at(0);
    bool extended = false;
    int idLen = 0;
    if (k == 'T') { extended = true; idLen = 8; }
    else if (k == 't') { extended = false; idLen = 3; }
    else return; // ignore r/R (RTR), replies, bells

    if (token.size() < 1 + idLen + 1)
        return;
    bool ok = false;
    const quint32 id = token.mid(1, idLen).toUInt(&ok, 16);
    if (!ok)
        return;
    const int dlc = QByteArray(1, token.at(1 + idLen)).toInt(&ok, 16);
    if (!ok || dlc < 0 || dlc > 8)
        return;
    const QByteArray dataHex = token.mid(1 + idLen + 1, dlc * 2);
    if (dataHex.size() < dlc * 2)
        return;
    const QByteArray data = QByteArray::fromHex(dataHex);
    Q_UNUSED(extended)

    // Diagnostics: count frames and remember which PGN/SA pairs are on the bus.
    ++m_rxFrames;
    const quint32 pgn = (id >> 8) & 0x3FFFF;
    const quint32 sa = id & 0xFF;
    const quint32 key = (pgn << 8) | sa;
    if (m_seen.size() < 24 && !m_seen.contains(key))
        m_seen.append(key);

    m_decoder.update(id, data);
    // Pace output on the position frame (~5 Hz) and emit the SAME four-sentence
    // bundle the Wi-Fi bridge sends (GGA, RMC, VTG, PANDA). By the time a FEF3
    // position frame arrives the decoder already holds the latest heading/speed/
    // attitude/sats from the other PGNs, so GpsModel receives a stream identical
    // to the bridge's — making direct-plug readouts AND coverage match.
    if (JdCanDecoder::isPositionFrame(id) && m_decoder.valid()) {
        if (!m_got) {
            m_got = true;
            emit status(QStringLiteral("Receiving JD GPS on %1").arg(m_device), true);
        }
        const QStringList msgs = m_decoder.bundle();
        for (const QString &s : msgs)
            if (!s.isEmpty())
                emit sentence(s);
    }
}

void CanGpsSource::feedBytes(const QByteArray &chunk)
{
    m_rxBytes += chunk.size();
    m_buf.append(chunk);
    int idx;
    while ((idx = m_buf.indexOf('\r')) >= 0) {
        const QByteArray token = m_buf.left(idx);
        m_buf.remove(0, idx + 1);
        if (!token.isEmpty())
            handleToken(token);
    }
    if (m_buf.size() > 8192)
        m_buf.clear();
}

void CanGpsSource::start()
{
    stop();
    m_got = false;
    m_rxBytes = 0;
    m_rxFrames = 0;
    m_seen.clear();
    // A "/dev/..." path means a raw TTY (rooted/permissive); otherwise USB-host.
    if (m_device.startsWith(QLatin1String("/dev/")))
        startTty();
    else
        startUsbHost();

    if (!m_diag) {
        m_diag = new QTimer(this);
        m_diag->setInterval(1000);
        connect(m_diag, &QTimer::timeout, this, &CanGpsSource::onDiag);
    }
    m_diag->start();
}

void CanGpsSource::onDiag()
{
    if (m_got) {
        emit status(QStringLiteral("JD GPS live  (%1 frames, %2 B)")
                        .arg(m_rxFrames).arg(m_rxBytes), true);
        return;
    }
    if (m_rxBytes == 0) {
        QString rep;
#ifdef Q_OS_ANDROID
        const QAndroidJniObject r = QAndroidJniObject::callStaticObjectMethod(
            "org/qtproject/example/JdUsbCan", "report", "()Ljava/lang/String;");
        if (r.isValid())
            rep = r.toString();
#endif
        if (rep.isEmpty())
            emit status(QStringLiteral("CAN %1k: no data — try the other bitrate / check wiring")
                            .arg(m_canBitrate / 1000), false);
        else
            emit status(QStringLiteral("CAN %1k: no data — %2").arg(m_canBitrate / 1000).arg(rep), false);
        return;
    }
    QStringList ids;
    for (int i = 0; i < m_seen.size() && ids.size() < 8; ++i) {
        const quint32 key = m_seen.at(i);
        ids << QStringLiteral("%1/%2")
                   .arg((key >> 8) & 0x3FFFF, 0, 16)
                   .arg(key & 0xFF, 2, 16, QChar('0'));
    }
    emit status(QStringLiteral("CAN %1k: %2 B, %3 frm, PGN/SA: %4")
                    .arg(m_canBitrate / 1000).arg(m_rxBytes).arg(m_rxFrames)
                    .arg(ids.join(QStringLiteral(" "))).toUpper(), false);
}

void CanGpsSource::stop()
{
    if (m_diag)
        m_diag->stop();
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
#ifdef HAVE_POSIX_SERIAL
    if (m_fd >= 0) {
        ::write(m_fd, "C\r", 2); // close slcan channel
        ::close(m_fd);
        m_fd = -1;
    }
#endif
    if (m_udp) {
#ifdef Q_OS_ANDROID
        QAndroidJniObject::callStaticMethod<void>(
            "org/qtproject/example/JdUsbCan", "stop", "()V");
#endif
        m_udp->deleteLater();
        m_udp = nullptr;
    }
    m_buf.clear();
}

void CanGpsSource::startUsbHost()
{
    m_udp = new QUdpSocket(this);
    if (!m_udp->bind(QHostAddress::LocalHost, kUsbHostPort)) {
        emit status(QStringLiteral("USB-CAN: local port busy (%1)").arg(m_udp->errorString()), false);
        m_udp->deleteLater();
        m_udp = nullptr;
        return;
    }
    connect(m_udp, &QUdpSocket::readyRead, this, &CanGpsSource::onUdpReady);

#ifdef Q_OS_ANDROID
    const QAndroidJniObject res = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/JdUsbCan", "start", "(III)Ljava/lang/String;",
        int(kUsbHostPort), m_ttyBaud, m_canBitrate);
    const QString msg = res.isValid() ? res.toString() : QStringLiteral("USB-CAN start failed");
    emit status(QStringLiteral("USB-CAN: %1").arg(msg), false);
#else
    emit status(QStringLiteral("USB-CAN USB-host needs the Android build"), false);
#endif
}

void CanGpsSource::onUdpReady()
{
    if (!m_udp)
        return;
    while (m_udp->hasPendingDatagrams()) {
        QByteArray dg;
        dg.resize(int(m_udp->pendingDatagramSize()));
        m_udp->readDatagram(dg.data(), dg.size());
        if (!dg.isEmpty())
            feedBytes(dg);
    }
}

#ifdef HAVE_POSIX_SERIAL

static speed_t canBaud(int baud)
{
    switch (baud) {
    case 9600:   return B9600;
    case 19200:  return B19200;
    case 38400:  return B38400;
    case 57600:  return B57600;
    case 115200: return B115200;
    case 230400: return B230400;
    case 460800: return B460800;
    case 921600: return B921600;
    default:     return B115200;
    }
}

void CanGpsSource::startTty()
{
    const QByteArray path = m_device.toLocal8Bit();
    m_fd = ::open(path.constData(), O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (m_fd < 0) {
        emit status(QStringLiteral("open %1 failed: %2")
                        .arg(m_device, QString::fromLocal8Bit(strerror(errno))),
                    false);
        return;
    }

    struct termios tio;
    memset(&tio, 0, sizeof(tio));
    if (tcgetattr(m_fd, &tio) == 0) {
        cfmakeraw(&tio);
        const speed_t b = canBaud(m_ttyBaud);
        cfsetispeed(&tio, b);
        cfsetospeed(&tio, b);
        tio.c_cflag |= (CLOCAL | CREAD);
        tio.c_cflag &= ~CRTSCTS;
        tio.c_cc[VMIN] = 0;
        tio.c_cc[VTIME] = 0;
        tcsetattr(m_fd, TCSANOW, &tio);
    }

    // slcan bring-up: close channel, set bitrate (S<code>), open channel.
    const QByteArray init = QByteArray("\rC\rS") + slcanCode(m_canBitrate) + "\rO\r";
    if (::write(m_fd, init.constData(), init.size()) < 0) { /* status below */ }

    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &CanGpsSource::onActivated);
    emit status(QStringLiteral("Opened %1 (CAN %2k, waiting for JD GPS)")
                    .arg(m_device).arg(m_canBitrate / 1000), false);
}

void CanGpsSource::onActivated()
{
    if (m_fd < 0)
        return;
    char tmp[512];
    ssize_t n;
    QByteArray chunk;
    while ((n = ::read(m_fd, tmp, sizeof(tmp))) > 0)
        chunk.append(tmp, int(n));
    if (!chunk.isEmpty())
        feedBytes(chunk);
}

#else // !HAVE_POSIX_SERIAL

void CanGpsSource::startTty()
{
    emit status(QStringLiteral("Raw TTY CAN needs the Android/Linux build"), false);
}
void CanGpsSource::onActivated() {}

#endif
