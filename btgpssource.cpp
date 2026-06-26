#include "btgpssource.h"

#include <QUdpSocket>
#include <QHostAddress>
#include <QTimer>

#ifdef Q_OS_ANDROID
#include <QAndroidJniObject>
#endif

// Localhost UDP port the Java BtGps helper delivers raw NMEA bytes on. Distinct
// from the USB-CAN helper's port (17626) so the two can never collide.
static constexpr quint16 kBtHostPort = 17627;

BtGpsSource::BtGpsSource(const QString &mac, int channel, QObject *parent)
    : GpsSource(parent), m_mac(mac), m_channel(channel)
{
}

BtGpsSource::~BtGpsSource()
{
    stop();
}

QString BtGpsSource::description() const
{
    return QStringLiteral("Bluetooth GPS %1").arg(m_mac);
}

void BtGpsSource::start()
{
    stop();
    m_got = false;
    m_rxBytes = 0;
    m_rxLines = 0;

    m_udp = new QUdpSocket(this);
    if (!m_udp->bind(QHostAddress::LocalHost, kBtHostPort)) {
        emit status(QStringLiteral("Bluetooth: local port busy (%1)").arg(m_udp->errorString()), false);
        m_udp->deleteLater();
        m_udp = nullptr;
        return;
    }
    connect(m_udp, &QUdpSocket::readyRead, this, &BtGpsSource::onUdpReady);

#ifdef Q_OS_ANDROID
    const QAndroidJniObject jmac = QAndroidJniObject::fromString(m_mac);
    const QAndroidJniObject res = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/BtGps", "start",
        "(ILjava/lang/String;I)Ljava/lang/String;",
        int(kBtHostPort), jmac.object<jstring>(), m_channel);
    const QString msg = res.isValid() ? res.toString() : QStringLiteral("Bluetooth start failed");
    emit status(QStringLiteral("Bluetooth: %1").arg(msg), false);
#else
    emit status(QStringLiteral("Bluetooth GPS needs the Android build"), false);
#endif

    if (!m_diag) {
        m_diag = new QTimer(this);
        m_diag->setInterval(1000);
        connect(m_diag, &QTimer::timeout, this, &BtGpsSource::onDiag);
    }
    m_diag->start();
}

void BtGpsSource::onDiag()
{
    if (m_got) {
        emit status(QStringLiteral("Bluetooth GPS live  (%1 sentences, %2 B)")
                        .arg(m_rxLines).arg(m_rxBytes), true);
        return;
    }
    QString rep;
#ifdef Q_OS_ANDROID
    const QAndroidJniObject r = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/BtGps", "report", "()Ljava/lang/String;");
    if (r.isValid())
        rep = r.toString();
#endif
    if (rep.isEmpty())
        emit status(QStringLiteral("Bluetooth: connecting / no data yet"), false);
    else
        emit status(QStringLiteral("Bluetooth: %1").arg(rep),
                    rep.startsWith(QLatin1String("connected")));
}

void BtGpsSource::onUdpReady()
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

void BtGpsSource::feedBytes(const QByteArray &chunk)
{
    m_rxBytes += chunk.size();
    m_buf.append(chunk);
    int idx;
    while ((idx = m_buf.indexOf('\n')) >= 0) {
        QByteArray line = m_buf.left(idx);
        m_buf.remove(0, idx + 1);
        if (line.endsWith('\r'))
            line.chop(1);
        const QString s = QString::fromLatin1(line).trimmed();
        if (!s.startsWith(QLatin1Char('$')))
            continue;
        ++m_rxLines;
        if (!m_got) {
            m_got = true;
            emit status(QStringLiteral("Bluetooth GPS live"), true);
        }
        emit sentence(s);
    }
    if (m_buf.size() > 8192)
        m_buf.clear();
}

void BtGpsSource::stop()
{
    if (m_diag)
        m_diag->stop();
    if (m_udp) {
#ifdef Q_OS_ANDROID
        QAndroidJniObject::callStaticMethod<void>(
            "org/qtproject/example/BtGps", "stop", "()V");
#endif
        m_udp->deleteLater();
        m_udp = nullptr;
    }
    m_buf.clear();
}
